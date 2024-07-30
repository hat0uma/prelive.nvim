local M = {}

---@diagnostic disable-next-line: param-type-mismatch
M.LOG_FILE_PATH = vim.fs.joinpath(vim.fn.stdpath("log"), "prelive.log")

---@class prelive.Config
local defaults = {
  server = {
    --- The host to bind the server to.
    --- It is strongly recommended not to expose it to the external network.
    host = "127.0.0.1",
    --- The port to bind the server to.
    --- If the value is 0, the server will bind to a random port.
    port = 2255,
  },
  log = {
    --- The log levels to print.
    --- The log levels are defined in `vim.log.levels`. see `vim.log.levels`.
    print_level = vim.log.levels.WARN,
    --- The log levels to write to the log file. see `vim.log.levels`.
    file_level = vim.log.levels.DEBUG,
    --- The maximum size of the log file in bytes.
    --- If 0, it does not output.
    max_file_size = 1 * 1024 * 1024,
    --- The maximum number of log files to keep.
    max_backups = 3,
  },
}

---@type prelive.Config
local options

--- Setup config
---@param opts? prelive.Config
function M.setup(opts)
  ---@type prelive.Config
  options = vim.tbl_deep_extend("force", {}, defaults, opts or {})

  -- create a logger and set it as the default logger.
  local log = require("prelive.core.log")
  local logger = log.new_logger()
  logger.add_notify_handler(options.log.print_level, { title = "prelive" })
  logger.add_file_handler(options.log.file_level, {
    file_path = M.LOG_FILE_PATH,
    max_backups = options.log.max_backups,
    max_file_size = options.log.max_file_size,
  })
  log.set_default(logger)
end

--- Get config
---@param opts? prelive.Config
---@return prelive.Config
function M.get(opts)
  return vim.tbl_deep_extend("force", options or defaults, opts or {})
end

return M
