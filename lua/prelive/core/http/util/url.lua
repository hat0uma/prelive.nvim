local M = {}

--- decode url
--- @param url string The url to decode.
--- @return string decoded The decoded url.
function M.decode(url)
  if vim.fn.has("nvim-0.11") == 1 then
    vim.validate("url", url, "string", false)
  else
    vim.validate({ url = { url, "string" } })
  end

  -- replace + with %20(space) then decode
  url = url:gsub("%+", "%%20")
  return vim.uri_decode(url)
end

--- parse url elements
--- This will parse the url and return the base, fragment, and query elements.
--- base: the base url without fragment and query. e.g. /path/to/file or http://example.com/path/to/file
--- @param url string The url to parse.
--- @return {base:string, fragment: string, query:string} elements The parsed elements.
function M.parse(url)
  if vim.fn.has("nvim-0.11") == 1 then
    vim.validate("url", url, "string", false)
  else
    vim.validate({ url = { url, "string" } })
  end

  local rest = url

  -- find fragment
  local fragment = ""
  local fragment_start = rest:find("%#")
  if fragment_start ~= nil then
    fragment = rest:sub(fragment_start + 1)
    rest = rest:sub(1, fragment_start - 1)
  end

  -- find parameters
  local query = ""
  local query_start = rest:find("%?")
  if query_start ~= nil then
    query = rest:sub(query_start + 1)
    rest = rest:sub(1, query_start - 1)
  end
  return {
    base = rest,
    fragment = fragment,
    query = query,
  }
end

return M

-- vim:ts=2:sts=2:sw=2:et:ai:si:sta:
