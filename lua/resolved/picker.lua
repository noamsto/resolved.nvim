local Job = require("plenary.job")

---@class resolved.FileReference : resolved.Reference
---@field file_path string Absolute path to file

---@class resolved.PickerIssue
---@field url string
---@field owner string
---@field repo string
---@field type "issue"|"pr"
---@field number integer
---@field title string
---@field state "open"|"closed"|"merged"|"unknown"
---@field locations resolved.FileReference[]
---@field is_stale boolean

local M = {}

---Get list of git-tracked files (async)
---@param callback fun(err: string?, files: string[]?)
local function get_tracked_files_async(callback)
  -- Check git executable
  if vim.fn.executable("git") ~= 1 then
    callback("git not found", nil)
    return
  end

  -- Use plenary.Job to run: git ls-files
  Job:new({
    command = "git",
    args = { "ls-files" },
    cwd = vim.fn.getcwd(),
    on_exit = function(j, code)
      vim.schedule(function()
        if code ~= 0 then
          local err = table.concat(j:stderr_result(), "\n")
          callback("Not a git repository: " .. err, nil)
          return
        end

        local output = j:result()
        local files = {}
        local cwd = vim.fn.getcwd()

        for _, rel_path in ipairs(output) do
          if rel_path ~= "" then
            table.insert(files, vim.fn.fnamemodify(cwd .. "/" .. rel_path, ":p"))
          end
        end

        callback(nil, files)
      end)
    end,
  }):start()
end

---Scan a file for GitHub references (async, non-blocking)
---@param file_path string
---@param callback fun(refs: resolved.FileReference[])
local function scan_file_async(file_path, callback)
  local uv = vim.loop

  -- Open file
  uv.fs_open(file_path, "r", 438, function(err_open, fd)
    if err_open or not fd then
      vim.schedule(function()
        callback({})
      end)
      return
    end

    -- Get file size
    uv.fs_fstat(fd, function(err_stat, stat)
      if err_stat or not stat then
        uv.fs_close(fd)
        vim.schedule(function()
          callback({})
        end)
        return
      end

      -- Skip large files (>1MB)
      if stat.size > 1048576 then
        uv.fs_close(fd)
        vim.schedule(function()
          callback({})
        end)
        return
      end

      -- Read file content
      uv.fs_read(fd, stat.size, 0, function(err_read, data)
        uv.fs_close(fd)

        if err_read or not data then
          vim.schedule(function()
            callback({})
          end)
          return
        end

        vim.schedule(function()
          -- Skip binary files (contains null byte)
          if data:find("\0") then
            callback({})
            return
          end

          -- Extract URLs using patterns module
          local patterns = require("resolved.detection.patterns")
          local config = require("resolved.config").get()
          local refs = {}

          -- Split into lines and scan each
          local line_num = 1
          for line_text in (data .. "\n"):gmatch("([^\n]*)\n") do
            local urls = patterns.extract_urls(line_text)
            local has_keywords = patterns.has_stale_keywords(line_text, config.stale_keywords)

            for _, url_match in ipairs(urls) do
              table.insert(refs, {
                url = url_match.url,
                owner = url_match.owner,
                repo = url_match.repo,
                type = url_match.type,
                number = url_match.number,
                line = line_num,
                col = url_match.start_col,
                end_col = url_match.end_col,
                comment_text = line_text:match("^%s*(.-)%s*$"), -- Trim
                has_stale_keywords = has_keywords,
                file_path = file_path,
              })
            end

            line_num = line_num + 1
          end

          callback(refs)
        end)
      end)
    end)
  end)
end

