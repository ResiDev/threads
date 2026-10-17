--- What hangs above a note's or step's first line in the code: a note's
--- bubble or a step's card, drawn by draw/ at its card size, brief or
--- whole, and framed: a note's in yellow, a step's in the colour of whose
--- move it is, so the two are never taken for each other. The review it
--- is in on the top edge and, while the cursor is on it, its keys on the
--- bottom; or its line.

local config = require 'thread.config'
local frame = require 'thread.code.frame'
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

--- The keys a card lists while the cursor is on it, or it is walked;
--- gone into, those of its float.
---@param p thread.Placed
---@param here integer  how many cover the cursor's line
---@param walking thread.Walking|nil  the walk it is walked in
---@param inside boolean|nil
---@param links boolean  whether it has any to go between
---@param more boolean  whether Tab shows more of it before it closes it
---@return thread.Chunks
local function hints(p, here, walking, inside, links, more)
  local z = config.options.zone or {}
  local list = {} ---@type { [1]: string, [2]: string }[]
  local k = config.options.walk or {}
  if inside then
    if links then
      list[#list + 1] = { 'w/b', 'links' }
      list[#list + 1] = { '⏎', 'follow' }
    end
    if z.page then
      list[#list + 1] = { look.show_key(z.page), 'page' }
    end
    list[#list + 1] = { 'q', 'out' }
    return look.hints(list)
  end
  -- Walked, only the keys a walk is for, as its bar has them, and the one
  -- that goes into it; the card's own work unsaid.
  if walking then
    if k.next and k.prev then
      list[#list + 1] = { look.show_key(k.next) .. '/' .. look.show_key(k.prev), 'next/prev' }
    end
    if k.enter then
      list[#list + 1] = { look.show_key(k.enter), 'enter' }
    end
    if k.focus then
      list[#list + 1] = { look.show_key(k.focus), look.toggle('focus', walking.focus) }
    end
    local diff = config.options.mappings.diff
    if diff then
      list[#list + 1] = { look.show_key(diff), look.toggle('diff', walking.diff) }
    end
    if k.help then
      list[#list + 1] = { look.show_key(k.help), 'keys' }
    end
    if k.quit then
      list[#list + 1] = { look.show_key(k.quit), 'end' }
    end
    return look.hints(list)
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

--- Parts drawn into a sheet, moved to where it landed in its frame.
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
---@field inside boolean|nil  drawn for the float over it, with that float's keys

--- Draw one: as a card, framed, or as a line. A card says how many of
--- its conversation's messages it has shown you: up to the first it cut
--- short; what in it goes somewhere, in its rows and byte columns; and
--- whether drawn whole it would show more.
---@param p thread.Placed
---@param size 'card'|'line'
---@param o thread.HangOpts
---@return thread.VirtChunk[][], integer|nil shown, thread.Part[] parts, boolean more
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
  -- From the first message you have not read; a walked step's whole
  -- conversation, each reply whole, since the walk reads it as it leaves.
  local c = M.conversation(p)
  local whole = o.whole or o.walk ~= nil
  local from_unread = whole and #c.messages or o.messages or M.messages(p)
  local cut = {} ---@type table<integer, true>
  local parts ---@type thread.Part[]
  if p.step then
    parts = step_draw.card(P, r, assert(p.tour), p.step, { width = width, messages = from_unread, whole = whole, cut = cut })
  else
    parts = note_draw.card(P, r, assert(p.note), { width = width, messages = from_unread, whole = whole, cut = cut })
  end
  local shown = #c.messages
  -- Whole, it would show the messages before these, or one cut short.
  local more = not whole and (from_unread < #c.messages or next(cut) ~= nil)
  for i in pairs(cut) do
    shown = math.min(shown, i - 1)
  end
  local links = false
  for _, q in ipairs(parts) do
    links = links or q.kind == 'link' or q.kind == 'name'
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
    keys = o.active and hints(p, o.here, o.walk, o.inside, links, more) or nil,
  })
  return lines, shown, moved(parts, at), more
end

return M
