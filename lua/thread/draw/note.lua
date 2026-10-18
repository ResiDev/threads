--- A note: as a row, in its review's index of notes and wherever notes
--- are listed; as a line; as a card, for a bubble in the code, its kind
--- and title and its last few messages, or all of them; whole, on its
--- page, with what it says, its replies, where it is and its chunk's
--- code, and the contracts its chunk touches.

local chunk = require 'thread.model.chunk'
local chunk_draw = require 'thread.draw.chunk'
local contracts = require 'thread.draw.contracts'
local conversation = require 'thread.model.conversation'
local draw = require 'thread.draw'
local labels = require 'thread.draw.labels'
local message = require 'thread.draw.message'
local note = require 'thread.model.note'
local review = require 'thread.model.review'
local text = require 'thread.base.text'
local touch = require 'thread.model.touch'

local M = {}

---@class thread.NoteOpts
---@field width integer
---@field indent integer|nil  else the sheet's
---@field messages integer|nil  a card: its last few messages
---@field most integer|nil  a card: rows of each message's text at most
---@field cut table<integer, true>|nil  a card, filled in: the places of the messages it cut short
---@field whole boolean|nil  a card: every message, each whole
---@field writing thread.Writing|nil  a card: rows made in it for what you write there
---@field code boolean|nil  whole: its chunk's code
---@field touches thread.Touches|nil  whole: what touches what in its review; else worked out
---@field label boolean|nil  a row: named by its kind, `note 12`, where rows of several kinds mix
---@field on_chunk boolean|nil  a row: under the chunk it is on, so where it is goes unsaid

--- `note 12`, as labels say it on screen, since ids repeat across kinds.
---@param n thread.Note
---@return string
function M.label(n)
  return 'note ' .. n.id
end

--- `✓ accepted` once you have accepted the code it is on, as it reads
--- now: said first, before its kind, where it is read first.
---@param r thread.Review
---@param n thread.Note
---@return { [1]: string, [2]: string }|nil
local function accepted(r, n)
  local c = review.chunk(r, n.chunk)
  if c and chunk.accepted(r, c) then
    return { '✓ accepted', 'ThreadAccepted' }
  end
end

--- Its state as a glyph, its label, its kind, its title, how it was
--- settled, and whether you have accepted it.
---@param r thread.Review
---@param n thread.Note
---@return thread.Chunks
local function head(r, n)
  local g, hl = labels.conversation(r, conversation.of_note(n))
  local out = { { g .. ' ', hl }, { M.label(n) .. '  ', 'ThreadMeta' } } ---@type thread.Chunks
  local yes = accepted(r, n)
  if yes then
    vim.list_extend(out, { yes, { '  ' } })
  end
  vim.list_extend(out, { labels.kind(n), { '  ' }, { n.title, note.closed(n) and 'ThreadMeta' or 'ThreadTitle' } })
  local status = labels.status(n)
  if status then
    vim.list_extend(out, { { '  ' }, status })
  end
  return out
end

--- Where it is, short: `thread.lua:134`; `on no line`.
---@param r thread.Review
---@param n thread.Note
---@return thread.Chunks
local function short_where(r, n)
  local c = review.chunk(r, n.chunk)
  if not c then
    return { { 'on no line', 'ThreadMeta' } }
  end
  return { chunk_draw.short(c, chunk.spec(r.diff)) }
end

--- A note in one row: its head; on the right, who said its last few
--- messages.
---@param P thread.Sheet
---@param r thread.Review
---@param n thread.Note
---@param o thread.NoteOpts
---@return thread.Part
function M.line(P, r, n, o)
  local c = conversation.of_note(n)
  local row = draw.row(P, head(r, n), labels.dots(n.messages, conversation.read(r, c)), o.width, o.indent)
  return { kind = 'note', first = row, last = row, note = n }
end

