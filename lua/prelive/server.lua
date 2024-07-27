local http = require("prelive.core.http")
local log = require("prelive.core.log")

local CHECK_INTERVAL = 500
local TIMEOUT = 30000

-- inject javascript to auto-reload
-- /update is long-polling endpoint.
-- when update is detected, it returns 200. if timeout, it returns 304.
local INJECT_POS_CANDIDATES = { "</head>", "</body>" }
local INJECT_JS_TEMPLATE = [[
<script>
  function update() {
    console.log("update start");
    fetch("/update/{directory_id}").then(res => {
      if (res.status === 200) {
        console.log("update received");
        location.reload();
      } else if (res.status === 304) {
        console.log("update not received. retrying...");
        update()
      } else {
        console.error("update failed: " + res.status);
        setTimeout(update, 1000);
      }
    });
  }
  update();
</script>
]]

---This class provides file-serving functionality with auto-reloading capabilities.
---It embeds JavaScript for auto-reloading in the HTML files served.
---When the server detects changes in the served directories, it notifies the browser to reload the page.
---If you want to notify the server of updates manually, use the `notify_update` method.
---@class prelive.PreLiveServer
---@field _instance prelive.http.Server | nil
---@field _dirs table<integer, { dir: string, update_detected: boolean, watch_handle?: uv_fs_event_t }>
---@field _next_id integer
---@field _host string
---@field _port integer
local PreLiveServer = {}

--- Create a new prelive.PreLiveServer.
---@param host string The address to bind.
---@param port integer The port to serve.
---@return prelive.PreLiveServer
function PreLiveServer:new(host, port)
  local obj = {}
  obj._dirs = {}
  obj._next_id = 1
  obj._instance = nil ---@type prelive.http.Server | nil
  obj._host = host
  obj._port = port

  setmetatable(obj, self)
  self.__index = self
  return obj
end

--- Serve files in the given directory.
---@param dir string The directory to serve.
---@param watch boolean Whether to watch changes in the directory. if false, you need to call `notify_update` manually.
---@return string? url The URL of the preview file or directory.
function PreLiveServer:start_serve(dir, watch)
  if self._instance then
    log.error("Server is already started.")
    return nil
  end

  -- Create a new server instance. and serve the update endpoint.
  self._instance = http.Server:new(self._host, self._port)
  self._instance:use_logger()
  self._instance:get("/update/", function(req, res) --- @async
    self:_handle_update(req, res)
  end)

  -- Serve the directory.
  local url = self:add_directory(dir, watch)
  self._instance:start_serve()
  return url
end

--- Add a directory to serve.
--- This function can be called after `start_serve`.
---@param dir string The directory to serve.
---@param watch boolean Whether to watch changes in the directory. if false, you need to call `notify_update` manually.
---@return string? url The URL of the preview file or directory.
function PreLiveServer:add_directory(dir, watch)
  if not self._instance then
    log.error("Server is not started.")
    return nil
  end

  -- Check if the directory is already being served.
  local directory_id = self:_get_directory_id(dir)
  if directory_id then
    log.warn("Already serving %s", dir)
    return self:_get_url(directory_id)
  end

  -- Watch changes in the directory.
  local watch_handle = nil
  if watch then
    local err_name, err_msg
    watch_handle, err_name, err_msg = self:_watch_changes(dir)
    if not watch_handle then
      log.error("Failed to start watching %s: %s %s", dir, err_name, err_msg)
      return nil
    end
  end

  -- Assign an id to the directory.
  directory_id = self._next_id
  self._next_id = self._next_id + 1
  self._dirs[directory_id] = { dir = dir, update_detected = false, watch_handle = watch_handle }

  -- Serve the directory.
  local path = self:_get_serve_path(directory_id)
  self._instance:use_static(path, dir, self:_create_prewrite_static(directory_id), path)
  return self:_get_url(directory_id)
end

--- Remove the directory from serving.
---@param dir string The directory to remove.
function PreLiveServer:remove_directory(dir)
  local directory_id = self:_get_directory_id(dir)
  if not directory_id then
    log.warn("Not serving %s", dir)
    return
  end

  -- Close the watch handle.
  local entry = self._dirs[directory_id]
  if entry.watch_handle then
    entry.watch_handle:close()
  end

  -- Remove the middleware.
  local middleware_name = self:_get_serve_path(directory_id)
  self._instance:remove_middleware(middleware_name)
  self._dirs[directory_id] = nil
