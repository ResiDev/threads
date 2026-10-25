--- What hangs above a note's or step's first line in the code: a note's
--- bubble or a step's card, drawn by draw/ at its card size, brief or
--- whole, and framed: a note's in yellow, a step's in the colour of whose
--- move it is, so the two are never taken for each other. The review it
--- is in on the top edge and, while the cursor is on it, its keys on the
--- bottom; or its line.

local config = require 'thread.config'
local draw = require 'thread.draw'
local frame = require 'thread.code.frame'
local go = require 'thread.go'
local labels = require 'thread.draw.labels'
local look = require 'thread.ui.look'
local message = require 'thread.draw.message'
local sheet = require 'thread.ui.sheet'
local step_draw = require 'thread.draw.step'
local text = require 'thread.base.text'
local conversation = require 'thread.model.conversation'
local note_draw = require 'thread.draw.note'

local M = {}

-- An inactive frame's colour, by the colour of whose move it is.
local BORDER = {
  ThreadSignAnswered = 'ThreadBorderAnswered',
  ThreadSignWaiting = 'ThreadBorderWaiting',
  ThreadSignInfo = 'ThreadBorderInfo',
  ThreadSignInfoNew = 'ThreadBorderInfo',
  ThreadSignDone = 'ThreadSignDone',
}

--- A placed one's conversation: its step's or its note's.
---@param p thread.Placed
---@return thread.Conversation
function M.conversation(p)
  if p.step then
    return conversation.of_step(p.step, p.tour)
  end
  return conversation.of_note(assert(p.note))
end

--- The colour of whose move a conversation is, for its sign and frame.
---@param p thread.Placed
---@return string
function M.colour(p)
  if p.gone then
    return 'DiagnosticWarn'
  end
  if p.step and #p.step.messages == 0 then
    return 'ThreadSignInfo'
  end
  local _, hl = labels.conversation(p.review, M.conversation(p))
  return hl
end

-- A walked step's conversation, in rows at most, before Tab or going in
-- shows it whole.
M.ROWS = 12

