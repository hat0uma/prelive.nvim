local log = require("presrv.core.log")
--- A middleware that logs the request and response to the console.
---@return presrv.http.MiddlewareHandler
return function()
  ---@async
  return function(req, res, donext)
    local request_time = os.time()
    donext(req, res)
    local response_time = os.time()
    log.debug(
      '%s "%s %s %s" %d %s (%.3fms)',
      req.client_ip,
      req.method,
      req.path,
      req.version,
      res:get_status(),
      res.headers:get("Content-Length") or "-",
      (response_time - request_time) * 1000
    )
  end
end
