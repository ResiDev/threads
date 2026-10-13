--- A thread: as a line, in its review's list; as a card, its last few
--- messages, for a bubble in the code; whole, in the screen, with its
--- chunk's code, its introduction set apart, its conversation, the tours
--- under the messages that brought them, and its checks.

local check = require 'thread.draw.check'
local chunk = require 'thread.model.chunk'
local chunk_draw = require 'thread.draw.chunk'
local draw = require 'thread.draw'
local labels = require 'thread.draw.labels'
local message = require 'thread.draw.message'
local prose = require 'thread.prose'
local text = require 'thread.base.text'
local thread = require 'thread.model.thread'
local tour = require 'thread.draw.tour'

local M = {}

-- A card's last few messages, unless it says.
M.CARD = 2

---@class thread.ThreadOpts
---@field width integer
---@field indent integer|nil  else the sheet's
---@field spec thread.DiffSpec|nil  what its review is about
---@field messages integer|nil  a card: its last few messages
---@field most integer|nil  a card: rows of each message's text at most

--- Its title: the agent's; on a thread of yours with none yet, the first
--- line of what you said.
---@param t thread.Thread
---@return string
local function title(t)
  return t.title or prose.first_line(t.messages[1] and t.messages[1].text)
end

--- Its state as a glyph, its id, its title, its labels, how it was
--- closed, and how many of its steps want you.
---@param r thread.Review
---@param t thread.Thread
---@return thread.Chunks
local function head(r, t)
  local own = thread.conversation(t)
  local g, hl = labels.conversation(r, own)
  local out = { { g .. ' ', hl }, { '#' .. t.id .. '  ', 'ThreadMeta' }, { title(t), thread.closed(t) and 'ThreadMeta' or 'ThreadTitle' } } ---@type thread.Chunks
  vim.list_extend(out, labels.badges(t, true))
  local closed = labels.closed(t)
  if closed then
    vim.list_extend(out, { { '  ' }, closed })
  end
  local steps = 0
  for _, c in ipairs(thread.conversations(t)) do
    steps = steps + ((c.step and labels.for_you(r, c)) and 1 or 0)
  end
  if steps > 0 then
    out[#out + 1] = { '  ' .. text.plural(steps, 'step') .. ' for you', 'ThreadSignAnswered' }
  end
  return out
end

--- A thread in one row: its head, and on the right who said the last few
--- of its messages.
---@param P thread.Sheet
---@param r thread.Review
---@param t thread.Thread
---@param o thread.ThreadOpts
---@return thread.Part
function M.line(P, r, t, o)
  local own = thread.conversation(t)
  local row = draw.row(P, head(r, t), labels.dots(t.messages, thread.read(r, own)), o.width, o.indent)
  return { kind = 'thread', first = row, last = row, thread = t }
end

--- A thread as a card: its head, then its last few messages, each cut
--- short; a row says how many came before.
---@param P thread.Sheet
---@param r thread.Review
---@param t thread.Thread
---@param o thread.ThreadOpts
---@return thread.Part[]  the thread, then what in it goes somewhere
function M.card(P, r, t, o)
  local indent = o.indent or P.indent
  local own = thread.conversation(t)
  local first = draw.row(P, head(r, t), labels.dots(t.messages, thread.read(r, own)), o.width, indent)
  local out = { { kind = 'thread', first = first, last = first } } ---@type thread.Part[]
  local from = math.max(1, #t.messages - (o.messages or M.CARD) + 1)
  P.add ''
  if from > 1 then
    P.chunks({ { '⋯ ' .. text.plural(from - 1, 'earlier message'), 'ThreadMeta' } }, indent)
    P.add ''
  end
  vim.list_extend(
    out,
    message.conversation(P, r, own, { width = o.width, indent = indent, spec = o.spec, most = o.most or message.MOST, from = from, brief = true })
  )
  out[1].last = #P.lines - 1
  draw.within(out, 1, { thread = t })
  return out
end

--- A thread whole: its head and labels; its chunk's code; its
--- introduction, set apart; the rest of its conversation, each tour under
--- the message that brought it; its checks.
---@param P thread.Sheet
---@param r thread.Review
---@param t thread.Thread
---@param o thread.ThreadOpts
---@return thread.Part[]  the thread, then what in it goes somewhere
function M.whole(P, r, t, o)
  local indent = o.indent or P.indent
  local own = thread.conversation(t)
  local first = P.chunks(text.fit_chunks(head(r, t), o.width), indent)
  local out = { { kind = 'thread', first = first, last = first } } ---@type thread.Part[]
  local risk = labels.risk(t)
  if risk and t.risk_why then
    draw.prose(prose.draw(P, t.risk_why, o.width, { indent = indent, lead = { 'why: ', risk[2] } }), out)
  end
  if t.chunk then
    P.add ''
    vim.list_extend(out, chunk_draw.draw(P, t.chunk, { width = o.width, indent = indent, spec = o.spec, accepted = chunk.accepted(r, t, t.chunk) }))
  end
  for i, m in ipairs(t.messages) do
    P.add ''
    vim.list_extend(out, message.draw(P, r, own, i, { width = o.width, indent = indent, spec = o.spec, intro = i == 1 }))
    for _, x in ipairs(m.tours or {}) do
      P.add ''
      vim.list_extend(out, tour.outline(P, r, t, x, { width = o.width - 2, indent = indent + 2, spec = o.spec }))
    end
  end
  for k, c in ipairs(t.checks or {}) do
    if k == 1 then
      P.add ''
      P.chunks(labels.rule('checks', o.width), indent)
    end
    P.add ''
    vim.list_extend(out, check.draw(P, c, { width = o.width, indent = indent }))
  end
  out[1].last = #P.lines - 1
  draw.within(out, 1, { thread = t })
  return out
end

return M
