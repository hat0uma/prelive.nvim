local log = require("presrv.core.log")
local server = require("presrv.server")
local M = {}

local function setup_logger()
  -- create a logger
  local logger = log.new_logger()
  local log_dir = vim.fn.stdpath("data") ---@cast log_dir string
  local logfile = vim.fs.joinpath(log_dir, "presrv.log")

  --- add handlers
  logger:add_notify_handler(vim.log.levels.INFO, { title = "presrv" })
  logger:add_file_handler(vim.log.levels.DEBUG, {
    file_path = logfile,
    max_backups = 3,
    max_file_size = 1024 * 1024,
  })
  -- set the default logger
  log.set_default(logger)
end

--- Open browser with the specified options.
local function open_browser(url)
  vim.system({ "explorer", url }, { text = true }, function(obj)
    if obj.code ~= 0 then
      log.error("Failed to open browser status=%d stderr=%s", obj.code, obj.stderr)
    end
  end)
end

--- setup
function M.setup()
  setup_logger()

  vim.api.nvim_create_user_command("PreSrvStartLive", function(opts)
    local dir = opts.fargs[1]
    M.start_reload(dir)
  end, { nargs = 1 })
end

function M.start_reload(dir)
  dir = vim.fn.fnamemodify(dir, ":p")
  local url = server.serve({
    dir = dir,
    host = "127.0.0.1",
    port = 2255,
  })

  vim._watch.watchdirs(dir, {}, function(path, change_type)
    server.notify_update(dir)
  end)

  open_browser(url)
end

return M
