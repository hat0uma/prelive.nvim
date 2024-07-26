-- Logging module.
-- This module provides a simple logging system.
-- The following classes are provided:
-- - Logger: Provides methods to write logs.
-- - FileHandler: Provides a handler to write logs to a file.
-- - NotifyHandler: Provides a handler to show logs using `vim.notify`.
-- - StringFormatter: Provides a formatter to format log records using a format string.

--- @class prelive.log.Record
--- @field level number
--- @field time number
--- @field message string

--- @class prelive.log.Formatter
--- @field format fun(self: prelive.log.Formatter, record: prelive.log.Record): string

--- @class prelive.log.Handler
--- @field write fun(self: prelive.log.Handler, record: prelive.log.Record)

------------------------------------------------------------------------
-- StringFormatter
------------------------------------------------------------------------

--- @class prelive.log.StringFormatter : prelive.log.Formatter
--- @field _format string
--- @field _level_text table<integer, string>
local StringFormatter = {}

--- Create a new StringFormatter.
--- This formatter uses a format string to format log records.
--- The format string can contain the following placeholders:
--- - {level}: log level
--- - {message}: log message
--- - {time:format}: log time. see `os.date` for format.
--- for example:
---   - "{level} [{time:%Y-%m-%d %H:%M:%S}] {message}"
---   - "INFO [{time:%Y-%m-%d %H:%M:%S}] hello, world!"
---@param format string
---@return prelive.log.StringFormatter
function StringFormatter:new(format)
  local obj = {}
  obj._format = format
  obj._level_text = {
    [vim.log.levels.INFO] = "INFO",
    [vim.log.levels.DEBUG] = "DEBUG",
    [vim.log.levels.ERROR] = "ERROR",
    [vim.log.levels.TRACE] = "TRACE",
    [vim.log.levels.WARN] = "WARN",
  }

  setmetatable(obj, self)
  self.__index = self
  return obj
end

--- Format a log record.
---@param record prelive.log.Record
---@return string
function StringFormatter:format(record)
  local text = self._format
  text = text:gsub("{level}", self._level_text[record.level] or "UNKNOWN")
  text = text:gsub("{message}", record.message)
  text = text:gsub("{time:(.-)}", function(fmt)
    return os.date(fmt, record.time)
  end)
  return text
end

------------------------------------------------------------------------
-- FileHandler
------------------------------------------------------------------------

--- @class prelive.log.FileHandler.Options
--- @field file_path string Path to log file.
--- @field max_file_size number Max file size in bytes.
--- @field max_backups number Number of log files to rotate.
local file_handler_default_options = {
  ---@diagnostic disable-next-line: param-type-mismatch
  file_path = vim.fs.joinpath(vim.fn.stdpath("data"), "http-access.log"),
  max_file_size = 1024 * 10,
  max_backups = 1,
}

--- @class prelive.log.FileHandler : prelive.log.Handler
--- @field _fd number?
--- @field _options prelive.log.FileHandler.Options
--- @field _formatter prelive.log.Formatter Formatter.
local FileHandler = {}

--- Create a new FileHandler.
---@param options prelive.log.FileHandler.Options
---@param formatter prelive.log.Formatter?
---@return prelive.log.FileHandler
function FileHandler:new(options, formatter)
  options = vim.tbl_deep_extend("force", file_handler_default_options, options)

  local obj = {}
  obj._fd = nil --- @type number?
  obj._options = options
  obj._formatter = formatter or StringFormatter:new("{level} [{time:%Y-%m-%d %H:%M:%S}] {message}")

  setmetatable(obj, self)
  self.__index = self
  return obj
end

--- Write a record to log file.
---@param record prelive.log.Record
function FileHandler:write(record)
  self:_ensure_open()
  self:rotate()

  local log = self._formatter:format(record)
  vim.uv.fs_write(self._fd, log)
  vim.uv.fs_write(self._fd, "\n")
end

