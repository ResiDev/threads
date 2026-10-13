--- A step: as a line in its tour's outline, labelled with its id; as a
--- card, in the code above its chunk; whole, on a page or in the screen,
--- with its chunk's code, what it says, its notes, its diagram, its checks
--- and its conversation.

local check = require 'thread.draw.check'
local chunk = require 'thread.model.chunk'
local chunk_draw = require 'thread.draw.chunk'
local diagram = require 'thread.prose.diagram'
local draw = require 'thread.draw'
local labels = require 'thread.draw.labels'
local link = require 'thread.prose.link'
local message = require 'thread.draw.message'
local note = require 'thread.prose.note'
local prose = require 'thread.prose'
local step = require 'thread.model.step'
local text = require 'thread.base.text'
local thread = require 'thread.model.thread'

local M = {}

---@class thread.StepOpts
---@field width integer
---@field indent integer|nil  else the sheet's
---@field here boolean|nil  a line: the step you are on
---@field ids integer|nil  a line: the width of its tour's widest id, so the titles line up
---@field most integer|nil  a card: rows of each message's text at most
---@field messages integer|nil  a card: its last few replies; else message.LAST
---@field cut table<integer, true>|nil  a card, filled in: the places of the replies it cut short
---@field whole boolean|nil  a card: its replies whole, none cut

--- A step's state: its conversation's, once there is one; else walked
--- or not.
---@param r thread.Review
---@param t thread.Thread
---@param x thread.Tour
---@param s thread.Step
---@return string glyph, string hl
local function state(r, t, x, s)
  if #s.messages > 0 then
    return labels.conversation(r, thread.conversation(t, s, x))
  end
  return labels.walked(step.walked(r, t, s))
end

--- Where a step is, short, ticked when you have accepted its chunk:
--- `✓ thread.lua:134`; `page` on no line.
---@param r thread.Review
---@param t thread.Thread
---@param s thread.Step
---@return thread.Chunks
local function short_where(r, t, s)
  local c = s.chunk
  if not c then
    return { { 'page', 'ThreadMeta' } }
  end
  local out = { chunk_draw.short(c, chunk.spec(r.diff)) }
  if chunk.accepted(r, t, c) then
    table.insert(out, 1, { '✓ ', 'ThreadAccepted' })
  end
  return out
end

