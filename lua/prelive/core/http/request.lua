local HTTPHeaders = require("prelive.core.http.headers")
local config = require("prelive.core.http.config")
local status = require("prelive.core.http.status")
local url = require("prelive.core.http.util.url")

local VALID_HTTP_METHODS = { "GET", "HEAD", "POST", "PUT", "DELETE", "OPTIONS" }

-- max chunk size string length limit for chunked body
-- This is a limit on the length of the chunk size string, not the maximum size of the chunk data.
local MAX_CHUNK_SIZE_HEXDIGIT = ("FFFFFFFF"):len() -- 32bit. see also `MAX_BODY_SIZE`

--- @class prelive.http.Request
--- @field version string
--- @field method string
--- @field path string
--- @field protocol string
--- @field headers prelive.http.Headers
--- @field body string
--- @field fragment string
--- @field client_ip string
--- @field query string
local HTTPRequest = {}

--- Create a new HTTPRequest object.
---@param param { version:string,method:string,path:string,headers:prelive.http.Headers,body:string,fragment:string,client_ip:string,query:string }
---@return prelive.http.Request
function HTTPRequest:new(param)
  local obj = {}
  obj.version = param.version
  obj.method = param.method
  obj.path = param.path
  obj.headers = param.headers
  obj.body = param.body
  obj.fragment = param.fragment
  obj.client_ip = param.client_ip
  obj.protocol = "http"
  obj.query = param.query

  setmetatable(obj, self)
  self.__index = self
  return obj
end

--- Get request url
---@return string url The request url.
function HTTPRequest:get_url()
  return ("%s://%s%s"):format(self.protocol, self.headers["Host"], self.path)
end

---@async
---Parse HTTP request line.
---@param reader prelive.StreamReader
---@param opts prelive.http.ServerOptions
---@return {method:string,path:string,version:string, query:string, fragment:string }? request, integer? err_status, string? err_msg
local function read_request_line_async(reader, opts)
  local line, err_msg = reader:readline_skip_empty_async(opts.max_request_line_size)
  if not line then
    return nil, nil, err_msg
  end

  -- check request line length
  if #line > opts.max_request_line_size then
    return nil, status.URI_TOO_LONG, "Request-URI Too Long."
  end

  -- TODO: need to handle too long headers.
  local request_line = vim.split(line, " ")
  if #request_line ~= 3 then
    return nil, status.BAD_REQUEST, "Bad request syntax."
  end

  -- check protocol
  local method, path, version = request_line[1], request_line[2], request_line[3]
  if not vim.startswith(version, "HTTP/") then
    return nil, status.BAD_REQUEST, "Invalid protocol."
  end

  -- check supported HTTP version
  if version ~= "HTTP/1.0" and version ~= "HTTP/1.1" then
    return nil, status.HTTP_VERSION_NOT_SUPPORTED, "Invalid HTTP version."
  end

  -- check HTTP method is valid
  if not vim.tbl_contains(VALID_HTTP_METHODS, method) then
    return nil, status.BAD_REQUEST, "Invalid HTTP method."
  end

  -- parse path
  local path_elems = url.parse(path)
  return {
    version = version,
    method = method,
    path = path_elems.base,
    query = path_elems.query,
    fragment = path_elems.fragment,
  }
end