--- The keys a card lists while the cursor is on it, or it is walked;
--- gone into, those of its float.
---@param p thread.Placed
---@param here integer  how many cover the cursor's line
---@param walking thread.Walking|nil  the walk it is walked in
---@param inside boolean|nil
---@param links boolean  whether it has any to go between
---@param more boolean  whether Tab shows more of it before it closes it
---@param yours boolean  whether the cursor is on a message of yours to edit or delete
---@return thread.Chunks
local function hints(p, here, walking, inside, links, more, yours)
  local z = config.options.zone or {}
  local list = {} ---@type { [1]: string, [2]: string }[]
  if inside then
    if links then
      list[#list + 1] = { 'w/b', 'links' }
      list[#list + 1] = { '⏎', 'follow' }
    end
    list[#list + 1] = { 'r', 'reply' }
    if yours then
      list[#list + 1] = { 'e/d', 'edit/delete' }
    end
    if z.page then
      list[#list + 1] = { look.show_key(z.page), 'page' }
    end
    list[#list + 1] = { 'q', 'out' }
    return look.hints(list)
  end
  -- Walked, the keys the walk lists for it; the card's own work unsaid.
  if walking then
    return look.hints(go.ask 'walk hints' or {})
  end
  local open = {} ---@type string[]
  for _, lhs in ipairs { z.focus or false, z.page or false } do
    if lhs then
      open[#open + 1] = (look.show_key(lhs):gsub('<CR>', '⏎'))
    end
  end
  if #open > 0 then
    list[#list + 1] = { table.concat(open, '/'), 'open' }
  end
  local walk = config.options.mappings.walk
  if walk and p.step then
    list[#list + 1] = { look.show_key(walk), 'walk from here' }
  end
  if z.enter then
    list[#list + 1] = { look.show_key(z.enter), 'into' }
  end
  if p.note and z.next_note and z.prev_note then
    list[#list + 1] = { look.show_key(z.next_note) .. '/' .. look.show_key(z.prev_note), 'next/prev' }
  end
  if here > 1 and z.next then
    list[#list + 1] = { (look.show_key(z.next):gsub('<S%-Tab>', 'S-tab')), here == 2 and 'the other here' or ('next of ' .. here) }
  end
  if z.fold then
    list[#list + 1] = { (look.show_key(z.fold):gsub('<Tab>', 'tab')), more and 'all' or 'close' }
  end
  return look.hints(list)
end

--- How many messages a card shows unless told: from the first you have
--- not read, and two at least.
---@param p thread.Placed
---@return integer
function M.messages(p)
  local c = M.conversation(p)
  return math.max(message.LAST, #c.messages - conversation.read(p.review, c))
end

--- Parts drawn into a sheet, moved to where it landed in its frame; a
--- message's `cols` stay the sheet's.
---@param parts thread.Part[]
---@param at thread.FrameAt
---@return thread.Part[]
local function moved(parts, at)
  local out = {} ---@type thread.Part[]
  for _, q in ipairs(parts) do
    local m = vim.tbl_extend('force', {}, q) ---@type thread.Part
    m.first, m.last = q.first + at.row, q.last + at.row
    m.s, m.e = q.s and q.s + at.col, q.e and q.e + at.col
    out[#out + 1] = m
  end
  return out
end

---@class thread.HangOpts
---@field indent integer
---@field room integer
---@field active boolean
---@field here integer
---@field walk thread.Walking|nil  the walk it is walked in
---@field messages integer|nil
---@field whole boolean|nil  a card: every message, each whole
---@field inside boolean|nil  gone into: drawn whole, and for the float over it, with that float's keys
---@field yours boolean|nil  gone into: the cursor on a message of yours, its keys saying e and d
---@field writing thread.Writing|nil  a card: rows made in it for what you write there, drawn whole
---@field highlights thread.ProseHighlights|nil  a walked step's, numbered in its text

--- Draw one: as a card, framed, or as a line. A card says how many of
--- its conversation's messages it has shown you: up to the first it cut
--- short; what in it goes somewhere, in its rows and byte columns; and
--- whether drawn whole it would show more; and where in its rows what
--- it drew from its sheet's top left begins.
---@param p thread.Placed
---@param size 'card'|'line'
---@param o thread.HangOpts
---@return thread.VirtChunk[][], integer|nil shown, thread.Part[] parts, boolean more, thread.FrameAt|nil at
function M.draw(p, size, o)
  -- A step's card has more room inside than a note's: it is read, not
  -- glanced at. Its padding comes out of what is written, so it is no wider.
  local pad = (size == 'card' and p.step) and 2 or 0
  local width = math.max(24, math.min(config.options.ui.width, o.room - o.indent - 6)) - 2 * pad
  local P = sheet.new()
  local r = p.review
  if size == 'line' then
    if p.step then
      step_draw.line(P, r, assert(p.tour), p.step, { width = width + 4 })
    else
      note_draw.line(P, r, assert(p.note), { width = width + 4 })
    end
    if p.gone then
      P.chunks(text.fit_chunks({ { '  ! its lines are gone; the first read ', 'DiagnosticWarn' }, { vim.trim(p.chunk.from), 'ThreadMeta' } }, width + 4), 0)
    end
    return frame.lines(P, o.indent), nil, {}, false
  end
  -- From the first message you have not read; whole, gone into it or
  -- writing in it. A walked step's text whole, and as much of its
  -- conversation, its last messages each whole, as fits in M.ROWS.
  local c = M.conversation(p)
  local whole = o.whole or o.inside or o.writing ~= nil
  local from_unread = whole and #c.messages or o.messages or M.messages(p)
  local most ---@type integer|nil
  if p.step and o.walk and not whole then
    local n, tall = message.fit(r, c, width, M.ROWS)
    from_unread, most = n, tall and M.ROWS or math.huge
  end
  local cut = {} ---@type table<integer, true>
  local parts ---@type thread.Part[]
  if p.step then
    parts = step_draw.card(
      P,
      r,
      assert(p.tour),
      p.step,
      { width = width, messages = from_unread, most = most, whole = whole, cut = cut, writing = o.writing, highlights = o.highlights }
    )
  else
    parts = note_draw.card(P, r, assert(p.note), { width = width, messages = from_unread, whole = whole, cut = cut, writing = o.writing })
  end
  local shown = #c.messages
  -- Whole, it would show the messages before these, or one cut short.
  local more = not whole and (from_unread < #c.messages or next(cut) ~= nil)
  -- Shown you up to the first of the agent's new messages it held back,
  -- before those it shows or cut short; yours, and those you have read,
  -- it never held back.
  local read = conversation.read(r, c)
  local held = vim.deepcopy(cut)
  for i = 1, #c.messages - from_unread do
    held[i] = true
  end
  for i in pairs(held) do
    if c.messages[i].from == 'agent' and i > read then
      shown = math.min(shown, i - 1)
    end
  end
  local links = false
  for _, q in ipairs(parts) do
    links = links or draw.goes(q)
  end
  local hl = M.colour(p)
  local border = o.active and hl or (BORDER[hl] or 'ThreadBorderInfo')
  if p.note then
    border = o.active and 'ThreadBorderNote' or 'ThreadBorderNoteQuiet'
  end
  local lines, at = frame.frame(P, {
    indent = o.indent,
    width = width,
    border = border,
    pad = pad,
    top = { { r.title, 'ThreadCrumb' } },
    keys = o.active and hints(p, o.here, o.walk, o.inside, links, more, o.yours or false) or nil,
  })
  return lines, shown, moved(parts, at), more, at
end

return M
