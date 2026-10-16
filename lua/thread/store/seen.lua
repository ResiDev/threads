--- What you have seen of a review, kept beside it in `<id>.seen`, which
--- only the plugin writes, so the agent never has to know: how many
--- messages of each conversation you have read, the steps you have
--- walked, the chunks you have accepted, and when each of the agent's
--- messages first showed up. Everything here is by name, `step:7`,
--- `note:12:2`; what a name stands for is thread.model's.

local file = require 'thread.store.file'

local M = {}

---@class thread.Seen
---@field read table<string, integer>   conversation -> messages read
---@field walked table<string, true>    step -> walked
---@field accepted table<string, true>  a chunk's lines, hashed -> accepted
---@field heard table<string, string>|nil  message -> when it first showed up; nil before the first time

local held = {} ---@type table<string, thread.Seen>  by review, for the repository the editor is in
local version = 0

---@param id string
---@return thread.Seen
local function of(id)
  local key = file.dir() .. '/' .. id
  local s = held[key]
  if not s then
    local raw = file.read_seen(id) or {}
    ---@param v any
    ---@return boolean
    local function map(v)
      return type(v) == 'table' and not vim.islist(v)
    end
    s = {
      read = map(raw.read) and raw.read or {},
      walked = map(raw.walked) and raw.walked or {},
      accepted = map(raw.accepted) and raw.accepted or {},
      heard = map(raw.heard) and raw.heard or nil,
    }
    held[key] = s
  end
  return s
end

--- Kept, and said, when it is a change to draw.
---@param id string
---@param fire boolean
local function save(id, fire)
  version = version + 1
  file.write_seen(id, of(id))
  if fire then
    file.fire(id)
  end
end

--- How many times what you have seen has changed: what is drawn from it
--- is drawn again once this moves on.
---@return integer
function M.version()
  return version
end

--- How many messages of a conversation you have read.
---@param id string  the review
---@param name string  the conversation's
---@return integer
function M.read(id, name)
  local n = of(id).read[name]
  return type(n) == 'number' and n or 0
end

--- You have read the first `n` messages of a conversation. It never goes
--- back down.
---@param id string
---@param name string
---@param n integer
---@return boolean changed
function M.mark_read(id, name, n)
  if M.read(id, name) >= n then
    return false
  end
  of(id).read[name] = n
  save(id, true)
  return true
end

---@param id string
---@param name string  the step's
---@return boolean
function M.walked(id, name)
  return of(id).walked[name] == true
end

---@param id string
---@param name string
---@return boolean changed
function M.walk(id, name)
  if M.walked(id, name) then
    return false
  end
  of(id).walked[name] = true
  save(id, true)
  return true
end

---@param id string
---@param key string  the chunk's lines, hashed
---@return boolean
function M.accepted(id, key)
  return of(id).accepted[key] == true
end

--- Accept a chunk, or take it back.
---@param id string
---@param key string
---@param on boolean
---@return boolean changed
function M.accept(id, key, on)
  if M.accepted(id, key) == on then
    return false
  end
  of(id).accepted[key] = on or nil
  save(id, true)
  return true
end

--- When a message first showed up, if it has been heard.
---@param id string
---@param name string  the message's
---@return string|nil  `2026-10-13T10:00:00`
function M.heard(id, name)
  return (of(id).heard or {})[name]
end

--- Messages showing up. The first time a review is heard, what is in it
--- already gets `before`, as its file says; after that, what is new gets
--- `now`.
---@param id string
---@param names string[]  the messages'
---@param now string
---@param before string
---@return boolean changed
function M.hear(id, names, now, before)
  local s = of(id)
  local first = s.heard == nil
  local heard = s.heard or {}
  s.heard = heard
  local changed = first
  for _, name in ipairs(names) do
    if not heard[name] then
      heard[name], changed = first and before or now, true
    end
  end
  if changed then
    save(id, false)
  end
  return changed
end

--- Forget a review that has gone.
---@param id string
function M.forget(id)
  held[file.dir() .. '/' .. id] = nil
end

return M
