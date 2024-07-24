local M = {}

--- Get timezone
---@return integer
local function get_timezone()
  local localtime = os.time()
  local gmt_date = os.date("!*t", localtime)

  ---@diagnostic disable-next-line: param-type-mismatch
  local gmtime = os.time(gmt_date)
  return os.difftime(localtime, gmtime)
end

M.timezone = get_timezone()

local MON = {
  Jan = 1,
  Feb = 2,
  Mar = 3,
  Apr = 4,
  May = 5,
  Jun = 6,
  Jul = 7,
  Aug = 8,
  Sep = 9,
  Oct = 10,
  Nov = 11,
  Dec = 12,
}

--- Convert timestamp from RFC1123 date format
---@param date string
---@return integer
function M.from_rfc1123_GMT(date)
  vim.validate("date", date, "string")

  -- for example:
  -- Wed, 21 Oct 2015 07:28:00 GMT
  local pattern = "%a+, (%d+) (%a+) (%d+) (%d+):(%d+):(%d+) (%a+)"
  local day, month, year, hour, min, sec, tz = string.match(date, pattern)
  assert(tz == "GMT")

  month = MON[month]
  local dateparam = { day = day, month = month, year = year, hour = hour, min = min, sec = sec }
  return os.time(dateparam) + M.timezone
end

--- Convert timestamp to RFC1123 date format(GMT)
---@param timestamp integer
---@return string
function M.to_rfc1123_GMT(timestamp)
  vim.validate("timestamp", timestamp, "number")
  return os.date("!%a, %d %b %Y %H:%M:%S GMT", timestamp) ---@type string
end

return M
