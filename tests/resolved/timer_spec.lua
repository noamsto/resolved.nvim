local resolved = require("resolved")

describe("timer race conditions", function()
  before_each(function()
    resolved.setup({ enabled = false })
  end)

  after_each(function()
    resolved.disable()
  end)

  it("should handle rapid buffer changes without crashing", function()
    local bufnr = vim.api.nvim_create_buf(false, true)

    -- Trigger multiple rapid scans
    for i = 1, 10 do
      resolved._debounced_scan(bufnr)
    end

    -- Wait for timers to process
    vim.wait(100)

    -- Should not crash
    assert.is_true(true)
  end)

  it("should handle timer closing during operation", function()
    local bufnr = vim.api.nvim_create_buf(false, true)

    -- Start a debounced scan
    resolved._debounced_scan(bufnr)

    -- Immediately try to start another (should close existing)
    local ok = pcall(function()
      resolved._debounced_scan(bufnr)
    end)

    assert.is_true(ok)
  end)

  it("should clean up timer when buffer is deleted", function()
    local bufnr = vim.api.nvim_create_buf(false, true)

    -- Start a debounced scan
    resolved._debounced_scan(bufnr)

    -- Delete buffer
    vim.api.nvim_buf_delete(bufnr, { force = true })

    -- Wait for cleanup
    vim.wait(100)

    -- Timer should be cleaned up
    assert.is_nil(resolved._debounce_timers[bufnr])
  end)
end)
