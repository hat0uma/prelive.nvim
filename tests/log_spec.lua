local log = require("presrv.core.log")

describe("log.Logger", function()
  local logger = log.new_logger(log.levels.INFO)

  describe("write", function()
    it("should log messages at the logger's log level", function() end)
    it("should not log messages below the logger's log level", function() end)
  end)

  describe("add_handler", function()
    it("should add a handler to the logger", function() end)
  end)

  describe("log levels", function()
    it("should have a log level of TRACE", function() end)
    it("should have a log level of DEBUG", function() end)
    it("should have a log level of INFO", function() end)
    it("should have a log level of WARNING", function() end)
    it("should have a log level of ERROR", function() end)
    it("should have a log level of CRITICAL", function() end)
  end)
end)

describe("log.handlers.FileHandler", function()
  local handler = log.handlers.FileHandler:new({
    file_path = "test.log",
    max_backups = 3,
    max_file_size = 1024,
  })

  describe("write", function()
    it("should write a formatted log message to a file", function() end)
    it("should handle errors gracefully", function() end)
  end)

  describe("rotate", function()
    it("should rotate log file when it reaches max_file_size", function() end)
    it("should delete the oldest log file when the number of log files exceeds max_backups", function() end)
    it("should truncate the log file when max_backups is 0", function() end)
  end)
end)

describe("log.handlers.NotifyHandler", function()
  local handler = log.handlers.NotifyHandler:new({
    title = "presrv",
    format = "{message}",
  })

  describe("write", function()
    it("should write a formatted log message to a notification", function() end)
    it("should handle errors gracefully", function() end)
  end)
end)

describe("log.formatters.StringFormatter", function()
  local formatter = log.formatters.StringFormatter:new("{level} [time:%Y-%m-%d %H:%M:%S] {message}")

  describe("format", function()
    it("should format a log message using the formatter's format string", function() end)
    it("should handle unknown log levels gracefully", function() end)
  end)
end)
