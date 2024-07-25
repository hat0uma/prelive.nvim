--- Convert header case for case-insensitive comparison.
---@param header string The header to convert.
---@return string converted The converted header.
local function convert_header_case(header)
  -- convert key to lowercase.
  -- This is because HTTP headers are case-insensitive.
  return header:lower()
end

--- @class presrv.http.Headers
--- @field _headers table<string,string>
local HTTPHeaders = {}

--- Create a new HTTPHeaders object.
---@param headers table<string,string> The headers.
---@return presrv.http.Headers
function HTTPHeaders:new(headers)
  vim.validate({ headers = { headers, "table" } })

  local obj = {}
  obj._headers = {} --- @type table<string,string>
  for key, value in pairs(headers) do
    obj._headers[convert_header_case(key)] = value
  end

  setmetatable(obj, self)
  self.__index = self
  return obj
end

--- Get a header value.
---@param key string The header key.
---@return string? value The header value.
function HTTPHeaders:get(key)
  vim.validate({ key = { key, "string" } })
  return self._headers[convert_header_case(key)]
end

--- Set a header value.
---@param key string The header key.
---@param value string The header value.
function HTTPHeaders:set(key, value)
  vim.validate({ key = { key, "string" }, value = { value, "string" } })
  self._headers[convert_header_case(key)] = value
end

--- Iterate over headers.
function HTTPHeaders:iter()
  return pairs(self._headers)
end

--- Get raw headers.
---@return table<string,string> headers The raw headers.
function HTTPHeaders:raw()
  return self._headers
end

return HTTPHeaders
