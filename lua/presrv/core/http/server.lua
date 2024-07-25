local StremReader = require("presrv.core.http.stream_reader")
local middleware = require("presrv.core.http.middleware")
local request = require("presrv.core.http.request")
local response = require("presrv.core.http.response")
local status = require("presrv.core.http.status")

--- @alias presrv.http.RequestHandler async fun(req:presrv.http.Request,res:presrv.http.Response)
--- @alias presrv.http.MiddlewareHandler async fun(req:presrv.http.Request,res:presrv.http.Response,donext:presrv.http.RequestHandler)

---@class presrv.http.ServerOptions
local default_options = {
  --- http keep-alive timeout in milliseconds.
  keep_alive_timeout = 60 * 1000,

  --- maximum number of pending connections.
  --- If the number of pending connections is greater than this value, the client will receive ECONNREFUSED.
  tcp_max_backlog = 16,
}

--- safe close libuv handles.
---@vararg uv_handle_t
local function safe_close(...)
  for _, handle in ipairs({ ... }) do
    if not handle:is_closing() then
      handle:close()
    end
  end
end

---@class presrv.http.Server
---@field _addr string
---@field _port integer
---@field _routes presrv.http.Server.Route[]
---@field _middlewares presrv.http.Server.Middleware[]
---@field _server uv_tcp_t
---@field _default_host string
---@field _options presrv.http.ServerOptions
---@field _connections uv_tcp_t[]
local HTTPServer = {}

---@alias presrv.http.Server.Middleware { pattern: string, method?: string, handler: presrv.http.MiddlewareHandler}
---@alias presrv.http.Server.Route { pattern: string, method?: string, handler: presrv.http.RequestHandler}

--- Create a new HTTPServer.
---
--- Example:
--- ```lua
--- local server = HTTPServer:new("127.0.0.1", 8080)
--- server:use_logger()
--- server:use_static("/static/", "/var/www")
--- server:get("/hello", function(req, res)
---   res:write("Hello, World!")
--- end)
--- server:start_serve()
--- ```
---
---@param addr string the address to listen on.
---@param port integer the port to listen on.
---@param options? presrv.http.ServerOptions the options.
---@return presrv.http.Server
function HTTPServer:new(addr, port, options)
  vim.validate("addr", addr, "string")
  vim.validate("port", port, "number")
  vim.validate("options", options, "table", true)

  -- merge options
  options = vim.tbl_deep_extend("force", default_options, options or {})

  local obj = {}
  obj._addr = addr
  obj._port = port
  obj._routes = {}
  obj._middlewares = {}
  obj._server = vim.uv.new_tcp()
  obj._default_host = ("%s:%s"):format(addr, port)
  obj._connections = {}
  obj._options = options
  setmetatable(obj, self)
  self.__index = self
  return obj
end

--- Start listening and serving.
function HTTPServer:start_serve()
  print("Listening on " .. self._addr .. ":" .. self._port)

  self._server:bind(self._addr, self._port)
  self._server:listen(self._options.tcp_max_backlog, function(err)
    if err then
      print("Error: " .. err)
      return
    end

    ---@async
    -- start connection coroutine
    local thread = coroutine.create(function()
      self:_handle_connection_async()
    end)

    local ok
    ok, err = coroutine.resume(thread)
    if not ok then
      error("failed to start connection coroutine: " .. err)
    end
  end)
end

---@async
--- Handle client connection asynchronously.
--- This function will be called for each client connection.
function HTTPServer:_handle_connection_async()
  -- create client connection
  local client = vim.uv.new_tcp()
  self._server:accept(client)
  local client_ip = client:getpeername().ip
  table.insert(self._connections, client)

  -- create connection timer and start it.
  -- close connection if no data is received within the timeout.
  -- TODO: writing big data
  local connection_timer = vim.uv.new_timer()
  local on_connection_timeout = function()
    print(string.format("%p close connection with timeout", client))
    safe_close(client, connection_timer)
  end
  connection_timer:start(self._options.keep_alive_timeout, 0, on_connection_timeout)

  -- create reader
  -- restart connection timer when reader receives data.
  local reader = StremReader:new(client)
  reader.on_receive = function()
    connection_timer:stop()
    connection_timer:start(self._options.keep_alive_timeout, 0, on_connection_timeout)
  end

  -- receive loop
  while true do
    -- read request
    local res = response:new(client)
    local req, err_status, err_msg = request.read_request_async(reader, client_ip, self._default_host)
    if not req then
      res:write(err_msg or "", nil, err_status or status.BAD_REQUEST)
      break
    end

    -- TODO: multiple values in header
    -- set response connection header
    local connection_header = req.headers:get("Connection")
    if connection_header then
      res.headers:set("Connection", connection_header)
    else
      res.headers:set("Connection", req.version == "HTTP/1.0" and "close" or "keep-alive")
    end

    -- handle request
    self:_handle_request(req, res)

    -- keep-alive connection
    if vim.stricmp(res.headers:get("Connection") or "", "keep-alive") ~= 0 then
      print("close connection")
      break
    end
  end

  connection_timer:stop()
  self:_remove_connection_entry(client)
  safe_close(client, connection_timer)
