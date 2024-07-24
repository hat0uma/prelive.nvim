local http = require("presrv.core.http")
local log = require("presrv.core.log")

local M = {}

-- inject javascript to auto-reload
-- /update is long-polling endpoint.
-- when update is detected, it returns 200. if timeout, it returns 304.
local INJECT_POS_CANDIDATES = { "</head>", "</body>" }
local INJECT_JS = [[
<script>
  function update() {
    console.log("update start");
    fetch("/update").then(res => {
      if (res.status === 200) {
        console.log("update received");
        location.reload();
      } else {
        console.log("update not received. retrying...");
        update()
      }
    });
  }
  update();
</script>
]]

local server = nil ---@type presrv.HTTPServer?
local update_detected = false

---@async
---Handle `/update` endpoint.
---this endpoint is long-polling.
---@param req presrv.HTTPRequest
---@param res presrv.HTTPResponse
local function handle_update(req, res)
  local CHECK_INTERVAL = 1000
  local TIMEOUT = 30000

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

    if update_detected then
      coroutine.resume(thread, http.status.OK)
      return
    end
  end)

  -- Wait for resume and return status code.
  local code = coroutine.yield() ---@type number
  timer:close()
  res:write_header(code)
  update_detected = false
end

--- prewrote hook function
---@param res presrv.HTTPResponse
---@param body string
---@return string body
local function prewrite_static(res, body)
  if res.headers:get("Content-Type") ~= "text/html" then
    return body
  end

  -- inject javascript code to auto-reload.
  for _, pos in ipairs(INJECT_POS_CANDIDATES) do
    local start, _ = body:find(pos, 1, true)
    if start then
      res.headers:set("Content-Length", tostring(#body + #INJECT_JS))
      return body:sub(1, start - 1) .. INJECT_JS .. body:sub(start)
    end
  end

  return body
end

--- Open browser with the specified options.
---@param opts presrv.ServeOptions
local function open_browser(opts)
  local url = string.format("http://%s:%d/static/%s", opts.host, opts.port, opts.open_file)
  local command = vim.tbl_map(
    ---@param arg string
    ---@return string
    function(arg)
      return (arg:gsub("{url}", url))
    end,
    opts.open_command
  )
  vim.system(command, { text = true }, function(obj)
    if obj.code ~= 0 then
      log.error("Failed to open browser status=%d stderr=%s", obj.code, obj.stderr)
    end
  end)
end

---@class presrv.ServeOptions
---@field port integer The port to serve.
---@field host string The address to bind.
---@field dir string The directory to serve.
---@field open_file string | nil The file to open. path is relative to `dir`.
---@field open_command string[] The command to open browser. {url} is placeholder for the file path.

---Open preview server.
---@param opts presrv.ServeOptions
function M.open(opts)
  if server then
    server:close()
    server = nil
  end

  -- start server
  server = http.Server:new(opts.host, opts.port)
  server:use_logger()
  server:use_static("/static/", opts.dir, prewrite_static)
  server:get("/update", handle_update)
  server:start_serve()

  -- open browser
  if opts.open_file then
    open_browser(opts)
  end
end

return M
