--- The verbs: what you do to a review and what is in it. Each changes the
--- data and saves it, and calls no surface: the store fires `User
--- ThreadChanged`, and whatever is open draws again. Each reads the review
--- again before it changes it, finding what it is given by id: a surface
--- holds what it read a while ago, and the agent may have written since.

local chunk = require 'thread.model.chunk'
local contract = require 'thread.model.contract'
local repo = require 'thread.base.repo'
local review = require 'thread.model.review'
local thread = require 'thread.model.thread'

local M = {}

--- How a thread is closed, in the order they are offered.
---@type thread.Status[]
M.CLOSED = { 'fixed', "won't fix", 'not a problem' }

--- The review as its file has it now; nil when it cannot be read.
---@param r thread.Review  as a surface read it
---@return thread.Review|nil
local function now(r)
  return (review.read(r.id))
end

--- A thread as its file has it now, and its review; nil when either has
--- gone.
---@param r thread.Review
---@param t thread.Thread
---@return thread.Review|nil, thread.Thread|nil
local function thread_now(r, t)
  local fresh = now(r)
  local found = fresh and review.find(fresh, t.id)
  if not (fresh and found) then
    return nil, nil
  end
  return fresh, found
end

--- Reply in a conversation. It opens a closed thread, and a closed
--- review, again.
---@param r thread.Review
---@param c thread.Conversation
---@param text string
---@return thread.Message|nil  nil when the review cannot be read, or the thread or step has gone
function M.reply(r, c, text)
  local fresh, t = thread_now(r, c.thread)
  if not (fresh and t) then
    return nil
  end
  -- A contract's, on format 3's carrier: found by its id.
  if c.contract then
    local k = contract.find(fresh, c.contract.id)
    if not (k and t.carrier) then
      return nil
    end
    local m = review.reply(fresh, thread.about(t, k), text)
    review.save(fresh)
    return m
  end
  local s, x ---@type thread.Step|nil, thread.Tour|nil
  if c.step then
    s, x = thread.step(t, c.step.id)
    if not s then
      return nil
    end
  end
  local m = review.reply(fresh, thread.conversation(t, s, x), text)
  review.save(fresh)
  return m
end

--- Start a thread of yours, on a chunk or on no line.
---@param r thread.Review
---@param c thread.Chunk|nil
---@param text string
---@return thread.Thread|nil  nil when the review cannot be read
function M.start(r, c, text)
  local fresh = now(r)
  if not fresh then
    return nil
  end
  local t = review.add(fresh, c, text)
  review.save(fresh)
  return t
end

--- A new review, by its title.
---@param title string
---@return thread.Review
function M.new_review(title)
  return review.create(title)
end

--- Close a thread, saying how, or open it again with `open`.
---@param r thread.Review
---@param t thread.Thread
---@param status thread.Status
function M.set_status(r, t, status)
  local fresh, found = thread_now(r, t)
  if fresh and found and found.status ~= status then
    found.status = status
    review.save(fresh)
  end
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

--- Accept every chunk in a thread, or take them all back when all of
--- them are accepted already.
---@param r thread.Review
---@param t thread.Thread
---@return boolean|nil on  whether they are accepted now; nil when it has none
function M.accept_thread(r, t)
  local all = thread.chunks(r, t)
  if #all == 0 then
    return nil
  end
  local on = false
  for _, c in ipairs(all) do
    on = on or not chunk.accepted(r, t, c)
  end
  for _, c in ipairs(all) do
    chunk.accept(r, t, c, on)
  end
  return on
end

--- Accept a chunk in a thread, or take it back.
---@param r thread.Review
---@param t thread.Thread
---@param c thread.Chunk
---@return boolean|nil on  whether it is accepted now; nil when the code no longer has it
function M.accept(r, t, c)
  local on = not chunk.accepted(r, t, c)
  if chunk.key(c, chunk.spec(r.diff)) == nil then
    return nil
  end
  chunk.accept(r, t, c, on)
  return on
end

--- Accept what a part of a drawing is on: on a thread's head or line,
--- every chunk in it; in a step, the step's chunk; else the thread's own.
--- A thread drawn whole is a part as tall as it: only its first row is its
--- head.
---@param r thread.Review
---@param part thread.Part
---@param row integer|nil  the row it is pressed on; nil: its head
---@return boolean|nil on  nil when there is nothing there to accept
function M.accept_part(r, part, row)
  local t = part.thread
  if not t then
    return nil
  end
  if part.kind == 'thread' and (row == nil or row == part.first) then
    return M.accept_thread(r, t)
  end
  local c = part.step and part.step.chunk or (not part.step and t.chunk) or nil
  if not c then
    return nil
  end
  return M.accept(r, t, c)
end

--- Run a check: a terminal at the repository's root with its line typed
--- in, for you to run or not. Only its first line: a line break would
--- run it.
---@param c thread.Check
function M.run(c)
  vim.cmd 'botright new'
  local job = vim.fn.jobstart({ vim.o.shell }, { term = true, cwd = repo.root() })
  vim.api.nvim_chan_send(job, (c.run:match '^[^\r\n]*'))
  vim.cmd 'startinsert'
end

return M
