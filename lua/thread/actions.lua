--- The verbs: what you do to a review and what is in it. Each changes the
--- data and saves it, and calls no surface: the store fires `User
--- ThreadChanged`, and whatever is open draws again.

local chunk = require 'thread.model.chunk'
local repo = require 'thread.base.repo'
local review = require 'thread.model.review'
local thread = require 'thread.model.thread'

local M = {}

--- How a thread is closed, in the order they are offered.
---@type thread.Status[]
M.CLOSED = { 'fixed', "won't fix", 'not a problem' }

--- Reply in a conversation. It opens a closed thread, and a closed
--- review, again.
---@param r thread.Review
---@param c thread.Conversation
---@param text string
---@return thread.Message
function M.reply(r, c, text)
  local m = review.reply(r, c, text)
  review.save(r)
  return m
end

--- Start a thread of yours, on a chunk or on no line.
---@param r thread.Review
---@param c thread.Chunk|nil
---@param text string
---@return thread.Thread
function M.start(r, c, text)
  local t = review.add(r, c, text)
  review.save(r)
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
  if t.status ~= status then
    t.status = status
    review.save(r)
  end
end

--- Close a review, or open it again.
---@param r thread.Review
---@param status 'open'|'closed'
function M.set_review_status(r, status)
  if r.status ~= status then
    r.status = status
    review.save(r)
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
---@param r thread.Review
---@param part thread.Part
---@return boolean|nil on  nil when there is nothing there to accept
function M.accept_part(r, part)
  local t = part.thread
  if not t then
    return nil
  end
  if part.kind == 'thread' then
    return M.accept_thread(r, t)
  end
  local c = part.step and part.step.chunk or (not part.step and t.chunk)
  return c and M.accept(r, t, c) or nil
end

--- Run a check: a terminal at the repository's root with its line typed
--- in, for you to run or not.
---@param c thread.Check
function M.run(c)
  vim.cmd 'botright new'
  local job = vim.fn.jobstart({ vim.o.shell }, { term = true, cwd = repo.root() })
  vim.api.nvim_chan_send(job, c.run)
  vim.cmd 'startinsert'
end

return M
