--- A step: as a line in its tour's outline, labelled with its id; as a
--- block, in its tour's section of the review; as a card, in the code
--- above its chunk; whole, on its page, with its chunk's code, what it
--- says and its conversation. Wherever it is drawn but a line, the notes
--- on its chunk are a row each under it, a key away.

local chunk = require 'thread.model.chunk'
local chunk_draw = require 'thread.draw.chunk'
local conversation = require 'thread.model.conversation'
local draw = require 'thread.draw'
local labels = require 'thread.draw.labels'
local message = require 'thread.draw.message'
local note_draw = require 'thread.draw.note'
local prose = require 'thread.prose'
local review = require 'thread.model.review'
local step = require 'thread.model.step'
local text = require 'thread.base.text'
local touch = require 'thread.model.touch'

local M = {}

---@class thread.StepOpts
---@field width integer
---@field indent integer|nil  else the sheet's
---@field here boolean|nil  a line: the step you are on
---@field ids integer|nil  a line: the width of its tour's widest id, so the titles line up
---@field label boolean|nil  a line: named by its kind, `step 3`, where rows of several kinds mix
---@field most integer|nil  a card: rows of each message's text at most
---@field messages integer|nil  a card: its last few messages; else message.LAST
---@field cut table<integer, true>|nil  a card, filled in: the places of the messages it cut short
---@field whole boolean|nil  a card: its messages whole, none cut
---@field writing thread.Writing|nil  a card: rows made in it for what you write there
---@field open boolean|nil  a block: drawn whole, its code unfolded
---@field code boolean|nil  a block: its code, unless walked; else only opened
---@field bar boolean|nil  a block: false, no bar down a walked one's side, its tour saying it

-- The prose reads well this wide at most.
local PROSE = 100

--- A step's state: its conversation's, once there is one; else walked
--- or not.
---@param r thread.Review
---@param x thread.Tour
---@param s thread.Step
---@return string glyph, string hl
local function state(r, x, s)
  if #s.messages > 0 then
    return labels.conversation(r, conversation.of_step(s, x))
  end
  return labels.walked(step.walked(r, s))
end

--- Where a step is, short: `thread.lua:134`; `page` on no line.
---@param r thread.Review
---@param s thread.Step
---@return thread.Chunks
local function short_where(r, s)
  local c = review.chunk(r, s.chunk)
  if not c then
    return { { 'page', 'ThreadMeta' } }
  end
  return { chunk_draw.short(c, chunk.spec(r.diff)) }
end

--- `step 3`, as labels say it on screen, since ids repeat across kinds.
---@param s thread.Step
---@return string
function M.label(s)
  return 'step ' .. s.id
end

