local M = {}

--- @type table<string, string[][]>
local browser_candidates = {
  ["windows"] = {
    { "rundll32", "url.dll,FileProtocolHandler", "{url}" },
  },
  ["unix"] = {
    { "xdg-open", "{url}" },
    { "x-www-browser", "{url}" },
    { "www-browser", "{url}" },
  },
  ["mac"] = {
    { "open", "{url}" },
  },
  ["wsl"] = {
    { "wslview", "{url}" },
    { "rundll32.exe", "url.dll,FileProtocolHandler", "{url}" },
    { "/mnt/c/WINDOWS/System32/rundll32.exe", "url.dll,FileProtocolHandler", "{url}" },
    { "/mnt/c/Windows/System32/rundll32.exe", "url.dll,FileProtocolHandler", "{url}" },
  },
}

--- Get the system name.
---@return "windows" | "unix" | "mac" | "wsl" | nil
local function get_sysname()
  local uname = vim.uv.os_uname()
  if uname.sysname:find("Windows") then
    return "windows"
  end

  if uname.sysname == "Darwin" then
    return "mac"
  end

  if uname.sysname == "Linux" then
    if uname.version:lower():find("microsoft") then
      return "wsl"
    else
      return "unix"
    end
  end

  if uname.sysname == "FreeBSD" then
    return "unix"
  end

  return nil
end

--- Inject the URL into the command.
---@param cmd string[]
---@param url string
---@return string[]
local function inject_url(cmd, url)
  ---@diagnostic disable-next-line: no-unknown
  return vim.tbl_map(function(arg)
    return arg:gsub("{url}", url)
  end, cmd)
end

--- Open the URL in the system browser.
---@param url string
---@param on_exit? fun(out: vim.SystemCompleted)
---@return vim.SystemObj object @see `vim.system()`
function M.open_system(url, on_exit)
  local sysname = get_sysname()
  if not sysname then
    error("Unsupported system")
  end

  -- find a browser
  local candidates = browser_candidates[sysname]
  for _, candidate in ipairs(candidates) do
    local cmd = candidate[1]
    if vim.fn.executable(cmd) ~= 0 then
      return vim.system(inject_url(candidate, url), { text = true }, on_exit)
    end
  end

  -- no browser found
  local executables = vim.tbl_map(
    ---@param c string[]
    ---@return string
    function(c)
      return c[1]
    end,
    candidates
  )
  local msg = string.format("No browser found: %s", table.concat(executables, ","))
  error(msg)
end

return M
