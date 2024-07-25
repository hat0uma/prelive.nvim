local log = require("presrv.core.log")
local M = {}

local function setup_logger()
  -- create a logger
  local logger = log.new_logger()
  local log_dir = vim.fn.stdpath("data") ---@cast log_dir string
  local logfile = vim.fs.joinpath(log_dir, "presrv.log")

  --- add handlers
  logger:add_notify_handler(vim.log.levels.WARN, { title = "presrv" })
  logger:add_file_handler(vim.log.levels.INFO, {
    file_path = logfile,
    max_backups = 3,
    max_file_size = 1024 * 1024,
  })
  -- set the default logger
  log.set_default(logger)
end

--- setup
function M.setup()
  setup_logger()
end

return M