end

--- Mark the directory as updated.
--- This will trigger the auto-reload.
---@param dir string
function PreLiveServer:notify_update(dir)
  local directory_id = self:_get_directory_id(dir)
  if not directory_id then
    log.warn("Not serving %s", dir)
    return
  end
  self._dirs[directory_id].update_detected = true
end

---Get a list of directories being served.
---@return { dir: string, url: string }[]
function PreLiveServer:get_served_directories()
  local result = {}
  for id, v in pairs(self._dirs) do
    table.insert(result, { dir = v.dir, url = self:_get_url(id) })
  end
  return result
end

--- Close the server.
function PreLiveServer:close()
  -- Remove all directories.
  for _, v in pairs(self._dirs) do
    self:remove_directory(v.dir)
  end

  -- Close the server.
  self._dirs = {}
  self._next_id = 1
  if self._instance then
    self._instance:close()
    self._instance = nil
  end
end

---@async
--- Handle `/update` endpoint.
--- this endpoint is long-polling.
---@param req prelive.http.Request
---@param res prelive.http.Response
function PreLiveServer:_handle_update(req, res)
  -- get the directory from the path
  local m = req.path:match("/update/(.+)")
  if not m then
    log.warn("Invalid path: %s", req.path)
    res:write_header(http.status.NOT_FOUND)
    return
  end

  -- get the directory id
  local id = tonumber(m)
  if not id or not self._dirs[id] then
    log.warn("Invalid id: %s", id)
    res:write_header(http.status.NOT_FOUND)
    return
  end

  -- Wait for update. If timeout, return 304.
  local elapsed = 0
  local thread = coroutine.running()
  local timer = vim.uv.new_timer()
  timer:start(CHECK_INTERVAL, CHECK_INTERVAL, function()
    elapsed = elapsed + CHECK_INTERVAL

    if elapsed >= TIMEOUT then
      coroutine.resume(thread, http.status.NOT_MODIFIED)
      return
    end

    if self._dirs[id].update_detected then
      coroutine.resume(thread, http.status.OK)
      return
    end
  end)

  -- Wait for resume and return status code.
  local code = coroutine.yield() ---@type number
  timer:close()
  res:write_header(code)
  self._dirs[id].update_detected = false
end

--- Get the directory id.
---@param dir string
---@return integer?
function PreLiveServer:_get_directory_id(dir)
  for id, v in pairs(self._dirs) do
    if v.dir == dir then
      return id
    end
  end
  return nil
end

--- Create a prewrite hook function for static files.
---@param id integer The id of the directory.
---@return fun(res: prelive.http.Response, body: string): string
function PreLiveServer:_create_prewrite_static(id)
  local inject_js = INJECT_JS_TEMPLATE:gsub("{directory_id}", id)

  --- prewrite hook function for static files.
  ---@param res prelive.http.Response
  ---@param body string
  ---@return string body
  return function(res, body)
    if res.headers:get("Content-Type") ~= "text/html" then
      return body
    end

    -- inject javascript code to auto-reload.
    for _, pos in ipairs(INJECT_POS_CANDIDATES) do
      local start, _ = body:find(pos, 1, true)
      if start then
        res.headers:set("Content-Length", tostring(#body + #inject_js))
        return body:sub(1, start - 1) .. inject_js .. body:sub(start)
      end
    end

    return body
  end
end

--- Get the path to serve the directory.
---@param id integer The id of the directory.
---@return string path
function PreLiveServer:_get_serve_path(id)
  return string.format("/static/%s/", id)
end

--- Get the URL of the directory.
---@param id integer The id of the directory.
---@return string url
function PreLiveServer:_get_url(id)
  return string.format("http://%s:%d%s", self._host, self._port, self:_get_serve_path(id))
end

--- Watch changes in the directory.
---@param dir string
---@return uv_fs_event_t? watch_handle, string? err_name, string? err_msg
function PreLiveServer:_watch_changes(dir)
  local watch_handle, err_name, err_msg = vim.uv.new_fs_event()
  if not watch_handle then
    return nil, err_name, err_msg
  end

  watch_handle:start(dir, { recursive = true }, function(err, filename, events)
    if err then
      log.error("Failed to watch %s: %s", dir, err)
      return
    end
    if filename then
      self:notify_update(dir)
    end
  end)
  return watch_handle
end

return PreLiveServer