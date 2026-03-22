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

local function define_highlights()
  local warn_hl = vim.api.nvim_get_hl(0, { name = "DiagnosticWarn", link = false })
  vim.api.nvim_set_hl(0, "ResolvedStaleUrl", {
    fg = warn_hl.fg,
    bg = warn_hl.bg,
    bold = true,
  })

  local comment_hl = vim.api.nvim_get_hl(0, { name = "Comment", link = false })
  vim.api.nvim_set_hl(0, "ResolvedClosedUrl", {
    fg = comment_hl.fg,
    italic = true,
  })
end

---"not_planned" means won't fix — workaround is still needed, so treat as open
---@param state resolved.IssueState
---@return boolean
local function is_resolved(state)
  return (state.state == "closed" or state.state == "merged")
    and state.state_reason ~= "not_planned"
end

---@param state resolved.IssueState
---@param has_stale_keywords boolean
---@return boolean
function M.is_stale(state, has_stale_keywords)
  return is_resolved(state) and has_stale_keywords
end

---@param item resolved.DisplayItem
---@return "stale"|"closed"|"open"
local function get_tier(item)
  if is_resolved(item.state) and item.has_stale_keywords then
    return "stale"
  elseif is_resolved(item.state) then
    return "closed"
  else
    return "open"
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

  local url_highlight_groups = {
    stale = cfg.highlights.stale_url or "ResolvedStaleUrl",
    closed = cfg.highlights.closed_url or "ResolvedClosedUrl",
  }

  for _, item in ipairs(items) do
    local tier = get_tier(item)
    local text, hl = format_virt_text(item, cfg)

    local extmark_opts = {
      virt_text = { { text, hl } },
      virt_text_pos = "inline",
      hl_mode = "combine",
      priority = 100,
    }

    if tier == "stale" and cfg.signs then
      local sign_icon, sign_hl = icons.stale_sign()
      extmark_opts.sign_text = sign_icon
      extmark_opts.sign_hl_group = sign_hl
    end

    local ok, err =
      pcall(vim.api.nvim_buf_set_extmark, bufnr, NS, item.line - 1, item.end_col, extmark_opts)
    if not ok then
      log_error(string.format("Failed to set extmark at %d:%d: %s", item.line, item.end_col, err))
    end

    local url_hl = url_highlight_groups[tier]
    if url_hl then
      ok, err = pcall(vim.api.nvim_buf_set_extmark, bufnr, NS_URL, item.line - 1, item.col, {
        end_col = item.end_col,
        hl_group = url_hl,
        priority = 200,
      })
      if not ok then
        log_error(
          string.format("Failed to set URL highlight at %d:%d: %s", item.line, item.col, err)
        )
      end
    end
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
