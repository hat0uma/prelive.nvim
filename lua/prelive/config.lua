local M = {}

---@class prelive.Config
local defaults = {
  server = {
    host = "127.0.0.1",
    port = 2255,
  },
  open = {
    cmd = "explorer",
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
---@return prelive.Config
function M.setup(opts)
  options = vim.tbl_deep_extend("force", {}, defaults, opts or {})
  return options
end

--- Get config
---@param opts? prelive.Config
---@return prelive.Config
function M.get(opts)
  return vim.tbl_deep_extend("force", options or defaults, opts or {})
end

return M
