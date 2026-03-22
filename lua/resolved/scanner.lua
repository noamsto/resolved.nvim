---## Indexing Conventions
---All line numbers returned are **1-indexed** (Neovim convention for user-facing APIs).
---All column numbers are **0-indexed** (Neovim API convention for nvim_buf_* functions).
---
---@module resolved.scanner

local treesitter = require("resolved.detection.treesitter")
local patterns = require("resolved.detection.patterns")
local config = require("resolved.config")

---@class resolved.Reference
---@field url string Full GitHub URL
---@field owner string Repository owner
---@field repo string Repository name
---@field type "issue"|"pr"
---@field number integer Issue/PR number
---@field line integer 1-indexed line number (Neovim convention)
---@field col integer 0-indexed column (start of URL, Neovim API convention)
---@field end_col integer 0-indexed column (end of URL, exclusive)
---@field comment_text string Full comment text containing the URL
---@field has_stale_keywords boolean Whether comment contains stale keywords

local M = {}

---Scan a buffer for GitHub issue/PR references in comments
---@param bufnr integer
---@return resolved.Reference[]
function M.scan(bufnr)
  local cfg = config.get()
  local comments = treesitter.get_comments(bufnr)
  local references = {}

  for _, comment in ipairs(comments) do
    local urls = patterns.extract_urls(comment.text)
    local has_keywords = patterns.has_stale_keywords(comment.text, cfg.stale_keywords)

    for _, url_match in ipairs(urls) do
      -- Filter out PRs unless include_prs is enabled
      if url_match.type == "issue" or cfg.include_prs then
        -- Calculate absolute line/col position
        -- For multi-line comments, we need to find which line the URL is on
        local url_line = comment.line
        local url_col = comment.col + url_match.start_col

        -- Handle multi-line comments: find actual line of URL
        local text_before_url = comment.text:sub(1, url_match.start_col)
        local newlines_before = select(2, text_before_url:gsub("\n", ""))
        if newlines_before > 0 then
          url_line = comment.line + newlines_before
          -- Find column on that line
          local last_newline = text_before_url:match(".*\n()")
          if last_newline then
            -- Calculate column with bounds check to ensure non-negative
            url_col = math.max(0, url_match.start_col - last_newline + 1)
          end
        end

        local url_end_col = url_col + #url_match.url

        table.insert(references, {
          url = url_match.url,
          owner = url_match.owner,
          repo = url_match.repo,
          type = url_match.type,
          number = url_match.number,
          line = url_line + 1, -- Convert to 1-indexed (see module docs)
          col = url_col,
          end_col = url_end_col,
          comment_text = comment.text,
          has_stale_keywords = has_keywords,
        })
      end
    end
  end

  return references
end

return M
