local HTTPHeaders = require("presrv.core.http.headers")
local log = require("presrv.core.log")
local status = require("presrv.core.http.status")

--- @class presrv.http.Response
--- @field headers presrv.http.Headers
--- @field _status integer
--- @field _connection uv_tcp_t
--- @field _header_written boolean
local HTTPResponse = {}

--- Create a new HTTPResponse object.
---@param connection uv_tcp_t The connection object to write to.
---@return presrv.http.Response object The new http.Response object.
function HTTPResponse:new(connection)
  local obj = {}
  obj._header_written = false
  obj._status = -1
  obj._connection = connection
  obj.headers = HTTPHeaders:new({})

  setmetatable(obj, self)
  self.__index = self
  return obj
end

--- Get status code.
---@return integer status The status code.
function HTTPResponse:get_status()
  return self._status
end

---@async
--- Write the response body to the connection.
--- This function will write the response header if it is not written yet.
---@param body string The body to write.
---@param size integer? The size of the body. If not provided, it will be calculated from the body.
---@param status_code integer? The status code to write. If not provided, it will be 200 OK.
---@return string|nil err_msg Error message if any.
function HTTPResponse:write(body, size, status_code)
  vim.validate("body", body, "string")
  vim.validate("size", size, "number", true)

  local thread = coroutine.running()
  if not thread then
    error("write must be called within a coroutine")
  end

  -- write header if not written
  if not self._header_written then
    self:_ensure_content_length(body, size)
    self:write_header(status_code or status.OK)
  else -- if header is already written, check status code
    if status_code ~= nil then
      vim.notify("Status code is ignored because the header is already written", vim.log.levels.WARN)
    end
  end

  -- write body
  if self._connection:is_closing() then
    vim.notify("Connection is already closing", vim.log.levels.WARN)
    return
  end

  self._connection:write(body, function(err)
    coroutine.resume(thread, err)
  end)
  return coroutine.yield() --- @type string|nil
end

---@async
--- Writes the response header to the connection explicitly.
---
--- This function is automatically called internally by `write()`, so you don't normally need to call it directly.
--- However, if you want to write only the header explicitly, you can call this function.
--- This function does nothing if the header is already written.
--- Currently, only HTTP/1.1 is supported.
---@param status_code integer The status code to write.
---@return string|nil err_msg Error message if any.
function HTTPResponse:write_header(status_code)
  vim.validate("status_code", status_code, "number")

  local thread = coroutine.running()
  if not thread then
    error("write_header must be called within a coroutine")
  end

  -- if header is already written, do nothing.
  if self._header_written then
    log.info("Header is already written with %d. incoming %d is ignored.", self._status, status_code)
    return
  end

  self._header_written = true
  self._status = status_code

  -- set Content-Length to 0 if not provided.
  if not self.headers:get("Content-Length") and not self.headers:get("Transfer-Encoding") then
    self.headers:set("Content-Length", "0")
  end

  -- serialize headers
  local lines = { "HTTP/1.1 " .. self._status }
  for key, value in self.headers:iter() do
    table.insert(lines, key .. ": " .. value)
  end

  table.insert(lines, "\r\n")

  if self._connection:is_closing() then
    vim.notify("Connection is already closing", vim.log.levels.WARN)
    return
  end

  -- write headers
  self._connection:write(table.concat(lines, "\r\n"), function(err)
    coroutine.resume(thread, err)
  end)
  return coroutine.yield() --- @type string|nil
end

--- Check if the header is written.
---@return boolean header_written True if the header is written.
function HTTPResponse:header_written()
  return self._header_written
end

--- Ensure the Content-Length header is set. If not set, it will be calculated from the body.
---@param body string The body to write.
---@param size integer? The size of the body. If not provided, it will be calculated from the body.
function HTTPResponse:_ensure_content_length(body, size)
  -- if Content-Length or Transfer-Encoding is provided, do nothing.
  if self.headers:get("Content-Length") then
    return
  end
  if self.headers:get("Transfer-Encoding") then
    return
  end

  -- set Content-Length
  size = size or body:len()
  self.headers:set("Content-Length", tostring(size))
end

return HTTPResponse
