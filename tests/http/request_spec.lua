---@diagnostic disable: await-in-sync
local StreamReader = require("prelive.core.http.stream_reader")
local request = require("prelive.core.http.request")
local status = require("prelive.core.http.status")

local CLIENT_IP = "1.1.1.1"

describe("read_request_async", function()
  local reader ---@type prelive.StreamReader
  before_each(function()
    local thread = coroutine.running()
    local dummy = vim.uv.new_tcp()
    reader = StreamReader:new(dummy, thread)
  end)

  after_each(function()
    reader:close()
  end)

  ---@param tbl string[]
  ---@param newline? string
  local function define_request(tbl, newline)
    newline = newline or "\r\n"
    local msg = table.concat(tbl, newline) .. newline
    reader._buffer = msg
  end

  ---------------------------------------------
  -- versions and protocols
  ---------------------------------------------
  it("should be parsing request of HTTP/1.0", function()
    define_request({
      "GET /hello HTTP/1.0",
      "Host: 192.168.0.1",
      "Content-Type: text/plain",
      "",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert(req, err_msg)
    assert.are_equal(req.method, "GET")
    assert.are_equal(req.path, "/hello")
    assert.are_equal(req.version, "HTTP/1.0")
    assert.are_equal(req.body, "")
    assert.are_equal(req.headers:get("Content-Type"), "text/plain")
    assert.are_equal(req.headers:get("Host"), "192.168.0.1")
    assert.are_equal(req.fragment, "")
    assert.are_equal(req.protocol, "http")
    assert.are_equal(req.client_ip, CLIENT_IP)
  end)

  it("should be parsing request of HTTP/1.1", function()
    define_request({
      "GET /hello HTTP/1.1",
      "Host: 192.168.0.1",
      "Content-Type: text/plain",
      "",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert(req, err_msg)
    assert.are_equal(req.method, "GET")
    assert.are_equal(req.path, "/hello")
    assert.are_equal(req.version, "HTTP/1.1")
    assert.are_equal(req.body, "")
    assert.are_equal(req.headers:get("Content-Type"), "text/plain")
    assert.are_equal(req.headers:get("Host"), "192.168.0.1")
    assert.are_equal(req.fragment, "")
    assert.are_equal(req.protocol, "http")
    assert.are_equal(req.client_ip, CLIENT_IP)
  end)

  it("should be parsing request of HTTP/1.0 without Host header", function()
    define_request({
      "GET /hello HTTP/1.0",
      "Content-Type: text/plain",
      "",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP, "2.2.2.2")
    assert(req, err_msg)
    assert.are_equal(req.method, "GET")
    assert.are_equal(req.path, "/hello")
    assert.are_equal(req.version, "HTTP/1.0")
    assert.are_equal(req.body, "")
    assert.are_equal(req.headers:get("Content-Type"), "text/plain")
    assert.are_equal(req.headers:get("Host"), "2.2.2.2")
    assert.are_equal(req.fragment, "")
    assert.are_equal(req.protocol, "http")
    assert.are_equal(req.client_ip, CLIENT_IP)
  end)

  it("should reject if the protocol is HTTP/1.1 and the Host header is missing.", function()
    define_request({
      "GET /hello HTTP/1.1",
      "Content-Type: text/plain",
      "",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP, "2.2.2.2")
    assert.are_nil(req, err_msg)
    assert.are_equal(err_code, 400)
  end)

  it("should reject if the protocol is not HTTP.", function()
    define_request({
      "GET /hello SMTP/1.1",
      "Content-Type: text/plain",
      "",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP, "2.2.2.2")
    assert.are_nil(req, err_msg)
    assert.are_equal(err_code, 400)
  end)

  it("should reject if the protocol is HTTP and the version is not 1.0 or 1.1.", function()
    define_request({
      "GET /hello HTTP/2.0",
      "Content-Type: text/plain",
      "",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP, "2.2.2.2")
    assert.are_nil(req, err_msg)
    assert.are_equal(err_code, status.HTTP_VERSION_NOT_SUPPORTED)

    define_request({
      "GET /hello HTTP/1.0.1",
      "Content-Type: text/plain",
      "",
    })
    req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP, "2.2.2.2")
    assert.are_nil(req, err_msg)
    assert.are_equal(err_code, status.HTTP_VERSION_NOT_SUPPORTED)
  end)

  ----------------------------------------------
  -- method
  ----------------------------------------------
  it("should be parsing request with various methods", function()
    define_request({
      "GET / HTTP/1.0",
      "",
    })
    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert(req, err_msg)
    assert.are_equal(req.method, "GET")

    define_request({
      "POST / HTTP/1.0",
      "Content-Length: 0",
      "",
    })
    req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert(req, err_msg)
    assert.are_equal(req.method, "POST")

    define_request({
      "PUT / HTTP/1.0",
      "Content-Length: 0",
      "",
    })
    req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert(req, err_msg)
    assert.are_equal(req.method, "PUT")

    define_request({
      "DELETE / HTTP/1.0",
      "Content-Length: 0",
      "",
    })
    req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert(req, err_msg)
    assert.are_equal(req.method, "DELETE")

    define_request({
      "OPTIONS / HTTP/1.0",
      "Content-Length: 0",
      "",
    })
    req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert(req, err_msg)
    assert.are_equal(req.method, "OPTIONS")

    define_request({
      "HEAD / HTTP/1.0",
      "",
    })
    req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert(req, err_msg)
    assert.are_equal(req.method, "HEAD")

    -- currently, we don't support other methods.
    -- - CONNECT
    -- - TRACE
    -- - PATCH
    --  etc.
  end)

  it("should reject if the method is invalid", function()
    -- invalid method
    define_request({
      "GET1 / HTTP/1.0",
      "",
    })
    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert.are_nil(req, err_msg)
    assert.are_equal(err_code, status.BAD_REQUEST)

    -- empty method
    define_request({
      " / HTTP/1.0",
      "",
    })
    req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert.are_nil(req, err_msg)
    assert.are_equal(err_code, status.BAD_REQUEST)
  end)

  ----------------------------------------------
  -- path
  ----------------------------------------------
  it("should reject if the path is empty", function()
    define_request({
      "GET HTTP/1.0",
      "",
    })
    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert.are_nil(req, err_msg)
    assert.are_equal(err_code, status.BAD_REQUEST)
  end)

  ----------------------------------------------
  -- query and fragment
  ----------------------------------------------
  it("should be parsing request with query", function()
    define_request({
      "GET /hello?foo=bar HTTP/1.1",
      "Host: 192.168.0.1",
      "Content-Type: text/plain",
      "",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert(req, err_msg)
    assert.are_equal(req.method, "GET")
    assert.are_equal(req.path, "/hello")
    assert.are_equal(req.version, "HTTP/1.1")
    assert.are_equal(req.body, "")
    assert.are_equal(req.headers:get("Content-Type"), "text/plain")
    assert.are_equal(req.headers:get("Host"), "192.168.0.1")
    assert.are_equal(req.fragment, "")
    assert.are_equal(req.query, "foo=bar")
    assert.are_equal(req.protocol, "http")
    assert.are_equal(req.client_ip, CLIENT_IP)
  end)

  it("should be parsing request with fragment", function()
    define_request({
      "GET /hello#foo HTTP/1.0",
      "",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert(req, err_msg)
    assert.are_equal(req.method, "GET")
    assert.are_equal(req.path, "/hello")
    assert.are_equal(req.version, "HTTP/1.0")
    assert.are_equal(req.body, "")
    assert.are_equal(req.fragment, "foo")
  end)

  it("should be parsing request with query and fragment", function()
    define_request({
      "GET /hello?foo=bar&abc#baz HTTP/1.0",
      "",
    })
    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert(req, err_msg)
    assert.are_equal(req.method, "GET")
    assert.are_equal(req.path, "/hello")
    assert.are_equal(req.version, "HTTP/1.0")
    assert.are_equal(req.body, "")
    assert.are_equal(req.fragment, "baz")
    assert.are_equal(req.query, "foo=bar&abc")
  end)

  ----------------------------------------------
  -- headers
  ----------------------------------------------
  it("should reject if the header name is empty", function()
    define_request({
      "GET / HTTP/1.0",
      ":",
      "",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert.are_nil(req, err_msg)
    assert.are_equal(err_code, status.BAD_REQUEST)
  end)

  it("should reject if the header is invalid", function()
    define_request({
      "GET / HTTP/1.0",
      "Host example.com",
      "",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert.are_nil(req, err_msg)
    assert.are_equal(err_code, status.BAD_REQUEST)
  end)

  ----------------------------------------------
  -- Content-Length
  ----------------------------------------------
  it("should be parsing request with Content-Length", function()
    define_request({
      "POST / HTTP/1.0",
      "Content-Length: 13",
      "",
      "Hello, World!",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert(req, err_msg)
    assert.are_equal(req.method, "POST")
    assert.are_equal(req.path, "/")
    assert.are_equal(req.version, "HTTP/1.0")
    assert.are_equal(req.body, "Hello, World!")
    assert.are_equal(req.headers:get("Content-Length"), "13")
  end)

  it("should be parsing request with Content-Length", function()
    define_request({
      "POST / HTTP/1.0",
      "Content-Length: 13",
      "",
      "Hello, World!",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert(req, err_msg)
    assert.are_equal(req.method, "POST")
    assert.are_equal(req.path, "/")
    assert.are_equal(req.version, "HTTP/1.0")
    assert.are_equal(req.body, "Hello, World!")
    assert.are_equal(req.headers:get("Content-Length"), "13")
  end)

  it("should reject if the Content-Length is empty", function()
    define_request({
      "POST / HTTP/1.0",
      "Content-Length:",
      "",
      "Hello, World!",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert.are_nil(req, err_msg)
    assert.are_equal(err_code, status.LENGTH_REQUIRED)
  end)

  --
  it("If the body is longer than the Content-Length, only read the Content-Length.", function()
    define_request({
      "POST / HTTP/1.0",
      "Content-Length: 12",
      "",
      "Hello, World!",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert(req, err_msg)
    assert.are_equal(req.body, "Hello, World")
  end)

  it("should reject if the Content-Length is negative", function()
    define_request({
      "POST / HTTP/1.0",
      "Content-Length: -1",
      "",
      "Hello, World!",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert.are_nil(req, err_msg)
    assert.are_equal(err_code, status.BAD_REQUEST)
  end)

  it("should reject if the Content-Length is float", function()
    define_request({
      "POST / HTTP/1.0",
      "Content-Length: 1.1",
      "",
      "Hello, World!",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert.are_nil(req, err_msg)
    assert.are_equal(err_code, status.BAD_REQUEST)
  end)

  it("should reject if the Content-Length is not a number", function()
    define_request({
      "POST / HTTP/1.0",
      "Content-Length: abc",
      "",
      "Hello, World!",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert.are_nil(req, err_msg)
    assert.are_equal(err_code, status.BAD_REQUEST)
  end)

  it("should reject if the Content-Length is missing", function()
    define_request({
      "POST / HTTP/1.0",
      "",
      "Hello, World!",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert.are_nil(req, err_msg)
    assert.are_equal(err_code, status.LENGTH_REQUIRED)
  end)

  it("should reject if the Content-Length is too large", function()
    define_request({
      "POST / HTTP/1.0",
      "Content-Length: " .. 2 ^ 31,
      "",
      "Hello, World!",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert.are_nil(req, err_msg)
    assert.are_equal(err_code, status.PAYLOAD_TOO_LARGE)
  end)

  ----------------------------------------------
  -- Transfer-Encoding
  ----------------------------------------------
  it("should be parsing chunked request", function()
    define_request({
      "GET / HTTP/1.1",
      "Host: 192.168.0.1",
      "Content-Type: text/plain",
      "Transfer-Encoding: chunked",
      "",
      "7",
      "Mozilla",
      "11",
      "Developer Network",
      "0",
      "",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert(req, err_msg)
    assert.are_equal(req.method, "GET")
    assert.are_equal(req.path, "/")
    assert.are_equal(req.version, "HTTP/1.1")
    assert.are_equal(req.body, "MozillaDeveloper Network")
    assert.are_equal(req.headers:get("Content-Type"), "text/plain")
    assert.are_equal(req.headers:get("Transfer-Encoding"), "chunked")
    assert.are_equal(req.headers:get("Host"), "192.168.0.1")
    assert.are_equal(req.fragment, "")
    assert.are_equal(req.protocol, "http")
    assert.are_equal(req.client_ip, CLIENT_IP)
  end)

  it("should be parsing chunked request with chunk extension", function()
    define_request({
      "GET / HTTP/1.1",
      "Host: 192.168.0.1",
      "Content-Type: text/plain",
      "Transfer-Encoding: chunked",
      "",
      "7;foo=bar",
      "Mozilla",
      "11",
      "Developer Network",
      "0",
      "",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert(req, err_msg)
    assert.are_equal(req.method, "GET")
    assert.are_equal(req.path, "/")
    assert.are_equal(req.version, "HTTP/1.1")
    assert.are_equal(req.body, "MozillaDeveloper Network")
    assert.are_equal(req.headers:get("Content-Type"), "text/plain")
    assert.are_equal(req.headers:get("Transfer-Encoding"), "chunked")
    assert.are_equal(req.headers:get("Host"), "192.168.0.1")
    assert.are_equal(req.fragment, "")
    assert.are_equal(req.protocol, "http")
    assert.are_equal(req.client_ip, CLIENT_IP)
  end)

  it("should be parsing chunked request with chunk extension and trailing headers", function()
    define_request({
      "GET / HTTP/1.0",
      "Transfer-Encoding: chunked",
      "",
      "7;foo=bar",
      "Mozilla",
      "11",
      "Developer Network",
      "0",
      "Trailer: foo",
      "Foo: bar",
      "",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert(req, err_msg)
    assert.are_equal(req.method, "GET")
    assert.are_equal(req.path, "/")
    assert.are_equal(req.version, "HTTP/1.0")
    assert.are_equal(req.body, "MozillaDeveloper Network")
    assert.are_equal(req.headers:get("Transfer-Encoding"), "chunked")
    -- currently, we don't support trailing headers.
    -- assert.are_equal(req.headers:get("Trailer"), "foo")
    -- assert.are_equal(req.headers:get("Foo"), "bar")
  end)

  it("should reject if the chunk size is invalid", function()
    define_request({
      "GET / HTTP/1.0",
      "Transfer-Encoding: chunked",
      "",
      "7a",
      "Mozilla",
      "11",
      "Developer Network",
      "0",
      "",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert.are_nil(req, err_msg)
    assert.are_equal(err_code, status.BAD_REQUEST)
  end)

  it("should reject if the chunk size is negative", function()
    define_request({
      "GET / HTTP/1.0",
      "Transfer-Encoding: chunked",
      "",
      "-7",
      "Mozilla",
      "11",
      "Developer Network",
      "0",
      "",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert.are_nil(req, err_msg)
    assert.are_equal(err_code, status.BAD_REQUEST)
  end)

  it("should reject if the chunk size is float", function()
    define_request({
      "GET / HTTP/1.0",
      "Transfer-Encoding: chunked",
      "",
      "7.1",
      "Mozilla",
      "11",
      "Developer Network",
      "0",
      "",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert.are_nil(req, err_msg)
    assert.are_equal(err_code, status.BAD_REQUEST)
  end)

  it("should reject if the chunk size is missing", function()
    define_request({
      "GET / HTTP/1.0",
      "Transfer-Encoding: chunked",
      "",
      "Mozilla",
      "11",
      "Developer Network",
      "0",
      "",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert.are_nil(req, err_msg)
    assert.are_equal(err_code, status.BAD_REQUEST)
  end)

  it("should reject if the chunk size is not equal to the body length", function()
    define_request({
      "GET / HTTP/1.0",
      "Transfer-Encoding: chunked",
      "",
      "7",
      "Mozilla",
      "10",
      "Developer Network",
      "0",
      "",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert.are_nil(req, err_msg)
    assert.are_equal(err_code, status.BAD_REQUEST)

    define_request({
      "GET / HTTP/1.0",
      "Transfer-Encoding: chunked",
      "",
      "7",
      "Mozilla",
      "12",
      "Developer Network",
      "0",
      "",
    })

    req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert.are_nil(req, err_msg)
    assert.are_equal(err_code, status.BAD_REQUEST)
  end)

  ----------------------------------------------
  -- Mallicious request
  ----------------------------------------------
  it("should reject if the request is too long", function()
    local long_line = string.rep("a", 8192)
    define_request({
      "GET /" .. long_line .. " HTTP/1.0",
      "",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert.are_nil(req, err_msg)
    assert.are_equal(err_code, status.REQUEST_URI_TOO_LONG)
  end)

  it("should reject if the request is too large", function()
    local long_line = string.rep("a", 8192)
    define_request({
      "GET / HTTP/1.0",
      "Host: " .. long_line,
      "",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert.are_nil(req, err_msg)
    assert.are_equal(err_code, status.REQUEST_HEADER_FIELDS_TOO_LARGE)
  end)

  it("should reject request smuggling", function()
    define_request({
      "POST / HTTP/1.1",
      "Host: example.com",
      "Content-Length: 13",
      "Transfer-Encoding: chunked",
      "",
      "0",
      "",
      "GET /admin HTTP/1.1",
      "Host: example.com",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert.are_nil(req, err_msg)
    assert.are_equal(err_code, status.BAD_REQUEST)
  end)

  it("should handle newline in the path", function()
    define_request({
      "GET /hello%0A HTTP/1.0",
      "",
    })

    local req, err_code, err_msg = request.read_request_async(reader, CLIENT_IP)
    assert(req, err_msg)
    assert.are_equal(req.method, "GET")
    assert.are_equal(req.path, "/hello\n")
    assert.are_equal(req.version, "HTTP/1.0")
    assert.are_equal(req.body, "")
    assert.are_equal(req.fragment, "")
  end)
end)
