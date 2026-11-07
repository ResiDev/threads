--- The verbs: what you do to a topic and what is in it. Each changes the
--- data and saves it, and calls no surface: the store fires `User
--- ThreadChanged`, and whatever is open draws again. Each reads the topic
--- again before it changes it, finding what it is given by id: a surface
--- holds what it read a while ago, and the agent may have written since.

local chunk = require 'thread.model.chunk'
local thread = require 'thread.model.thread'
local topic = require 'thread.model.topic'

local M = {}

--- The topic as its file has it now; nil when it cannot be read.
---@param r thread.Topic  as a surface read it
---@return thread.Topic|nil
local function now(r)
  return (topic.read(r.id))
end

--- Reply in a conversation. It opens a settled thread, and a closed
--- topic, again.
---@param r thread.Topic
---@param c thread.Conversation
---@param text string
---@return thread.Message|nil  nil when the topic cannot be read, or what it was in has gone
function M.reply(r, c, text)
  local fresh = now(r)
  local found = fresh and topic.conversation(fresh, c.kind, c.id)
  if not (fresh and found) then
    return nil
  end
  local m = topic.reply(fresh, found, text)
  topic.save(fresh)
  return m
end

--- Rewrite a message of yours the agent has not answered.
---@param r thread.Topic
---@param c thread.Conversation
---@param i integer  its place in the conversation
---@param text string
---@return boolean ok
---@return string|nil why  not ok: the topic cannot be read, what it was in has gone, or the agent has answered it
function M.edit(r, c, i, text)
  local fresh = now(r)
  local found = fresh and topic.conversation(fresh, c.kind, c.id)
  if not (fresh and found) then
    return false, 'what it was in has gone, or its topic cannot be read'
  end
  if not topic.edit(fresh, found, i, text) then
    return false, 'the agent has answered it since'
  end
  topic.save(fresh)
  return true
end

--- Take back a message of yours the agent has not answered; a thread's
--- first takes the thread with it.
---@param r thread.Topic
---@param c thread.Conversation
---@param i integer
---@return boolean ok
---@return string|nil why
function M.unsay(r, c, i)
  local fresh = now(r)
  local found = fresh and topic.conversation(fresh, c.kind, c.id)
  if not (fresh and found) then
    return false, 'what it was in has gone, or its topic cannot be read'
  end
  if not topic.unsay(fresh, found, i) then
    return false, 'the agent has answered it since'
  end
  topic.save(fresh)
  return true
end

--- Start a thread of yours, on lines or on no line: a comment on lines and
--- a question on none, unless told.
---@param r thread.Topic
---@param a thread.Anchor|nil
---@param text string
---@param kind thread.ThreadKind|nil
---@return thread.Thread|nil  nil when the topic cannot be read
function M.start(r, a, text, kind)
  local fresh = now(r)
  if not fresh then
    return nil
  end
  local n = topic.add(fresh, a, text, kind or (a and 'comment' or 'question'))
  topic.save(fresh)
  return n
end

--- A new topic, by its title.
---@param title string
---@return thread.Topic
function M.new_topic(title)
  return topic.create(title)
end

--- How a thread of its kind can be settled, in the order they are offered:
--- its statuses but `open`.
---@param n thread.Thread
---@return string[]
function M.settles(n)
  return vim.list_slice(thread.STATUSES[n.kind] or {}, 2)
end

--- Settle a thread, saying how, or open it again with `open`. A comment
--- has no status, and is left as it is.
---@param r thread.Topic
---@param n thread.Thread
---@param status string
function M.set_status(r, n, status)
  local fresh = now(r)
  local found = fresh and topic.thread(fresh, n.id)
  if not (fresh and found) or found.kind == 'comment' or found.status == status then
    return
  end
  if not vim.tbl_contains(thread.STATUSES[found.kind], status) then
    return
  end
  found.status = status
  topic.save(fresh)
end

--- Close a topic, or open it again.
---@param r thread.Topic
---@param status 'open'|'closed'
function M.set_topic_status(r, status)
  local fresh = now(r)
  if fresh and fresh.status ~= status then
    fresh.status = status
    topic.save(fresh)
  end
end

--- Accept a chunk, or take it back.
---@param r thread.Topic
---@param c thread.Chunk
---@return boolean|nil on  whether it is accepted now; nil when the code no longer has it
function M.accept(r, c)
  if chunk.key(c, chunk.spec(r.diff)) == nil then
    return nil
  end
  local on = not chunk.accepted(r, c)
  chunk.accept(r, c, on)
  return on
end

--- Accept the thread a part of a drawing is in: the code it is on. A
--- step's or a tour's is walked, not accepted.
---@param r thread.Topic
---@param part thread.Part
---@return boolean|nil on  nil when there is nothing there to accept
function M.accept_part(r, part)
  local c = part.thread and topic.chunk(r, part.thread.chunk)
  if not c then
    return nil
  end
  return M.accept(r, c)
end

return M
