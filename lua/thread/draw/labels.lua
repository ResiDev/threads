--- How primitives are labelled, the same wherever they are drawn: whose
--- move a conversation is, who wrote a message, a step walked, a chunk
--- accepted, a tour's colour, and a note's kind and status as a badge.
--- Glyphs are Nerd Font icons, or plain shapes with `ui.icons` off.

local config = require 'thread.config'
local conversation = require 'thread.model.conversation'
local look = require 'thread.ui.look'
local note = require 'thread.model.note'
local step = require 'thread.model.step'
local text = require 'thread.base.text'
local tour = require 'thread.model.tour'

local M = {}

---@return boolean
local function nerd()
  -- A config that says it has no Nerd Font, as kickstart's does, is
  -- taken at its word.
  return config.options.ui.icons ~= false and vim.g.have_nerd_font ~= false
end

--- A conversation's state as a glyph: closed, a check; the agent's move,
--- an envelope on its way; yours, an envelope, sealed while something in
--- it is new; nobody's (only the agent has spoken), a dot while new and
--- nothing once read, since it asks nothing of you. Plain: ✓ ◔ ● ○ •.
---@param closed boolean
---@param move 'agent'|'you'|nil
---@param unread boolean
---@return string glyph, string hl
function M.state(closed, move, unread)
  if closed then
    return nerd() and '󰗡' or '✓', 'ThreadSignDone'
  elseif move == 'agent' then
    return nerd() and '󱡯' or '◔', 'ThreadSignWaiting'
  elseif move == 'you' then
    if unread then
      return nerd() and '󰇮' or '●', 'ThreadSignAnswered'
    end
    return nerd() and '󰗯' or '○', 'ThreadSignAnswered'
  elseif unread then
    return '•', 'ThreadSignInfoNew'
  end
  return ' ', 'ThreadSignInfo'
end

--- A conversation's state, read from the model.
---@param r thread.Review
---@param c thread.Conversation
---@return string glyph, string hl
function M.conversation(r, c)
  return M.state(conversation.closed(c), conversation.move(c), conversation.unread(r, c) > 0)
end

-- The states conversations count in a list, the ones that ask
-- most first; nobody's move once read asks nothing, so it is left out.
local MOVES = {
  { 'you', true },
  { 'you', false },
  { 'agent', false },
  { nil, true },
}

