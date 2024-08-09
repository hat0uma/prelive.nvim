local PreLiveServer = require("prelive.server")
local config = require("prelive.config")
local log = require("prelive.core.log")
local mime = require("prelive.core.http.util.mime")
local util = require("prelive.util")
local webbrowser = require("prelive.core.webbrowser")

local M = {
  _server = nil,
}

--- setup
---@param opts? prelive.Config
function M.setup(opts)
  config.setup(opts)
end

--- Start live.
--- Start the web server and begin serving files and watching for changes in the specified directory.
--- If the `file` is specified, open the file in the browser.
--- `file` must be in the `dir`.
---@param dir string The directory to serve.
---@param file? string The file to open. If nil, open the top page.
---@param go_opts? { watch: boolean }
function M.go(dir, file, go_opts)
  vim.validate({
    dir = { dir, "string" },
    file = { file, "string", true },
    go_opts = { go_opts, "table", true },
  })

  local opts = config.get()
  go_opts = go_opts or { watch = true }

  -- check directory exists.
  local result, err
  result, err = vim.uv.fs_realpath(vim.fs.normalize(dir)) -- normalize for expand ~
  if not result then
    log.error(err or (dir .. " is not found."))
    return
  end

  dir = result
  if vim.fn.isdirectory(dir) == 0 then
    log.error("Not a Directory %s", dir)
    return
  end

  if file and file ~= "" then
    if not util.is_absolute_path(file) then
      file = vim.fs.joinpath(dir, file)
    end

    -- check file exists.
    result, err = vim.uv.fs_realpath(vim.fs.normalize(file))
    if not result then
      log.error(err or (file .. " is not found."))
      return
    end

    -- check `file` is in the `dir`
    if result:sub(1, #dir) == dir then
      file = result:sub(#dir + 1)
    else
      log.warn("The file is not in the directory. Open the top page.")
      file = nil
    end
  end

  -- start the server.
  if not M._server then
    M._server = PreLiveServer:new(opts.server.host, opts.server.port)
    if not M._server:start_serve() then
      M._server:close()
      M._server = nil
      return
    end
  end
  local top_page = M._server:add_directory(dir, go_opts.watch)
  if not top_page then
    return
  end

  -- open the browser
  -- if file is html, open the file page. Otherwise, open the top page.
  local url = top_page
  if file and file ~= "" then
    local ext = vim.fn.fnamemodify(file, ":e")
    local mime_type = mime.from_extension(ext)
    if mime_type == "text/html" then
      url = vim.fs.joinpath(url, (file:gsub("\\", "/")))
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

--- Reload the page.
--- Use this when you want to reload the page regardless of whether there are changes.
--- This is intended to be used when `{watch = false}` is specified with `go()`.
--- Please specify the directory you specified with `go()` for `dir`.
---@param dir string The
function M.reload(dir)
  if not M._server then
    log.warn("The server is not running.")
    return
  end

  -- check directory exists.
  local result, err
  result, err = vim.uv.fs_realpath(vim.fs.normalize(dir)) -- normalize for expand ~
  if not result then
    log.error(err or (dir .. " is not found."))
    return
  end

  dir = result
  if vim.fn.isdirectory(dir) == 0 then
    log.error("Not a Directory %s", dir)
    return
  end

  M._server:notify_update(dir)
end

return M
