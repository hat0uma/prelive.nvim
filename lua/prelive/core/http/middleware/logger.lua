local log = require("prelive.core.log")
--- A middleware that logs the request and response to the console.
---@return prelive.http.MiddlewareHandler
return function()
  ---@async
  return function(req, res, donext)
    local request_time = vim.uv.now()
    donext(req, res)
    local response_time = vim.uv.now()
    log.debug(
      '%s "%s %s %s" %d %s (%dms)',
      req.client_ip,
      req.method,
      req.path,
      req.version,
      res:get_status(),
      res.headers:get("Content-Length") or "-",
      response_time - request_time
    )
  end
end
