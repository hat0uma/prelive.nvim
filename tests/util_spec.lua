local util = require("prelive.util")

describe("util", function()
  describe("is_absolute", function()
    it("for windows", function()
      util._is_windows = true
      assert.are_true(util.is_absolute_path("C:/Users/test"))
      assert.are_true(util.is_absolute_path("C:\\Users\\test"))
      assert.are_true(util.is_absolute_path("c:/Users/test"))
      assert.are_true(util.is_absolute_path("c:\\Users\\test"))
      assert.are_true(util.is_absolute_path("//server/share"))
      assert.are_true(util.is_absolute_path("\\\\server\\share"))
      assert.are_false(util.is_absolute_path("\\Windows"))
      assert.are_false(util.is_absolute_path("/Windows"))
      assert.are_false(util.is_absolute_path("c:Users"))
    end)

    it("for unix", function()
      util._is_windows = false
      assert.are_true(util.is_absolute_path("/home/test"))
    end)
  end)
end)
