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

--- A format 3 review's tours and notes, checked. Steps and notes each
--- count their own ids, from 1, so `#step:7` and `#note:7` are two things.
---@param p thread.Problems
---@param raw table
function M.parse(p, raw)
  raw.tours = fields.list(p, 'the review', raw, 'tours') or {}
  local steps = {} ---@type table<integer, string>  an id -> the step that has it
  for k, x in ipairs(raw.tours) do
    if tour.parse(p, 'tour ' .. k, x) then
      for j, s in ipairs(type(x.steps) == 'table' and x.steps or {}) do
        local id, where = type(s) == 'table' and s.id, string.format('tour %d, step %d', k, j)
        if type(id) == 'number' and steps[id] then
          fields.bad(p, where, string.format("its id %d is %s's too: each step has its own", id, steps[id]))
        elseif type(id) == 'number' then
          steps[id] = where
        end
      end
    end
  end
  raw.notes = fields.list(p, 'the review', raw, 'notes') or {}
  local notes = {} ---@type table<integer, true>
  for i, n in ipairs(raw.notes) do
    if thread.parse(p, n, i, true) and type(n.id) == 'number' then
      if notes[n.id] then
        fields.bad(p, 'note ' .. n.id, 'its id is used twice: each note has its own')
      end
      notes[n.id] = true
    end
  end
end

--- Format 3, read as format 2's threads: its notes, each marked one, after
--- a carrier for its tours, which is no thread (thread.model.thread). Its
--- one message holds the tours, and says nothing: the review's
--- introduction is said above them. It carries the contracts'
--- conversations too.
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
  for _, n in ipairs(r.notes) do
    n.note = true
    r.threads[#r.threads + 1] = n
  end
end

return M
