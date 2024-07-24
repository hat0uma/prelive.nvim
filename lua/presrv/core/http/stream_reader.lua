---@class presrv.StreamReader
---@field _stream uv_stream_t
---@field _buffer string
---@field on_receive fun()?
local StreamReader = {}

--- Create a new StreamReader object.
---@param stream uv_stream_t The stream to read from.
---@return presrv.StreamReader
function StreamReader:new(stream)
  local obj = {}
  obj._stream = stream
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
---*This function must be called within a coroutine.*
---@return string? line, string? err_msg
function StreamReader:readline_async()
  -- check if the function is called within a coroutine
  local thread = coroutine.running()
  if not thread then
    return nil, "`StreamReader:readline_async` must call in a coroutine"
  end

  return self:_read_and_pop_async(function()
    return self:_pop_line_from_buffer()
  end, thread)
end

---@async
---Read data asynchronously
---*This function must be called within a coroutine.*
---@param size integer
---@return string? line, string? err_msg
function StreamReader:read_async(size)
  -- check if the function is called within a coroutine
  local thread = coroutine.running()
  if not thread then
    return nil, "`StreamReader:read_async` must call in a coroutine"
  end

  return self:_read_and_pop_async(function()
    return self:_pop_data_from_buffer(size)
  end, thread)
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

  return self._buffer:sub(1, size)
end

---@async
---Read data from the stream asynchronously.
---@param read_fn fun():string?
---@param thread thread
---@return string? line, string? err_msg
function StreamReader:_read_and_pop_async(read_fn, thread)
  -- if there is expected data in the buffer, return the line
  local buffered_data = read_fn()
  if buffered_data then
    return buffered_data
  end

  -- otherwise, read from the stream
  self._stream:read_start(vim.schedule_wrap(function(err, data)
    if err then
      return coroutine.resume(thread, nil, err)
    end

    if not data then
      return coroutine.resume(thread, nil, "stream closed.")
    end

    if self.on_receive then
      self.on_receive()
    end

    -- append data to buffer and
    -- PERF: use table.concat for better performance
    self._buffer = self._buffer .. data
    data = read_fn()
    if data then
      return coroutine.resume(thread, data, nil)
    end
  end))

  -- Wait until resume in the callback of `start_read`.
  local data, err = coroutine.yield(thread) ---@type string? ,string?
  self._stream:read_stop()

  if coroutine.status(thread) == "dead" then
    return nil, "coroutine dead"
  end

  return data, err
end

return StreamReader
