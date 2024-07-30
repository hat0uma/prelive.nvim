local PreLiveServer = require("prelive.server")
local config = require("prelive.config")
local log = require("prelive.core.log")
local mime = require("prelive.core.http.util.mime")
local webbrowser = require("prelive.core.webbrowser")

local M = {
  _server = nil,
}

--- Start live.
--- If the file is specified, open the file in the browser.
---@param dir string
---@param file string | nil The file to open. Specify it as a relative path from dir.
---@param opts prelive.Config | nil
function M.go(dir, file, opts)
  vim.validate({
    dir = { dir, "string" },
    file = { file, "string", true },
    opts = { opts, "table", true },
  })

  opts = config.get(opts)
  if file == "" then
    file = nil
  end

  -- normalize paths
  dir = vim.fs.normalize(dir)
  if file then
    file = vim.fs.normalize(file)
  end

  -- check input
  if not vim.fn.isdirectory(dir) == 0 then
    log.error("Directory not found: %s", dir)
    return
  end
  if file and vim.fn.filereadable(vim.fs.joinpath(dir, file)) == 0 then
    log.error("The file must be a relative path from the directory: %s", file)
    return
  end

  -- start the server.
  if not M._server then
    M._server = PreLiveServer:new(opts.server.host, opts.server.port)
    M._server:start_serve()
  end
  local top_page = M._server:add_directory(dir, true)
  if not top_page then
    return
  end

  -- open the browser
  -- if file is html, open the file page. Otherwise, open the top page.
  local url = top_page
  if file then
    local ext = vim.fn.fnamemodify(file, ":e")
    local mime_type = mime.from_extension(ext)
    if mime_type == "text/html" then
      url = vim.fs.joinpath(url, file)
    end
  end
  webbrowser.open_system(url, function(obj)
    if obj.code ~= 0 then
      log.error("Failed to open the browser: %s", obj.stderr)
    end
  end)
end

---Select a served directory.
---@param prompt string The prompt message.
---@param on_select fun(selected: { dir: string, url: string })
local function select_served_directories(prompt, on_select)
  if not M._server then
    log.warn("The server is not running.")
    return
  end

  local directories = M._server:get_served_directories()
  if #directories == 0 then
    log.info("No directories are being served.")
    return
  end

  -- calculate the width of the url for formatting.
  local create_format_item = function()
    local url_width = 0
    for _, dir in ipairs(directories) do
      url_width = math.max(url_width, vim.fn.strdisplaywidth(dir.url))
    end
    return function(item)
      return string.format("%-" .. url_width .. "s    %s", item.url, item.dir)
    end
  end

  --- Select a directory and call on_select.
  vim.ui.select(directories, {
    prompt = prompt,
    format_item = create_format_item(),
  }, function(selected)
    if not selected then
      return
    end
    on_select(selected)
  end)
end

function M.status()
  select_served_directories("Select a directory to open.", function(selected)
    webbrowser.open_system(selected.url, function(obj)
      if obj.code ~= 0 then
        log.error("Failed to open the browser: %s", obj.stderr)
      end
    end)
  end)
end

function M.select_close()
  select_served_directories("Select a directory to close serving.", function(selected)
    M.close(selected.dir)
  end)
end

---Stop serving the directory. if the directory is not specified, stop all.
---@param dir string | nil
function M.close(dir)
  vim.validate({ dir = { dir, "string", true } })
  if not M._server then
    log.warn("The server is not running.")
    return
  end

  --- Stop all.
  if not dir then
    M._server:close()
    M._server = nil
    return
  end

  --- Stop the specified directory.
  M._server:remove_directory(dir)
  local directories = M._server:get_served_directories()
  if #directories == 0 then
    M._server:close()
    M._server = nil
  end
end

function M.open_log()
  vim.cmd("tabedit " .. config.LOG_FILE_PATH)
end

return M
