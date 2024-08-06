local StremReader = require("prelive.core.http.stream_reader")
local log = require("prelive.core.log")
local middleware = require("prelive.core.http.middleware")
local request = require("prelive.core.http.request")
local response = require("prelive.core.http.response")
local status = require("prelive.core.http.status")

--- @alias prelive.http.RequestHandler async fun(req:prelive.http.Request,res:prelive.http.Response)
--- @alias prelive.http.MiddlewareHandler async fun(req:prelive.http.Request,res:prelive.http.Response,donext:prelive.http.RequestHandler)

---@class prelive.http.ServerOptions
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

---@class prelive.http.Server
---@field _addr string
---@field _port integer
---@field _routes prelive.http.Server.Route[]
---@field _middlewares prelive.http.Server.Middleware[]
---@field _server uv_tcp_t
---@field _default_host string
---@field _options prelive.http.ServerOptions
---@field _connections { socket: uv_tcp_t , reader: prelive.StreamReader }[]
local HTTPServer = {}

---@alias prelive.http.Server.Middleware { name?:string, pattern: string, method?: string, handler: prelive.http.MiddlewareHandler}
---@alias prelive.http.Server.Route { pattern: string, method?: string, handler: prelive.http.RequestHandler}

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
---@param options? prelive.http.ServerOptions the options.
---@return prelive.http.Server
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
---@return boolean success, string? err
function HTTPServer:start_serve()
  local ok, err_name, err_msg = self._server:bind(self._addr, self._port)
  if not ok then
    local err = string.format("bind on `%s:%d` failed: %s", self._addr, self._port, err_msg)
    return false, err
  end

  ok, err_name, err_msg = self._server:listen(self._options.tcp_max_backlog, function(err)
    if err then
      log.error("Error occured in tcp listen: %s", err)
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
      log.error("failed to start connection coroutine: %s", err or "")
    end
  end)

  if not ok then
    local err = string.format("listen on `%s:%d` failed: %s", self._addr, self._port, err_msg)
    return false, err
  end

  log.info("Listening on %s:%d", self._addr, self._port)
  return true
end

---@async
--- Handle client connection asynchronously.
--- This function will be called for each client connection.
function HTTPServer:_handle_connection_async()
  -- create client connection
  local client = vim.uv.new_tcp()
  self._server:accept(client)
  local client_ip = client:getpeername().ip

  -- create connection timer and start it.
  -- close connection if no data is received within the timeout.
  -- TODO: writing big data
  local connection_timer = vim.uv.new_timer()
  local on_connection_timeout = function()
    log.trace("%p close connection with timeout", client)
    safe_close(client, connection_timer)
  end
  connection_timer:start(self._options.keep_alive_timeout, 0, on_connection_timeout)

  -- create reader
  -- restart connection timer when reader receives data.
  local reader = StremReader:new(client, coroutine.running())
  reader.on_receive = function()
    connection_timer:stop()
    connection_timer:start(self._options.keep_alive_timeout, 0, on_connection_timeout)
  end

  -- add connection entry
  table.insert(self._connections, { socket = client, reader = reader })

  -- receive loop
  while true do
    -- read request
    local res = response:new(client)
    local req, err_status, err_msg = request.read_request_async(reader, client_ip, self._default_host)
    if not req then
      if not client:is_closing() then
        res:write(err_msg or "", nil, err_status or status.BAD_REQUEST)
      end
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
      log.trace("close connection %p.", client)
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
    if self._connections[i].socket == conn then
      self._connections[i].reader:close()
      table.remove(self._connections, i)
      break
    end
  end
end

