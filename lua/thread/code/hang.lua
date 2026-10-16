--- What hangs above a note's or step's first line in the code: a note's
--- bubble or a step's card, drawn by draw/ at its card size and
--- framed in the colour of whose move it is, the review it is in on the
--- top edge and, while the cursor is on it, its keys on the bottom; or its
--- line.

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

--- The keys a card lists while the cursor is on it, or it is walked.
---@param p thread.Placed
---@param here integer  how many cover the cursor's line
---@param size 'card'|'line'
---@param walking thread.Walking|nil  the walk it is walked in
---@return thread.Chunks
local function hints(p, here, size, walking)
  local z = config.options.zone or {}
  local list = {} ---@type { [1]: string, [2]: string }[]
  local k = config.options.walk or {}
  -- Walked, only the keys a walk is for, as its bar has them; the card's
  -- own work unsaid.
  if walking then
    if k.next and k.prev then
      list[#list + 1] = { look.show_key(k.next) .. '/' .. look.show_key(k.prev), 'next/prev' }
    end
    if k.focus then
      list[#list + 1] = { look.show_key(k.focus), look.toggle('focus', walking.focus) }
    end
    local diff = config.options.mappings.diff
    if diff then
      list[#list + 1] = { look.show_key(diff), look.toggle('diff', walking.diff) }
    end
    if k.up then
      list[#list + 1] = { look.show_key(k.up), 'review' }
    end
    if k.quit then
      list[#list + 1] = { look.show_key(k.quit), 'end' }
    end
    return look.hints(list)
  end
  if z.focus then
    list[#list + 1] = { look.show_key(z.focus):gsub('<CR>', '⏎'), 'open' }
  end
  local walk = config.options.mappings.walk
  if walk and p.step then
    list[#list + 1] = { look.show_key(walk), 'walk from here' }
  end
  if here > 1 and z.next then
    list[#list + 1] = { (look.show_key(z.next):gsub('<S%-Tab>', 'S-tab')), here == 2 and 'the other here' or ('next of ' .. here) }
  end
  if z.fold then
    list[#list + 1] = { (look.show_key(z.fold):gsub('<Tab>', 'tab')), size == 'line' and 'whole' or 'fold' }
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

--- Draw one: as a card, framed, or as a line. A card says how many of
--- its conversation's messages it has shown you: up to the first it cut
--- short.
---@param p thread.Placed
---@param size 'card'|'line'
---@param o { indent: integer, room: integer, active: boolean, here: integer, walk: thread.Walking|nil, messages: integer|nil }  `walk` the walk it is walked in
---@return thread.VirtChunk[][], integer|nil shown
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
    return frame.lines(P, o.indent), nil
  end
  -- From the first message you have not read; a walked step's whole
  -- conversation, each reply whole, since the walk reads it as it leaves.
  local c = M.conversation(p)
  local from_unread = o.messages or M.messages(p)
  local cut = {} ---@type table<integer, true>
  if p.step then
    step_draw.card(P, r, assert(p.tour), p.step, {
      width = width,
      messages = o.walk and #p.step.messages or from_unread,
      whole = o.walk ~= nil,
      cut = cut,
    })
  else
    note_draw.card(P, r, assert(p.note), { width = width, messages = from_unread, cut = cut })
  end
  local shown = #c.messages
  for i in pairs(cut) do
    shown = math.min(shown, i - 1)
  end
  local hl = M.colour(p)
  return frame.frame(P, {
    indent = o.indent,
    width = width,
    border = o.active and hl or (BORDER[hl] or 'ThreadBorderInfo'),
    pad = pad,
    top = { { r.title, 'ThreadCrumb' } },
    keys = o.active and hints(p, o.here, size, o.walk) or nil,
  }),
    shown
end

return M
