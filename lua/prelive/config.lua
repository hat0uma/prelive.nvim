local M = {}

---@diagnostic disable-next-line: param-type-mismatch
M.LOG_FILE_PATH = vim.fs.joinpath(vim.fn.stdpath("log"), "prelive.log")

---@class prelive.Config
M.defaults = {
  ---@class prelive.Config.Server
  server = {
    --- The host to bind the server to.
    --- It is strongly recommended not to expose it to the external network.
    host = "127.0.0.1",

    --- The port to bind the server to.
    --- If the value is 0, the server will bind to a random port.
    port = 2255,
  },

  ---@class prelive.Config.Http
  http = {
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
  },

  ---@class prelive.Config.Log
  log = {
    --- The log levels to print. see `vim.log.levels`.
    print_level = vim.log.levels.WARN,

    --- The log levels to write to the log file. see `vim.log.levels`.
    file_level = vim.log.levels.DEBUG,

    --- The maximum size of the log file in bytes.
    --- If 0, it does not output.
    max_file_size = 1 * 1024 * 1024,

    --- The maximum number of log files to keep.
    max_backups = 3,
  },
}

---@type prelive.Config
local options

--- Setup config
---@param opts? prelive.Config
function M.setup(opts)
  ---@type prelive.Config
  options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})

  -- create a logger and set it as the default logger.
  local log = require("prelive.core.log")
  local logger = log.new_logger()
  logger.add_notify_handler(options.log.print_level, { title = "prelive" })
  logger.add_file_handler(options.log.file_level, {
    file_path = M.LOG_FILE_PATH,
    max_backups = options.log.max_backups,
    max_file_size = options.log.max_file_size,
  })
  log.set_default(logger)
end

--- Get config
---@param opts? prelive.Config
---@return prelive.Config
function M.get(opts)
  if not options then
    M.setup()
  end
  return vim.tbl_deep_extend("force", options, opts or {})
end

return M
