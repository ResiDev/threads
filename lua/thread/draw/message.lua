--- A message: who wrote it and when, its prose with its excerpts, links
--- and diagrams, and the code it changed, each chunk with its range. The
--- agent's runs from the left and stops short on the right; yours is set
--- in from the left, as a chat draws it. What a note says, its first
--- message, is drawn apart: no mark for who wrote it.

local chunk = require 'thread.model.chunk'
local chunk_draw = require 'thread.draw.chunk'
local conversation = require 'thread.model.conversation'
local draw = require 'thread.draw'
local labels = require 'thread.draw.labels'
local message = require 'thread.model.message'
local prose = require 'thread.prose'
local review = require 'thread.model.review'
local text = require 'thread.base.text'

local M = {}

-- The label's columns, `󰚩  ` before the text.
local LABEL = 3
M.LABEL = LABEL

-- A card's last few messages, and rows of each one's text.
M.LAST, M.MOST = 2, 6

---@class thread.MessageOpts
---@field width integer  the room, from the indent
---@field indent integer|nil  else the sheet's
---@field most integer|nil  rows of its text at most, an excerpt one row; past them it trails off
---@field intro boolean|nil  what its note says, its first message
---@field brief boolean|nil  a card's: what it changed said in a row, not drawn
---@field last integer|nil  a conversation: its last few messages, a row saying how many came before
---@field cut table<integer, true>|nil  filled in: the places of the messages `most` cut short

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
  return c.messages[i].from == 'agent' and i > conversation.read(r, c)
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

--- What a conversation holds it in, for its parts.
---@param c thread.Conversation
---@param i integer
---@return thread.PartOf
local function within(c, i)
  return { conversation = c, message = i, step = c.step, tour = c.tour, note = c.note, contract = c.contract }
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
  draw.prose(prose.draw(P, m.prose, room, { indent = at, lead = lead, most = o.most, review = r }), out)
  if o.most and o.cut and prose.cut(m.prose, room - (lead and text.width(lead[1]) or 0), o.most, r) then
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
  local changes = {} ---@type thread.Chunk[]
  for _, id in ipairs(m.changes or {}) do
    changes[#changes + 1] = review.chunk(r, id)
  end
  if o.brief then
    if #changes > 0 then
      P.chunks({ { text.fit('▸ ' .. text.plural(#changes, 'change'), inner), 'ThreadMeta' } }, hang)
    end
  else
    for j, ch in ipairs(changes) do
      if j == 1 then
        P.add ''
      end
      local where = { { j == 1 and 'changed  ' or '         ', 'ThreadMeta' } }
      vim.list_extend(where, chunk_draw.where(ch, chunk.locate(ch, spec)))
      local row = P.chunks(text.fit_chunks(where, inner), hang)
      out[#out + 1] = { kind = 'change', first = row, last = row, chunk = ch }
    end
  end
  out[1].last = math.max(out[1].first, #P.lines - 1)
  draw.within(out, 1, within(c, i))
  return out
end

--- Where your next message in a conversation goes, so you write it there:
--- after `row`, set in from the left as yours are, `s` the column its text
--- starts at and `e` the column it ends at.
---@param c thread.Conversation
---@param row integer  the last row of what it follows
---@param o thread.MessageOpts
---@return thread.Part
function M.reply(c, row, o)
  local indent = o.indent or 0
  local room = side(o.width)
  local at = indent + o.width - room
  return { kind = 'reply', first = row, last = row, s = at + LABEL, e = at + room, conversation = c }
end

--- A conversation: its messages, or its last few, a blank row between; a
--- note's opens with what it says.
---@param P thread.Sheet
---@param r thread.Review
---@param c thread.Conversation
---@param o thread.MessageOpts
---@return thread.Part[]
function M.conversation(P, r, c, o)
  local out = {} ---@type thread.Part[]
  local from = math.max(1, #c.messages - (o.last or #c.messages) + 1)
  if from > 1 then
    P.chunks({ { text.fit('⋯ ' .. text.plural(from - 1, 'earlier message'), o.width), 'ThreadMeta' } }, o.indent)
    P.add ''
  end
  for i = from, #c.messages do
    if i > from then
      P.add ''
    end
    vim.list_extend(out, M.draw(P, r, c, i, vim.tbl_extend('force', o, { intro = i == 1 and c.note ~= nil })))
  end
  return out
end

return M