--- A note in one row, wherever notes are listed: its state, its id or
--- label, its kind said quietly and its title; where it is on the right.
--- Settled ones are quiet, their status said. Accepted, a green wash
--- and a tick in the margin left of it, the columns lined up still.
---@param P thread.Sheet
---@param r thread.Review
---@param n thread.Note
---@param o thread.NoteOpts|{ ids: integer|nil }
---@return thread.Part
function M.row(P, r, n, o)
  local g, hl = labels.conversation(r, conversation.of_note(n))
  local id = o.label and M.label(n) or tostring(n.id)
  local left = { { g .. ' ', hl }, { string.rep(' ', (o.ids or #id) - #id) .. id .. '  ', 'ThreadMeta' } } ---@type thread.Chunks
  vim.list_extend(left, labels.tag(n))
  left[#left + 1] = { '  ' .. n.title, note.closed(n) and 'ThreadMeta' or 'ThreadText' }
  local right = o.on_chunk and {} or short_where(r, n)
  local status = labels.status(n)
  if status then
    table.insert(right, 1, { vim.trim(status[1]) .. '  ', 'ThreadMeta' })
  end
  local indent = o.indent or P.indent
  local yes = accepted(r, n) ~= nil
  local margin = yes and indent >= 2
  if margin then
    left = vim.list_extend({ { '✓ ', 'ThreadAccepted' } }, left)
  end
  local from = margin and indent - 2 or indent
  local row = draw.row(P, left, right, o.width + indent - from, from)
  if yes then
    P.hl(row, from, -1, 'ThreadAcceptedRow', { priority = 14 })
  end
  return { kind = 'note', first = row, last = row, note = n, item = true }
end

--- A card's head: its state, its kind, and its title whole, wrapped
--- under itself. No label: the card's own look says it is a note, and
--- its kind and title are what you read it for.
---@param P thread.Sheet
---@param r thread.Review
---@param n thread.Note
---@param width integer
---@param indent integer
---@return integer  its first row
local function card_head(P, r, n, width, indent)
  local g, hl = labels.conversation(r, conversation.of_note(n))
  -- Its state when it has one: nobody's move is no glyph, and no gap.
  local lead = vim.trim(g) ~= '' and { { g .. ' ', hl } } or {} ---@type thread.Chunks
  local yes = accepted(r, n)
  if yes then
    vim.list_extend(lead, { yes, { '  ' } })
  end
  vim.list_extend(lead, { labels.kind(n), { '  ' } })
  local status = labels.status(n)
  local hang = 0
  for _, c in ipairs(lead) do
    hang = hang + text.width(c[1])
  end
  local rows = text.wrap(n.title, math.max(12, width - hang))
  local first ---@type integer|nil
  for i, t in ipairs(rows) do
    local line = i == 1 and lead or { { string.rep(' ', hang) } } ---@type thread.Chunks
    line = vim.list_extend(vim.deepcopy(line), { { t, note.closed(n) and 'ThreadMeta' or 'ThreadTitle' } })
    if i == #rows and status then
      vim.list_extend(line, { { '  ' }, status })
    end
    local row = P.chunks(text.fit_chunks(line, width), indent)
    first = first or row
  end
  return assert(first)
end

--- A note as a card: its kind and title, then its last few messages,
--- each cut short; a row says how many came before. With `whole`, every
--- message, none cut.
---@param P thread.Sheet
---@param r thread.Review
---@param n thread.Note
---@param o thread.NoteOpts
---@return thread.Part[]  the note, then what in it goes somewhere
function M.card(P, r, n, o)
  local indent = o.indent or P.indent
  local first = card_head(P, r, n, o.width, indent)
  local out = { { kind = 'note', first = first, last = first } } ---@type thread.Part[]
  P.add ''
  local most, last = o.most or message.MOST, o.messages or message.LAST ---@type integer|nil, integer
  if o.whole then
    most, last = nil, #n.messages
  end
  local conv = conversation.of_note(n)
  vim.list_extend(
    out,
    message.conversation(P, r, conv, { width = o.width, indent = indent, most = most, brief = true, last = last, cut = o.cut, writing = o.writing })
  )
  out[#out + 1] = message.reply(conv, #P.lines - 1, { width = o.width, indent = indent })
  -- Whose move it is, however little of the conversation shows.
  local status = message.status(conv)
  if status then
    P.add ''
    P.chunks({ { text.fit(status, o.width), 'ThreadMeta' } }, indent)
  end
  out[1].last = #P.lines - 1
  draw.within(out, 1, { note = n })
  return out
end

--- A note whole, on its page: its head; what it says; its replies, and
--- where the next goes; where it is, its code with `code`; the contracts
--- its chunk touches, worked out.
---@param P thread.Sheet
---@param r thread.Review
---@param n thread.Note
---@param o thread.NoteOpts
---@return thread.Part[]  the note, then what in it goes somewhere
function M.whole(P, r, n, o)
  local indent = o.indent or P.indent
  local spec = chunk.spec(r.diff)
  local first = P.chunks(text.fit_chunks(head(r, n), o.width), indent)
  local out = { { kind = 'note', first = first, last = first, item = true } } ---@type thread.Part[]
  local conv = conversation.of_note(n)
  ---@param i integer
  local function said(i)
    local at = #out + 1
    vim.list_extend(out, message.draw(P, r, conv, i, { width = o.width, indent = indent, intro = i == 1 }))
    out[at].item = true
  end
  -- What it says, then the conversation in answer to it, then the code
  -- it is about: you read on from what was said to what was said back.
  if conv.messages[1] then
    P.add ''
    said(1)
  end
  -- The replies under a rule, as a step's page has.
  for i = 2, #conv.messages do
    P.add ''
    if i == 2 then
      P.chunks(labels.rule('conversation', o.width), indent)
      P.add ''
    end
    said(i)
  end
  out[#out + 1] = message.reply(conv, #P.lines - 1, { width = o.width, indent = indent })
  if conversation.move(conv) == 'agent' then
    P.add ''
    P.chunks({ { 'waiting on the agent', 'ThreadMeta' } }, indent)
  elseif #conv.messages == 1 then
    P.add ''
    P.chunks({ { text.fit('r replies; the answer comes back here.', o.width), 'ThreadMeta' } }, indent)
  end
  local c = review.chunk(r, n.chunk)
  if c and o.code then
    P.add ''
    local at = #out + 1
    vim.list_extend(out, chunk_draw.draw(P, c, spec, { width = o.width, indent = indent, accepted = chunk.accepted(r, c) }))
    -- An item, so j lands on it and ⏎ goes to it in the code.
    out[at].item = true
  elseif c then
    P.add ''
    local row = P.chunks(text.fit_chunks(chunk_draw.where(c, chunk.locate(c, spec)), o.width), indent)
    out[#out + 1] = { kind = 'chunk', first = row, last = row, chunk = c, item = true }
  else
    P.add ''
    P.chunks({ { 'on no line', 'ThreadMeta' } }, indent)
  end
  local T = o.touches or touch.index(r)
  local touched = T.contracts[n] or {}
  if #touched > 0 then
    P.add ''
    vim.list_extend(out, contracts.draw(P, touched, { width = o.width, indent = indent, all = true, review = r }))
  end
  out[1].last = #P.lines - 1
  draw.within(out, 1, { note = n })
  return out
end

return M
