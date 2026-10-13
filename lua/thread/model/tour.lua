--- A tour: an introduction, then steps, walked in order. It comes with a
--- message. How far you have walked it is its state.

local fields = require 'thread.model.fields'
local step = require 'thread.model.step'

local M = {}

---@class (exact) thread.Tour
---@field title string
---@field introduction string|nil
---@field steps thread.Step[]

local FIELDS = { 'title', 'introduction', 'steps' }

---@param p thread.Problems
---@param where string
---@param raw any
---@return thread.Tour|nil
function M.parse(p, where, raw)
  if not fields.object(p, where, raw, FIELDS) then
    return nil
  end
  fields.text(p, where, raw, 'title', true)
  fields.text(p, where, raw, 'introduction')
  local steps = fields.list(p, where, raw, 'steps')
  if not steps or #steps == 0 then
    fields.bad(p, where, 'no `steps`')
  end
  for i, s in ipairs(steps or {}) do
    step.parse(p, where .. ', step ' .. i, s)
  end
  return raw
end

--- How many of a tour's steps you have walked.
---@param r thread.Review
---@param t thread.Thread  the tour's
---@param tour thread.Tour
---@return integer
function M.walked(r, t, tour)
  local n = 0
  for _, s in ipairs(tour.steps) do
    n = n + (step.walked(r, t, s) and 1 or 0)
  end
  return n
end

--- Where the first step you have not walked is in the tour; nil once you
--- have walked them all.
---@param r thread.Review
---@param t thread.Thread
---@param tour thread.Tour
---@return integer|nil
function M.next(r, t, tour)
  for i, s in ipairs(tour.steps) do
    if not step.walked(r, t, s) then
      return i
    end
  end
end

return M
