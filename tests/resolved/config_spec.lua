local config = require("resolved.config")

describe("configuration validation", function()
  it("should reject invalid cache_ttl type", function()
    assert.has_error(function()
      config.setup({ cache_ttl = "five" })
    end)
  end)

  it("should reject negative cache_ttl", function()
    assert.has_error(function()
      config.setup({ cache_ttl = -100 })
    end)
  end)

  it("should reject zero cache_ttl", function()
    assert.has_error(function()
      config.setup({ cache_ttl = 0 })
    end)
  end)

  it("should reject invalid debounce_ms type", function()
    assert.has_error(function()
      config.setup({ debounce_ms = "fast" })
    end)
  end)

  it("should reject invalid enabled type", function()
    assert.has_error(function()
      config.setup({ enabled = "yes" })
    end)
  end)

  it("should reject invalid icons type", function()
    assert.has_error(function()
      config.setup({ icons = "emoji" })
    end)
  end)

  it("should accept valid configuration", function()
    assert.has_no.errors(function()
      config.setup({
        cache_ttl = 600,
        debounce_ms = 500,
        enabled = true,
        icons = {
          stale = "!",
          closed = "x",
          open = "o"
        }
      })
    end)
  end)

  it("should accept empty configuration", function()
    assert.has_no.errors(function()
      config.setup({})
    end)
  end)

  it("should accept nil configuration", function()
    assert.has_no.errors(function()
      config.setup(nil)
    end)
  end)
end)