---@async
---Read headers asynchronously
---@param reader prelive.StreamReader
---@param opts prelive.http.ServerOptions
---@return prelive.http.Headers? headers, integer? err_status, string? err_msg
local function read_headers_async(reader, opts)
  -- check if the function is called within a coroutine
  local thread = coroutine.running()
  if not thread then
    return nil, nil, "`read_request_async` must call in a coroutine"
  end

  local header_count = 0
  local headers = HTTPHeaders:new({})
  while header_count <= opts.max_header_num do
    -- reaad
    local line, err_msg = reader:readline_async(opts.max_header_field_size)
    if not line then
      return nil, nil, err_msg
    end

    -- check header length
    if #line > opts.max_header_field_size then
      return nil, status.REQUEST_HEADER_FIELDS_TOO_LARGE, "Request Header Fields Too Large."
    end

    -- header end
    if line == "" then
      return headers
    end

    -- parse header
    local delim, delim_end = line:find(":%s*")
    if not delim then
      return nil, status.BAD_REQUEST, "Bad header syntax."
    end

    -- header key and value
    local key = line:sub(1, delim - 1)
    local value = line:sub(delim_end + 1)
    if key == "" then
      return nil, status.BAD_REQUEST, "Bad header syntax."
    end

    header_count = header_count + 1
    headers:set(key, value)
  end

  return nil, status.REQUEST_HEADER_FIELDS_TOO_LARGE, "Request Header Fields Too Large."
end

---@async
---Read chunked body
---@param reader prelive.StreamReader
---@param opts prelive.http.ServerOptions
---@return string? data ,integer? err_status, string? err_msg
local function read_chunked_body(reader, opts)
  -- RFC 9112 4.1. Chunked Transfer Coding
  -- chunked-body = *chunk
  --                last-chunk
  --                trailer-section
  --                CRLF
  -- chunk = chunk-size [ chunk-ext ] CRLF chunk-data CRLF
  -- chunk-size = 1*HEXDIG
  -- last-chunk = 1*("0") [ chunk-ext ] CRLF
  -- chunk-data = 1*OCTET ; a sequence of chunk-size octets
  -- read chunks
  --
  -- For example:
  -- HTTP/1.1 200 OK
  -- Content-Type: text/plain
  -- Transfer-Encoding: chunked
  --
  -- 7\r\n
  -- Mozilla\r\n
  -- 9\r\n
  -- Developer\r\n
  -- 7\r\n
  -- Network\r\n
  -- 0\r\n
  -- \r\n

  -- read chunks
  local total_size = 0
  local body = {}
  while true do
    local max = opts.max_chunk_ext_size + MAX_CHUNK_SIZE_HEXDIGIT + 2
    local line, err_msg = reader:readline_async(max)
    if not line then
      return nil, nil, err_msg
    end

    -- check max line length
    if #line > max then
      return nil, status.BAD_REQUEST, "Chunk size or chunk-ext is too long."
    end

    -- chunk-size and chunk-ext
    -- TODO: currently skipping chunk-ext
    local chunk_head = vim.split(line, ";")
    local chunk_size = tonumber(chunk_head[1], 16)
    if not chunk_size or chunk_size < 0 then
      return nil, status.BAD_REQUEST, "invalid chunk size format"
    end

    -- check body size
    total_size = total_size + chunk_size ---@type integer
    if total_size > opts.max_body_size then
      return nil, status.PAYLOAD_TOO_LARGE, string.format("Request must be less than %d bytes.", opts.max_body_size)
    end

    -- chunk end
    if chunk_size == 0 then
      break
    end

    -- read chunk body
    -- NOTE: Since CRLF is not included in the chunk size, line breaks are discarded after reading the specified size.
    local chunk_body
    chunk_body, err_msg = reader:read_async(chunk_size)
    if not chunk_body then
      return nil, nil, err_msg
    end
    -- skip CRLF after chunk body
    if (reader:readline_async()) ~= "" then
      return nil, status.BAD_REQUEST, "Chunk size is wrong."
    end
    table.insert(body, chunk_body)
  end

  -- read trailer fields.
  -- TODO: currently not supported any trailers.
  while true do
    local line, err_msg = reader:readline_async()
    if not line then
      return nil, nil, err_msg
    end
    if line == "" then
      break
    end
  end

  return table.concat(body)
end