---Scan all files in batches (async with progress)
---@param files string[]
---@param on_progress fun(completed: integer, total: integer, found: integer)
---@param callback fun(refs: resolved.FileReference[])
local function scan_files_batched(files, on_progress, callback)
  local all_refs = {}
  local batch_size = 20
  local completed = 0
  local last_progress_time = 0
  local progress_throttle_ms = 500 -- Update notifications at most every 500ms

  local function process_batch(start_idx)
    if start_idx > #files then
      -- Final progress update
      on_progress(completed, #files, #all_refs)
      callback(all_refs)
      return
    end

    local batch_end = math.min(start_idx + batch_size - 1, #files)
    local batch = vim.list_slice(files, start_idx, batch_end)
    local pending = #batch

    -- Process all files in batch in parallel
    for _, file in ipairs(batch) do
      scan_file_async(file, function(refs)
        vim.list_extend(all_refs, refs)
        pending = pending - 1
        completed = completed + 1

        if pending == 0 then
          -- Batch complete - throttle progress updates
          local now = vim.loop.now()
          if now - last_progress_time >= progress_throttle_ms then
            on_progress(completed, #files, #all_refs)
            last_progress_time = now
          end

          -- Schedule next batch (yield to event loop)
          vim.schedule(function()
            process_batch(batch_end + 1)
          end)
        end
      end)
    end
  end

  process_batch(1)
end

---Group references by issue URL
---@param refs resolved.FileReference[]
---@return table<string, resolved.FileReference[]>
local function group_by_url(refs)
  local by_url = {}

  for _, ref in ipairs(refs) do
    if not by_url[ref.url] then
      by_url[ref.url] = {}
    end
    table.insert(by_url[ref.url], ref)
  end

  return by_url
end

---Format issue for picker display with color indicators
---@param issue resolved.PickerIssue
---@return string
local function format_issue(issue)
  local icon, color_marker

  if issue.is_stale then
    icon = "⚠ "
    color_marker = "●" -- Yellow/warning dot
  elseif issue.state == "open" then
    icon = " "
    color_marker = "●" -- Green dot
  else
    icon = "✓ "
    color_marker = "●" -- Gray dot
  end

  local ref_count = #issue.locations

  -- Truncate title if too long
  local title = issue.title
  local max_title_len = 50
  if #title > max_title_len then
    title = title:sub(1, max_title_len - 3) .. "..."
  end

  -- Build format: color_marker [state] icon owner/repo#number (refs) - title
  local status = string.format("[%-6s]", issue.state) -- Pad status to 6 chars for alignment
  local issue_id = string.format("%s/%s#%d", issue.owner, issue.repo, issue.number)

  -- Only show ref count if > 1 to save space
  local ref_info = ref_count > 1 and string.format(" (%d refs)", ref_count) or ""

  return string.format("%s %s %s%s%s - %s", color_marker, status, icon, issue_id, ref_info, title)
end

---Build picker issues from refs and states
---@param by_url table<string, resolved.FileReference[]>
---@param states table<string, resolved.IssueState>
---@return resolved.PickerIssue[]
local function build_picker_issues(by_url, states)
  local issues = {}

  for url, refs in pairs(by_url) do
    local ref = refs[1]
    local state = states[url] or { state = "unknown", title = "Unknown" }

    -- Check if stale (any location has keywords + closed)
    local is_stale = false
    if state.state == "closed" or state.state == "merged" then
      for _, r in ipairs(refs) do
        if r.has_stale_keywords then
          is_stale = true
          break
        end
      end
    end

    local issue = {
      url = url,
      owner = ref.owner,
      repo = ref.repo,
      type = ref.type,
      number = ref.number,
      title = state.title,
      state = state.state,
      locations = refs,
      is_stale = is_stale,
    }

    -- Add fields for snacks.picker
    issue.text = format_issue(issue)
    issue.file = ref.file_path -- For preview
    issue.pos = { ref.line, ref.col } -- Line and column for preview

    -- Add highlight group for coloring
    if issue.is_stale then
      issue.hl = "DiagnosticWarn" -- Yellow/orange for stale
    elseif issue.state == "open" then
      issue.hl = "DiagnosticInfo" -- Blue/cyan for open
    else
      issue.hl = "Comment" -- Gray for closed
    end

    table.insert(issues, issue)
  end

  -- Sort: stale > closed > open (closed first as requested)
  table.sort(issues, function(a, b)
    local function tier(issue)
      if issue.is_stale then
        return 1
      end
      if issue.state == "closed" or issue.state == "merged" then
        return 2
      end
      return 3 -- open
    end
    return tier(a) < tier(b)
  end)

  return issues
end

---Fetch states for URLs (async, uses cache)
---@param by_url table<string, resolved.FileReference[]>
---@param on_progress fun(fetched: integer, total: integer)
---@param callback fun(issues: resolved.PickerIssue[])
local function fetch_and_build_issues(by_url, on_progress, callback)
  local resolved = require("resolved")
  local github = require("resolved.github")

  -- Check cache first
  local to_fetch = {}
  local states = {} -- url -> state

  for url, refs in pairs(by_url) do
    local cached = resolved._cache:get(url)
    if cached then
      states[url] = cached
    else
      local ref = refs[1] -- Use first ref for metadata
      table.insert(to_fetch, {
        url = url,
        owner = ref.owner,
        repo = ref.repo,
        number = ref.number,
        type = ref.type,
      })
    end
  end

  -- If all cached, build issues immediately
  if #to_fetch == 0 then
    local issues = build_picker_issues(by_url, states)
    callback(issues)
    return
  end

  -- Fetch uncached
  on_progress(0, #to_fetch)

  github.fetch_batch(to_fetch, function(results)
    for url, result in pairs(results) do
      if result.state then
        resolved._cache:set(url, result.state)
        states[url] = result.state
      end
    end

    local issues = build_picker_issues(by_url, states)
    callback(issues)
  end)
end

---Jump to file location
---@param location resolved.FileReference
local function jump_to_location(location)
  -- Open file
  vim.cmd.edit(vim.fn.fnameescape(location.file_path))

  -- Jump to position
  vim.api.nvim_win_set_cursor(0, { location.line, location.col })

  -- Center view
  vim.cmd("normal! zz")

  -- Flash highlight (optional)
  vim.defer_fn(function()
    local bufnr = vim.api.nvim_get_current_buf()
    if vim.api.nvim_buf_is_valid(bufnr) then
      local ns = vim.api.nvim_create_namespace("resolved_picker_flash")
      vim.api.nvim_buf_set_extmark(bufnr, ns, location.line - 1, location.col, {
        end_col = location.end_col,
        hl_group = "IncSearch",
      })
      vim.defer_fn(function()
        pcall(vim.api.nvim_buf_clear_namespace, bufnr, ns, 0, -1)
      end, 500)
    end
  end, 50)
end

---Show location picker for multiple refs
---@param issue resolved.PickerIssue
local function show_location_picker(issue)
  local has_snacks, snacks = pcall(require, "snacks")

  local format_loc = function(loc)
    local rel_path = vim.fn.fnamemodify(loc.file_path, ":~:.")
    return string.format("%s:%d - %s", rel_path, loc.line, loc.comment_text)
  end

  -- Add text field to locations for snacks.picker
  local locations_with_text = {}
  for _, loc in ipairs(issue.locations) do
    local loc_copy = vim.tbl_extend("force", {}, loc)
    loc_copy.text = format_loc(loc)
    table.insert(locations_with_text, loc_copy)
  end

  if has_snacks and snacks.picker then
    snacks.picker.pick({
      items = locations_with_text,
      format = "text",
      prompt = string.format("References to #%d", issue.number),
      on_select = jump_to_location,
    })
  else
    vim.ui.select(issue.locations, {
      prompt = "Select reference:",
      format_item = format_loc,
    }, function(selected)
      if selected then
        jump_to_location(selected)
      end
    end)
  end
end

---Handle issue selection
---@param issue resolved.PickerIssue
local function handle_issue_selection(issue)
  if #issue.locations == 1 then
    jump_to_location(issue.locations[1])
  else
    show_location_picker(issue)
  end
end

---Show snacks picker or fallback
---@param issues resolved.PickerIssue[]
local function show_picker(issues)
  local has_snacks, snacks = pcall(require, "snacks")

  if has_snacks and snacks.picker then
    -- Use snacks.ui picker with highlight support
    snacks.picker.pick({
      items = issues,
      format = function(item)
        -- Return array of {text, highlight} tuples for colored display
        return {
          { item.text, item.hl or "Normal" }
        }
      end,
      prompt = "GitHub Issues",
      on_select = function(item)
        handle_issue_selection(item)
      end,
    })
  else
    -- Fallback to vim.ui.select
    vim.ui.select(issues, {
      prompt = "Select issue:",
      format_item = format_issue,
    }, function(selected)
      if selected then
        handle_issue_selection(selected)
      end
    end)
  end
end

---Show GitHub issues picker
---@param opts? {force_refresh: boolean?}
function M.show_issues_picker(opts)
  opts = opts or {}
  local resolved = require("resolved")

  -- Verify setup
  if not resolved._setup_done then
    vim.notify("[resolved.nvim] Run setup() first", vim.log.levels.ERROR)
    return
  end

  -- Use consistent ID string for automatic notification replacement
  local notif_id = "resolved_picker_progress"

  -- Create initial notification
  vim.notify("Getting file list...", vim.log.levels.INFO, { id = notif_id, timeout = false })

  get_tracked_files_async(function(err, files)
    if err then
      vim.notify("[resolved.nvim] " .. err, vim.log.levels.ERROR, { id = notif_id, timeout = 3000 })
      return
    end

    if not files or #files == 0 then
      vim.notify("[resolved.nvim] No tracked files", vim.log.levels.INFO, { id = notif_id, timeout = 2000 })
      return
    end

    -- Step 2: Scan files
    scan_files_batched(
      files,
      function(completed, total, found)
        -- Reuse same ID to automatically replace notification
        vim.notify(
          string.format("Scanning: %d/%d files (%d refs)", completed, total, found),
          vim.log.levels.INFO,
          { id = notif_id, timeout = false }
        )
      end,
      function(refs)
        if #refs == 0 then
          vim.notify("[resolved.nvim] No GitHub references found", vim.log.levels.INFO, { id = notif_id, timeout = 2000 })
          return
        end

        -- Step 3: Group by URL
        local by_url = group_by_url(refs)

        -- Step 4: Fetch states
        vim.notify(
          string.format("Fetching status for %d issues...", vim.tbl_count(by_url)),
          vim.log.levels.INFO,
          { id = notif_id, timeout = false }
        )

        fetch_and_build_issues(
          by_url,
          function(fetched, total)
            -- Progress callback (currently unused, could show)
          end,
          function(issues)
            -- Step 5: Replace notification with success message that auto-dismisses
            vim.notify(
              string.format("Found %d issues", #issues),
              vim.log.levels.INFO,
              { id = notif_id, timeout = 500 }
            )
            show_picker(issues)
          end
        )
      end
    )
  end)
end

return M
