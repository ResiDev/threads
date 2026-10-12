--- What you have seen of a review, kept beside it in `<id>.seen`, which
--- only the plugin writes, so the agent never has to know: how many
--- messages of each conversation you have read, the steps you have walked
--- and the chunks you have accepted in each thread, and when each of the
--- agent's messages first showed up. Everything here is by key; what a
--- key stands for is thread.model's.

local file = require 'thread.store.file'

local M = {}

---@class thread.Seen
---@field read table<string, integer>                 conversation -> messages read
---@field walked table<string, table<string, true>>   thread -> steps walked
---@field accepted table<string, table<string, true>> thread -> chunks accepted
---@field heard table<string, string>|nil             message -> when it first showed up; nil before the first time

local held = {} ---@type table<string, thread.Seen>  by review, for the repository the editor is in

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
  file.write_seen(id, of(id))
  if fire then
    file.fire(id)
  end
end

--- How many messages of a conversation you have read.
---@param id string  the review
---@param conversation string
---@return integer
function M.read(id, conversation)
  return of(id).read[conversation] or 0
end

--- You have read the first `n` messages of a conversation. It never goes
--- back down.
---@param id string
---@param conversation string
---@param n integer
---@return boolean changed
function M.mark_read(id, conversation, n)
  local s = of(id)
  if (s.read[conversation] or 0) >= n then
    return false
  end
  s.read[conversation] = n
  save(id, true)
  return true
end

---@param id string
---@param thread string
---@param step string
---@return boolean
function M.walked(id, thread, step)
  local t = of(id).walked[thread]
  return t ~= nil and t[step] == true
end

---@param id string
---@param thread string
---@param step string
---@return boolean changed
function M.walk(id, thread, step)
  if M.walked(id, thread, step) then
    return false
  end
  local s = of(id)
  s.walked[thread] = s.walked[thread] or {}
  s.walked[thread][step] = true
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
---@param message string
---@return string|nil  `2026-10-13T10:00:00`
function M.heard(id, message)
  local h = of(id).heard
  return h and h[message]
end

--- Messages showing up. The first time a review is heard, what is in it
--- already gets `before`, as its file says; after that, what is new gets
--- `now`.
---@param id string
---@param messages string[]
---@param now string
---@param before string
---@return boolean changed
function M.hear(id, messages, now, before)
  local s = of(id)
  local first = s.heard == nil
  local heard = s.heard or {}
  s.heard = heard
  local changed = first
  for _, key in ipairs(messages) do
    if not heard[key] then
      heard[key] = first and before or now
      changed = true
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
