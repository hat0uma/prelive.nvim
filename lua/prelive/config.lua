local M = {}
local log = require("prelive.core.log")

---@class prelive.Config
local defaults = {
  server = {
    host = "127.0.0.1",
    port = 2255,
  },
  logger = {
    notify_level = vim.log.levels.INFO,
    file_level = vim.log.levels.DEBUG,
    --- @type prelive.log.NotifyHandler.Options
    notify = {
      title = "prelive",
    },
    --- @type prelive.log.FileHandler.Options
    file = {
      ---@diagnostic disable-next-line: param-type-mismatch
      file_path = vim.fs.joinpath(vim.fn.stdpath("data"), "/prelive.log"),
      max_backups = 3,
      max_file_size = 1024 * 1024,
    },
  },
}

---@type prelive.Config
local options

--- Setup config
---@param opts? prelive.Config
function M.setup(opts)
  options = vim.tbl_deep_extend("force", {}, defaults, opts or {})

  -- create a logger and set it as the default logger.
  local logger = log.new_logger()
  logger.add_notify_handler(options.logger.notify_level, options.logger.notify)
  logger.add_file_handler(options.logger.file_level, options.logger.file)
  log.set_default(logger)
end

--- Get config
---@param opts? prelive.Config
---@return prelive.Config
function M.get(opts)
  return vim.tbl_deep_extend("force", options or defaults, opts or {})
end

return M
