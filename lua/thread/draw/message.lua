--- A message: who wrote it and when, its text with its excerpts and links,
--- its notes with their lines, its diagram and the code it changed. The
--- agent's runs from the left and stops short on the right; yours is set
--- in from the left, as a chat draws it. A thread's introduction is drawn
--- apart: no mark for who wrote it. The tours an
--- agent's message carries are its thread's to draw, under it.

local chunk = require 'thread.model.chunk'
local contract = require 'thread.model.contract'
local chunk_draw = require 'thread.draw.chunk'
local diagram = require 'thread.prose.diagram'
local draw = require 'thread.draw'
local labels = require 'thread.draw.labels'
local message = require 'thread.model.message'
local note = require 'thread.prose.note'
local prose = require 'thread.prose'
local text = require 'thread.base.text'
local thread = require 'thread.model.thread'

local M = {}

-- The label's columns, `󰚩  ` before the text.
local LABEL = 3

-- A card's last few messages, and rows of each one's text.
M.LAST, M.MOST = 2, 6

---@class thread.MessageOpts
---@field width integer  the room, from the indent
---@field indent integer|nil  else the sheet's
---@field most integer|nil  rows of its text at most, an excerpt one row; past them it trails off
---@field intro boolean|nil  its thread's introduction
---@field brief boolean|nil  a card's: its notes, diagram, changes and tours said in a row, not drawn
---@field last integer|nil  a conversation: its last few messages, a row saying how many came before
---@field cut table<integer, true>|nil  filled in: the places of the new messages `most` cut short

--- How wide a message's text runs, label and all: four fifths of the
--- room, so the agent's stop short on the right and yours on the left.
---@param width integer
---@return integer
local function side(width)
  return math.max(16 + LABEL, math.floor(width * 0.8))
end

--- When a message was written, said as a person says it.
---@param r thread.Review
---@param c thread.Conversation
---@param i integer
---@return string|nil
local function when(r, c, i)
  return text.ago(message.when(r, c, i))
end

--- Whether a message is new to you: the agent's, past what you have read.
---@param r thread.Review
---@param c thread.Conversation
---@param i integer
---@return boolean
local function new(r, c, i)
  return c.messages[i].from == 'agent' and i > thread.read(r, c)
end