--- How conversations stand, each state its glyph and how many are in
--- it: `󰇮 2  󰗯 5  󱡯 6`. Those that ask nothing are left out.
---@param r thread.Review
---@param list thread.Conversation[]
---@return thread.Chunks
function M.count(r, list)
  local out = {} ---@type thread.Chunks
  local count = {} ---@type table<string, integer>
  for _, c in ipairs(list) do
    if #c.messages > 0 and not conversation.closed(c) then
      -- Waiting on the agent is one state, read or not.
      local move = conversation.move(c)
      local key = tostring(move) .. ':' .. tostring(move ~= 'agent' and conversation.unread(r, c) > 0)
      count[key] = (count[key] or 0) + 1
    end
  end
  for _, m in ipairs(MOVES) do
    local n = count[tostring(m[1]) .. ':' .. tostring(m[2])]
    if n then
      local g, hl = M.state(false, m[1], m[2])
      vim.list_extend(out, { { (#out > 0 and '  ' or '') .. g .. ' ', hl }, { tostring(n), 'ThreadMeta' } })
    end
  end
  return out
end

--- The highlight groups for a tour of colour `c` (else the palette's at
--- `place`): for its name, and for the bar or tree down its side.
---@param c thread.Colour|nil
---@param place integer|nil
---@return string name, string line
function M.colour(c, place)
  c = c or tour.COLOURS[((place or 1) - 1) % #tour.COLOURS + 1]
  local name = 'ThreadGroup' .. c:sub(1, 1):upper() .. c:sub(2)
  return name, name .. 'Line'
end

--- Who wrote a message, as a shape, and its colour: a person for you, a
--- robot for the agent, lit while you have not read it. Plain: ● you,
--- ▲ the agent, △ unread.
---@param from 'you'|'agent'
---@param new boolean|nil
---@return string glyph, string hl  the shape's, as a dot
function M.who(from, new)
  if from == 'you' then
    return nerd() and '󰀄' or '●', 'ThreadDotYou'
  elseif new then
    return nerd() and '󰚩' or '△', 'ThreadDotAgentNew'
  end
  return nerd() and '󰚩' or '▲', 'ThreadDotAgent'
end

--- A message's label beside its text: its shape, coloured as its writer.
---@param from 'you'|'agent'
---@param new boolean|nil
---@return string glyph, string hl
function M.label(from, new)
  local g = M.who(from, new)
  if from == 'you' then
    return g, 'ThreadYou'
  end
  return g, new and 'ThreadAgentNew' or 'ThreadAgent'
end

--- How many messages `dots` shows.
M.DOTS = 5

--- The last few messages of a conversation, a shape each for who wrote
--- it, `…` before them when there are more.
---@param messages thread.Message[]
---@param read integer  how many you have read
---@return thread.Chunks
function M.dots(messages, read)
  local out = { { #messages > M.DOTS and '… ' or '', 'ThreadMeta' } } ---@type thread.Chunks
  for i = math.max(1, #messages - M.DOTS + 1), #messages do
    local g, hl = M.who(messages[i].from, i > read)
    out[#out + 1] = { g .. (i < #messages and ' ' or ''), hl }
  end
  return out
end

--- A step walked, or not yet: a track's cell, filled or not. Never a
--- tick, which says a note accepted.
---@param walked boolean
---@return string glyph, string hl
function M.walked(walked)
  if walked then
    return '▰', 'ThreadSignDone'
  end
  return '▱', 'ThreadSignInfo'
end

-- Steps a track shows as cells; a longer tour is `3/20`.
M.TRACK = 12

--- How far you have walked a tour: a cell a step, filled once walked,
--- the step you are on lit.
---@param r thread.Review
---@param x thread.Tour
---@param here thread.Step|nil
---@return thread.Chunks
function M.track(r, x, here)
  local cells, at = {}, nil ---@type { [1]: string, [2]: 'done'|'here'|'left' }[], integer|nil
  for i, s in ipairs(x.steps) do
    if s == here then
      at = i
      cells[i] = { '▰', 'here' }
    else
      cells[i] = step.walked(r, s) and { '▰', 'done' } or { '▱', 'left' }
    end
  end
  if #x.steps > M.TRACK then
    local walked = #vim.tbl_filter(function(c)
      return c[2] == 'done'
    end, cells)
    return { { string.format('%d/%d', at or walked, #x.steps), 'ThreadMeta' } }
  end
  return look.track(cells)
end

--- `── label ─────` across `width`.
---@param label string
---@param width integer
---@return thread.Chunks
function M.rule(label, width)
  label = text.fit(label, math.max(1, width - 6))
  return { { '── ' .. label .. ' ', 'ThreadCrumb' }, { string.rep('─', math.max(2, width - text.width(label) - 4)), 'ThreadTabRule' } }
end

--- A chunk accepted, or not yet.
---@param accepted boolean
---@return string glyph, string hl
function M.accepted(accepted)
  if accepted then
    return '✓', 'ThreadAccepted'
  end
  return '·', 'ThreadMeta'
end

-- Each kind of note's colour: a defect, something to weigh, something
-- to answer, quiet.
local KIND = {
  issue = 'ThreadVerdictBad',
  decision = 'ThreadVerdictInfo',
  question = 'ThreadVerdictWarn',
  suggestion = 'ThreadVerdictGood',
  fix = 'ThreadVerdictInfo',
  comment = 'ThreadKindQuiet',
}

-- A badge's colour as a tag: its text alone, no wash behind it.
local TAG = {
  ThreadVerdictBad = 'ThreadTagBad',
  ThreadVerdictWarn = 'ThreadTagWarn',
  ThreadVerdictInfo = 'ThreadTagInfo',
  ThreadVerdictGood = 'ThreadTagGood',
  ThreadKindQuiet = 'ThreadTagQuiet',
}

-- A severity's shape and colour, so it reads without either.
local SEVERITY = {
  high = { '●', 'ThreadRiskHigh' },
  medium = { '◐', 'ThreadRiskMedium' },
  low = { '○', 'ThreadRiskLow' },
}

-- A note's kind as an icon, an issue's by what it is: Nerd Font, plain.
local ICONS = {
  bug = { '', 'ж' },
  risk = { '', '⚠' },
  flaw = { '', '≠' },
  question = { '', '?' },
  decision = { '', '⚖' },
  suggestion = { '', '✦' },
  fix = { '', '✚' },
  comment = { '', '❝' },
}

-- An open issue's icon, coloured by how severe it is.
local SEVERE = { high = 'ThreadIconHigh', medium = 'ThreadIconMedium', low = 'ThreadIconLow' }

--- A note's icon, its shape its kind and its colour how much it
--- matters: settled, faded; a comment, which asks nothing, quiet; an
--- issue, how severe; the rest, your call.
---@param n thread.Note
---@return string glyph, string hl
function M.icon(n)
  local pair = ICONS[n.kind == 'issue' and (n.issue or 'risk') or n.kind] or ICONS.comment
  local hl = 'ThreadIconAsk'
  if note.closed(n) then
    hl = 'ThreadIconDone'
  elseif n.kind == 'comment' then
    hl = 'ThreadIconQuiet'
  elseif n.kind == 'issue' then
    hl = SEVERE[n.severity or 'low'] or 'ThreadIconLow'
  end
  return pair[nerd() and 1 or 2], hl
end

-- How a settled note ended, as a shape: done, turned down, let be.
local OUTCOMES = {
  fixed = { '', '✓' },
  agreed = { '', '✓' },
  answered = { '', '✓' },
  taken = { '', '✓' },
  checked = { '', '✓' },
  reversed = { '', '✗' },
  declined = { '', '✗' },
  ["won't fix"] = { '', '⊘' },
  ['not a problem'] = { '', '⊘' },
}

--- A settled note's status with its shape: `✓ agreed`; nil while open.
---@param n thread.Note
---@return string|nil
function M.outcome(n)
  local pair = note.closed(n) and OUTCOMES[n.status]
  return pair and (pair[nerd() and 1 or 2] .. ' ' .. n.status) or nil
end

--- A shape by name, Nerd Font or plain: the inbox's sections and its
--- unread dot.
---@type table<string, { [1]: string, [2]: string }>
M.GLYPHS = {
  yours = { '', '↩' },
  new = { '', '○' },
  waiting = { '', '⧗' },
  reference = ICONS.comment,
  settled = { '', '✓' },
  unread = { '●', '●' },
}

--- A shape of M.GLYPHS, as `ui.icons` says.
---@param name string
---@return string
function M.glyph(name)
  return M.GLYPHS[name][nerd() and 1 or 2]
end

--- A note's kind as a badge, an issue's with what it is and how bad:
--- ` BUG · high `, ` decision `.
---@param n thread.Note
---@return { [1]: string, [2]: string }
function M.kind(n)
  local said = n.kind == 'issue' and n.issue and (n.issue:upper() .. (n.severity and (' · ' .. n.severity) or '')) or n.kind
  return { ' ' .. said .. ' ', KIND[n.kind] or 'ThreadKindQuiet' }
end

--- A note's kind said quietly, for a list: a coloured word, an issue's
--- severity as a shape before it, `◐ bug`; only a high one keeps its
--- badge, so it is what stands out.
---@param n thread.Note
---@return thread.Chunks
function M.tag(n)
  if n.kind == 'issue' and n.severity == 'high' then
    return { M.kind(n) }
  end
  local out = {} ---@type thread.Chunks
  local sev = n.kind == 'issue' and SEVERITY[n.severity or '']
  if sev then
    out[#out + 1] = { sev[1] .. ' ', sev[2] }
  end
  out[#out + 1] = { n.kind == 'issue' and (n.issue or 'issue') or n.kind, TAG[KIND[n.kind]] or 'ThreadMeta' }
  return out
end

--- A note's status when it is settled, as a badge: ` fixed `; nothing
--- while it is open, or for a comment.
---@param n thread.Note
---@return { [1]: string, [2]: string }|nil
function M.status(n)
  if not n.status or n.status == 'open' then
    return nil
  end
  return { ' ' .. n.status .. ' ', 'ThreadKindQuiet' }
end

return M
