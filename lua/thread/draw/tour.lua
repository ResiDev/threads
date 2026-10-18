--- A tour: a line, its title and how far you have walked it; its
--- outline, that line and a line for each step; its briefing, what the
--- walk opens on; or a section of its review, a row in its colour that
--- opens in place to its briefing and a tree of its steps. Its track,
--- for a card's or a winbar's head, is thread.draw.labels.track.

local conversation = require 'thread.model.conversation'
local draw = require 'thread.draw'
local labels = require 'thread.draw.labels'
local prose = require 'thread.prose'
local step = require 'thread.draw.step'
local step_model = require 'thread.model.step'
local text = require 'thread.base.text'
local tour = require 'thread.model.tour'

local M = {}

---@class thread.TourOpts
---@field width integer
---@field indent integer|nil  else the sheet's
---@field here thread.Step|nil  the step you are on
---@field open table<string, true>|nil  a section: the steps opened, by draw.key
---@field code boolean|nil  a section: each step's code, not only where opened
---@field folded boolean|nil  a section: a row, not its briefing and a tree of its steps
---@field place integer|nil  its place among the review's tours, for its colour when it has none
---@field groups table<string, boolean>|nil  sections: each folded to a row or not, by draw.key, apart from `tours`
---@field tours boolean|nil  sections: every one opened, not a row

-- The prose reads well this wide at most.
local PROSE = 100