--- A step in one row: its state, its id, its title and verdict, and on
--- the right where it is.
---@param P thread.Sheet
---@param r thread.Review
---@param t thread.Thread
---@param x thread.Tour
---@param s thread.Step
---@param o thread.StepOpts
---@return thread.Part
function M.line(P, r, t, x, s, o)
  local g, hl = state(r, t, x, s)
  local id = tostring(s.id)
  local left = {
    { g .. ' ', hl },
    { string.rep(' ', (o.ids or #id) - #id) .. id .. '  ', 'ThreadMeta' },
    { s.title, o.here and 'ThreadCrumbHere' or 'ThreadText' },
  }
  local v = labels.verdict(s)
  if v then
    vim.list_extend(left, { { '  ' }, v })
  end
  local row = draw.row(P, left, short_where(r, t, s), o.width, o.indent or P.indent)
  return { kind = 'step', first = row, last = row, thread = t, tour = x, step = s }
end

--- A step as a card, in the code above its chunk: its tour's track and
--- its title, the thread it is in; what it says; its last few replies.
--- Its notes are drawn in the code.
---@param P thread.Sheet
---@param r thread.Review
---@param t thread.Thread
---@param x thread.Tour
---@param s thread.Step
---@param o thread.StepOpts
---@return thread.Part[]  the step, then what in it goes somewhere
function M.card(P, r, t, x, s, o)
  local indent = o.indent or P.indent
  local spec = chunk.spec(r.diff)
  local out = { { kind = 'step', first = #P.lines, last = #P.lines } } ---@type thread.Part[]
  local head = labels.track(r, t, x, s)
  vim.list_extend(head, { { '  ' }, { s.title, 'ThreadTitle' }, { ' · ' .. (t.title or ('#' .. t.id)), 'ThreadCrumb' } })
  local v = labels.verdict(s)
  draw.row(P, head, v and { v } or {}, o.width, indent)
  if s.text then
    P.add ''
    draw.prose(prose.draw(P, s.text, o.width, { indent = indent, spec = spec }), out)
  end
  if #s.messages > 0 then
    P.add ''
    local c = thread.conversation(t, s, x)
    vim.list_extend(
      out,
      message.conversation(P, r, c, {
        width = o.width,
        indent = indent,
        most = not o.whole and (o.most or message.MOST) or nil,
        brief = true,
        last = o.messages or message.LAST,
        cut = o.cut,
      })
    )
  end
  out[1].last = #P.lines - 1
  draw.within(out, 1, { thread = t, tour = x, step = s })
  return out
end

--- A step whole: its link and title, where it is in its review, its
--- labels; its chunk's code with its notes on their lines; what it says;
--- its notes, with their lines when the code above does not show them;
--- its diagram, its checks and its conversation.
---@param P thread.Sheet
---@param r thread.Review
---@param t thread.Thread
---@param x thread.Tour
---@param s thread.Step
---@param o thread.StepOpts
---@return thread.Part[]  the step, then what in it goes somewhere
function M.whole(P, r, t, x, s, o)
  local indent = o.indent or P.indent
  local spec = chunk.spec(r.diff)
  local out = { { kind = 'step', first = #P.lines, last = #P.lines } } ---@type thread.Part[]
  local head = { { link.to(thread.conversation(t, s, x)) .. '  ', 'ThreadMeta' }, { s.title, 'ThreadTitle' } }
  P.chunks(text.fit_chunks(head, o.width), indent)
  draw.row(P, { { 'in ' .. x.title .. ' · ' .. (t.title or ('#' .. t.id)), 'ThreadCrumb' } }, labels.track(r, t, x, s), o.width, indent)
  local badges = labels.badges(s)
  if #badges > 0 then
    badges[1] = { '' }
    P.chunks(text.fit_chunks(badges, o.width), indent)
  end
  local risk = labels.risk(s)
  if risk and s.risk_why then
    draw.prose(prose.draw(P, s.risk_why, o.width, { indent = indent, lead = { 'why: ', risk[2] } }), out)
  end
  -- Its notes on the lines the code shows, by where they are.
  local shown = {} ---@type table<string, true>
  if s.chunk then
    P.add ''
    local accepted = chunk.accepted(r, t, s.chunk)
    for _, p in ipairs(chunk_draw.draw(P, s.chunk, spec, { width = o.width, indent = indent, notes = s.notes, accepted = accepted })) do
      out[#out + 1] = p
      local c = p.kind == 'line' and p.chunk
      if c then
        shown[c.file .. (c.side == 'old' and ':-' or ':') .. c.line] = true
      end
    end
  end
  if s.text then
    P.add ''
    draw.prose(prose.draw(P, s.text, o.width, { indent = indent, spec = spec }), out)
  end
  for k, n in ipairs(s.notes or {}) do
    if k == 1 then
      P.add ''
    end
    local at = chunk.locate(n, spec)
    local key = at and (n.file .. (at.old and (':-' .. at.old) or (':' .. at.line)))
    if key and shown[key] and n.rev == (s.chunk and s.chunk.rev) then
      draw.prose(note.draw(P, k, n, o.width, { indent = indent, spec = spec }), out)
    else
      draw.prose(note.line(P, k, n, o.width, { indent = indent, spec = spec }), out)
    end
  end
  if s.diagram then
    P.add ''
    local d = diagram.draw(P, s.diagram, o.width, indent)
    out[#out + 1] = { kind = 'diagram', first = d.first, last = d.last, diagram = d }
  end
  for k, c in ipairs(s.checks or {}) do
    if k == 1 then
      P.add ''
      P.chunks(labels.rule('checks', o.width), indent)
    end
    P.add ''
    vim.list_extend(out, check.draw(P, c, { width = o.width, indent = indent }))
  end
  if #s.messages > 0 then
    P.add ''
    P.chunks(labels.rule('replies', o.width), indent)
    P.add ''
    vim.list_extend(out, message.conversation(P, r, thread.conversation(t, s, x), { width = o.width, indent = indent }))
  end
  out[1].last = #P.lines - 1
  draw.within(out, 1, { thread = t, tour = x, step = s })
  return out
end

return M
