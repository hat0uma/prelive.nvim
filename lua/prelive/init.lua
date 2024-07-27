local api = require("prelive.api")
local config = require("prelive.config")
local log = require("prelive.core.log")

local M = {}

--- Setup logger
--- @param opts prelive.Config
local function setup_logger(opts)
  -- create a logger and set it as the default logger.
  local logger = log.new_logger()
  logger.add_notify_handler(opts.logger.notify_level, opts.logger.notify)
  logger.add_file_handler(opts.logger.file_level, opts.logger.file)
  log.set_default(logger)
end

local function setup_commands()
  vim.api.nvim_create_user_command("PreLiveStart", function()
    local dir = vim.uv.cwd()
    local file = vim.api.nvim_buf_get_name(0)
    if file ~= "" then
      file = vim.fn.fnamemodify(file, ":~:.")
    end
    api.start(dir, file)
  end, {})

  vim.api.nvim_create_user_command("PreLiveShow", function()
    api.show()
  end, {})

  vim.api.nvim_create_user_command("PreLiveStop", function()
    api.select_stop()
  end, {})

  vim.api.nvim_create_user_command("PreLiveStopAll", function()
    api.stop()
  end, {})

  vim.api.nvim_create_user_command("PreLiveLog", function()
    api.open_log()
  end, {})
end

--- setup
---@param opts? prelive.Config
function M.setup(opts)
  opts = config.setup(opts)
  setup_logger(opts)
  setup_commands()
end

return M
