---@class resolved.CacheEntry
---@field data any The cached data
---@field fetched_at integer Timestamp when fetched (os.time())

---@class resolved.Cache
---@field _entries table<string, resolved.CacheEntry>
---@field _ttl integer TTL in seconds
local Cache = {}
Cache.__index = Cache

local M = {}

---Create a new cache instance
---@param ttl integer TTL in seconds
---@return resolved.Cache
function M.new(ttl)
  local self = setmetatable({}, Cache)
  self._entries = {}
  self._ttl = ttl
  return self
end

---Check if an entry is still valid
---@param entry resolved.CacheEntry
---@return boolean
function Cache:_is_valid(entry)
  if not entry then
    return false
  end
  return (os.time() - entry.fetched_at) < self._ttl
end

---Get a cached value
---@param key string
---@return any|nil data Returns nil if not found or expired
function Cache:get(key)
  local entry = self._entries[key]
  if self:_is_valid(entry) then
    return entry.data
  end
  if entry then
    self._entries[key] = nil
  end
  return nil
end

---Set a cached value
---@param key string
---@param data any
function Cache:set(key, data)
  self._entries[key] = {
    data = data,
    fetched_at = os.time(),
  }
end

---Check if key exists and is valid
---@param key string
---@return boolean
function Cache:has(key)
  return self:get(key) ~= nil
end

---Remove a specific key
---@param key string
function Cache:remove(key)
  self._entries[key] = nil
end

---Clear all entries
function Cache:clear()
  self._entries = {}
end

---Prune expired entries
function Cache:prune()
  for key, entry in pairs(self._entries) do
    if not self:_is_valid(entry) then
      self._entries[key] = nil
    end
  end
end

---Get number of entries (including expired)
---@return integer
function Cache:size()
  return vim.tbl_count(self._entries)
end

return M
