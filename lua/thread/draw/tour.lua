--- A tour: a line, its title and how far you have walked it; or its
--- outline, that line, its introduction, and a line for each step. Its
--- track, for a card's or a winbar's head, is thread.draw.labels.track.

local chunk = require 'thread.model.chunk'
local draw = require 'thread.draw'
local labels = require 'thread.draw.labels'
local prose = require 'thread.prose'
local step = require 'thread.draw.step'
local tour = require 'thread.model.tour'

local M = {}

---@class thread.TourOpts
---@field width integer
---@field indent integer|nil  else the sheet's
---@field here thread.Step|nil  the step you are on

--- A tour in one row: `▶ ` its title, how far you have walked it on the
--- right.
---@param P thread.Sheet
---@param r thread.Review
---@param t thread.Thread  the tour's
---@param x thread.Tour
---@param o thread.TourOpts
---@return thread.Part
function M.line(P, r, t, x, o)
  local right = {} ---@type thread.Chunks
  if #x.steps <= labels.TRACK then
    right = labels.track(r, t, x, o.here)
    right[#right + 1] = { '  ' }
  end
  right[#right + 1] = { tour.walked(r, t, x) .. '/' .. #x.steps .. ' walked', 'ThreadMeta' }
  local row = draw.row(P, { { '▶ ', 'ThreadLeads' }, { x.title, 'ThreadTitle' } }, right, o.width, o.indent)
  return { kind = 'tour', first = row, last = row, thread = t, tour = x }
end

--- A tour's outline: its line, its introduction, then each step's line,
--- set in under it.
---@param P thread.Sheet
---@param r thread.Review
---@param t thread.Thread
---@param x thread.Tour
---@param o thread.TourOpts
---@return thread.Part[]  the tour, then what in it goes somewhere, then its steps
function M.outline(P, r, t, x, o)
  local indent = o.indent or P.indent
  local out = { M.line(P, r, t, x, o) }
  if x.introduction then
    draw.prose(prose.draw(P, x.introduction, o.width - 2, { indent = indent + 2, spec = chunk.spec(r.diff), hl = 'ThreadMeta' }), out)
  end
  local ids = 0
  for _, s in ipairs(x.steps) do
    ids = math.max(ids, #tostring(s.id))
  end
  for _, s in ipairs(x.steps) do
    out[#out + 1] = step.line(P, r, t, x, s, { width = o.width - 2, indent = indent + 2, here = s == o.here, ids = ids })
  end
  out[1].last = #P.lines - 1
  draw.within(out, 1, { thread = t, tour = x })
  return out
end

return M
