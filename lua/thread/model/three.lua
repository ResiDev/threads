--- Format 3: a review of tours and notes, with no threads. It is read as
--- format 2's threads, so all that works on a thread's steps and
--- conversations works on it unchanged: each note is a thread whose
--- messages carry no tours, and the tours ride on a thread of their own,
--- id 0, its carrier, which has no conversation and which nothing lists
--- (thread.model.thread). Written back, a review is its tours and notes
--- again, never its threads (thread.model.review).

local fields = require 'thread.model.fields'
local thread = require 'thread.model.thread'
local tour = require 'thread.model.tour'

local M = {}

--- A format 3 review's tours and notes, checked. Steps and notes share
--- one run of ids, so `#7` links to whichever has it.
---@param p thread.Problems
---@param raw table
function M.parse(p, raw)
  raw.tours = fields.list(p, 'the review', raw, 'tours') or {}
  local ids = {} ---@type table<integer, string>  an id -> what has it
  ---@param id any
  ---@param where string
  local function own(id, where)
    if type(id) ~= 'number' then
      return
    end
    if ids[id] then
      fields.bad(p, where, string.format("its id %d is %s's too: steps and notes share one run of ids, each its own", id, ids[id]))
    end
    ids[id] = ids[id] or where
  end
  for k, x in ipairs(raw.tours) do
    if tour.parse(p, 'tour ' .. k, x) then
      for j, s in ipairs(type(x.steps) == 'table' and x.steps or {}) do
        own(type(s) == 'table' and s.id, string.format('tour %d, step %d', k, j))
      end
    end
  end
  raw.notes = fields.list(p, 'the review', raw, 'notes') or {}
  for i, n in ipairs(raw.notes) do
    if thread.parse(p, n, i, true) then
      own(n.id, 'note ' .. tostring(n.id))
    end
  end
end

--- Format 3, read as format 2's threads: its notes, after a carrier for
--- its tours, which is no thread (thread.model.thread). Its one message
--- holds the tours, and says nothing: the review's introduction is said
--- above them. It carries the contracts' conversations too.
---@param r thread.Review
function M.carry(r)
  ---@type thread.Thread
  local t = {
    id = 0,
    carrier = true,
    title = r.title,
    status = 'open',
    messages = { { from = 'agent', text = '', tours = r.tours } },
    contracts = r.contracts,
  }
  r.threads = { t }
  vim.list_extend(r.threads, r.notes)
end

return M
