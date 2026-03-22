local config = require("resolved.config")
local cache_mod = require("resolved.cache")
local github = require("resolved.github")
local scanner = require("resolved.scanner")
local display = require("resolved.display")

local M = {}

M._enabled = false
M._setup_done = false
M._setup_pending = false
M._setup_generation = 0
M._cache = nil ---@type resolved.Cache|nil
M._debounce_timers = {} ---@type table<integer, uv_timer_t>
M._augroup = nil ---@type integer|nil
M._last_changedtick = {} ---@type table<integer, integer>

---@param timer uv_timer_t
local function close_timer(timer)
  pcall(function()
    if timer:is_closing() == false then
      timer:stop()
      timer:close()
    end
  end)
end

---@return boolean
function M.is_enabled()
  return M._enabled
end

function M.enable()
  if M._setup_pending then
    vim.notify("[resolved.nvim] Setup in progress, please wait...", vim.log.levels.INFO)
    return
  end
  if not M._setup_done then
    vim.notify(
      "[resolved.nvim] Plugin not set up. Call require('resolved').setup() first.",
      vim.log.levels.WARN
    )
    return
  end
  M._enabled = true
  M.refresh()
end

---@param full_reset? boolean If true, also reset setup state (for testing)
function M.disable(full_reset)
  M._enabled = false
  display.clear_all()
  for bufnr, timer in pairs(M._debounce_timers) do
    close_timer(timer)
    M._debounce_timers[bufnr] = nil
  end

  if full_reset then
    M._setup_done = false
    M._setup_pending = false
    M._setup_generation = M._setup_generation + 1
    M._cache = nil
    M._last_changedtick = {}
    if M._augroup then
      pcall(vim.api.nvim_del_augroup_by_id, M._augroup)
      M._augroup = nil
    end
    github._reset_auth_check()
  end
end

function M.toggle()
  if M._enabled then
    M.disable()
  else
    M.enable()
  end
end

function M.clear_cache()
  if M._cache then
    M._cache:clear()
  end
end

function M.refresh()
  if not M._enabled then
    return
  end
  local bufnr = vim.api.nvim_get_current_buf()
  M._scan_buffer(bufnr)
end

function M.refresh_all()
  if not M._enabled then
    return
  end
  local seen = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local bufnr = vim.api.nvim_win_get_buf(win)
    if not seen[bufnr] then
      seen[bufnr] = true
      M._scan_buffer(bufnr)
    end
  end
end

---@param bufnr integer
---@param refs resolved.Reference[]
local function process_refs(bufnr, refs)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local to_fetch = {}
  local cached_results = {}

  for _, ref in ipairs(refs) do
    local cached = M._cache:get(ref.url)
    if cached then
      cached_results[ref.url] = cached
    else
      table.insert(to_fetch, ref)
    end
  end

  local function update_display(results)
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    local display_items = {}

    for _, ref in ipairs(refs) do
      local state = results[ref.url]
      if state then
        table.insert(display_items, {
          line = ref.line,
          col = ref.col,
          end_col = ref.end_col,
          url = ref.url,
          state = state,
          is_stale = display.is_stale(state, ref.has_stale_keywords),
          has_stale_keywords = ref.has_stale_keywords,
        })
      end
    end

    pcall(display.update, bufnr, display_items)
  end

  if #to_fetch == 0 then
    update_display(cached_results)
    return
  end

  github.fetch_batch(to_fetch, function(fetch_results)
    local all_results = vim.tbl_extend("force", {}, cached_results)

    for url, result in pairs(fetch_results) do
      if result.state then
        M._cache:set(url, result.state)
        all_results[url] = result.state
      elseif result.err then
        vim.schedule(function()
          vim.notify(string.format("[resolved.nvim] %s", result.err), vim.log.levels.DEBUG)
        end)
      end
    end

    vim.schedule(function()
      update_display(all_results)
    end)
  end)
end

---@param bufnr integer
function M._scan_buffer(bufnr)
  if not M._enabled or not M._setup_done then
    return
  end

  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local buftype = vim.bo[bufnr].buftype
  if buftype ~= "" then
    return
  end

  local refs = scanner.scan(bufnr)
  if #refs == 0 then
    display.clear(bufnr)
    return
  end

  process_refs(bufnr, refs)
end

