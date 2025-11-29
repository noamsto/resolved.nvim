local display = require("resolved.display")

describe("display module", function()
  local bufnr

  before_each(function()
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "-- https://github.com/owner/repo/issues/123"
    })
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("should update display with stale issue", function()
    assert.has_no.errors(function()
      display.update(bufnr, {
        {
          url = "https://github.com/owner/repo/issues/123",
          line = 1,
          col = 4,
          end_col = 47,
          state = {
            state = "closed",
            state_reason = "completed",
            title = "Test Issue",
            labels = {},
          },
          is_stale = true,
          has_stale_keywords = true,
        }
      })
    end)
  end)

  it("should update display with closed non-stale issue", function()
    assert.has_no.errors(function()
      display.update(bufnr, {
        {
          url = "https://github.com/owner/repo/issues/123",
          line = 1,
          col = 4,
          end_col = 47,
          state = {
            state = "closed",
            state_reason = "completed",
            title = "Test Issue",
            labels = {},
          },
          is_stale = false,
          has_stale_keywords = false,
        }
      })
    end)
  end)

  it("should update display with open issue", function()
    assert.has_no.errors(function()
      display.update(bufnr, {
        {
          url = "https://github.com/owner/repo/issues/123",
          line = 1,
          col = 4,
          end_col = 47,
          state = {
            state = "open",
            title = "Test Issue",
            labels = {},
          },
          is_stale = false,
          has_stale_keywords = false,
        }
      })
    end)
  end)

  it("should update display with merged PR", function()
    assert.has_no.errors(function()
      display.update(bufnr, {
        {
          url = "https://github.com/owner/repo/pull/123",
          line = 1,
          col = 4,
          end_col = 47,
          state = {
            state = "merged",
            title = "Test PR",
            labels = {},
            merged_at = "2024-01-01T00:00:00Z",
          },
          is_stale = false,
          has_stale_keywords = false,
        }
      })
    end)
  end)

  it("should clear display", function()
    -- First add some extmarks
    display.update(bufnr, {
      {
        url = "https://github.com/owner/repo/issues/123",
        line = 1,
        col = 4,
        end_col = 47,
        state = {
          state = "open",
          title = "Test Issue",
          labels = {},
        },
        is_stale = false,
        has_stale_keywords = false,
      }
    })

    -- Then clear
    assert.has_no.errors(function()
      display.clear(bufnr)
    end)
  end)

  it("should handle invalid buffer gracefully", function()
    local invalid_buf = 9999
    assert.has_no.errors(function()
      display.update(invalid_buf, {})
    end)
  end)

  it("should clear all buffers", function()
    assert.has_no.errors(function()
      display.clear_all()
    end)
  end)

  it("should return namespace ID", function()
    local ns = display.get_namespace()
    assert.is_number(ns)
    assert.is_true(ns > 0)
  end)
end)