--- A tour in one row: `▶ ` its title, how far you have walked it on the
--- right.
---@param P thread.Sheet
---@param r thread.Review
---@param x thread.Tour
---@param o thread.TourOpts
---@return thread.Part
function M.line(P, r, x, o)
  local right = {} ---@type thread.Chunks
  if #x.steps <= labels.TRACK then
    right = labels.track(r, x, o.here)
    right[#right + 1] = { '  ' }
  end
  right[#right + 1] = { tour.walked(r, x) .. '/' .. #x.steps .. ' walked', 'ThreadMeta' }
  local name = labels.colour(x.colour, o.place)
  local row = draw.row(P, { { '▶ ', 'ThreadLeads' }, { x.title, name } }, right, o.width, o.indent)
  return { kind = 'tour', first = row, last = row, tour = x }
end

--- Its steps a line each, set in by two, the one you are on marked.
---@param P thread.Sheet
---@param r thread.Review
---@param x thread.Tour
---@param o thread.TourOpts
---@param out thread.Part[]
local function step_lines(P, r, x, o, out)
  local indent = o.indent or P.indent
  local ids = 0
  for _, s in ipairs(x.steps) do
    ids = math.max(ids, #tostring(s.id))
  end
  for _, s in ipairs(x.steps) do
    out[#out + 1] = step.line(P, r, x, s, { width = o.width - 2, indent = indent + 2, here = s == o.here, ids = ids })
  end
end

--- A tour's outline: its line, then each step's line, set in under it.
---@param P thread.Sheet
---@param r thread.Review
---@param x thread.Tour
---@param o thread.TourOpts
---@return thread.Part[]  the tour, then its steps
function M.outline(P, r, x, o)
  local out = { M.line(P, r, x, o) }
  step_lines(P, r, x, o, out)
  out[1].last = #P.lines - 1
  draw.within(out, 1, { tour = x })
  return out
end

--- A tour's briefing, what the walk opens on and comes back to: its
--- title in its colour and how far you have walked it, its
--- introduction whole with its diagrams, then its steps a line each.
---@param P thread.Sheet
---@param r thread.Review
---@param x thread.Tour
---@param o thread.TourOpts
---@return thread.Part[]  the tour, then what in it goes somewhere, then its steps
function M.briefing(P, r, x, o)
  local indent = o.indent or P.indent
  local name = labels.colour(x.colour, o.place)
  local first = draw.row(P, { { x.title, name } }, labels.track(r, x, o.here), o.width, indent)
  local out = { { kind = 'tour', first = first, last = first, tour = x, item = true } } ---@type thread.Part[]
  P.chunks({ { text.plural(#x.steps, 'step') .. ' · ' .. tour.walked(r, x) .. ' walked', 'ThreadMeta' } }, indent)
  P.add ''
  draw.prose(prose.draw(P, x.introduction, math.min(o.width, PROSE), { indent = indent, review = r }), out)
  P.add ''
  P.chunks(labels.rule('steps', o.width), indent)
  step_lines(P, r, x, vim.tbl_extend('force', o, { indent = indent - 2, width = o.width + 2 }), out)
  out[1].last = #P.lines - 1
  draw.within(out, 1, { tour = x })
  return out
end

-- Columns a tour's bar or tree takes, left of its rows.
M.GUTTER = 3

--- How its steps' conversations stand, and how many of its steps you
--- have walked, for its row: `3/10 walked`, never a tick, which says a
--- note accepted.
---@param r thread.Review
---@param x thread.Tour
---@return thread.Chunks
local function counts(r, x)
  local yes, all = tour.walked(r, x), #x.steps
  local conversations = {} ---@type thread.Conversation[]
  for _, s in ipairs(x.steps) do
    conversations[#conversations + 1] = conversation.of_step(s, x)
  end
  local right = labels.count(r, conversations)
  if all > 0 then
    vim.list_extend(right, { { #right > 0 and '   ' or '' }, { string.format('%d/%d walked', yes, all), yes == all and 'ThreadAccepted' or 'ThreadMeta' } })
  end
  return right
end

--- A tour as a section of its review: its title in its colour, how its
--- steps' conversations stand and how many of its steps you have
--- walked. Folded, that row and a bar down its side. Open, its
--- briefing under it, then a tree of its steps, each a block.
---@param P thread.Sheet
---@param r thread.Review
---@param x thread.Tour
---@param o thread.TourOpts
---@return thread.Part[]  the tour, then its steps and what in it goes somewhere
function M.section(P, r, x, o)
  local indent = o.indent or P.indent
  local inner, width = indent + M.GUTTER, o.width - M.GUTTER
  local name, line = labels.colour(x.colour, o.place)
  local folded = o.folded
  local row = draw.row(P, { { x.title, name } }, counts(r, x), width, inner)
  draw.gutter(P, row, row, folded and '▌' or '━━', line, indent)
  local out = { { kind = 'tour', first = row, last = row, tour = x, item = true } } ---@type thread.Part[]
  if folded then
    draw.within(out, 1, { tour = x })
    return out
  end
  local from = #P.lines
  draw.prose(prose.draw(P, x.introduction, math.min(width, PROSE), { indent = inner, hl = 'ThreadSummary', review = r }), out)
  draw.gutter(P, from, #P.lines - 1, '│', line, indent)
  for i, s in ipairs(x.steps) do
    local last = i == #x.steps
    P.add ''
    draw.gutter(P, #P.lines - 1, #P.lines - 1, '│', line, indent)
    local block = { kind = 'step', first = 0, last = 0, step = s } ---@type thread.Part
    local open = (o.open or {})[draw.key(block)] == true
    local drawn = step.block(P, r, x, s, { width = width, indent = inner, open = open, code = o.code, bar = false })
    vim.list_extend(out, drawn)
    -- A walked step's line down its side is the done colour.
    local down = step_model.walked(r, s) and 'ThreadAcceptedBar' or line
    draw.gutter(P, drawn[1].first, drawn[1].first, last and '└─' or '├─', line, indent)
    if not last then
      draw.gutter(P, drawn[1].first + 1, drawn[1].last, '│', down, indent)
    elseif down ~= line then
      draw.gutter(P, drawn[1].first + 1, drawn[1].last, ' ▌', down, indent)
    end
  end
  out[1].last = #P.lines - 1
  draw.within(out, 1, { tour = x })
  return out
end

--- A review's tours as sections, M.section each, under a rule that is an
--- item: Tab on it opens every one. Each a row until opened; rows go
--- together, and an opened one is set apart, a row either side.
---@param P thread.Sheet
---@param r thread.Review
---@param o thread.TourOpts
---@return thread.Part[]
function M.sections(P, r, o)
  local out = {} ---@type thread.Part[]
  if #r.tours == 0 then
    return out
  end
  local steps = 0
  for _, x in ipairs(r.tours) do
    steps = steps + #x.steps
  end
  P.add ''
  local row = P.chunks(labels.rule('tours · ' .. #r.tours .. ' · ' .. text.plural(steps, 'step'), o.width), o.indent)
  out[#out + 1] = { kind = 'heading', first = row, last = row, name = 'tours', item = true }
  local apart = true
  for place, x in ipairs(r.tours) do
    local folded = (o.groups or {})[draw.key { kind = 'tour', first = 0, last = 0, tour = x }]
    if folded == nil then
      folded = not o.tours
    end
    if apart or not folded then
      P.add ''
    end
    apart = not folded
    vim.list_extend(out, M.section(P, r, x, vim.tbl_extend('force', o, { folded = folded, place = place })))
  end
  return out
end

return M