--- A step in one row: its state, its id, its title, and on the right
--- where it is.
---@param P thread.Sheet
---@param r thread.Review
---@param x thread.Tour
---@param s thread.Step
---@param o thread.StepOpts
---@return thread.Part
function M.line(P, r, x, s, o)
  local g, hl = state(r, x, s)
  local id = o.label and M.label(s) or tostring(s.id)
  local left = {
    { g .. ' ', hl },
    { string.rep(' ', (o.ids or #id) - #id) .. id .. '  ', 'ThreadMeta' },
    { s.title, o.here and 'ThreadCrumbHere' or 'ThreadText' },
  }
  local row = draw.row(P, left, short_where(r, s), o.width, o.indent or P.indent)
  return { kind = 'step', first = row, last = row, tour = x, step = s }
end

--- The notes on its chunk, a row each as thread.draw.note draws one,
--- set in at `indent`. Each is an item, so the cursor lands on it and ⏎
--- opens it.
---@param P thread.Sheet
---@param r thread.Review
---@param s thread.Step
---@param width integer
---@param indent integer
---@param out thread.Part[]
---@param item boolean|nil  each an item of the screen's
---@return integer  how many
function M.notes(P, r, s, width, indent, out, item)
  local list = touch.notes_on(r, s)
  for _, n in ipairs(list) do
    local part = note_draw.row(P, r, n, { width = width, indent = indent, label = true, on_chunk = true })
    part.item = item
    out[#out + 1] = part
  end
  return #list
end

-- A block's code, rows at most, until it is opened.
M.CODE = 12

--- A step as a block, in its tour's section: its state and title, where
--- it is on the right; what it says; its last message, or every one once
--- opened; the notes on its chunk; its chunk's code. A walked one has
--- a bar down its side; the code shows with `code`, unless walked, and
--- opened.
---@param P thread.Sheet
---@param r thread.Review
---@param x thread.Tour
---@param s thread.Step
---@param o thread.StepOpts
---@return thread.Part[]  the step, then what in it goes somewhere
function M.block(P, r, x, s, o)
  local indent = o.indent or P.indent
  local spec = chunk.spec(r.diff)
  local c = review.chunk(r, s.chunk)
  local walked = step.walked(r, s)
  local first = #P.lines
  local out = { { kind = 'step', first = first, last = first, item = true } } ---@type thread.Part[]
  -- Walked, or whose move its conversation is.
  local g, hl = ' ', 'ThreadMeta'
  if walked then
    g, hl = labels.walked(true)
  elseif #s.messages > 0 then
    g, hl = labels.conversation(r, conversation.of_step(s, x))
  end
  local left = { { g .. ' ', hl }, { s.title, walked and 'ThreadMeta' or 'ThreadTitle' } }
  -- Room for the path, the title keeping the rest.
  local right = c and chunk_draw.path(c, spec, math.floor(o.width * 0.4)) or { { 'page', 'ThreadMeta' } }
  draw.row(P, left, right, o.width, indent)
  local hang = indent + 2
  local room = o.width - (hang - indent)
  if s.text then
    draw.prose(prose.draw(P, s.text, math.min(room, PROSE), { indent = hang, review = r, most = not o.open and 3 or nil }), out)
  end
  if #s.messages > 0 then
    P.add ''
    vim.list_extend(out, message.conversation(P, r, conversation.of_step(s, x), { width = room, indent = hang, last = not o.open and 1 or nil }))
  end
  local notes = touch.notes_on(r, s)
  if #notes > 0 then
    P.add ''
    M.notes(P, r, s, room, hang, out)
  end
  if c and (o.open or (o.code and not walked)) then
    P.add ''
    vim.list_extend(out, chunk_draw.draw(P, c, spec, { width = room, indent = hang, rows = not o.open and M.CODE or nil }))
  end
  out[1].last = #P.lines - 1
  if walked and o.bar ~= false then
    draw.bar(P, first, out[1].last, indent, 'ThreadAcceptedBar')
  end
  draw.within(out, 1, { tour = x, step = s })
  return out
end

--- A step as a card, in the code above its chunk: its tour's track, its
--- title and its tour's; what it says; its last few messages; the notes
--- on its chunk.
---@param P thread.Sheet
---@param r thread.Review
---@param x thread.Tour
---@param s thread.Step
---@param o thread.StepOpts
---@return thread.Part[]  the step, then what in it goes somewhere
function M.card(P, r, x, s, o)
  local indent = o.indent or P.indent
  local out = { { kind = 'step', first = #P.lines, last = #P.lines } } ---@type thread.Part[]
  local head = labels.track(r, x, s)
  vim.list_extend(head, { { '  ' }, { s.title, 'ThreadTitle' }, { ' · ' .. x.title, 'ThreadCrumb' } })
  draw.row(P, head, { { M.label(s), 'ThreadMeta' } }, o.width, indent)
  if s.text then
    P.add ''
    local first = #P.lines
    draw.prose(prose.draw(P, s.text, o.width, { indent = indent, review = r }), out)
    out[#out + 1] = { kind = 'block', name = 'prose', first = first, last = #P.lines - 1 }
  end
  local conv = conversation.of_step(s, x)
  if #s.messages > 0 then
    P.add ''
    vim.list_extend(
      out,
      message.conversation(P, r, conv, {
        width = o.width,
        indent = indent,
        most = not o.whole and (o.most or message.MOST) or nil,
        brief = true,
        last = o.messages or message.LAST,
        cut = o.cut,
        writing = o.writing,
      })
    )
  elseif o.writing then
    message.writing(P, o.writing, out)
  end
  out[#out + 1] = message.reply(conv, #P.lines - 1, { width = o.width, indent = indent })
  -- Whose move it is, however little of the conversation shows.
  local status = message.status(conv)
  if status then
    P.add ''
    P.chunks({ { text.fit(status, o.width), 'ThreadMeta' } }, indent)
  end
  if #touch.notes_on(r, s) > 0 then
    P.add ''
    M.notes(P, r, s, o.width, indent, out)
  end
  out[1].last = #P.lines - 1
  draw.within(out, 1, { tour = x, step = s })
  return out
end

--- A step whole, on its page: its label and title, where it is in its
--- tour; its chunk's code; what it says; its conversation, and where the
--- next message goes; the notes on its chunk, each an item.
---@param P thread.Sheet
---@param r thread.Review
---@param x thread.Tour
---@param s thread.Step
---@param o thread.StepOpts
---@return thread.Part[]  the step, then what in it goes somewhere
function M.whole(P, r, x, s, o)
  local indent = o.indent or P.indent
  local spec = chunk.spec(r.diff)
  local out = { { kind = 'step', first = #P.lines, last = #P.lines, item = true } } ---@type thread.Part[]
  local head = { { M.label(s) .. '  ', 'ThreadMeta' }, { s.title, 'ThreadTitle' } }
  P.chunks(text.fit_chunks(head, o.width), indent)
  local at = 0
  for i, other in ipairs(x.steps) do
    at = other == s and i or at
  end
  local name = labels.colour(x.colour)
  draw.row(P, { { 'in ', 'ThreadCrumb' }, { x.title, name }, { ' · ' .. at .. ' of ' .. #x.steps, 'ThreadCrumb' } }, labels.track(r, x, s), o.width, indent)
  local c = review.chunk(r, s.chunk)
  if c then
    P.add ''
    local code_at = #out + 1
    vim.list_extend(out, chunk_draw.draw(P, c, spec, { width = o.width, indent = indent }))
    -- An item, so j lands on it and ⏎ goes to it in the code.
    out[code_at].item = true
  end
  if s.text then
    P.add ''
    draw.prose(prose.draw(P, s.text, math.min(o.width, PROSE), { indent = indent, review = r }), out)
  end
  -- The conversation straight after what it answers; with none yet,
  -- your first message goes there.
  local conv = conversation.of_step(s, x)
  if #conv.messages > 0 then
    P.add ''
    P.chunks(labels.rule('conversation', o.width), indent)
    P.add ''
    local from = #out + 1
    vim.list_extend(out, message.conversation(P, r, conv, { width = o.width, indent = indent }))
    for i = from, #out do
      out[i].item = out[i].kind == 'message' or nil
    end
  end
  out[#out + 1] = message.reply(conv, #P.lines - 1, { width = o.width, indent = indent })
  if conversation.move(conv) == 'agent' then
    P.add ''
    P.chunks({ { 'waiting on the agent', 'ThreadMeta' } }, indent)
  end
  local notes = touch.notes_on(r, s)
  if #notes > 0 then
    P.add ''
    P.chunks(labels.rule('notes here · ' .. #notes, o.width), indent)
    P.add ''
    M.notes(P, r, s, o.width, indent, out, true)
  end
  out[1].last = #P.lines - 1
  draw.within(out, 1, { tour = x, step = s })
  return out
end

return M