function FileHandler:close()
  vim.uv.fs_close(self._fd)
  self._fd = nil
end

function FileHandler:rotate()
  self:_ensure_open()
  local stat = vim.uv.fs_fstat(self._fd)
  if not stat then
    return
  end

  -- check if log file size exceeds the limit
  if stat.size < self._options.max_file_size then
    return
  end

  -- if max_backups is 0, truncate log file
  if self._options.max_backups == 0 then
    assert(vim.uv.fs_ftruncate(self._fd, 0))
    return
  end

  -- rotate log files
  -- For example(when max_backups = 3):
  --   foo.log.2 -> foo.log.3
  --   foo.log.1 -> foo.log.2
  --   foo.log   -> foo.log.1
  self:close()
  for i = self._options.max_backups, 1, -1 do
    local old_file = self._options.file_path
    if i > 1 then
      old_file = old_file .. "." .. i - 1
    end
    local new_file = self._options.file_path .. "." .. i

    if vim.uv.fs_stat(old_file) then
      vim.uv.fs_rename(old_file, new_file)
    end
  end

  -- open log file again
  self:_ensure_open()
end

function FileHandler:_ensure_open()
  if self._fd then
    return
  end

  local err
  self._fd, err = vim.uv.fs_open(self._options.file_path, "a", 438)
  if not self._fd then
    error("failed to open log file: " .. self._options.file_path .. " " .. err)
  end
end

------------------------------------------------------------------------
-- NotifyHandler
------------------------------------------------------------------------

--- @class prelive.log.NotifyHandler.Options
--- @field title string?
local notify_handler_default_options = {
  title = nil,
}

--- @class prelive.log.NotifyHandler : prelive.log.Handler
--- @field _options prelive.log.NotifyHandler.Options Options.
--- @field _formatter prelive.log.Formatter Formatter.
local NotifyHandler = {}

--- Create a new NotifyHandler.
---@param options prelive.log.NotifyHandler.Options
---@param formatter prelive.log.Formatter?
---@return prelive.log.NotifyHandler
function NotifyHandler:new(options, formatter)
  options = vim.tbl_deep_extend("force", notify_handler_default_options, options)

  local obj = {}
  obj._options = options
  obj._formatter = formatter or StringFormatter:new("{message}")

  setmetatable(obj, self)
  self.__index = self
  return obj
end

--- Write a record to notify.
---@param record prelive.log.Record
function NotifyHandler:write(record)
  local log = self._formatter:format(record)
  self._last_notification = vim.notify(log, record.level, {
    title = self._options.title,
    replace = self._last_notification,
  })
end

------------------------------------------------------------------------
-- Logger
------------------------------------------------------------------------

--- @class prelive.log.Logger
--- @field handlers {level: integer, handler: prelive.log.Handler}[]
local Logger = {}

--- Create a new Logger.
---@param handlers ({level: integer, handler: prelive.log.Handler}[])?
---@return prelive.log.Logger
function Logger:new(handlers)
  local obj = {}
  obj.handlers = handlers or {}

  setmetatable(obj, self)
  self.__index = self
  return obj
end

--- Add a handler.
---@param handler prelive.log.Handler
---@param level integer Log level.
function Logger:add_handler(handler, level)
  table.insert(self.handlers, { level = level, handler = handler })
end

--- Add a file handler.
---@param level integer Log level.
---@param options prelive.log.FileHandler.Options File handler options.
---@param formatter prelive.log.Formatter | string | nil Formatter. if nil, use default formatter. if string, use `StringFormatter`.
function Logger:add_file_handler(level, options, formatter)
  if type(formatter) == "string" then
    formatter = StringFormatter:new(formatter)
  end
  self:add_handler(FileHandler:new(options, formatter), level)
end

--- Add a notify handler.
---@param level integer Log level.
---@param options prelive.log.NotifyHandler.Options Notify handler options.
---@param formatter prelive.log.Formatter | string | nil Formatter. if nil, use default formatter. if string, use `StringFormatter`.
function Logger:add_notify_handler(level, options, formatter)
  if type(formatter) == "string" then
    formatter = StringFormatter:new(formatter)
  end
  self:add_handler(NotifyHandler:new(options, formatter), level)