--- A message in one row: its label, the first line of its text, when it
--- was written on the right.
---@param P thread.Sheet
---@param r thread.Review
---@param c thread.Conversation
---@param i integer  its place in the conversation
---@param o thread.MessageOpts
---@return thread.Part
function M.line(P, r, c, i, o)
  local m = c.messages[i]
  local g, hl = labels.label(m.from, new(r, c, i))
  local said = prose.first_line(m.text, contract.names(r))
  if said == '' and m.tours then
    said = text.plural(#m.tours, 'tour')
  end
  local right = when(r, c, i) or ''
  local room = o.width - LABEL - (right ~= '' and (text.width(right) + 2) or 0)
  local row = P.chunks(
    { { text.pad(g, LABEL), hl }, { text.pad(text.fit(said, room), room), 'ThreadText' }, { right ~= '' and ('  ' .. right) or '', 'ThreadMeta' } },
    o.indent
  )
  return { kind = 'message', first = row, last = row, thread = c.thread, tour = c.tour, step = c.step, message = i }
end

--- Its time, on the right of its first row, when there is room past the
--- text.
---@param P thread.Sheet
---@param row integer
---@param stamp string|nil
---@param right integer  the column it ends at
local function time_at(P, row, stamp, right)
  local line = P.lines[row + 1]
  if not stamp or right - text.width(stamp) < text.width(line) + 2 then
    return
  end
  P.lines[row + 1] = line .. string.rep(' ', right - text.width(stamp) - text.width(line)) .. stamp
  P.hl(row, #P.lines[row + 1] - #stamp, -1, 'ThreadMeta')
end

--- A message whole.
---@param P thread.Sheet
---@param r thread.Review
---@param c thread.Conversation
---@param i integer  its place in the conversation
---@param o thread.MessageOpts
---@return thread.Part[]  the message, then what in it goes somewhere
function M.draw(P, r, c, i, o)
  local m = c.messages[i]
  local indent = o.indent or P.indent
  local spec = chunk.spec(r.diff)
  local is_new = new(r, c, i)
  local out = { { kind = 'message', first = #P.lines, last = #P.lines } } ---@type thread.Part[]
  local stamp = when(r, c, i)
  local room, at, lead = side(o.width), indent, nil ---@type integer, integer, { [1]: string, [2]: string }|nil
  if o.intro then
    -- Read first, so from the left, as wide as reads well.
    room = math.min(o.width, 100)
  else
    local g, hl = labels.label(m.from, is_new)
    lead = { text.pad(g, LABEL), hl }
    if m.from == 'you' then
      at = indent + o.width - room
    end
  end
  local first = #P.lines
  local names = contract.names(r)
  draw.prose(prose.draw(P, m.text, room, { indent = at, spec = spec, lead = lead, most = o.most, names = names }), out)
  if is_new and o.most and o.cut and prose.cut(m.text, room - (lead and text.width(lead[1]) or 0), o.most, names) then
    o.cut[i] = true
  end
  if stamp and #P.lines > first then
    if m.from == 'you' and not o.intro then
      -- To the left of yours, in the spaces it is set in by.
      local line = P.lines[first + 1]
      local from = at - text.width(stamp) - 2
      if from >= indent then
        P.lines[first + 1] = line:sub(1, from) .. stamp .. line:sub(from + #stamp + 1)
        P.hl(first, from, from + #stamp, 'ThreadMeta')
      end
    else
      time_at(P, first, stamp, indent + o.width)
    end
  end
  local hang = at + (o.intro and 0 or LABEL)
  local inner = room - (o.intro and 0 or LABEL)
  if o.brief then
    local more = {} ---@type string[]
    if m.notes then
      more[#more + 1] = text.plural(#m.notes, 'note')
    end
    if m.diagram then
      more[#more + 1] = 'a ' .. m.diagram.kind .. ' diagram'
    end
    if m.changes then
      more[#more + 1] = text.plural(#m.changes, 'change')
    end
    local tours = m.tours or {}
    if #tours > 0 then
      local steps = 0
      for _, x in ipairs(tours) do
        steps = steps + #x.steps
      end
      more[#more + 1] = (#tours == 1 and 'a tour' or (#tours .. ' tours')) .. ' of ' .. text.plural(steps, 'step')
    end
    if #more > 0 then
      P.chunks({ { text.fit('▸ ' .. table.concat(more, ' · '), inner), 'ThreadMeta' } }, hang)
    end
    out[1].last = math.max(out[1].first, #P.lines - 1)
    draw.within(out, 1, { thread = c.thread, tour = c.tour, step = c.step, message = i })
    return out
  end
  for k, n in ipairs(m.notes or {}) do
    if k == 1 then
      P.add ''
    end
    draw.prose(note.line(P, k, n, inner, { indent = hang, spec = spec }), out)
  end
  if m.diagram then
    P.add ''
    local d = diagram.draw(P, m.diagram, inner, hang)
    out[#out + 1] = { kind = 'diagram', first = d.first, last = d.last, diagram = d }
  end
  for j, ch in ipairs(m.changes or {}) do
    if j == 1 then
      P.add ''
    end
    local where = { { j == 1 and 'changed  ' or '         ', 'ThreadMeta' } }
    vim.list_extend(where, chunk_draw.where(ch, chunk.locate(ch, spec)))
    local row = P.chunks(text.fit_chunks(where, inner), hang)
    out[#out + 1] = { kind = 'change', first = row, last = row, chunk = ch }
  end
  out[1].last = math.max(out[1].first, #P.lines - 1)
  draw.within(out, 1, { thread = c.thread, tour = c.tour, step = c.step, message = i })
  return out
end

--- A conversation: its messages, or its last few, a blank row between;
--- a thread's own opens with its introduction.
---@param P thread.Sheet
---@param r thread.Review
---@param c thread.Conversation
---@param o thread.MessageOpts
---@return thread.Part[]
function M.conversation(P, r, c, o)
  local out = {} ---@type thread.Part[]
  local from = math.max(1, #c.messages - (o.last or #c.messages) + 1)
  if from > 1 then
    P.chunks({ { '⋯ ' .. text.plural(from - 1, 'earlier message'), 'ThreadMeta' } }, o.indent)
    P.add ''
  end
  for i = from, #c.messages do
    if i > from then
      P.add ''
    end
    vim.list_extend(out, M.draw(P, r, c, i, vim.tbl_extend('force', o, { intro = i == 1 and not c.step })))
  end
  return out
end

return M