end

--- release connection
---@param conn uv_tcp_t
function HTTPServer:_remove_connection_entry(conn)
  for i = 1, #self._connections do
    if self._connections[i] == conn then
      table.remove(self._connections, i)
      break
    end
  end
end

--- match request with entry.
---@param req presrv.http.Request the request.
---@param entry presrv.http.Server.Middleware | presrv.http.Server.Route the entry.
---@return boolean
function HTTPServer:_match(req, entry)
  -- check method
  if entry.method and req.method ~= entry.method then
    return false
  end

  -- check path
  -- if pattern ends with slash, it means subtree match.
  -- otherwise, it means exact match.
  if vim.endswith(entry.pattern, "/") then
    return vim.startswith(req.path, entry.pattern)
  else
    return req.path == entry.pattern
  end
end

---@async
---Handle request.
---@param req presrv.http.Request the request.
---@param res presrv.http.Response the response.
function HTTPServer:_handle_request(req, res)
  local current = 1

  ---@async
  ---Call next middleware or route handler.
  ---@param _req presrv.http.Request
  ---@param _res presrv.http.Response
  local function donext(_req, _res)
    -- apply all matching middlewares
    for i = current, #self._middlewares do
      local entry = self._middlewares[i]
      if self:_match(_req, entry) then
        current = i + 1
        entry.handler(_req, _res, donext)
        return
      end
    end

    -- apply first matching route
    for _, entry in ipairs(self._routes) do
      if self:_match(_req, entry) then
        entry.handler(_req, _res)
        break
      end
    end

    -- if no route matched or no response is written by middleware, return 404.
    if not _res:header_written() then
      _res:write_header(status.NOT_FOUND)
    end
  end
  donext(req, res)
end

local function path_validate()
  return function(value)
    return type(value) == "string" and vim.startswith(value, "/")
  end, "string start with /"
end

--- Add API route.
---@param path string
---@param method string
---@param handler presrv.http.RequestHandler
function HTTPServer:_add_route(path, method, handler)
  vim.validate({
    path = { path, path_validate() },
    method = { method, "string" },
    handler = { handler, "function" },
  })

  table.insert(self._routes, { pattern = path, method = method, handler = handler })
end

--- Add a route for GET method.
---@param path string if path ends with slash, it means subtree match. otherwise, it means exact match.
---@param handler presrv.http.RequestHandler the handler function.
function HTTPServer:get(path, handler)
  self:_add_route(path, "GET", handler)
end

--- Add a route for PUT method.
---@param path string if path ends with slash, it means subtree match. otherwise, it means exact match.
---@param handler presrv.http.RequestHandler the handler function.
function HTTPServer:put(path, handler)
  self:_add_route(path, "PUT", handler)
end

--- Add a route for POST method.
---@param path string if path ends with slash, it means subtree match. otherwise, it means exact match.
---@param handler presrv.http.RequestHandler the handler function.
function HTTPServer:post(path, handler)
  self:_add_route(path, "POST", handler)
end

--- Add a route for DELETE method.
---@param path string if path ends with slash, it means subtree match. otherwise, it means exact match.
---@param handler presrv.http.RequestHandler the handler function.
function HTTPServer:delete(path, handler)
  self:_add_route(path, "DELETE", handler)
end

--- Add a middleware.
--- The registered middlewares will be applied in the order they are registered.
---@param path string if path ends with slash, it means subtree match. otherwise, it means exact match.
---@param handler presrv.http.MiddlewareHandler the middleware handler.
function HTTPServer:use(path, handler)
  vim.validate({
    path = { path, path_validate() },
    handler = { handler, "function" },
  })
  table.insert(self._middlewares, { pattern = path, handler = handler })
end

--- Add a static file middleware.
---@param path string the path prefix of static files.
---@param rootdir string the root directory of static files. it should be an absolute path.
---@param prewrite (fun(res:presrv.http.Response,body:string):string)?
function HTTPServer:use_static(path, rootdir, prewrite)
  if not vim.endswith(path, "/") then
    path = path .. "/"
  end
  self:use(path, middleware.static(path, rootdir, prewrite))
end

--- Add a logger middleware.
---@param path? string if path is specified, only log the request and response for the path.
function HTTPServer:use_logger(path)
  if not path then
    path = "/"
  end
  self:use(path, middleware.logger())
end

--- Close server
function HTTPServer:close()
  self._server:close()
  for i = #self._connections, 1, -1 do
    table.remove(self._connections, i)
  end
end

return HTTPServer