---@param bufnr integer
function M._debounced_scan(bufnr)
  if not M._enabled then
    return
  end

  local cfg = config.get()

  local existing = M._debounce_timers[bufnr]
  if existing then
    close_timer(existing)
  end

  local timer = vim.uv.new_timer()
  M._debounce_timers[bufnr] = timer

  timer:start(cfg.debounce_ms, 0, function()
    timer:stop()
    timer:close()
    M._debounce_timers[bufnr] = nil

    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      M._scan_buffer(bufnr)
    end)
  end)
end

local function setup_autocmds()
  if M._augroup then
    vim.api.nvim_del_augroup_by_id(M._augroup)
  end

  M._augroup = vim.api.nvim_create_augroup("resolved", { clear = true })

  for _, event in ipairs({ "BufEnter", "BufWritePost" }) do
    vim.api.nvim_create_autocmd(event, {
      group = M._augroup,
      callback = function(args)
        if M._enabled then
          M._last_changedtick[args.buf] = nil
          M._debounced_scan(args.buf)
        end
      end,
    })
  end

  -- Skip rescan if buffer content hasn't changed since last scan
  vim.api.nvim_create_autocmd("CursorHold", {
    group = M._augroup,
    callback = function(args)
      if not M._enabled then
        return
      end
      local tick = vim.api.nvim_buf_get_changedtick(args.buf)
      if M._last_changedtick[args.buf] == tick then
        return
      end
      M._last_changedtick[args.buf] = tick
      M._debounced_scan(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufDelete", {
    group = M._augroup,
    callback = function(args)
      local timer = M._debounce_timers[args.buf]
      if timer then
        close_timer(timer)
      end
      M._debounce_timers[args.buf] = nil
      M._last_changedtick[args.buf] = nil
    end,
  })
end

local subcommands = {
  enable = {
    fn = function()
      M.enable()
    end,
    desc = "Enable the plugin",
  },
  disable = {
    fn = function()
      M.disable()
    end,
    desc = "Disable the plugin",
  },
  toggle = {
    fn = function()
      M.toggle()
    end,
    desc = "Toggle enabled state",
  },
  refresh = {
    fn = function()
      M.refresh()
    end,
    desc = "Refresh current buffer",
  },
  clear_cache = {
    fn = function()
      M.clear_cache()
      vim.notify("[resolved.nvim] Cache cleared", vim.log.levels.INFO)
    end,
    desc = "Clear the issue status cache",
  },
  status = {
    fn = function()
      local state = M._enabled and "enabled" or "disabled"
      vim.notify(string.format("[resolved.nvim] %s", state), vim.log.levels.INFO)
    end,
    desc = "Show plugin status",
  },
  issues = {
    fn = function()
      require("resolved.picker").show_issues_picker()
    end,
    desc = "Show all GitHub issues in workspace",
  },
}

local function setup_commands()
  vim.api.nvim_create_user_command("Resolved", function(opts)
    local args = opts.fargs
    local subcmd = args[1]

    if not subcmd then
      subcommands.status.fn()
      return
    end

    local cmd = subcommands[subcmd]
    if cmd then
      cmd.fn()
    else
      vim.notify(string.format("[resolved.nvim] Unknown command: %s", subcmd), vim.log.levels.ERROR)
    end
  end, {
    nargs = "?",
    desc = "resolved.nvim commands",
    complete = function(arg_lead)
      local names = vim.tbl_keys(subcommands)
      table.sort(names)

      if arg_lead == "" then
        return names
      end

      return vim.tbl_filter(function(name)
        return name:find(arg_lead, 1, true) == 1
      end, names)
    end,
  })
end

---@param user_config? resolved.Config
function M.setup(user_config)
  if M._setup_done then
    vim.notify(
      "[resolved.nvim] Already initialized. Call resolved.disable() first if you want to reconfigure.",
      vim.log.levels.WARN
    )
    return
  end

  if M._setup_pending then
    vim.notify("[resolved.nvim] Setup already in progress.", vim.log.levels.WARN)
    return
  end

  config.setup(user_config)
  local cfg = config.get()

  setup_commands()

  M._setup_pending = true
  M._setup_generation = M._setup_generation + 1
  local my_generation = M._setup_generation

  github.check_auth_async(function(ok, err)
    if M._setup_generation ~= my_generation then
      return
    end

    M._setup_pending = false

    if not ok then
      return
    end

    M._cache = cache_mod.new(cfg.cache_ttl)

    setup_autocmds()

    M._setup_done = true

    if cfg.enabled then
      M.enable()
    end
  end)
end

return M
