local M = {}

M._is_windows = vim.uv.os_uname().sysname:find("Windows") ~= nil

--- Check the path is absolute.
---@param path string
---@return boolean
function M.is_absolute_path(path)
  if M._is_windows then
    return path:match("^%a:[/\\]") ~= nil or path:match("^[/\\][/\\]") ~= nil
  else
    return path:match("^/") ~= nil
  end
end

return M
