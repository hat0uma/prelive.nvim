--- @class prelive.Util
local M = {}

M._is_windows = vim.uv.os_uname().sysname:find("Windows") ~= nil

--- Check the path is absolute.
--- @param path string
--- @return boolean
function M.is_absolute_path(path)
  if vim.fn.has("nvim-0.11") == 1 then
    vim.validate("path", path, "string", false)
  else
    vim.validate({ path = { path, "string" } })
  end

  if M._is_windows then
    return path:match("^%a:[/\\]") ~= nil or path:match("^[/\\][/\\]") ~= nil
  end

  return path:match("^/") ~= nil
end

return M

-- vim:ts=2:sts=2:sw=2:et:ai:si:sta:
