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

---@class thread.ThreadOpts
---@field width integer
---@field indent integer|nil  else the sheet's
---@field messages integer|nil  a card: its last few messages
---@field most integer|nil  a card: rows of each message's text at most
---@field cut table<integer, true>|nil  a card, filled in: the places of the messages it cut short

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
  local g, hl = labels.conversation(r, thread.conversation(t))
  local out = { { g .. ' ', hl }, { '#' .. t.id .. '  ', 'ThreadMeta' }, { title(t), thread.closed(t) and 'ThreadMeta' or 'ThreadTitle' } } ---@type thread.Chunks
  vim.list_extend(out, labels.badges(t, true))
  local closed = labels.closed(t)
  if closed then
    vim.list_extend(out, { { '  ' }, closed })
  end
  local steps = 0
  for _, c in ipairs(thread.conversations(t)) do
    steps = steps + ((c.step and thread.for_you(r, c)) and 1 or 0)
  end
  if steps > 0 then
    out[#out + 1] = { '  ' .. text.plural(steps, 'step') .. ' for you', 'ThreadSignAnswered' }
  end
  return out
end

--- How many of its chunks you have accepted in it, of how many.
---@param r thread.Review
---@param t thread.Thread
---@return integer accepted, integer chunks
local function accepted(r, t)
  local all = thread.chunks(r, t)
  local yes = 0
  for _, c in ipairs(all) do
    yes = yes + (chunk.accepted(r, t, c) and 1 or 0)
  end
  return yes, #all
end

--- What a thread's line has on the right: how much of it you have
--- accepted, and who said the last few of its messages.
---@param r thread.Review
---@param t thread.Thread
---@return thread.Chunks
local function right(r, t)
  local out = {} ---@type thread.Chunks
  local yes, all = accepted(r, t)
  if all > 0 then
    out[#out + 1] = { string.format('✓ %d/%d  ', yes, all), yes == all and 'ThreadAccepted' or 'ThreadMeta' }
  end
  return vim.list_extend(out, labels.dots(t.messages, thread.read(r, thread.conversation(t))))
end

--- A thread in one row: its head; on the right, how much of it you have
--- accepted and who said its last few messages.
---@param P thread.Sheet
---@param r thread.Review
---@param t thread.Thread
---@param o thread.ThreadOpts
---@return thread.Part
function M.line(P, r, t, o)
  local row = draw.row(P, head(r, t), right(r, t), o.width, o.indent)
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
  local first = draw.row(P, head(r, t), right(r, t), o.width, indent)
  local out = { { kind = 'thread', first = first, last = first } } ---@type thread.Part[]
  P.add ''
  local own = thread.conversation(t)
  vim.list_extend(
    out,
    message.conversation(
      P,
      r,
      own,
      { width = o.width, indent = indent, most = o.most or message.MOST, brief = true, last = o.messages or message.LAST, cut = o.cut }
    )
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
    vim.list_extend(out, chunk_draw.draw(P, t.chunk, chunk.spec(r.diff), { width = o.width, indent = indent, accepted = chunk.accepted(r, t, t.chunk) }))
  end
  for i, m in ipairs(t.messages) do
    P.add ''
    vim.list_extend(out, message.draw(P, r, own, i, { width = o.width, indent = indent, intro = i == 1 }))
    for _, x in ipairs(m.tours or {}) do
      P.add ''
      vim.list_extend(out, tour.outline(P, r, t, x, { width = o.width - 2, indent = indent + 2 }))
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
