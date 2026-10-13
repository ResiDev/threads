--- What you have seen of a review, kept beside it in `<id>.seen`, which
--- only the plugin writes, so the agent never has to know: how many
--- messages of each conversation you have read, the steps you have
--- walked, the chunks you have accepted in each thread, and when each of the
--- agent's messages first showed up. Everything here is by name; what a
--- name stands for is thread.model's. A conversation or a message can go
--- by more than one: a mark under any is its mark, marking it marks them
--- all, and `join` copies one name's marks to the others, so it is still
--- found when one of them goes.

local file = require 'thread.store.file'

local M = {}

---@class thread.Seen
---@field read table<string, integer>                 conversation -> messages read
---@field walked table<string, true>                step -> walked
---@field accepted table<string, table<string, true>> thread -> chunks accepted
---@field heard table<string, string>|nil             message -> when it first showed up; nil before the first time

local held = {} ---@type table<string, thread.Seen>  by review, for the repository the editor is in
local version = 0

---@param id string
---@return thread.Seen
local function of(id)
  local key = file.dir() .. '/' .. id
  local s = held[key]
  if not s then
    local raw = file.read_seen(id) or {}
    s = {
      read = type(raw.read) == 'table' and raw.read or {},
      walked = type(raw.walked) == 'table' and raw.walked or {},
      accepted = type(raw.accepted) == 'table' and raw.accepted or {},
      heard = type(raw.heard) == 'table' and raw.heard or nil,
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
---@param names string[]  the conversation's
---@return integer
function M.read(id, names)
  local read, n = of(id).read, 0
  for _, name in ipairs(names) do
    n = math.max(n, read[name] or 0)
  end
  return n
end

--- You have read the first `n` messages of a conversation. It never goes
--- back down.
---@param id string
---@param names string[]
---@param n integer
---@return boolean changed
function M.mark_read(id, names, n)
  if M.read(id, names) >= n then
    return false
  end
  local s = of(id)
  for _, name in ipairs(names) do
    s.read[name] = n
  end
  save(id, true)
  return true
end

---@param id string
---@param names string[]  the step's
---@return boolean
function M.walked(id, names)
  local walked = of(id).walked
  for _, name in ipairs(names) do
    if walked[name] then
      return true
    end
  end
  return false
end

---@param id string
---@param names string[]
---@return boolean changed
function M.walk(id, names)
  if M.walked(id, names) then
    return false
  end
  local s = of(id)
  for _, name in ipairs(names) do
    s.walked[name] = true
  end
  save(id, true)
  return true
end

---@param id string
---@param thread string
---@param chunk string
---@return boolean
function M.accepted(id, thread, chunk)
  local t = of(id).accepted[thread]
  return t ~= nil and t[chunk] == true
end

--- Accept a chunk, or take it back.
---@param id string
---@param thread string
---@param chunk string
---@param on boolean
---@return boolean changed
function M.accept(id, thread, chunk, on)
  if M.accepted(id, thread, chunk) == on then
    return false
  end
  local s = of(id)
  s.accepted[thread] = s.accepted[thread] or {}
  s.accepted[thread][chunk] = on or nil
  save(id, true)
  return true
end

--- When a message first showed up, if it has been heard.
---@param id string
---@param names string[]  the message's
---@return string|nil  `2026-10-13T10:00:00`
function M.heard(id, names)
  local h = of(id).heard or {}
  for _, name in ipairs(names) do
    if h[name] then
      return h[name]
    end
  end
  return nil
end

--- Messages showing up. The first time a review is heard, what is in it
--- already gets `before`, as its file says; after that, what is new gets
--- `now`. One heard by any of its names gets that time under the others.
---@param id string
---@param messages string[][]  each one's names
---@param now string
---@param before string
---@return boolean changed
function M.hear(id, messages, now, before)
  local s = of(id)
  local first = s.heard == nil
  local heard = s.heard or {}
  s.heard = heard
  local changed = first
  for _, names in ipairs(messages) do
    local at = M.heard(id, names) or (first and before or now)
    for _, name in ipairs(names) do
      if not heard[name] then
        heard[name], changed = at, true
      end
    end
  end
  if changed then
    save(id, false)
  end
  return changed
end

--- Conversations by their names now: what you have read and walked of one
--- under any of them is copied to the others, so it is still found when
--- the one it was under goes. Nothing you see changes, so nothing fires.
---@param id string
---@param conversations string[][]  each one's names
---@return boolean changed
function M.join(id, conversations)
  local s = of(id)
  local changed = false
  for _, names in ipairs(conversations) do
    local read, walked = M.read(id, names), M.walked(id, names)
    for _, name in ipairs(names) do
      if read > 0 and (s.read[name] or 0) < read then
        s.read[name], changed = read, true
      end
      if walked and not s.walked[name] then
        s.walked[name], changed = true, true
      end
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
