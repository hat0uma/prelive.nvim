---@class prelive.StreamReader
---@field _stream uv_stream_t
---@field _buffer string
---@field _reading boolean
---@field _thread thread
---@field on_receive fun()?
local StreamReader = {}

--- Create a new StreamReader object.
---@param stream uv_stream_t The stream to read from.
---@param thread thread The coroutine to run the reader.
---@return prelive.StreamReader
function StreamReader:new(stream, thread)
  vim.validate({
    stream = { stream, "userdata" },
    thread = { thread, "thread" },
  })

  local obj = {}
  obj._stream = stream
  obj._thread = thread
  obj._reading = false
  obj._buffer = ""
  obj.on_reveive = nil --- @type fun()?
  setmetatable(obj, self)
  self.__index = self
  return obj
end

local Bytes = {
  CR = ("\r"):byte(),
  LF = ("\n"):byte(),
}

---@async
---Read a line from the stream asynchronously.
---@return string? line, string? err_msg
function StreamReader:readline_async()
  return self:_read_and_pop_async(function()
    return self:_pop_line_from_buffer()
  end)
end

---@async
---Read data asynchronously
---*This function must be called within a coroutine.*
---@param size integer
---@return string? line, string? err_msg
function StreamReader:read_async(size)
  return self:_read_and_pop_async(function()
    return self:_pop_data_from_buffer(size)
  end)
end

--- Pop a line from the buffer
--- A line here refers to a string that ends with LF or CRLF.
--- A single CR is not considered the end of a line.
---@return string? line
function StreamReader:_pop_line_from_buffer()
  -- find LF.
  local newline = self._buffer:find("\n")
  if not newline then
    return nil
  end

  -- If it is CRLF, shift the end of the line by one.
  local line_end = newline - 1
  if self._buffer:byte(newline - 1) == Bytes.CR then
    line_end = newline - 2
  end

  -- Get the line and remove it from the buffer.
  local line = self._buffer:sub(1, line_end)
  self._buffer = self._buffer:sub(newline + 1)
  return line
end

---@async
---Read a line, but skip empty line
---@return string? line ,string? err_msg
function StreamReader:readline_skip_empty_async()
  while true do
    local line, err_msg = self:readline_async()
    if not line then
      return nil, err_msg
    end
    if line ~= "" then
      return line
    end
  end
end

--- Pop specified size from the buffer
---@param size integer
---@return string? line
function StreamReader:_pop_data_from_buffer(size)
  if #self._buffer < size then
    return nil
  end

  -- Get the data and remove it from the buffer.
  local data = self._buffer:sub(1, size)
  self._buffer = self._buffer:sub(size + 1)
  return data
end

---@async
---Read data from the stream asynchronously.
---@param read_fn fun():string?
---@return string? line, string? err_msg
function StreamReader:_read_and_pop_async(read_fn)
  -- if there is expected data in the buffer, return the line
  local buffered_data = read_fn()
  if buffered_data then
    return buffered_data
  end

  -- otherwise, read from the stream
  self._stream:read_start(vim.schedule_wrap(function(err, data)
    if err then
      return coroutine.resume(self._thread, nil, err)
    end

    if not data then
      return coroutine.resume(self._thread, nil, "stream closed.")
    end

    if self.on_receive then
      self.on_receive()
    end

    -- append data to buffer and
    -- PERF: use table.concat for better performance
    self._buffer = self._buffer .. data
    data = read_fn()
    if data then
      return coroutine.resume(self._thread, data, nil)
    end
  end))

  -- Wait until resume in the callback of `start_read`.
  self._reading = true
  local data, err = coroutine.yield() ---@type string? ,string?
  self._reading = false
  self._stream:read_stop()

  if coroutine.status(self._thread) == "dead" then
    return nil, "coroutine dead"
  end

  return data, err
end

--- Close the stream reader and the stream.
function StreamReader:close()
  if not self._stream:is_closing() then
    self._stream:close()
  end

  if self._reading and coroutine.status(self._thread) == "suspended" then
    coroutine.resume(self._thread, nil, "stream closed.")
  end
end

return StreamReader
