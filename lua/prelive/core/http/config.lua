local M = {}

---@class prelive.http.ServerOptions
local options = {
  --- maximum number of pending connections.
  --- If the number of pending connections is greater than this value, the client will receive ECONNREFUSED.
  --- @type integer
  tcp_max_backlog = 16,

  --- tcp recv buffer size.
  --- The size of the buffer used to receive data from the client.
  --- This value is used for `vim.uv.recv_buffer_size()`.
  --- @type integer
  tcp_recv_buffer_size = 1024,

  --- http keep-alive timeout in milliseconds.
  --- If the client does not send a new request within this time, the server will close the connection.
  --- @type integer
  keep_alive_timeout = 60 * 1000,

  --- request body size limit
  --- If the request body size exceeds this value, the server will return 413 Payload Too Large.
  --- @type integer
  max_body_size = 1024 * 1024 * 1,

  --- request line size limit
  --- The request line consists of the request method, request URI, and HTTP version.
  --- If the request line size exceeds this value, the server will return 414 URI Too Long.
  --- @type integer
  max_request_line_size = 1024 * 4,

  --- header field size limit (key + value)
  --- If the size of a header field exceeds this value, the server will return 431 Request Header Fields Too Large.
  --- @type integer
  max_header_field_size = 1024 * 4,

  --- max header count.
  --- If the number of header fields exceeds this value, the server will return 431 Request Header Fields Too Large.
  --- @type integer
  max_header_num = 100,

  --- max chunk-ext size limit for chunked body
  --- If the size of a chunk-ext exceeds this value, the server will return 400 Bad Request.
  --- @type integer
  max_chunk_ext_size = 1024 * 1,
}

--- Get the default options.
---@param opts prelive.http.ServerOptions | nil
---@return prelive.http.ServerOptions
function M.get(opts)
  return vim.tbl_deep_extend("force", {}, options, opts or {})
end

return M
