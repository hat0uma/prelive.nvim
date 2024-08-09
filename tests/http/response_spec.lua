---@diagnostic disable: await-in-sync

local HTTPResponse = require("prelive.core.http.response")
local status = require("prelive.core.http.status")

-- Mocking uv_tcp_t
local function create_dummy_socket()
  local dummy_socket = { data = "" }
  function dummy_socket:is_closing()
    return false
  end
  function dummy_socket:write(data, callback)
    vim.schedule(function()
      dummy_socket.data = dummy_socket.data .. data
      callback()
    end)
  end
  return dummy_socket
end

describe("HTTPResponse", function()
  local response ---@type prelive.http.Response
  local dummy_socket
  before_each(function()
    dummy_socket = create_dummy_socket()
    response = HTTPResponse:new(dummy_socket)
  end)

  describe("write", function()
    it("should write the Content-Length and 200 OK headers when only the body is specified.", function()
      local body = "Hello, World!"
      response:write(body)
      local expected = {
        "HTTP/1.1 200",
        "Content-Length: 13",
        "",
        "Hello, World!",
      }
      assert.is_true(response._header_written)
      assert.are.same(dummy_socket.data, table.concat(expected, "\r\n"))
    end)

    it("should write the Content-Length and specified status code headers.", function()
      local body = "Hello, World!"
      response:write(body, nil, status.ACCEPTED)
      local expected = {
        "HTTP/1.1 202",
        "Content-Length: 13",
        "",
        "Hello, World!",
      }
      assert.is_true(response._header_written)
      assert.are.same(dummy_socket.data, table.concat(expected, "\r\n"))
    end)

    it("should ignore the status code if the header is already written.", function()
      local body = "Hello, World!"
      response:write(body)
      response:write(body, nil, status.ACCEPTED)
      local expected = {
        "HTTP/1.1 200",
        "Content-Length: 13",
        "",
        "Hello, World!Hello, World!",
      }
      assert.is_true(response._header_written)
      assert.are.same(dummy_socket.data, table.concat(expected, "\r\n"))
    end)
  end)
end)
