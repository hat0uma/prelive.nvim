---@diagnostic disable: await-in-sync
local StreamReader = require("prelive.core.http.stream_reader")

local HOST = "127.0.0.1"

local function find_free_port()
  local server_socket = vim.uv.new_tcp()
  server_socket:bind(HOST, 0)
  local data, err = server_socket:getsockname()
  assert(data, err)
  server_socket:close()
  return data.port
end

--- safe close libuv handles.
---@vararg uv_handle_t
local function safe_close(...)
  for _, handle in ipairs({ ... }) do
    if not handle:is_closing() then
      handle:close()
    end
  end
end

--- Create a stream reader and return it.
---@param thread thread
---@return prelive.StreamReader reader, uv_tcp_t write_socket, uv_tcp_t server_socket
local function create_stream_reader(thread)
  local server_socket = vim.uv.new_tcp()
  local port = find_free_port()
  server_socket:bind(HOST, port)
  server_socket:listen(1, function(err)
    if err then
      error(err)
    end
    local client = vim.uv.new_tcp()
    server_socket:accept(client)
    coroutine.resume(thread, StreamReader:new(client, thread))
  end)

  local write_socket = vim.uv.new_tcp()
  write_socket:connect(HOST, port, function(err)
    if err then
      error(err)
    end
  end)

  local reader = coroutine.yield() ---@type prelive.StreamReader
  return reader, write_socket, server_socket
end

--- Write messages step by step.
---@param write_socket uv_tcp_t
---@param messages string[]
local function write_message_step_by_step(write_socket, messages)
  local timer = vim.uv.new_timer()
  timer:start(10, 10, function()
    if #messages == 0 then
      timer:stop()
      timer:close()
      return
    end
    local message = table.remove(messages, 1)
    assert(write_socket:write(message))
  end)
end

describe("StreamReader", function()
  local write_socket ---@type uv_tcp_t
  local server_socket ---@type uv_tcp_t
  local reader ---@type prelive.StreamReader

  local thread = coroutine.running()
  if not thread then
    error("not in coroutine")
  end

  ---@async
  before_each(function()
    reader, write_socket, server_socket = create_stream_reader(thread)
  end)

  after_each(function()
    safe_close(server_socket, write_socket, reader._stream)
  end)

  describe("readline_async", function()
    local cases = {
      { name = "should read a line with LF", message = { "aa", "bb", "cc", "\n" }, expect = "aabbcc" },
      { name = "should read a line with CRLF", message = { "aa", "bb", "cc", "\r\n" }, expect = "aabbcc" },
      {
        name = "CR without LF should not be considered a line",
        message = { "aa", "bb", "cc", "\r", "dd", "ee", "ff", "\n" },
        expect = "aabbcc\rddeeff",
      },
    }
    for _, case in ipairs(cases) do
      it(case.name, function()
        write_message_step_by_step(write_socket, case.message)
        assert.are.same(case.expect, reader:readline_async())
      end)
    end

    it("buffered data should be read first", function()
      reader._buffer = "aa\n"
      assert.are.same("aa", reader:readline_async())

      write_message_step_by_step(write_socket, { "bb", "cc", "dd\n" })
      assert.are.same("bbccdd", reader:readline_async())
    end)

    it("should return nil when the client kills the connection", function()
      local timer = vim.uv.new_timer()
      timer:start(100, 0, function()
        timer:stop()
        timer:close()
        write_socket:close()
      end)
      assert.are_nil(reader:readline_async())
    end)

    it("should return nil when the server kills the connection", function()
      local timer = vim.uv.new_timer()
      timer:start(100, 0, function()
        timer:stop()
        timer:close()
        reader:close()
      end)
      assert.are_nil(reader:readline_async())
    end)
  end)

  describe("read_async", function()
    it("should read data with the specified size", function()
      write_message_step_by_step(write_socket, { "aa", "bb\n", "cc\r", "dd" })
      assert.are.same("aabb\nc", reader:read_async(6))
      assert.are.same("c\rd", reader:read_async(3))
      assert.are_same("d", reader:read_async(1))
    end)

    it("buffered data should be read first", function()
      reader._buffer = "aa"
      assert.are.same("a", reader:read_async(1))
      write_message_step_by_step(write_socket, { "bb", "cc" })
      assert.are.same("abbcc", reader:read_async(5))
    end)

    it("should return nil when the client kills the connection", function()
      local timer = vim.uv.new_timer()
      timer:start(100, 0, function()
        timer:stop()
        timer:close()
        write_socket:close()
      end)
      assert.are_nil(reader:read_async(1))
    end)

    it("should return nil when the server kills the connection", function()
      local timer = vim.uv.new_timer()
      timer:start(100, 0, function()
        timer:stop()
        timer:close()
        reader:close()
      end)
      assert.are_nil(reader:read_async(1))
    end)
  end)
end)
