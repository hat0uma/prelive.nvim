local HTTPHeaders = require("prelive.core.http.headers")

describe("HTTPHeaders", function()
  it("should create a new HTTPHeaders object", function()
    local headers = HTTPHeaders:new({
      ["content-type"] = "text/html",
      ["content-length"] = "1024",
    })

    assert.are.same(headers:get("content-type"), "text/html")
    assert.are.same(headers:get("content-length"), "1024")
  end)

  it("should set a header value", function()
    local headers = HTTPHeaders:new({
      ["content-type"] = "text/html",
      ["content-length"] = "1024",
    })

    headers:set("content-type", "application/json")
    headers:set("content-length", "2048")

    assert.are.same(headers:get("content-type"), "application/json")
    assert.are.same(headers:get("content-length"), "2048")
  end)

  it("should case-insensitive get a header value", function()
    local headers = HTTPHeaders:new({})

    headers:set("content-type", "application/json")

    assert.are.same(headers:get("content-type"), "application/json")
    assert.are.same(headers:get("Content-type"), "application/json")
    assert.are.same(headers:get("content-Type"), "application/json")
    assert.are.same(headers:get("Content-Type"), "application/json")
  end)
end)
