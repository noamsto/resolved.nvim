local config = require("resolved.config")
local icons = require("resolved.icons")

---@class resolved.DisplayItem
---@field line integer 1-indexed line number
---@field col integer 0-indexed column (start of URL)
---@field end_col integer 0-indexed column (end of URL)
---@field url string
---@field state resolved.IssueState
---@field is_stale boolean Whether this reference is stale
---@field has_stale_keywords boolean Whether comment contains stale keywords

local M = {}

local NS = vim.api.nvim_create_namespace("resolved")
local NS_URL = vim.api.nvim_create_namespace("resolved_url")

---Log an error safely without blocking
---@param msg string Error message
---@param level integer? Log level (default: DEBUG)
local function log_error(msg, level)
  level = level or vim.log.levels.DEBUG
  vim.schedule(function()
    vim.notify(string.format("[resolved.nvim] %s", msg), level)
  end)
end

-- Define highlight groups
local highlights_defined = false
local function define_highlights()
  if highlights_defined then
    return
  end

  -- Stale URL (closed + keywords): bold + warning color (no strikethrough)
  local warn_hl = vim.api.nvim_get_hl(0, { name = "DiagnosticWarn", link = false })
  vim.api.nvim_set_hl(0, "ResolvedStaleUrl", {
    fg = warn_hl.fg,
    bg = warn_hl.bg,
    bold = true,
  })

  -- Closed URL (no keywords): italic (subtle but clear)
  local comment_hl = vim.api.nvim_get_hl(0, { name = "Comment", link = false })
  vim.api.nvim_set_hl(0, "ResolvedClosedUrl", {
    fg = comment_hl.fg,
    italic = true,
  })

  highlights_defined = true
end

---Determine the tier for a reference
---@param item resolved.DisplayItem
---@return "stale"|"closed"|"open"
local function get_tier(item)
  local state = item.state
  -- "not_planned" means won't fix - workaround still needed, treat as open
  local is_resolved = (state.state == "closed" or state.state == "merged")
    and state.state_reason ~= "not_planned"

  if is_resolved and item.has_stale_keywords then
    return "stale" -- High priority: resolved + keywords
  elseif is_resolved then
    return "closed" -- Low priority: resolved, no keywords
  else
    return "open" -- Still open or not_planned
  end
end

---Format the virtual text for a reference
---@param item resolved.DisplayItem
---@param cfg resolved.Config
---@return string text
---@return string highlight
local function format_virt_text(item, cfg)
  local state = item.state
  local tier = get_tier(item)

  -- Build status text
  local status_text = state.state
  if state.state == "merged" then
    status_text = "merged"
  elseif state.state_reason and state.state_reason ~= vim.NIL then
    status_text = state.state_reason
  end

  if tier == "stale" then
    return string.format(" [%s]", status_text), cfg.highlights.stale
  elseif tier == "closed" then
    return string.format(" [%s]", status_text), cfg.highlights.closed
  else
    return string.format(" [%s]", status_text), cfg.highlights.open
  end
end

---Update display for a buffer
---@param bufnr integer
---@param items resolved.DisplayItem[]
function M.update(bufnr, items)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Clear existing
  M.clear(bufnr)

  -- Ensure highlights are defined
  define_highlights()

  local cfg = config.get()

  for _, item in ipairs(items) do
    local tier = get_tier(item)
    local text, hl = format_virt_text(item, cfg)

    -- Build extmark options for virtual text (inline, right after URL)
    local extmark_opts = {
      virt_text = { { text, hl } },
      virt_text_pos = "inline",
      hl_mode = "combine",
      priority = 100,
    }

    -- Add sign in gutter only for stale (high priority) items
    if tier == "stale" and cfg.signs then
      local sign_icon, sign_hl = icons.stale_sign()
      extmark_opts.sign_text = sign_icon
      extmark_opts.sign_hl_group = sign_hl
    end

    -- Place extmark at end of URL for inline positioning
    local ok, err = pcall(vim.api.nvim_buf_set_extmark, bufnr, NS, item.line - 1, item.end_col, extmark_opts)
    if not ok then
      log_error(string.format("Failed to set extmark at %d:%d: %s", item.line, item.end_col, err))
    end

    -- Highlight URL based on tier
    if tier == "stale" then
      -- High priority: strikethrough + warning color
      local ok, err = pcall(vim.api.nvim_buf_set_extmark, bufnr, NS_URL, item.line - 1, item.col, {
        end_col = item.end_col,
        hl_group = cfg.highlights.stale_url or "ResolvedStaleUrl",
        priority = 200,
      })
      if not ok then
        log_error(string.format("Failed to set stale URL highlight at %d:%d: %s", item.line, item.col, err))
      end
    elseif tier == "closed" then
      -- Low priority: subtle strikethrough
      local ok, err = pcall(vim.api.nvim_buf_set_extmark, bufnr, NS_URL, item.line - 1, item.col, {
        end_col = item.end_col,
        hl_group = cfg.highlights.closed_url or "ResolvedClosedUrl",
        priority = 200,
      })
      if not ok then
        log_error(string.format("Failed to set closed URL highlight at %d:%d: %s", item.line, item.col, err))
      end
    end
    -- Open issues: no URL highlight, just virtual text
  end
end

---Clear all extmarks from a buffer
---@param bufnr integer
function M.clear(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
    vim.api.nvim_buf_clear_namespace(bufnr, NS_URL, 0, -1)
  end
end

---Clear all extmarks and signs from all buffers
function M.clear_all()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    M.clear(bufnr)
  end
end

---Get the namespace ID (for external use)
---@return integer
function M.get_namespace()
  return NS
end

return M
