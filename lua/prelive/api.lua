local PreLiveServer = require("prelive.server")
local config = require("prelive.config")
local log = require("prelive.core.log")
local mime = require("prelive.core.http.util.mime")
local webbrowser = require("prelive.core.webbrowser")

local M = {
  _server = nil,
}

local function register_close_on_leave()
  vim.api.nvim_create_autocmd({ "VimLeavePre" }, {
    callback = function()
      if M._server then
        M._server:close()
      end
    end,
    group = vim.api.nvim_create_augroup("prelive_server_close", {}),
    desc = "Close the prelive server on VimLeavePre.",
  })
end

--- Start the server and add the directory.
---@param dir string
---@param opts prelive.Config
---@return string | nil url
local function start_serve(dir, opts)
  if not M._server then
    M._server = PreLiveServer:new(opts.server.host, opts.server.port)
    register_close_on_leave()
    return M._server:start_serve(dir, true)
  end
  return M._server:add_directory(dir, true)
end

--- Start live.
--- If the file is specified, open the file in the browser.
---@param dir string
---@param file string | nil The file to open. Specify it as a relative path from dir.
---@param opts prelive.Config | nil
function M.start(dir, file, opts)
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
  local top_page = start_serve(dir, opts)
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
  webbrowser.open_system(url):wait()
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

  --- Select a directory and call on_select.
  vim.ui.select(directories, {
    prompt = prompt,
    format_item = function(item)
      return item.url .. "    " .. item.dir
    end,
  }, function(selected)
    if not selected then
      return
    end
    on_select(selected)
  end)
end

function M.show()
  select_served_directories("Select a directory to open.", function(selected)
    webbrowser.open_system(selected.url):wait()
  end)
end

function M.select_stop()
  select_served_directories("Select a directory to stop serving.", function(selected)
    M.stop(selected.dir)
  end)
end

---Stop serving the directory. if the directory is not specified, stop all.
---@param dir string | nil
function M.stop(dir)
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
  local opts = config.get()
  vim.cmd("tabedit " .. opts.logger.file.file_path)
end

return M
