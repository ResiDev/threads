--- A tour: a line, its title and how far you have walked it; or its
--- outline, that line, its introduction, and a line for each step. Its
--- track, for a card's or a winbar's head, is thread.draw.labels.track.

local chunk = require 'thread.model.chunk'
local draw = require 'thread.draw'
local files = require 'thread.draw.files'
local labels = require 'thread.draw.labels'
local prose = require 'thread.prose'
local step = require 'thread.draw.step'
local text = require 'thread.base.text'
local tour = require 'thread.model.tour'

local M = {}

---@class thread.TourOpts
---@field width integer
---@field indent integer|nil  else the sheet's
---@field here thread.Step|nil  the step you are on
---@field open table<string, true>|nil  a section: the steps or files opened, by draw.key
---@field files boolean|nil  a section: its chunks by file
---@field fold boolean|nil  a section: its introduction one row
---@field code boolean|nil  a section: each step's code, not only where opened

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

--- A tour as a section of its thread on the screen: a rule with its
--- title and how much of it you have accepted and walked; its
--- introduction; then each step as a block with its code, or its chunks
--- by file.
---@param P thread.Sheet
---@param r thread.Review
---@param t thread.Thread
---@param x thread.Tour
---@param o thread.TourOpts
---@return thread.Part[]  the tour, then its steps and what in them goes somewhere
function M.section(P, r, t, x, o)
  local indent = o.indent or P.indent
  local yes, all = 0, 0
  for _, s in ipairs(x.steps) do
    if s.chunk then
      all = all + 1
      yes = yes + (chunk.accepted(r, t, s.chunk) and 1 or 0)
    end
  end
  local said = {} ---@type string[]
  if all > 0 then
    said[#said + 1] = string.format('✓ %d/%d', yes, all)
  end
  said[#said + 1] = tour.walked(r, t, x) .. '/' .. #x.steps .. ' walked'
  local tail = table.concat(said, ' · ')
  -- `── title ──── ✓ 3/7 · 2/7 walked`: the title gives way first, then
  -- the walk.
  if text.width(tail) > o.width - 12 then
    tail = said[1]
  end
  local title = text.fit(x.title, math.max(4, o.width - 3 - 4 - text.width(tail)))
  local fill = math.max(2, o.width - 3 - text.width(title) - 2 - text.width(tail))
  local row = P.chunks(
    text.fit_chunks({
      { '── ', 'ThreadTabRule' },
      { title, 'ThreadTitle' },
      { ' ' .. string.rep('─', fill) .. ' ', 'ThreadTabRule' },
      { tail, yes == all and all > 0 and 'ThreadAccepted' or 'ThreadMeta' },
    }, o.width),
    indent
  )
  local out = { { kind = 'tour', first = row, last = row, thread = t, tour = x, item = true } } ---@type thread.Part[]
  if x.introduction then
    P.add ''
    local most = o.fold and not (o.open or {})[draw.key(out[1])] and 1 or nil
    draw.prose(prose.draw(P, x.introduction, o.width, { indent = indent, spec = chunk.spec(r.diff), hl = 'ThreadMeta', most = most }), out)
  end
  if o.files then
    P.add ''
    vim.list_extend(out, files.draw(P, r, files.of_thread(t, x), { width = o.width, indent = indent, open = o.open, code = o.code }))
  else
    local ids = 0
    for _, s in ipairs(x.steps) do
      ids = math.max(ids, #tostring(s.id))
    end
    for _, s in ipairs(x.steps) do
      P.add ''
      local block = { kind = 'step', first = 0, last = 0, step = s } ---@type thread.Part
      local open = (o.open or {})[draw.key(block)] == true
      vim.list_extend(out, step.block(P, r, t, x, s, { width = o.width - 2, indent = indent + 2, ids = ids, open = open, code = o.code }))
    end
  end
  out[1].last = #P.lines - 1
  draw.within(out, 1, { thread = t, tour = x })
  return out
end

return M
