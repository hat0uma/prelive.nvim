local DEFAULT_POLLING_INTERVAL = 100

---Polls for changes in the specified files.
---@class prelive.Watcher
---@field _dir string
---@field _timer uv_timer_t
---@field _watch_files table<string,{ stat?: uv.aliases.fs_stat_table } >
local Watcher = {}

--- Create a new prelive.Watcher.
---@param dir string The directory to watch.
---@param interval? integer The interval to poll for changes in milliseconds.
---@return prelive.Watcher
function Watcher:new(dir, interval)
  local obj = {}
  obj._interval = interval or DEFAULT_POLLING_INTERVAL
  obj._dir = vim.fs.normalize(dir)
  obj._timer = vim.uv.new_timer()
  obj._watch_files = {}

  setmetatable(obj, self)
  self.__index = self
  return obj
end

--- start watching the directory.
---@param callback fun(path: string)
function Watcher:watch(callback)
  --- Polling for changes in the specified files.
  local function on_timeout()
    for file, entry in pairs(self._watch_files) do
      vim.uv.fs_stat(file, function(err, stat)
        if self:_is_modified(entry.stat, stat) then
          entry.stat = stat
          callback(file)
        end
      end)
    end
  end
  self._timer:start(0, DEFAULT_POLLING_INTERVAL, vim.schedule_wrap(on_timeout))
end

function Watcher:add_watch_file(file)
  file = vim.fs.normalize(file)
  if self._watch_files[file] then
    return
  end

  vim.uv.fs_stat(file, function(err, stat)
    self._watch_files[file] = { stat = stat }
  end)
end

function Watcher:close()
  self._watch_files = {}
  if not self._timer:is_closing() then
    self._timer:stop()
    self._timer:close()
  end
end

--- Check if the file is modified, created, or removed.
---@param prev_stat? uv.aliases.fs_stat_table
---@param current_stat? uv.aliases.fs_stat_table
---@return boolean
function Watcher:_is_modified(prev_stat, current_stat)
  -- file is not exists or created.
  if not prev_stat then
    return current_stat ~= nil
  end

  -- file is not exists or removed.
  if not current_stat then
    return prev_stat ~= nil
  end

  -- file is modified
  return prev_stat.mtime.sec ~= current_stat.mtime.sec or prev_stat.size ~= current_stat.size
end

return Watcher
