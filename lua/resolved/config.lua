---@class resolved.FiletypeConfig
---@field node_types string[] Treesitter node types to search for URLs

---@class resolved.Config
---@field enabled boolean Initial enabled state
---@field cache_ttl integer Cache TTL in seconds
---@field debounce_ms integer Debounce delay in milliseconds
---@field stale_keywords string[] Keywords indicating acknowledged stale references
---@field filetypes table<string, resolved.FiletypeConfig|false> Per-filetype treesitter config
---@field icons table<string, string> Icons for display
---@field highlights table<string, string> Highlight groups

local M = {}

---@type resolved.Config
M.defaults = {
  enabled = true,
  cache_ttl = 300, -- 5 minutes
  debounce_ms = 500,
  stale_keywords = {
    "TODO",
    "FIXME",
    "HACK",
    "XXX",
    "WA",
    "workaround",
    "temporary",
    "temp",
    "WIP",
    "blocked",
    "waiting",
    "upstream",
  },
  filetypes = {
    lua = { node_types = { "comment" } },
    python = { node_types = { "comment", "string" } },
    go = { node_types = { "comment" } },
    javascript = { node_types = { "comment" } },
    typescript = { node_types = { "comment" } },
    typescriptreact = { node_types = { "comment" } },
    javascriptreact = { node_types = { "comment" } },
    rust = { node_types = { "line_comment", "block_comment" } },
    nix = { node_types = { "comment" } },
    c = { node_types = { "comment" } },
    cpp = { node_types = { "comment" } },
    java = { node_types = { "comment", "line_comment", "block_comment" } },
    ruby = { node_types = { "comment" } },
    sh = { node_types = { "comment" } },
    bash = { node_types = { "comment" } },
    zsh = { node_types = { "comment" } },
    yaml = { node_types = { "comment" } },
    toml = { node_types = { "comment" } },
    ["*"] = { node_types = { "comment" } },
  },
  icons = {
    stale = "⚠",
    stale_sign = "⚠",
    open = "",
  },
  highlights = {
    -- High priority: closed + keywords (warning/yellow)
    stale = "DiagnosticWarn",
    stale_sign = "DiagnosticWarn",
    stale_url = "ResolvedStaleUrl",
    -- Low priority: closed, no keywords (hint/blue-ish)
    closed = "DiagnosticHint",
    closed_url = "ResolvedClosedUrl",
    -- Open issues (green/ok)
    open = "DiagnosticOk",
  },
  -- Show sign column indicators
  signs = true,
  -- Icon provider: "mini" (mini.icons), "devicons" (nvim-web-devicons), or false for defaults
  icon_provider = false,
}

---@type resolved.Config
M.current = vim.deepcopy(M.defaults)

---Validate user configuration
---@param user_config resolved.Config?
---@return boolean ok
---@return string? error
local function validate_config(user_config)
  if user_config == nil then
    return true, nil
  end

  if type(user_config) ~= "table" then
    return false, "config must be a table"
  end

  -- Validate cache_ttl
  if user_config.cache_ttl ~= nil then
    if type(user_config.cache_ttl) ~= "number" then
      return false, "cache_ttl must be a number"
    end
    if user_config.cache_ttl <= 0 then
      return false, "cache_ttl must be positive"
    end
  end

  -- Validate debounce_ms
  if user_config.debounce_ms ~= nil then
    if type(user_config.debounce_ms) ~= "number" then
      return false, "debounce_ms must be a number"
    end
    if user_config.debounce_ms < 0 then
      return false, "debounce_ms must be non-negative"
    end
  end

  -- Validate enabled
  if user_config.enabled ~= nil then
    if type(user_config.enabled) ~= "boolean" then
      return false, "enabled must be a boolean"
    end
  end

  -- Validate icons
  if user_config.icons ~= nil then
    if type(user_config.icons) ~= "table" then
      return false, "icons must be a table"
    end
  end

  -- Validate tier_priority
  if user_config.tier_priority ~= nil then
    if type(user_config.tier_priority) ~= "table" then
      return false, "tier_priority must be a table"
    end
  end

  return true, nil
end

---Merge user config with defaults
---@param user_config? resolved.Config
function M.setup(user_config)
  -- Validate configuration
  local ok, err = validate_config(user_config)
  if not ok then
    error(string.format("[resolved.nvim] Invalid configuration: %s", err))
  end

  M.current = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), user_config or {})
end

---Get current config
---@return resolved.Config
function M.get()
  return M.current
end

---Get filetype config, falling back to wildcard
---@param ft string
---@return resolved.FiletypeConfig|false|nil
function M.get_filetype(ft)
  local cfg = M.current.filetypes[ft]
  if cfg ~= nil then
    return cfg
  end
  return M.current.filetypes["*"]
end

return M
