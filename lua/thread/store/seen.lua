--- What you have seen of a batch: the messages you have read in each
--- thread, the stops of each tour you have been to, what you accepted in a
--- review, and when each of the agent's messages first showed up. Kept
--- beside the batch in its own file, which only the plugin writes, so the
--- agent never has to know.

local file = require 'thread.store.file'
local json = require 'thread.json'

local M = {}

local function seen_path(batch)
  return file.dir() .. '/' .. batch.id .. '.seen'
end

---@param batch thread.Batch
---@return table<string, integer>  comment id -> messages seen
local function seen(batch)
  if not batch.seen then
    batch.seen = (json.decode(file.read(seen_path(batch)) or '') or {})
  end
  return batch.seen
end

local function save(batch)
  file.write(seen_path(batch), json.encode(seen(batch)))
end

--- What is kept for one tour or review: the table under `name` (`_walked`,
--- `_accepted`) and `owner`, made when `make` says so.
local function slot(batch, name, owner, make)
  local s = seen(batch)
  local key = tostring(owner)
  if make and type(s[name]) ~= 'table' then
    s[name] = {}
  end
  if make and type(s[name][key]) ~= 'table' then
    s[name][key] = {}
  end
  local t = type(s[name]) == 'table' and s[name][key]
  return type(t) == 'table' and t or nil
end

--- The agent writes its messages into the file with no time, so when one
--- first shows up its time is noted beside what you have seen. The first
--- time a batch is read, what is already there has no time.
---@param batch thread.Batch
function M.hear(batch)
  local s = seen(batch)
  local first = type(s._heard) ~= 'table'
  if first then
    s._heard = {}
  end
  local now, changed = os.date '%Y-%m-%dT%H:%M:%S', first
  for _, c in ipairs(batch.data.threads) do
    for i, m in ipairs(c.messages) do
      local key = c.id .. ':' .. i
      if m.from ~= 'you' and not m.at and s._heard[key] == nil then
        s._heard[key] = not first and now or false
        changed = true
      end
    end
  end
  if changed then
    save(batch)
  end
end

--- When message `i` of a thread was written: yours as you saved it (or
--- when its round was sent), the agent's as it first showed up.
---@param batch thread.Batch
---@param comment thread.Comment
---@param i integer
---@return string|nil  `2026-10-11T04:23:58`
function M.when(batch, comment, i)
  local m = comment.messages[i]
  if not m then
    return nil
  end
  if m.at then
    return m.at
  end
  if m.from == 'you' then
    local r = m.round and batch.data.rounds[m.round]
    return r and r.sent
  end
  local h = seen(batch)._heard
  return type(h) == 'table' and h[comment.id .. ':' .. i] or nil
end

-- A stop drawn as a thread (thread.tour.display) carries the stop's words
-- as an extra first message: its real thread, and how many it adds. A stop
-- no one has replied in is read once you have walked it.
local function real_of(comment)
  if comment.real then
    return comment.real, #comment.messages - #comment.real.messages
  end
  return comment, 0
end

--- Whether the comment has a message from the agent you have not looked at.
---@param batch thread.Batch
---@param comment thread.Comment
function M.unseen(batch, comment)
  if comment.virtual then
    return not M.visited(batch, comment.stop.owner, comment.stop.n)
  end
  local real, extra = real_of(comment)
  local n = (seen(batch)[tostring(real.id)] or 0) + extra
  for i = #comment.messages, n + 1, -1 do
    if comment.messages[i].from ~= 'you' then
      return true
    end
  end
  return false
end

--- How many of the thread's messages you had seen.
---@param batch thread.Batch
---@param comment thread.Comment
---@return integer
function M.seen_count(batch, comment)
  if comment.virtual then
    return M.visited(batch, comment.stop.owner, comment.stop.n) and 1 or 0
  end
  local real, extra = real_of(comment)
  return (seen(batch)[tostring(real.id)] or 0) + extra
end

--- Mark every message in the thread seen.
---@param batch thread.Batch
---@param comment thread.Comment
---@return boolean changed
function M.mark_seen(batch, comment)
  if comment.virtual then
    return M.visit(batch, comment.stop.owner, comment.stop.n)
  end
  comment = real_of(comment)
  local s = seen(batch)
  local key = tostring(comment.id)
  if (s[key] or 0) >= #comment.messages then
    return false
  end
  s[key] = #comment.messages
  save(batch)
  return true
end

--- Whether you have been to stop `n` of a thread's tour.
---@param batch thread.Batch
---@param owner integer
---@param n integer
function M.visited(batch, owner, n)
  local t = slot(batch, '_walked', owner)
  return t ~= nil and t[tostring(n)] == true
end

--- Mark stop `n` of a thread's tour as been to.
---@return boolean changed
function M.visit(batch, owner, n)
  if M.visited(batch, owner, n) then
    return false
  end
  slot(batch, '_walked', owner, true)[tostring(n)] = true
  save(batch)
  return true
end

--- What you accepted in a review, by key: a group's (`g2`, the hash of
--- its hunks when you did) or a hunk's (`h<hash>`).
---@param batch thread.Batch
---@param owner integer  the review's thread
---@param key string
---@return string|true|nil
function M.accepted(batch, owner, key)
  local t = slot(batch, '_accepted', owner)
  return t and t[key] or nil
end

---@param batch thread.Batch
---@param owner integer
---@param key string
---@param value string|true|nil  nil takes it back
function M.accept(batch, owner, key, value)
  slot(batch, '_accepted', owner, true)[key] = value
  save(batch)
end

return M
