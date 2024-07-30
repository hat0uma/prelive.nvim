local M = {}

---@diagnostic disable-next-line: param-type-mismatch
M.LOG_FILE_PATH = vim.fs.joinpath(vim.fn.stdpath("log"), "prelive.log")

---@class prelive.Config
local defaults = {
  server = {
    host = "127.0.0.1",
    port = 2255,
  },
  log = {
    print_level = vim.log.levels.WARN,
    file_level = vim.log.levels.DEBUG,
    max_file_size = 1 * 1024 * 1024,
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