---@async
---Read body with specified size
---@param reader prelive.StreamReader
---@param content_length string
---@param opts prelive.http.ServerOptions
---@return string? data ,integer? err_status, string? err_msg
local function read_sized_body(reader, content_length, opts)
  -- check content-length
  if content_length:match("^%d+$") == nil then
    return nil, status.BAD_REQUEST, "Invalid Content-Length."
  end

  -- check content-length format
  local size = tonumber(content_length, 10)
  if not size or size < 0 then
    return nil, status.BAD_REQUEST, "Invalid Content-Length."
  end

  -- check body size
  if size >= opts.max_body_size then
    return nil, status.PAYLOAD_TOO_LARGE, string.format("Request must be less than %d bytes.", opts.max_body_size)
  end

  -- read body
  local data, err_msg = reader:read_async(size)
  if not data then
    return nil, nil, err_msg
  end

  return data
end

---@async
---Read request body
---@param reader prelive.StreamReader
---@param headers prelive.http.Headers
---@param method string
---@param opts prelive.http.ServerOptions
---@return string? data ,integer? err_status, string? err_msg
local function read_body(reader, headers, method, opts)
  local content_length = headers:get("Content-Length")
  local transfer_encoding = headers:get("Transfer-Encoding")
  content_length = content_length ~= "" and content_length or nil

  if content_length and transfer_encoding then
    return nil, status.BAD_REQUEST, "Both 'Content-Length' and 'Transfer-Encoding' are specified."
  end

  -- Content-Length or Transfer-Encoding required for methods other than GET and HEAD
  if (not content_length and not transfer_encoding) and (method ~= "GET" and method ~= "HEAD") then
    return nil, status.LENGTH_REQUIRED, "Content-Length or Transfer-Encoding required."
  end

  local err_msg = nil
  local err_status = nil

  local body = ""
  if content_length then
    -- content-length body
    local data
    data, err_status, err_msg = read_sized_body(reader, content_length, opts)
    if not data then
      return nil, err_status, err_msg
    end
    body = data
  elseif transfer_encoding and vim.stricmp(transfer_encoding, "chunked") == 0 then
    -- chunked body
    local data
    data, err_status, err_msg = read_chunked_body(reader, opts)
    if not data then
      return nil, err_status, err_msg
    end
    body = data
  else
    -- no body
  end

  return body
end

---@async
---Read request asynchronously
---@param reader prelive.StreamReader
---@param client_ip string
---@param default_host string?
---@param opts prelive.http.ServerOptions?
---@return prelive.http.Request? request, integer? err_status, string? err_msg
local function read_request_async(reader, client_ip, default_host, opts)
  vim.validate({
    reader = { reader, "table" },
    client_ip = { client_ip, "string" },
    default_host = { default_host, "string", true },
    opts = { opts, "table", true },
  })

  -- get default options
  opts = config.get(opts)

  -- check if the function is called within a coroutine
  local thread = coroutine.running()
  if not thread then
    return nil, nil, "`read_request_async` must call in a coroutine"
  end

  local err_msg = nil
  local err_status = nil

  -- read request line
  -- TODO: max-length
  local request_line
  request_line, err_status, err_msg = read_request_line_async(reader, opts)
  if not request_line then
    return nil, err_status, err_msg
  end

  -- read headers
  local headers
  headers, err_status, err_msg = read_headers_async(reader, opts)
  if not headers then
    return nil, err_status, err_msg
  end

  -- check required header
  local host = headers:get("Host")
  if request_line.version == "HTTP/1.1" and not host then
    return nil, status.BAD_REQUEST, "'Host' header required."
  end

  -- set default host for HTTP/1.0
  if request_line.version == "HTTP/1.0" and not host and default_host then
    headers:set("Host", default_host)
  end

  -- TODO: should handle "expect: 100-continue"

  -- read body
  local body
  body, err_status, err_msg = read_body(reader, headers, request_line.method, opts)
  if not body then
    return nil, err_status, err_msg
  end

  return HTTPRequest:new({
    headers = headers,
    body = body,
    method = request_line.method,
    path = url.decode(request_line.path),
    version = request_line.version,
    client_ip = client_ip,
    fragment = request_line.fragment,
    query = request_line.query,
  })
end

return {
  read_request_async = read_request_async,
  HTTPRequest = HTTPRequest,
}