--- match request with entry.
---@param req prelive.http.Request the request.
---@param entry prelive.http.Server.Middleware | prelive.http.Server.Route the entry.
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
---@param req prelive.http.Request the request.
---@param res prelive.http.Response the response.
function HTTPServer:_handle_request(req, res)
  local current = 1

  ---@async
  ---Call next middleware or route handler.
  ---@param _req prelive.http.Request
  ---@param _res prelive.http.Response
  local function donext(_req, _res)
    -- apply all matching middlewares
    for i = current, #self._middlewares do
      local entry = self._middlewares[i]
      if self:_match(_req, entry) then
        current = i + 1
        ---@type boolean, string | nil
        local ok, err = pcall(entry.handler, _req, _res, donext)
        if not ok then
          log.error("Error occured in middleware of '%s': %s", entry.pattern, err or "")
          res:write_header(status.INTERNAL_SERVER_ERROR)
          return
        end
        return
      end
    end

    -- apply first matching route
    for _, entry in ipairs(self._routes) do
      if self:_match(_req, entry) then
        ---@type boolean, string | nil
        local ok, err = pcall(entry.handler, _req, _res)
        if not ok then
          log.error("Error occured in handler of '%s': %s", entry.pattern, err or "")
          res:write_header(status.INTERNAL_SERVER_ERROR)
          return
        end
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
---@param handler prelive.http.RequestHandler
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
---@param handler prelive.http.RequestHandler the handler function.
function HTTPServer:get(path, handler)
  self:_add_route(path, "GET", handler)
end

--- Add a route for PUT method.
---@param path string if path ends with slash, it means subtree match. otherwise, it means exact match.
---@param handler prelive.http.RequestHandler the handler function.
function HTTPServer:put(path, handler)
  self:_add_route(path, "PUT", handler)
end

--- Add a route for POST method.
---@param path string if path ends with slash, it means subtree match. otherwise, it means exact match.
---@param handler prelive.http.RequestHandler the handler function.
function HTTPServer:post(path, handler)
  self:_add_route(path, "POST", handler)
end

--- Add a route for DELETE method.
---@param path string if path ends with slash, it means subtree match. otherwise, it means exact match.
---@param handler prelive.http.RequestHandler the handler function.
function HTTPServer:delete(path, handler)
  self:_add_route(path, "DELETE", handler)
end

--- Add a middleware.
--- The registered middlewares will be applied in the order they are registered.
---@param path string if path ends with slash, it means subtree match. otherwise, it means exact match.
---@param handler prelive.http.MiddlewareHandler the middleware handler.
---@param name? string the name of the middleware. it is used for `prelive.http.Server:remove_middleware`.
function HTTPServer:use(path, handler, name)
  vim.validate({
    path = { path, path_validate() },
    handler = { handler, "function" },
    name = { name, "string", true },
  })
  table.insert(self._middlewares, { name = name, pattern = path, handler = handler })
end

--- Remove a middleware.
---@param name string the name of the middleware. use the name specified in `prelive.http.Server:use`.
function HTTPServer:remove_middleware(name)
  for i = #self._middlewares, 1, -1 do
    if self._middlewares[i].name == name then
      table.remove(self._middlewares, i)
      return
    end
  end
  log.warn("middleware '%s' not found", name)
end

--- Add a static file middleware.
---@param path string the path prefix of static files.
---@param rootdir string the root directory of static files. it should be an absolute path.
---@param prewrite? prelive.http.middleware.static_prewrite the prewrite hook function.
---@param name? string the name of the middleware. it is used for `prelive.http.Server:remove_middleware`.
function HTTPServer:use_static(path, rootdir, prewrite, name)
  if not vim.endswith(path, "/") then
    path = path .. "/"
  end
  self:use(path, middleware.static(path, rootdir, prewrite), name)
end

--- Add a logger middleware.
---@param path? string if path is specified, only log the request and response for the path.
---@param name? string the name of the middleware. it is used for `prelive.http.Server:remove_middleware`.
function HTTPServer:use_logger(path, name)
  if not path then
    path = "/"
  end
  self:use(path, middleware.logger(), name)
end

--- Close server
function HTTPServer:close()
  for i = #self._connections, 1, -1 do
    -- close reader and remove connection entry
    self._connections[i].reader:close()
    table.remove(self._connections, i)
  end
  self._server:close()
  self._server = nil
end

--- Get bound port.
--- This is useful when the port is set to 0 (random port).
---@return integer? port, string? err
function HTTPServer:get_bound_port()
  if not self._server then
    return nil
  end
  local addr = self._server:getsockname()
  if not addr then
    return nil
  end
  return addr.port
end

return HTTPServer
