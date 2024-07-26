local http = require("prelive.core.http")
local log = require("prelive.core.log")

local M = {
  --- The server instance.
  --- @type prelive.http.Server?
  _instance = nil,
  --- The directories being served.
  --- @type table<integer, { dir: string, update_detected: boolean }>
  _serving_dirs = {},
  _next_id = 1, ---@type integer
}

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

---@class prelive.ServeOptions
---@field port integer The port to serve.
---@field host string The address to bind.
---@field dir string The directory to serve.

--- Get the directory id.
---@param dir string
---@return integer?
local function get_directory_id(dir)
  for id, v in pairs(M._serving_dirs) do
    if v.dir == dir then
      return id
    end
  end
  return nil
end

---@async
--- Handle `/update` endpoint.
--- this endpoint is long-polling.
---@param req prelive.http.Request
---@param res prelive.http.Response
local function handle_update(req, res)
  local CHECK_INTERVAL = 1000
  local TIMEOUT = 30000

  -- get the directory from the path
  local m = req.path:match("/update/(.+)")
  if not m then
    log.warn("Invalid path: %s", req.path)
    res:write_header(http.status.NOT_FOUND)
    return
  end

  local id = tonumber(m)
  if not id or not M._serving_dirs[id] then
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

    if M._serving_dirs[id].update_detected then
      coroutine.resume(thread, http.status.OK)
      return
    end
  end)

  -- Wait for resume and return status code.
  local code = coroutine.yield() ---@type number
  timer:close()
  res:write_header(code)
  M._serving_dirs[id].update_detected = false
end

--- create prewrite hook function
---@param id integer The id of the directory.
---@return fun(res: prelive.http.Response, body: string): string
local function create_prewrite_static(id)
  local inject_js = INJECT_JS_TEMPLATE:gsub("{directory_id}", id)

  --- prewrite hook function
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

--- Get the URL of the directory.
---@param id integer The id of the directory.
---@return string url
function M.get_url(id)
  return string.format("http://localhost:2255/static/%d/", id)
end

--- Serve files in the given directory.
---@param opts prelive.ServeOptions
---@return string url
function M.serve(opts)
  -- Start the server if not already started.
  if not M._instance then
    M._instance = http.Server:new(opts.host, opts.port)
    M._instance:use_logger()
    M._instance:get("/update/", handle_update)
    M._instance:start_serve()
  end

  -- Check if the directory is already being served.
  local directory_id = get_directory_id(opts.dir)
  if directory_id then
    log.warn("Already serving %s", opts.dir)
    return M.get_url(directory_id)
  end

  -- Assign an id to the directory.
  directory_id = M._next_id
  M._next_id = M._next_id + 1
  M._serving_dirs[directory_id] = { dir = opts.dir, update_detected = false }

  -- Serve the directory.
  local path = string.format("/static/%s/", directory_id)
  M._instance:use_static(path, opts.dir, create_prewrite_static(directory_id))
  return M.get_url(directory_id)
end

--- Mark the directory as updated.
--- This will trigger the auto-reload.
---@param dir string
function M.notify_update(dir)
  local directory_id = get_directory_id(dir)
  if not directory_id then
    log.warn("Not serving %s", dir)
    return
  end
  M._serving_dirs[directory_id].update_detected = true
end

return M
