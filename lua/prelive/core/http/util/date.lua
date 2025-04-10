local M = {}

local timezone = {
  cache = nil,
}

--- Get timezone offset in seconds
---@return integer timezone offset in seconds
timezone.get = function()
  if timezone.cache then
    return timezone.cache
  end

  local localtime = os.time()
  local gmt_date = os.date("!*t", localtime)

  ---@diagnostic disable-next-line: param-type-mismatch
  local gmtime = os.time(gmt_date)
  timezone.cache = os.difftime(localtime, gmtime)
  return timezone.cache
end

local MON2NUM = {
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

local NUM2WDAY = {
  [1] = "Sun",
  [2] = "Mon",
  [3] = "Tue",
  [4] = "Wed",
  [5] = "Thu",
  [6] = "Fri",
  [7] = "Sat",
}

local NUM2MON = {
  [1] = "Jan",
  [2] = "Feb",
  [3] = "Mar",
  [4] = "Apr",
  [5] = "May",
  [6] = "Jun",
  [7] = "Jul",
  [8] = "Aug",
  [9] = "Sep",
  [10] = "Oct",
  [11] = "Nov",
  [12] = "Dec",
}

--- Convert timestamp from RFC1123 date format
---@param date string
---@return integer
function M.from_rfc1123_GMT(date)
  vim.validate({ date = { date, "string" } })

  -- for example:
  -- Wed, 21 Oct 2015 07:28:00 GMT
  local pattern = "%a+, (%d+) (%a+) (%d+) (%d+):(%d+):(%d+) (%a+)"
  local day, month, year, hour, min, sec, tz = string.match(date, pattern)
  assert(tz == "GMT", "Timezone must be GMT: " .. date)
  month = MON2NUM[month]
  local dateparam = { day = day, month = month, year = year, hour = hour, min = min, sec = sec }
  return os.time(dateparam) + timezone.get()
end

--- Convert timestamp to RFC1123 date format(GMT)
---@param timestamp integer
---@return string
function M.to_rfc1123_GMT(timestamp)
  vim.validate({ timestamp = { timestamp, "number" } })

  ---@type osdate
  local osdate = os.date("!*t", timestamp) ---@diagnostic disable-line: assign-type-mismatch
  local weekday = NUM2WDAY[osdate.wday]
  local month = NUM2MON[osdate.month]

  -- for example:
  -- Wed, 21 Oct 2015 07:28:00 GMT
  return string.format(
    "%s, %02d %s %04d %02d:%02d:%02d GMT",
    weekday,
    osdate.day,
    month,
    osdate.year,
    osdate.hour,
    osdate.min,
    osdate.sec
  )
end

return M
