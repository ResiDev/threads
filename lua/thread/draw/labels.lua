--- How primitives are labelled, the same wherever they are drawn: whose
--- move a conversation is, who wrote a message, a step walked, a chunk
--- accepted, and the labels a thread or a step carries (its verdict, risk
--- and kind) as badges. Glyphs are Nerd Font icons, or plain shapes with
--- `ui.icons` off.

local config = require 'thread.config'
local look = require 'thread.ui.look'
local step = require 'thread.model.step'
local text = require 'thread.base.text'
local thread = require 'thread.model.thread'

local M = {}

---@return boolean
local function nerd()
  return config.options.ui.icons ~= false
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
  return M.state(thread.closed(c.thread), thread.move(c), thread.unread(r, c) > 0)
end

-- The states a thread's conversations count in a list, the ones that ask
-- most first; nobody's move once read asks nothing, so it is left out.
local MOVES = {
  { 'you', true },
  { 'you', false },
  { 'agent', false },
  { nil, true },
}

--- How threads' conversations stand, their own and their steps', each
--- state its glyph and how many are in it: `󰇮 2  󰗯 5  󱡯 6`. Closed
--- threads count nothing, nor do states that ask nothing.
---@param r thread.Review
---@param list thread.Thread[]
---@return thread.Chunks
function M.moves(r, list)
  local out = {} ---@type thread.Chunks
  local count = {} ---@type table<string, integer>
  for _, t in ipairs(list) do
    for _, c in ipairs(thread.closed(t) and {} or thread.conversations(t)) do
      if #c.messages > 0 then
        -- Waiting on the agent is one state, read or not.
        local move = thread.move(c)
        local key = tostring(move) .. ':' .. tostring(move ~= 'agent' and thread.unread(r, c) > 0)
        count[key] = (count[key] or 0) + 1
      end
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

--- A step walked, or not yet.
---@param walked boolean
---@return string glyph, string hl
function M.walked(walked)
  if walked then
    return '✓', 'ThreadSignDone'
  end
  return '·', 'ThreadSignInfo'
end

-- Steps a track shows as cells; a longer tour is `3/20`.
M.TRACK = 12

--- How far you have walked a tour: a cell a step, filled once walked,
--- the step you are on lit.
---@param r thread.Review
---@param t thread.Thread  the tour's
---@param x thread.Tour
---@param here thread.Step|nil
---@return thread.Chunks
function M.track(r, t, x, here)
  local cells, at = {}, nil ---@type { [1]: string, [2]: 'done'|'here'|'left' }[], integer|nil
  for i, s in ipairs(x.steps) do
    if s == here then
      at = i
      cells[i] = { '▰', 'here' }
    else
      cells[i] = step.walked(r, t, s) and { '▰', 'done' } or { '▱', 'left' }
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
  return { { '── ' .. label .. ' ', 'ThreadCrumb' }, { string.rep('─', math.max(2, width - text.width(label) - 4)), 'ThreadTabRule' } }
end

--- A chunk accepted in its thread, or not yet.
---@param accepted boolean
---@return string glyph, string hl
function M.accepted(accepted)
  if accepted then
    return '✓', 'ThreadAccepted'
  end
  return '○', 'ThreadMeta'
end

-- A verdict's colour: a defect, a cost to weigh, an explanation, fine.
local VERDICT = {
  bug = 'ThreadVerdictBad',
  flaw = 'ThreadVerdictBad',
  risk = 'ThreadVerdictWarn',
  ['trade-off'] = 'ThreadVerdictWarn',
  decision = 'ThreadVerdictInfo',
  ['how it works'] = 'ThreadVerdictInfo',
  fine = 'ThreadVerdictGood',
}

-- A kind's colour: new things green, fixes red, the routine quiet.
local KIND = {
  feat = 'ThreadVerdictGood',
  fix = 'ThreadVerdictBad',
  perf = 'ThreadVerdictWarn',
  refactor = 'ThreadVerdictInfo',
  test = 'ThreadVerdictInfo',
  docs = 'ThreadKindQuiet',
  chore = 'ThreadKindQuiet',
  style = 'ThreadKindQuiet',
}

-- A risk's shape and colour, so it reads without either.
local RISK = {
  high = { '●', 'ThreadRiskHigh' },
  medium = { '◐', 'ThreadRiskMedium' },
  low = { '○', 'ThreadRiskLow' },
}

--- A verdict as a badge, with its severity: ` BUG · high `.
---@param x thread.Labels
---@return { [1]: string, [2]: string }|nil
function M.verdict(x)
  if not x.verdict then
    return nil
  end
  return { ' ' .. x.verdict:upper() .. (x.severity and (' · ' .. x.severity) or '') .. ' ', VERDICT[x.verdict] }
end

--- A kind as a badge: ` feat `.
---@param x thread.Labels
---@return { [1]: string, [2]: string }|nil
function M.kind(x)
  if not x.kind then
    return nil
  end
  return { ' ' .. x.kind .. ' ', KIND[x.kind] }
end

--- A risk: `● high risk`, or short, `●`.
---@param x thread.Labels
---@param short boolean|nil
---@return { [1]: string, [2]: string }|nil
function M.risk(x, short)
  local r = x.risk and RISK[x.risk]
  if not r then
    return nil
  end
  return { short and r[1] or (r[1] .. ' ' .. x.risk .. ' risk'), r[2] }
end

-- A tag's colour: its text alone, no wash behind it.
local TAG = {
  ThreadVerdictBad = 'ThreadTagBad',
  ThreadVerdictWarn = 'ThreadTagWarn',
  ThreadVerdictInfo = 'ThreadTagInfo',
  ThreadVerdictGood = 'ThreadTagGood',
  ThreadKindQuiet = 'ThreadTagQuiet',
}

--- A thread or a step's labels said quietly, for a list: its kind and
--- its verdict as coloured words, `feat · bug medium`. Only a high
--- severity keeps its badge, so it is what stands out.
---@param x thread.Labels
---@return thread.Chunks
function M.tags(x)
  local out = {} ---@type thread.Chunks
  local k = M.kind(x)
  if k then
    out[#out + 1] = { vim.trim(k[1]), TAG[k[2]] or 'ThreadMeta' }
  end
  local v = M.verdict(x)
  if v then
    if #out > 0 then
      out[#out + 1] = { ' · ', 'ThreadMeta' }
    end
    if x.severity == 'high' then
      out[#out + 1] = v
    else
      out[#out + 1] = { x.verdict .. (x.severity and (' ' .. x.severity) or ''), TAG[v[2]] or 'ThreadMeta' }
    end
  end
  return out
end

--- A thread or a step's labels in a row: its kind, its risk and its
--- verdict, two columns apart; nothing when it has none.
---@param x thread.Labels
---@param short boolean|nil  the risk as its shape alone
---@return thread.Chunks
function M.badges(x, short)
  local out = {} ---@type thread.Chunks
  for _, b in ipairs { M.kind(x) or false, M.risk(x, short) or false, M.verdict(x) or false } do
    if b then
      out[#out + 1] = { '  ' }
      out[#out + 1] = b
    end
  end
  return out
end

--- How a closed thread was closed, as a badge: ` fixed `.
---@param t thread.Thread
---@return { [1]: string, [2]: string }|nil
function M.closed(t)
  if not thread.closed(t) then
    return nil
  end
  return { ' ' .. t.status .. ' ', 'ThreadKindQuiet' }
end

return M
