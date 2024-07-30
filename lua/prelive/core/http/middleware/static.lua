local date = require("prelive.core.http.util.date")
local mime = require("prelive.core.http.util.mime")
local status = require("prelive.core.http.status")

--- Render directory listing.
--- This will render a directory listing in HTML format.
---@param directory string The directory to render.
---@param path string The path to render.
---@return string body The rendered directory listing.
local function render_directory(directory, path)
  local body = {
    "<!DOCTYPE html>",
    '<html lang="en">',
    "<head>",
    '<meta charset="utf-8">',
    "</head>",
    "<h1>Index of " .. path .. "</h1>",
    "<hr>",
    "<ul>",
  }
  if path ~= "/" then
    table.insert(body, '<li><a href="../">../</a></li>')
  end
  for name, type in vim.fs.dir(directory) do
    if type == "directory" then
      name = name .. "/"
    end
    table.insert(body, ('<li><a href="%s">%s</a></li>'):format(name, name))
  end
  table.insert(body, "</ul>")
  return table.concat(body, "\r\n")
end

--- @alias prelive.http.middleware.static_prewrite fun(res:prelive.http.Response,filename:string,body:string):string

--- Check file is not modified
---@param req prelive.http.Request
---@param stat uv.aliases.fs_stat_table
---@return boolean
local function is_file_not_modified(req, stat)
  local if_modified_since = req.headers:get("If-Modified-Since")
  if not if_modified_since then
    return false
  end

  local timestamp = date.from_rfc1123_GMT(if_modified_since)
  return timestamp == stat.mtime.sec
end

---@async
---Serve static files.
---@param path string The path prefix of static files.
---@param rootdir string The root directory of static files. It should be an absolute path.
---@param prewrite? prelive.http.middleware.static_prewrite The prewrite hook function.
---@param req prelive.http.Request The request object.
---@param res prelive.http.Response The response object.
local function serve_static(path, rootdir, prewrite, req, res)
  -- normalize requested path
  local requested_path = req.path:gsub("^" .. path, "/")
  local file = vim.fs.normalize(vim.fs.joinpath(rootdir, requested_path))

  -- check directory traversal
  if not vim.startswith(file, rootdir) then
    res:write_header(status.FORBIDDEN)
    return
  end

  local thread = coroutine.running()

  -- check entry exists
  vim.uv.fs_stat(file, function(err, stat)
    coroutine.resume(thread, stat, err)
  end)

  local stat = coroutine.yield() --- @type uv.aliases.fs_stat_table|nil
  if not stat then
    res:write_header(status.NOT_FOUND)
    return
  end

  -- if directory, render directory listing
  if stat.type == "directory" then
    local body = render_directory(file, requested_path)
    res.headers:set("Content-Type", "text/html")
    res:write(body)
    return
  end

  -- if not a file or directory, forbidden
  if stat.type ~= "file" then
    res:write_header(status.FORBIDDEN)
    return
  end

  -- check modified
  if is_file_not_modified(req, stat) then
    res:write_header(status.NOT_MODIFIED)
    return
  end

  -- open file
  vim.uv.fs_open(file, "r", 438, function(err, fd)
    coroutine.resume(thread, fd, err)
  end)

  local fd = coroutine.yield() --- @integer?
  if type(fd) ~= "number" then
    res:write_header(status.INTERNAL_SERVER_ERROR)
    return
  end

  -- read file
  vim.uv.fs_read(fd, stat.size, 0, function(err, data)
    coroutine.resume(thread, data, err)
  end)
  local data = coroutine.yield() ---@type string?

  vim.uv.fs_close(fd)
  if type(data) ~= "string" then
    res:write_header(status.INTERNAL_SERVER_ERROR)
    return
  end

  -- determine mime type
  local ext = vim.fn.fnamemodify(file, ":e")
  local mime_type = mime.from_extension(ext, "text/plain")
  local last_modified = date.to_rfc1123_GMT(stat.mtime.sec)

  -- ok
  res.headers:set("Content-Type", mime_type)
  res.headers:set("Last-Modified", last_modified)
  res.headers:set("Content-Length", tostring(stat.size))
  if prewrite then
    data = prewrite(res, file, data)
  end
  res:write(data)
end

--- A middleware that serves static files.
---@param path string The path prefix of static files.
---@param rootdir string The root directory of static files. It should be an absolute path.
---@param prewrite? prelive.http.middleware.static_prewrite The prewrite hook function.
---@return prelive.http.MiddlewareHandler
return function(path, rootdir, prewrite)
  vim.validate({
    path = { path, "string" },
    rootdir = { rootdir, { "string" } },
    prewrite = { prewrite, { "function", true } },
  })

  rootdir = vim.fs.normalize(rootdir)
  ---@async
  return function(req, res, donext)
    if req.method ~= "GET" then
      res.headers:set("Allow", "GET")
      res:write_header(status.METHOD_NOT_ALLOWED)
    else
      serve_static(path, rootdir, prewrite, req, res)
    end

    if not res:header_written() then
      donext(req, res)
    end
  end
end
