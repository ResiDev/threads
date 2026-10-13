--- A thread or a step as the code draws it above its first line: its
--- card from draw/, framed in the colour of whose move it is, the review
--- it is in on the top edge and, while the cursor is on it, its keys on
--- the bottom; or its line.

local bubble = require 'thread.code.bubble'
local config = require 'thread.config'
local labels = require 'thread.draw.labels'
local look = require 'thread.ui.look'
local message = require 'thread.draw.message'
local sheet = require 'thread.ui.sheet'
local step_draw = require 'thread.draw.step'
local text = require 'thread.base.text'
local thread = require 'thread.model.thread'
local thread_draw = require 'thread.draw.thread'

local M = {}

-- An inactive frame's colour, by the colour of whose move it is.
local BORDER = {
  ThreadSignAnswered = 'ThreadBorderAnswered',
  ThreadSignWaiting = 'ThreadBorderWaiting',
  ThreadSignInfo = 'ThreadBorderInfo',
  ThreadSignInfoNew = 'ThreadBorderInfo',
  ThreadSignDone = 'ThreadSignDone',
}

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
  local _, hl = labels.conversation(p.review, thread.conversation(p.thread, p.step, p.tour))
  return hl
end

--- The keys a card lists while the cursor is on it, or it is walked.
---@param p thread.Placed
---@param here integer  how many cover the cursor's line
---@param size 'card'|'line'
---@param on_walk boolean
---@return thread.Chunks
local function hints(p, here, size, on_walk)
  local z = config.options.zone or {}
  local list = {} ---@type { [1]: string, [2]: string }[]
  if z.focus then
    list[#list + 1] = { look.show_key(z.focus):gsub('<CR>', '⏎'), 'open' }
  end
  local k = config.options.walk or {}
  local walk = config.options.mappings.walk
  if on_walk then
    if k.next and k.prev then
      list[#list + 1] = { look.show_key(k.next) .. '/' .. look.show_key(k.prev), 'next/prev' }
    end
    if k.quit then
      list[#list + 1] = { look.show_key(k.quit), 'end' }
    end
  elseif walk and (p.step or #thread.tours(p.thread) > 0) then
    list[#list + 1] = { look.show_key(walk), p.step and 'walk from here' or 'walk it' }
  end
  if here > 1 and z.next then
    list[#list + 1] = { (look.show_key(z.next):gsub('<S%-Tab>', 'S-tab')), here == 2 and 'the other here' or ('next of ' .. here) }
  end
  if z.fold then
    list[#list + 1] = { (look.show_key(z.fold):gsub('<Tab>', 'tab')), size == 'line' and 'whole' or 'fold' }
  end
  return look.hints(list)
end

--- Draw one: as a card, framed, or as a line. A card says how many of
--- its conversation's messages it has shown you: up to the first it cut
--- short.
---@param p thread.Placed
---@param size 'card'|'line'
---@param o { indent: integer, room: integer, active: boolean, here: integer, walked: boolean }
---@return thread.VirtChunk[][], integer|nil shown
function M.draw(p, size, o)
  local width = math.max(24, math.min(config.options.ui.width, o.room - o.indent - 6))
  local P = sheet.new()
  local r, t = p.review, p.thread
  if size == 'line' then
    if p.step then
      step_draw.line(P, r, t, assert(p.tour), p.step, { width = width + 4 })
    else
      thread_draw.line(P, r, t, { width = width + 4 })
    end
    if p.gone then
      local c = assert(t.chunk)
      P.chunks(text.fit_chunks({ { '  ! its line is gone; it read ', 'DiagnosticWarn' }, { vim.trim(c.text), 'ThreadMeta' } }, width + 4), 0)
    end
    return bubble.lines(P, o.indent), nil
  end
  -- From the first message you have not read; a walked step's whole
  -- conversation, each reply whole, since the walk reads it as it leaves.
  local c = thread.conversation(t, p.step, p.tour)
  local from_unread = math.max(message.LAST, #c.messages - thread.read(r, c))
  local cut = {} ---@type table<integer, true>
  if p.step then
    step_draw.card(P, r, t, assert(p.tour), p.step, {
      width = width,
      messages = o.walked and #p.step.messages or from_unread,
      whole = o.walked,
      cut = cut,
    })
  else
    thread_draw.card(P, r, t, { width = width, messages = from_unread, cut = cut })
  end
  local shown = #c.messages
  for i in pairs(cut) do
    shown = math.min(shown, i - 1)
  end
  local hl = M.colour(p)
  return bubble.frame(P, {
    indent = o.indent,
    width = width,
    border = o.active and hl or (BORDER[hl] or 'ThreadBorderInfo'),
    top = { { r.title, 'ThreadCrumb' } },
    keys = o.active and hints(p, o.here, size, o.walked) or nil,
  }),
    shown
end

return M
