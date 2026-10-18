--- A tour: a part of the change, walked a step at a time, named for what
--- it is about. Its briefing, its introduction, is the walk's first stop:
--- what its steps show and how they fit. Its colour, the agent's pick,
--- tells it apart. How far you have walked it is its state.
---
--- A tour is listed in its review, a row in its tours, unless the agent
--- says not: an unlisted tour is a short walk that explains something,
--- seen only where prose places it, `{{tour:2}}`, so it needs no colour
--- and no briefing of its own.

local fields = require 'thread.model.fields'
local prose = require 'thread.model.prose'
local step = require 'thread.model.step'

local M = {}

---@class (exact) thread.Tour
---@field id integer
---@field title string
---@field listed boolean|nil  false: only where prose places it; none: listed
---@field colour thread.Colour|nil  a listed tour's
---@field introduction thread.Prose|nil  its briefing; a listed tour's
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

local FIELDS = { 'id', 'title', 'listed', 'colour', 'introduction', 'steps' }

--- Steps an unlisted tour has before it is warned of: it is an aside, and
--- a walk longer than this is one to list.
M.STEPS = 3

---@param p thread.Problems
---@param where string
---@param raw any
---@param ctx thread.ParseContext
---@return thread.Tour|nil
function M.parse(p, where, raw, ctx)
  if not fields.object(p, where, raw, FIELDS) then
    return nil
  end
  fields.count(p, where, raw, 'id', true)
  fields.line(p, where, raw, 'title', true)
  if raw.listed ~= nil and type(raw.listed) ~= 'boolean' then
    fields.bad(p, where, '`listed` is true or false')
    raw.listed = nil
  end
  local listed = M.listed(raw)
  fields.one_of(p, where, raw, 'colour', M.COLOURS, listed)
  if not prose.parse(p, where, raw, 'introduction', ctx.file, listed) and listed then
    raw.introduction = { text = '' }
  end
  local steps = fields.list(p, where, raw, 'steps')
  if not steps or #steps == 0 then
    fields.bad(p, where, 'no `steps`')
  elseif not listed and #steps > M.STEPS then
    fields.warn(p, where, string.format('%d steps: an unlisted tour is a few, %d at most as a rule; a longer walk is one to list', #steps, M.STEPS))
  end
  raw.steps = steps or {}
  for i, s in ipairs(raw.steps) do
    step.parse(p, where .. ', step ' .. i, s, ctx)
  end
  return raw
end

--- Whether it is a row in its review's tours, not only where prose
--- places it.
---@param x { listed: boolean|nil }
---@return boolean
function M.listed(x)
  return x.listed ~= false
end

--- The tours listed in its review, in its order.
---@param r { tours: thread.Tour[] }
---@return thread.Tour[]
function M.list(r)
  return vim.tbl_filter(M.listed, r.tours)
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
