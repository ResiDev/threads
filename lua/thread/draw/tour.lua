--- A tour: a line, its title and how far you have walked it; or its
--- outline, that line, its introduction, and a line for each step. Its
--- track, for a card's or a winbar's head, is thread.draw.labels.track.

local chunk = require 'thread.model.chunk'
local contract = require 'thread.model.contract'
local draw = require 'thread.draw'
local files = require 'thread.draw.files'
local labels = require 'thread.draw.labels'
local prose = require 'thread.prose'
local step = require 'thread.draw.step'
local text = require 'thread.base.text'
local thread = require 'thread.model.thread'
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
---@field folded boolean|nil  a section: a row, not a tree of its steps' blocks
---@field place integer|nil  a section: its place among its thread's tours, for its colour

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

-- Columns a tour's bar or tree takes, left of its rows.
M.GUTTER = 3

--- A tour as a section of its thread on the screen, the steps the agent
--- put together: its title in its colour, how its steps' conversations
--- stand and how many of its chunks you have accepted; its introduction,
--- what they are about; then a tree of its steps, each a block with its
--- code, or its chunks by file. Folded, a row: a bar in its colour, its
--- title, how many steps and the same counts.
---@param P thread.Sheet
---@param r thread.Review
---@param t thread.Thread
---@param x thread.Tour
---@param o thread.TourOpts
---@return thread.Part[]  the tour, then its steps and what in it goes somewhere
function M.section(P, r, t, x, o)
  local indent = o.indent or P.indent
  local inner, width = indent + M.GUTTER, o.width - M.GUTTER
  local name, line = labels.colour(x.colour, o.place or 1)
  local folded = o.folded and not o.files
  local yes, all = 0, 0
  local conversations = {} ---@type thread.Conversation[]
  for _, s in ipairs(x.steps) do
    conversations[#conversations + 1] = thread.conversation(t, s, x)
    if s.chunk then
      all = all + 1
      yes = yes + (chunk.accepted(r, t, s.chunk) and 1 or 0)
    end
  end
  local right = labels.count(r, conversations)
  if folded then
    table.insert(right, 1, { text.plural(#x.steps, 'step') .. (#right > 0 and '   ' or ''), 'ThreadMeta' })
  end
  if all > 0 then
    vim.list_extend(right, { { #right > 0 and '   ' or '' }, { string.format('✓ %d/%d', yes, all), yes == all and 'ThreadAccepted' or 'ThreadMeta' } })
  end
  local row = draw.row(P, { { x.title, name } }, right, width, inner)
  draw.gutter(P, row, row, folded and '▌' or '━━', line, indent)
  local out = { { kind = 'tour', first = row, last = row, thread = t, tour = x, item = true } } ---@type thread.Part[]
  local spec = chunk.spec(r.diff)
  if folded then
    draw.within(out, 1, { thread = t, tour = x })
    return out
  end
  if x.introduction then
    local from = #P.lines
    local most = o.fold and not (o.open or {})[draw.key(out[1])] and 1 or nil
    draw.prose(
      prose.draw(P, x.introduction, math.min(width, 100), { indent = inner, spec = spec, hl = 'ThreadSummary', most = most, names = contract.names(r) }),
      out
    )
    draw.gutter(P, from, #P.lines - 1, '│', line, indent)
  end
  if o.files then
    P.add ''
    vim.list_extend(out, files.draw(P, r, files.of_thread(t, x), { width = o.width, indent = indent, open = o.open, code = o.code }))
  else
    for i, s in ipairs(x.steps) do
      local last = i == #x.steps
      P.add ''
      draw.gutter(P, #P.lines - 1, #P.lines - 1, '│', line, indent)
      local block = { kind = 'step', first = 0, last = 0, step = s } ---@type thread.Part
      local open = (o.open or {})[draw.key(block)] == true
      local drawn = step.block(P, r, t, x, s, { width = width, indent = inner, open = open, code = o.code, bar = false })
      vim.list_extend(out, drawn)
      -- An accepted step's line down its side is the accepted colour.
      local down = s.chunk and chunk.accepted(r, t, s.chunk) and 'ThreadAcceptedBar' or line
      draw.gutter(P, drawn[1].first, drawn[1].first, last and '└─' or '├─', line, indent)
      if not last then
        draw.gutter(P, drawn[1].first + 1, drawn[1].last, '│', down, indent)
      elseif down ~= line then
        draw.gutter(P, drawn[1].first + 1, drawn[1].last, ' ▌', down, indent)
      end
    end
  end
  out[1].last = #P.lines - 1
  draw.within(out, 1, { thread = t, tour = x })
  return out
end

return M
