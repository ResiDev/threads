--- The store: batches of threads, what is in them and whose move each is.
--- How they are kept on disk is thread.store.file; what you have seen of
--- them, thread.store.seen. Both are reached through here.

local M = {}

---@class thread.Message
---@field from 'you'|'agent'
---@field text string
---@field round integer|nil   the round it went to the agent in
---@field changes thread.Anchor[]|nil
---@field notes thread.Note[]|nil
---@field diagram table|nil
---@field verdict string|nil
---@field severity string|nil
---@field walk thread.Stop[]|nil  the tour it leads to, in order

---@class thread.Note: thread.Anchor
---@field note string|nil  what it says; none is a highlight only
---@field mark string|nil  a word on the line to pick out

---@class thread.Anchor
---@field file string   repo-relative
---@field rev string|nil
---@field line integer
---@field lines integer|nil
---@field text string
---@field side 'old'|nil  on a removed line of a review's diff (thread.review)

---@class thread.Thread: thread.Anchor
---@field id integer
---@field file string|nil   none: a thread about no line, shown as a page
---@field status 'open'|'closed'|nil
---@field title string|nil   the agent names a thread in its first reply
---@field messages thread.Message[]
---@field on { thread: integer, step: integer, at: string|nil }|nil  a reply in a tour's stop
---@field review integer|nil  started on a line of this review's diff

---@class thread.Batch
---@field id string
---@field path string
---@field mtime integer
---@field data { title: string, reply: string, diff: table|nil, rounds: table[], threads: thread.Thread[] }
---@field derived table|nil  what thread.tour works out once per load

--- Whose move it is, worked out from the messages: waiting on the agent,
--- answered (your move), info (only the agent has spoken: an explanation,
--- not a turn you owe), or closed. A message of yours is with the agent as
--- soon as it is saved: there are no drafts.
---@param thread thread.Thread
---@return 'waiting'|'answered'|'info'|'closed'
function M.status(thread)
  -- `resolved` and `dismissed` are what closing used to be called.
  local s = thread.status
  if s == 'closed' or s == 'resolved' or s == 'dismissed' then
    return 'closed'
  end
  local last = thread.messages[#thread.messages]
  if last and last.from ~= 'you' then
    return M.talked(thread) and 'answered' or 'info'
  end
  return 'waiting'
end

--- Whether you have said anything in the thread.
---@param thread thread.Thread
function M.talked(thread)
  for _, m in ipairs(thread.messages) do
    if m.from == 'you' then
      return true
    end
  end
  return false
end

--- A thread's name: its title, else the start of its first message.
---@param thread thread.Thread
---@return string
function M.title(thread)
  if thread.title and thread.title ~= '' then
    return thread.title
  end
  return require('thread.text').first_line(thread.messages[1] and thread.messages[1].text)
end

--- Whether a thread is about lines of code, or about none (a page).
---@param thread thread.Thread
function M.anchored(thread)
  return type(thread.file) == 'string' and thread.file ~= ''
end

--- A message of yours goes to the agent as you save it. It joins the round
--- still waiting on an answer; when nothing is waiting, it starts a new
--- round, and the code is snapshotted so the agent's changes can be shown
--- against it.
---@param batch thread.Batch
---@param msg thread.Message
local function stamp(batch, msg)
  local rounds = batch.data.rounds
  local open = false
  if #rounds > 0 then
    for _, c in ipairs(batch.data.threads) do
      if M.status(c) == 'waiting' then
        open = true
        break
      end
    end
  end
  if not open then
    local n = #rounds + 1
    local ok, sha = pcall(require('thread.git').snapshot, batch, n)
    rounds[n] = { sent = os.date '%Y-%m-%dT%H:%M:%S', snapshot = ok and sha or nil }
  end
  msg.round = #rounds
  msg.at = os.date '%Y-%m-%dT%H:%M:%S'
end

--- The id the next new thread gets.
---@param batch thread.Batch
---@return integer
function M.next_id(batch)
  local id = 0
  for _, c in ipairs(batch.data.threads) do
    id = math.max(id, c.id or 0)
  end
  return id + 1
end

--- Saved, and everyone listening told.
local function changed(batch)
  M.save(batch)
  M.notify()
end

--- A new thread of yours: on `anchor`, or with none a question about no line.
---@param batch thread.Batch
---@param anchor thread.Anchor|nil
---@param text string
---@param extra table|nil  more fields for the thread, such as `on`
---@return thread.Thread
function M.add(batch, anchor, text, extra)
  local msg = { from = 'you', text = text }
  stamp(batch, msg)
  local thread = vim.tbl_extend('force', anchor or {}, extra or {}, { id = M.next_id(batch), status = 'open', messages = { msg } })
  batch.data.threads[#batch.data.threads + 1] = thread
  changed(batch)
  return thread
end

---@param batch thread.Batch
---@param id integer
---@return thread.Thread|nil, integer|nil index
function M.find(batch, id)
  for i, c in ipairs(batch.data.threads) do
    if c.id == id then
      return c, i
    end
  end
end

---@param batch thread.Batch
---@param thread thread.Thread
function M.remove(batch, thread)
  local _, i = M.find(batch, thread.id)
  if i then
    table.remove(batch.data.threads, i)
    changed(batch)
  end
end

--- One reply, added to each of several threads, in one round.
---@param batch thread.Batch
---@param ids integer[]
---@param text string
function M.reply_all(batch, ids, text)
  local sent = {}
  stamp(batch, sent)
  for _, id in ipairs(ids) do
    local c = M.find(batch, id)
    if c then
      c.messages[#c.messages + 1] = { from = 'you', text = text, round = sent.round, at = sent.at }
      c.status = 'open'
    end
  end
  changed(batch)
end

---@param batch thread.Batch
---@param thread thread.Thread
---@param text string
function M.reply(batch, thread, text)
  M.reply_all(batch, { thread.id }, text)
end

---@param batch thread.Batch
---@param ids integer[]
---@param status 'open'|'closed'
function M.set_status_all(batch, ids, status)
  for _, id in ipairs(ids) do
    local c = M.find(batch, id)
    if c then
      c.status = status
    end
  end
  changed(batch)
end

---@param batch thread.Batch
---@param thread thread.Thread
---@param status 'open'|'closed'
function M.set_status(batch, thread, status)
  M.set_status_all(batch, { thread.id }, status)
end

-- The batches on disk, and what you have seen of them, are the store's
-- too: one interface for both.
local file = require 'thread.store.file'
for _, name in ipairs { 'root', 'dir', 'load', 'save', 'list', 'new', 'delete', 'active_id', 'set_active', 'active', 'on_change', 'notify', 'watch' } do
  M[name] = file[name]
end
local seen = require 'thread.store.seen'
for _, name in ipairs { 'hear', 'when', 'unseen', 'seen_count', 'mark_seen', 'visited', 'visit', 'accepted', 'accept' } do
  M[name] = seen[name]
end

return M
