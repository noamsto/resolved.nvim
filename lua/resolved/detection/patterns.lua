---@class resolved.UrlMatch
---@field url string Full URL
---@field owner string Repository owner
---@field repo string Repository name
---@field number integer Issue/PR number
---@field type "issue"|"pr"
---@field start_col integer 0-indexed start column within text
---@field end_col integer 0-indexed end column within text

local M = {}

-- GitHub URL pattern
-- Matches: https://github.com/owner/repo/issues/123
--          https://github.com/owner/repo/pull/456
-- Owner/repo can contain alphanumeric, hyphen, underscore, dot
local GITHUB_PATTERN = "https?://github%.com/([%w%-%.]+)/([%w%-%.]+)/(issues?)/(%d+)"
local GITHUB_PR_PATTERN = "https?://github%.com/([%w%-%.]+)/([%w%-%.]+)/(pull)/(%d+)"

---Validates a GitHub repository component (owner or repo name)
---@param str string The component to validate
---@return boolean True if valid
local function is_valid_repo_component(str)
  if not str or str == "" then
    return false
  end

  -- GitHub allows alphanumeric, hyphens, and dots
  -- But not leading/trailing dots or consecutive dots
  if str:match("^%.") or str:match("%.$") or str:match("%.%.") then
    return false
  end

  -- Must only contain allowed characters
  if not str:match("^[%w%-%.]+$") then
    return false
  end

  return true
end

---Extract all GitHub URLs from text
---@param text string
---@return resolved.UrlMatch[]
function M.extract_urls(text)
  local matches = {}

  local url_patterns = {
    { pattern = GITHUB_PATTERN, type = "issue" },
    { pattern = GITHUB_PR_PATTERN, type = "pr" },
  }

  for _, pat in ipairs(url_patterns) do
    local search_start = 1
    while true do
      local start_pos, end_pos, owner, repo, _, number_str = text:find(pat.pattern, search_start)
      if not start_pos then
        break
      end

      if is_valid_repo_component(owner) and is_valid_repo_component(repo) then
        table.insert(matches, {
          url = text:sub(start_pos, end_pos),
          owner = owner,
          repo = repo,
          number = tonumber(number_str),
          type = pat.type,
          start_col = start_pos - 1,
          end_col = end_pos,
        })
      end
      search_start = end_pos + 1
    end
  end

  -- Sort by position
  table.sort(matches, function(a, b)
    return a.start_col < b.start_col
  end)

  return matches
end

---Check if text contains any stale keywords (case-insensitive)
---@param text string
---@param keywords string[]
---@return boolean
function M.has_stale_keywords(text, keywords)
  local lower_text = text:lower()
  for _, keyword in ipairs(keywords) do
    if lower_text:find(keyword:lower(), 1, true) then
      return true
    end
  end
  return false
end

return M
