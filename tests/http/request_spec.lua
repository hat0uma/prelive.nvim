---@diagnostic disable: await-in-sync
local StreamReader = require("prelive.core.http.stream_reader")
local request = require("prelive.core.http.request")

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

    local req, err_code, err_msg = request.read_request_async(reader, "1.1.1.1")
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
    assert.are_equal(req.client_ip, "1.1.1.1")
  end)
end)