end

--- Write a log record.
---@param level integer Log level.
---@param format string Log format.
---@param ... any
function Logger:write(level, format, ...)
  -- handle log record
  ---@type prelive.log.Record
  local record
  for _, iter in ipairs(self.handlers) do
    -- check log level and write log
    if level >= iter.level then
      if not record then
        record = {
          level = level,
          time = os.time(),
          message = string.format(format, ...),
        }
      end
      iter.handler:write(record)
    end
  end
end

--- info log
---@param format string
---@param ... any
function Logger:info(format, ...)
  self:write(vim.log.levels.INFO, format, ...)
end

--- error log
---@param format string
---@param ... any
function Logger:error(format, ...)
  self:write(vim.log.levels.ERROR, format, ...)
end

--- warn log
---@param format string
---@param ... any
function Logger:warn(format, ...)
  self:write(vim.log.levels.WARN, format, ...)
end

--- debug log
---@param format string
---@param ... any
function Logger:debug(format, ...)
  self:write(vim.log.levels.DEBUG, format, ...)
end

--- trace log
---@param format string
---@param ... any
function Logger:trace(format, ...)
  self:write(vim.log.levels.TRACE, format, ...)
end

------------------------------------------------------------------------
-- APIs
------------------------------------------------------------------------
local M = {}

local default_loggger = Logger:new({ {
  level = vim.log.levels.DEBUG,
  handler = NotifyHandler:new({}),
} })

--- Create a new Logger
-- The following example shows how to write logs to a file and notify:
-- ```lua
-- local log = require("prelive.log")
-- -- use default logger
-- log.info("Hello, World!")
-- -- create a new logger
-- local logger = log.new_logger()
-- logger:add_file_handler(vim.log.levels.INFO, {
--   file_path = vim.fn.stdpath("data") .. "/prelive.log",
--   max_file_size = 1024 * 1024,
--   max_backups = 3,
-- }, "{level} [{time:%Y-%m-%d %H:%M:%S}] {message}")
-- logger:add_notify_handler(vim.log.levels.WARN, { title = "prelive" }, "{message}")
-- logger:info("Hello, World!")
--
-- --- Set the default logger
-- log.set_default(logger)
-- log.info("Hello, World!")
-- log.error("Something went wrong!")
-- ```
---@param handlers ({level: integer?, handler: prelive.log.Handler}[])?
---@return prelive.log.Logger
function M.new_logger(handlers)
  return Logger:new(handlers)
end

--- Set a logger to default
---@param logger prelive.log.Logger
function M.set_default(logger)
  default_loggger = logger
end

--- Set a log level to default logger.
--- available log levels are listed in `vim.log.levels`.(default is `DEBUG`)
--- This function sets the log level for all handlers.
--- If you want to set the log level for each handler, use `logger:add_handler`.
---@param level integer
function M.set_level(level)
  for _, iter in ipairs(default_loggger.handlers) do
    iter.level = level
  end
end

--- info log
---@param format string
---@param ... any
function M.info(format, ...)
  default_loggger:info(format, ...)
end

--- error log
---@param format string
---@param ... any
function M.error(format, ...)
  default_loggger:error(format, ...)
end

--- warn log
---@param format string
---@param ... any
function M.warn(format, ...)
  default_loggger:warn(format, ...)
end

--- degug log
---@param format string
---@param ... any
function M.debug(format, ...)
  default_loggger:debug(format, ...)
end

--- trace log
---@param format string
---@param ... any
function M.trace(format, ...)
  default_loggger:trace(format, ...)
end

M.handlers = {
  FileHandler = FileHandler,
  NotifyHandler = NotifyHandler,
}

M.formatters = {
  StringFormatter = StringFormatter,
}

return M
