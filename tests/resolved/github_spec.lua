local github = require("resolved.github")

describe("GitHub auth", function()
  it("should check auth asynchronously", function()
    local completed = false
    local auth_ok = false
    local err_msg = nil

    github.check_auth_async(function(ok, err)
      completed = true
      auth_ok = ok
      err_msg = err
    end)

    -- Wait for async operation
    vim.wait(5000, function() return completed end)

    assert.is_true(completed)
    -- Don't assert auth_ok since it depends on environment
  end)

  it("should timeout if gh command hangs", function()
    -- This test would require mocking, skip for now
    pending("requires mocking gh command")
  end)
end)
