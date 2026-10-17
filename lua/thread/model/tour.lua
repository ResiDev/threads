--- A tour: a part of the change, walked a step at a time, named for what
--- it is about. Its briefing, its introduction, is the walk's first stop:
--- what its steps show and how they fit. Its colour, the agent's pick,
--- tells it apart. How far you have walked it is its state.

local fields = require 'thread.model.fields'
local prose = require 'thread.model.prose'
local step = require 'thread.model.step'

local M = {}

---@class (exact) thread.Tour
---@field title string
---@field colour thread.Colour
---@field introduction thread.Prose  its briefing
---@field steps thread.Step[]

--- A tour's colour, by name, for the colorscheme to say how it looks. It
--- only tells tours apart, in their review. Red is left out: it reads as
--- wrong.
---@alias thread.Colour 'orange'|'yellow'|'lime'|'teal'|'sky'|'blue'|'violet'|'pink'|'rose'|'amber'|'green'|'mint'|'cyan'|'indigo'|'purple'|'magenta'

-- The first eight are furthest apart; the next eight sit between them,
-- told apart by lightness as much as by hue.
M.COLOURS = {
  'orange',
  'yellow',
  'lime',
  'teal',
  'sky',
  'blue',
  'violet',
  'pink',
  'rose',
  'amber',
  'green',
  'mint',
  'cyan',
  'indigo',
  'purple',
  'magenta',
}

local FIELDS = { 'title', 'colour', 'introduction', 'steps' }

---@param p thread.Problems
---@param where string
---@param raw any
---@param ctx thread.ParseContext
---@return thread.Tour|nil
function M.parse(p, where, raw, ctx)
  if not fields.object(p, where, raw, FIELDS) then
    return nil
  end
  fields.line(p, where, raw, 'title', true)
  fields.one_of(p, where, raw, 'colour', M.COLOURS, true)
  if not prose.parse(p, where, raw, 'introduction', ctx.file, true) then
    raw.introduction = { text = '' }
  end
  local steps = fields.list(p, where, raw, 'steps')
  if not steps or #steps == 0 then
    fields.bad(p, where, 'no `steps`')
  end
  raw.steps = steps or {}
  for i, s in ipairs(raw.steps) do
    step.parse(p, where .. ', step ' .. i, s, ctx)
  end
  return raw
end

--- How many of a tour's steps you have walked.
---@param r thread.Review
---@param x thread.Tour
---@return integer
function M.walked(r, x)
  local n = 0
  for _, s in ipairs(x.steps) do
    n = n + (step.walked(r, s) and 1 or 0)
  end
  return n
end

--- Where the first step you have not walked is in the tour; nil once you
--- have walked them all.
---@param r thread.Review
---@param x thread.Tour
---@return integer|nil
function M.next(r, x)
  for i, s in ipairs(x.steps) do
    if not step.walked(r, s) then
      return i
    end
  end
end

return M
