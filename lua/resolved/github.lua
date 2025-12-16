---@class resolved.IssueState
---@field state "open"|"closed"|"merged"
---@field state_reason? string For closed issues: "completed", "not_planned", "reopened"
---@field title string
---@field labels string[]
---@field closed_at? string ISO timestamp when closed
---@field merged_at? string ISO timestamp when merged (PRs only)

local M = {}

---@type boolean|nil
local _auth_checked = nil
---@type string|nil
local _auth_error = nil

---Check if gh CLI is authenticated (async version)
---@param callback fun(ok: boolean, err: string?)
function M.check_auth_async(callback)
  -- Check if gh exists
  if vim.fn.executable("gh") ~= 1 then
    callback(false, "gh CLI not found. Install from https://cli.github.com/")
    return
  end

  vim.system({ "gh", "auth", "status" }, {}, function(obj)
    vim.schedule(function()
      if obj.code == 0 then
        callback(true, nil)
      else
        local stderr = obj.stderr or ""
        local msg = "GitHub CLI not authenticated. Run: gh auth login"
        if stderr ~= "" then
          msg = msg .. "\n" .. stderr
        end
        callback(false, msg)
      end
    end)
  end)
end

---Check if gh CLI is available and authenticated (sync version with timeout)
---@return boolean ok True if authenticated
---@return string? error Error message if not authenticated
function M.check_auth()
  -- Return cached result if already checked
  if _auth_checked ~= nil then
    return _auth_checked, _auth_error
  end

  local completed = false
  local result_ok = false
  local result_err = nil

  M.check_auth_async(function(ok, err)
    completed = true
    result_ok = ok
    result_err = err
  end)

  -- Wait with timeout (5 seconds)
  local timeout_ms = 5000
  local waited = vim.wait(timeout_ms, function()
    return completed
  end)

  if not waited then
    _auth_checked = false
    _auth_error = "GitHub CLI auth check timed out after " .. (timeout_ms / 1000) .. " seconds"
    return _auth_checked, _auth_error
  end

  -- Cache the result
  _auth_checked = result_ok
  _auth_error = result_err

  return result_ok, result_err
end

---Reset auth check (for testing)
function M._reset_auth_check()
  _auth_checked = nil
  _auth_error = nil
end

---Build the jq filter for extracting issue/PR data
---@param type "issue"|"pr"
---@return string
local function build_jq_filter(type)
  if type == "pr" then
    return [[{
      state: .state,
      merged: .merged,
      merged_at: .merged_at,
      title: .title,
      labels: [.labels[].name],
      closed_at: .closed_at
    }]]
  else
    return [[{
      state: .state,
      state_reason: .state_reason,
      title: .title,
      labels: [.labels[].name],
      closed_at: .closed_at
    }]]
  end
end

---Fetch issue or PR state from GitHub
---@param owner string Repository owner
---@param repo string Repository name
---@param number integer Issue/PR number
---@param type "issue"|"pr"
---@param callback fun(err?: string, state?: resolved.IssueState)
function M.fetch(owner, repo, number, type, callback)
  local endpoint = type == "pr" and string.format("repos/%s/%s/pulls/%d", owner, repo, number)
    or string.format("repos/%s/%s/issues/%d", owner, repo, number)

  local jq_filter = build_jq_filter(type)

  vim.system({ "gh", "api", endpoint, "--jq", jq_filter }, {}, function(obj)
    vim.schedule(function()
      if obj.code ~= 0 then
        local stderr = obj.stderr or ""
        -- Handle common errors gracefully
        if stderr:match("404") or stderr:match("Not Found") then
          callback(string.format("Issue/PR not found: %s/%s#%d", owner, repo, number))
        elseif stderr:match("401") or stderr:match("403") then
          callback("GitHub API authentication error. Try: gh auth login")
        else
          callback("gh api error: " .. stderr)
        end
        return
      end

      local output = obj.stdout or ""
      local ok, data = pcall(vim.json.decode, output)
      if not ok then
        callback("Failed to parse GitHub response: " .. output)
        return
      end

      -- Determine effective state
      local state = data.state
      if type == "pr" and data.merged then
        state = "merged"
      end

      ---@type resolved.IssueState
      local issue_state = {
        state = state,
        state_reason = data.state_reason,
        title = data.title or "",
        labels = data.labels or {},
        closed_at = data.closed_at,
        merged_at = data.merged_at,
      }

      callback(nil, issue_state)
    end)
  end)
end

---Fetch multiple issues/PRs (sequential for simplicity)
---@param refs {owner: string, repo: string, number: integer, type: "issue"|"pr", url: string}[]
---@param callback fun(results: table<string, {err?: string, state?: resolved.IssueState}>)
function M.fetch_batch(refs, callback)
  local results = {}
  local pending = #refs

  if pending == 0 then
    callback(results)
    return
  end

  for _, ref in ipairs(refs) do
    M.fetch(ref.owner, ref.repo, ref.number, ref.type, function(err, state)
      results[ref.url] = { err = err, state = state }
      pending = pending - 1
      if pending == 0 then
        callback(results)
      end
    end)
  end
end

return M
