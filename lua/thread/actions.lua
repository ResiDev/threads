--- The verbs: what you do to a review and what is in it. Each changes the
--- data and saves it, and calls no surface: the store fires `User
--- ThreadChanged`, and whatever is open draws again. Each reads the review
--- again before it changes it, finding what it is given by id: a surface
--- holds what it read a while ago, and the agent may have written since.

local chunk = require 'thread.model.chunk'
local note = require 'thread.model.note'
local review = require 'thread.model.review'

local M = {}

--- The review as its file has it now; nil when it cannot be read.
---@param r thread.Review  as a surface read it
---@return thread.Review|nil
local function now(r)
  return (review.read(r.id))
end

--- Reply in a conversation. It opens a settled note, and a closed
--- review, again.
---@param r thread.Review
---@param c thread.Conversation
---@param text string
---@return thread.Message|nil  nil when the review cannot be read, or what it was in has gone
function M.reply(r, c, text)
  local fresh = now(r)
  local found = fresh and review.conversation(fresh, c.kind, c.id)
  if not (fresh and found) then
    return nil
  end
  local m = review.reply(fresh, found, text)
  review.save(fresh)
  return m
end

--- Rewrite a message of yours the agent has not answered.
---@param r thread.Review
---@param c thread.Conversation
---@param i integer  its place in the conversation
---@param text string
---@return boolean ok
---@return string|nil why  not ok: the review cannot be read, what it was in has gone, or the agent has answered it
function M.edit(r, c, i, text)
  local fresh = now(r)
  local found = fresh and review.conversation(fresh, c.kind, c.id)
  if not (fresh and found) then
    return false, 'what it was in has gone, or its review cannot be read'
  end
  if not review.edit(fresh, found, i, text) then
    return false, 'the agent has answered it since'
  end
  review.save(fresh)
  return true
end

--- Take back a message of yours the agent has not answered; a note's
--- first takes the note with it.
---@param r thread.Review
---@param c thread.Conversation
---@param i integer
---@return boolean ok
---@return string|nil why
function M.unsay(r, c, i)
  local fresh = now(r)
  local found = fresh and review.conversation(fresh, c.kind, c.id)
  if not (fresh and found) then
    return false, 'what it was in has gone, or its review cannot be read'
  end
  if not review.unsay(fresh, found, i) then
    return false, 'the agent has answered it since'
  end
  review.save(fresh)
  return true
end

--- Start a note of yours, on lines or on no line: a comment on lines and
--- a question on none, unless told.
---@param r thread.Review
---@param a thread.Anchor|nil
---@param text string
---@param kind thread.NoteKind|nil
---@return thread.Note|nil  nil when the review cannot be read
function M.start(r, a, text, kind)
  local fresh = now(r)
  if not fresh then
    return nil
  end
  local n = review.add(fresh, a, text, kind or (a and 'comment' or 'question'))
  review.save(fresh)
  return n
end

--- A new review, by its title.
---@param title string
---@return thread.Review
function M.new_review(title)
  return review.create(title)
end

--- How a note of its kind can be settled, in the order they are offered:
--- its statuses but `open`.
---@param n thread.Note
---@return string[]
function M.settles(n)
  return vim.list_slice(note.STATUSES[n.kind] or {}, 2)
end

--- Settle a note, saying how, or open it again with `open`. A comment
--- has no status, and is left as it is.
---@param r thread.Review
---@param n thread.Note
---@param status string
function M.set_status(r, n, status)
  local fresh = now(r)
  local found = fresh and review.note(fresh, n.id)
  if not (fresh and found) or found.kind == 'comment' or found.status == status then
    return
  end
  if not vim.tbl_contains(note.STATUSES[found.kind], status) then
    return
  end
  found.status = status
  review.save(fresh)
end

--- Close a review, or open it again.
---@param r thread.Review
---@param status 'open'|'closed'
function M.set_review_status(r, status)
  local fresh = now(r)
  if fresh and fresh.status ~= status then
    fresh.status = status
    review.save(fresh)
  end
end

--- Accept a chunk, or take it back.
---@param r thread.Review
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

--- Accept the note a part of a drawing is in: the code it is on. A
--- step's or a tour's is walked, not accepted.
---@param r thread.Review
---@param part thread.Part
---@return boolean|nil on  nil when there is nothing there to accept
function M.accept_part(r, part)
  local c = part.note and review.chunk(r, part.note.chunk)
  if not c then
    return nil
  end
  return M.accept(r, c)
end

return M
