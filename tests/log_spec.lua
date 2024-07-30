local log = require("prelive.core.log")

local TEST_LOG_DIR = "./test_log"

---Read the contents of a file.
---@param fname string The file path.
---@return string contents
local function read_test_file(fname)
  local fd = vim.uv.fs_open(vim.fs.joinpath(TEST_LOG_DIR, fname), "r", 438)
  if not fd then
    return ""
  end
  local stat = vim.uv.fs_fstat(fd)
  if not stat then
    vim.uv.fs_close(fd)
    return ""
  end

  local data = vim.uv.fs_read(fd, stat.size, -1)
  vim.uv.fs_close(fd)
  ---@diagnostic disable-next-line: return-type-mismatch
  return data or ""
end

local function remove_test_files()
  for file, type in vim.fs.dir(TEST_LOG_DIR) do
    if type == "file" then
      vim.uv.fs_unlink(vim.fs.joinpath(TEST_LOG_DIR, file))
    end
  end
end

describe("log.handlers.FileHandler", function()
  local function create_handler(max_backups, max_file_size)
    return log.handlers.FileHandler:new({
      file_path = vim.fs.joinpath(TEST_LOG_DIR, "test.log"),
      max_backups = max_backups or 3,
      max_file_size = max_file_size or 1024,
    }, log.formatters.StringFormatter:new("{level} {message}"))
  end

  local handler --- @type prelive.log.FileHandler | nil
  before_each(function()
    vim.uv.fs_mkdir(TEST_LOG_DIR, 493)
    remove_test_files()
  end)
  after_each(function()
    if handler then
      handler:close()
    end
  end)

  describe("write", function()
    it("should write a formatted log message to a file", function()
      handler = create_handler()
      handler:write({
        level = vim.log.levels.INFO,
        message = "Hello, world!",
        time = os.time(),
      })
      assert.are_equal("INFO  Hello, world!\n", read_test_file("test.log"))
    end)

    it("should not create log file if max_file_size is 0", function()
      handler = create_handler(3, 0)
      handler:write({ level = vim.log.levels.INFO, message = "aaaa", time = os.time() })
      handler:write({ level = vim.log.levels.INFO, message = "bbbb", time = os.time() })
      handler:write({ level = vim.log.levels.INFO, message = "cccc", time = os.time() })

      assert.is_nil(vim.loop.fs_stat(vim.fs.joinpath(TEST_LOG_DIR, "test.log")))
      assert.is_nil(vim.loop.fs_stat(vim.fs.joinpath(TEST_LOG_DIR, "test.log.1")))
      assert.is_nil(vim.loop.fs_stat(vim.fs.joinpath(TEST_LOG_DIR, "test.log.2")))
    end)
  end)

  describe("rotate", function()
    it("should rotate log file when it reaches max_file_size", function()
      handler = create_handler()
      local resource = {
        { message = ("a"):rep(2048), file = "test.log.1" },
        { message = "bbbb", file = "test.log" },
      }

      for _, v in ipairs(resource) do
        handler:write({
          level = vim.log.levels.INFO,
          message = v.message,
          time = os.time(),
        })
      end

      for _, v in ipairs(resource) do
        assert.are_equal("INFO  " .. v.message .. "\n", read_test_file(v.file))
      end
    end)

    it("should delete the oldest log file when the number of log files exceeds max_backups", function()
      handler = create_handler()
      for i = 1, 5 do
        local level = vim.log.levels.INFO
        local message = tostring(i):rep(1024)
        handler:write({ level = level, message = message, time = os.time() })
      end

      local expectation = {
        { message = ("5"):rep(1024), file = "test.log" },
        { message = ("4"):rep(1024), file = "test.log.1" },
        { message = ("3"):rep(1024), file = "test.log.2" },
        { message = ("2"):rep(1024), file = "test.log.3" },
      }

      -- Check contents of log files
      for _, v in ipairs(expectation) do
        assert.are_equal("INFO  " .. v.message .. "\n", read_test_file(v.file))
      end

      -- Check that the oldest log file has been deleted
      local stat = vim.loop.fs_stat(vim.fs.joinpath(TEST_LOG_DIR, "test.log.4"))
      assert.is_nil(stat)
    end)

    it("should truncate the log file when max_backups is 0", function()
      handler = create_handler(0)
      handler:write({ level = vim.log.levels.INFO, message = ("1"):rep(1024), time = os.time() })
      handler:write({ level = vim.log.levels.INFO, message = "rotated", time = os.time() })

      assert.are_equal("INFO  rotated\n", read_test_file("test.log"))
      local stat = vim.loop.fs_stat(vim.fs.joinpath(TEST_LOG_DIR, "test.log.1"))
      assert.is_nil(stat)
    end)
  end)
end)

describe("log.Logger", function()
  local function create_logger(level)
    local logger = log.new_logger()
    logger.add_file_handler(level or vim.log.levels.INFO, {
      file_path = vim.fs.joinpath(TEST_LOG_DIR, "test.log"),
      max_backups = 3,
      max_file_size = 1024,
    }, "{level} {message}")
    return logger
  end

  local logger --- @type prelive.log.Logger | nil
  before_each(function()
    vim.uv.fs_mkdir(TEST_LOG_DIR, 493)
    remove_test_files()
  end)
  after_each(function()
    if logger then
      logger.close()
    end
  end)

  describe("write", function()
    it("should log messages at the logger's log level", function()
      logger = create_logger()
      logger.write(vim.log.levels.INFO, "%s %s", "Hello,", "world!")
      assert.are_equal("INFO  Hello, world!\n", read_test_file("test.log"))
    end)

    it("should not log messages below the logger's log level", function()
      logger = create_logger()
      logger.write(vim.log.levels.DEBUG, "Hello, world!")
      assert.are_equal("", read_test_file("test.log"))
      logger.write(vim.log.levels.WARN, "Hello, world!")
      assert.are_equal("WARN  Hello, world!\n", read_test_file("test.log"))
    end)
  end)

  describe("add_handler", function()
    it("should add a handler to the logger", function()
      logger = create_logger()
      logger.add_file_handler(vim.log.levels.INFO, {
        file_path = vim.fs.joinpath(TEST_LOG_DIR, "test2.log"),
        max_backups = 1,
        max_file_size = 1024,
      }, "logger2 {level} {message}")

      logger.write(vim.log.levels.INFO, "Hello, world!")
      assert.are_equal("INFO  Hello, world!\n", read_test_file("test.log"))
      assert.are_equal("logger2 INFO  Hello, world!\n", read_test_file("test2.log"))
    end)
  end)

  describe("log levels", function()
    it("should have a log level of TRACE", function()
      logger = create_logger(vim.log.levels.TRACE)
      logger.trace("")
      assert.are_equal("TRACE \n", read_test_file("test.log"))
    end)
    it("should have a log level of DEBUG", function()
      logger = create_logger(vim.log.levels.TRACE)
      logger.debug("")
      assert.are_equal("DEBUG \n", read_test_file("test.log"))
    end)
    it("should have a log level of INFO", function()
      logger = create_logger(vim.log.levels.TRACE)
      logger.info("")
      assert.are_equal("INFO  \n", read_test_file("test.log"))
    end)
    it("should have a log level of WARNING", function()
      logger = create_logger(vim.log.levels.TRACE)
      logger.warn("")
      assert.are_equal("WARN  \n", read_test_file("test.log"))
    end)
    it("should have a log level of ERROR", function()
      logger = create_logger(vim.log.levels.TRACE)
      logger.error("")
      assert.are_equal("ERROR \n", read_test_file("test.log"))
    end)
  end)
end)
