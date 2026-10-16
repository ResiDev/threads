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

--- Accept every chunk of a tour's steps, or take them all back when all
--- of them are accepted already. A chunk the code no longer has cannot
--- be accepted, so it is left out: else the tour could never be taken
--- back.
---@param r thread.Review
---@param x thread.Tour
---@return boolean|nil on  whether they are accepted now; nil when it has none in the code
function M.accept_tour(r, x)
  local spec = chunk.spec(r.diff)
  local all = {} ---@type thread.Chunk[]
  for _, s in ipairs(x.steps) do
    local c = review.chunk(r, s.chunk)
    if c and chunk.key(c, spec) ~= nil then
      all[#all + 1] = c
    end
  end
  if #all == 0 then
    return nil
  end
  local on = false
  for _, c in ipairs(all) do
    on = on or not chunk.accepted(r, c)
  end
  for _, c in ipairs(all) do
    chunk.accept(r, c, on)
  end
  return on
end

--- Accept what a part of a drawing is on: a tour's every chunk; a
--- chunk, or one a message changed; a step's or a note's chunk.
---@param r thread.Review
---@param part thread.Part
---@return boolean|nil on  nil when there is nothing there to accept
function M.accept_part(r, part)
  if part.kind == 'tour' and part.tour then
    return M.accept_tour(r, part.tour)
  end
  local c = ((part.kind == 'chunk' or part.kind == 'change') and part.chunk) or review.chunk(r, part.step and part.step.chunk or part.note and part.note.chunk)
  if not c then
    return nil
  end
  return M.accept(r, c)
end

return M
