--- This module monitors file changes.
--- It detects changes in files by polling and invokes a callback function when changes are detected.
--- Initially, I used `vim.uv.fs_event`, but it didn't work correctly across different platforms and
--- it became slow when there were many files. Therefore, I switched to polling specific files instead.

local DEFAULT_POLLING_INTERVAL = 100

--- @class prelive.Watcher
--- @field _timer uv.uv_timer_t
--- @field _watch_files table<string, { stat?: uv.fs_stat.result }>
local Watcher = {}

--- Create a new prelive.Watcher.
--- @param interval? integer The interval to poll for changes in milliseconds.
--- @return prelive.Watcher
function Watcher:new(interval)
  if vim.fn.has("nvim-0.11") == 1 then
    vim.validate("interval", interval, "number", true, "integer")
  else
    vim.validate({ interval = { interval, { "number", "nil" } } })
  end

  local obj = {}
  obj._interval = interval or DEFAULT_POLLING_INTERVAL
  obj._timer = vim.uv.new_timer()
  obj._watch_files = {}

  setmetatable(obj, self)
  self.__index = self
  return obj
end

--- Start watching the files.
--- When the file is modified, the callback function is called with the path of the file.
--- The files to watch are added with `add_watch_file`.
--- @param callback fun(path: string)
function Watcher:watch(callback)
  --- Polling for changes in the specified files.
  local function on_timeout()
    for file, entry in pairs(self._watch_files) do
      vim.uv.fs_stat(file, function(_, stat)
        if self:_is_modified(entry.stat, stat) then
          entry.stat = stat
          callback(file)
        end
      end)
    end
  end
  self._timer:start(0, DEFAULT_POLLING_INTERVAL, vim.schedule_wrap(on_timeout))
end

--- Add a file to watch.
--- @param file string The file to watch.
function Watcher:add_watch_file(file)
  if vim.fn.has("nvim-0.11") == 1 then
    vim.validate("file", file, "string", false)
  else
    vim.validate({ file = { file, "string" } })
  end
  file = vim.fs.normalize(file)
  if self._watch_files[file] then
    return
  end

  vim.uv.fs_stat(file, function(_, stat)
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
--- @param prev_stat? uv.fs_stat.result
--- @param current_stat? uv.fs_stat.result
--- @return boolean
function Watcher:_is_modified(prev_stat, current_stat)
  --- File does not exist or created.
  if not prev_stat then
    return current_stat ~= nil
  end

  --- File does not exist or has been removed.
  if not current_stat then
    return prev_stat ~= nil
  end

  --- File is modified
  return prev_stat.mtime.sec ~= current_stat.mtime.sec or prev_stat.size ~= current_stat.size
end

return Watcher

-- vim:ts=2:sts=2:sw=2:et:ai:si:sta:
