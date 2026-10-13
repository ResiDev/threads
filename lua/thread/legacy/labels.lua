--- How today's screens label things: whose move a thread is, who wrote a
--- message, a verdict, a group's kind and risk. It came out of ui/look as
--- it was, and stays here for legacy until the switch; thread.draw.labels
--- is the rebuild's.

local config = require 'thread.config'

local M = {}

--- Whose move it is, as a glyph: an envelope when it is yours (sealed
--- when there is something new, open once read), while it is the agent's
--- an envelope on its way, a map for a tour or explanation (nobody's), a check
--- when closed. Without `ui.icons`: ● ○ ◔ ◇ · ✓.
---@param status string
---@param unseen boolean|nil
---@param stale boolean|nil
---@return string glyph, string hl
function M.glyph(status, unseen, stale)
  local nerd = config.options.ui.icons ~= false
  if status == 'closed' then
    return nerd and '󰗡' or '✓', 'ThreadSignDone'
  elseif stale then
    return '!', 'DiagnosticWarn'
  elseif status == 'waiting' then
    return nerd and '󱡯' or '◔', 'ThreadSignWaiting'
  elseif status == 'info' then
    if unseen then
      return nerd and '󰍍' or '◇', 'ThreadSignInfoNew'
    end
    return nerd and '󰦂' or '·', 'ThreadSignInfo'
  elseif unseen then
    return nerd and '󰇮' or '●', 'ThreadSignAnswered'
  end
  return nerd and '󰗯' or '○', 'ThreadSignAnswered'
end

--- Who wrote a message, as a shape: a person for you, a robot for the
--- agent, lit when you have not read it. With `ui.icons` off, ● you and ▲
--- the agent, △ unread.
---@param m table  the message
---@param unread boolean|nil
---@return string glyph, string hl
function M.who(m, unread)
  local nerd = config.options.ui.icons ~= false
  if m.from == 'you' then
    return nerd and '󰀄' or '●', 'ThreadDotYou'
  elseif unread then
    return nerd and '󰚩' or '△', 'ThreadDotAgentNew'
  end
  return nerd and '󰚩' or '▲', 'ThreadDotAgent'
end

--- A message's label: its shape, `󰚩`.
---@param m table  the message
---@param unread boolean|nil
---@return string label, string hl
function M.label(m, unread)
  local g = M.who(m, unread)
  if m.from == 'you' then
    return g, 'ThreadYou'
  end
  return g, unread and 'ThreadAgentNew' or 'ThreadAgent'
end

--- The last few messages, a shape each for who wrote it.
M.DOTS = 5
M.DOTS_WIDTH = 2 + M.DOTS * 2
---@param messages table[]
---@param seen integer  messages seen
---@return { [1]: string, [2]: string }[]
function M.dots(messages, seen)
  local out = { { #messages > M.DOTS and '… ' or ' ', 'ThreadMeta' } }
  local from = math.max(1, #messages - M.DOTS + 1)
  for i = from, #messages do
    local g, hl = M.who(messages[i], messages[i].from ~= 'you' and i > seen)
    out[#out + 1] = { g .. (i < #messages and ' ' or ''), hl }
  end
  return out
end

-- A verdict's badge colour: a defect, a cost to weigh, an explanation, fine.
local VERDICT_HL = {
  bug = 'ThreadVerdictBad',
  flaw = 'ThreadVerdictBad',
  risk = 'ThreadVerdictWarn',
  ['trade-off'] = 'ThreadVerdictWarn',
  decision = 'ThreadVerdictInfo',
  ['how it works'] = 'ThreadVerdictInfo',
  fine = 'ThreadVerdictGood',
}

-- A review group's kind: new things green, fixes red, the routine quiet.
local KIND_HL = {
  feat = 'ThreadVerdictGood',
  fix = 'ThreadVerdictBad',
  perf = 'ThreadVerdictWarn',
  refactor = 'ThreadVerdictInfo',
  test = 'ThreadVerdictInfo',
  docs = 'ThreadKindQuiet',
  chore = 'ThreadKindQuiet',
  style = 'ThreadKindQuiet',
}

--- A review group's kind as a badge: ` feat `.
---@param kind string|nil
---@return { [1]: string, [2]: string }|nil
function M.kind_badge(kind)
  if type(kind) ~= 'string' or kind == '' then
    return nil
  end
  return { ' ' .. kind .. ' ', KIND_HL[kind] or 'ThreadKindQuiet' }
end

-- How risky a group is: a shape and a colour, so it reads without either.
local RISK = {
  high = { '●', 'ThreadRiskHigh' },
  medium = { '◐', 'ThreadRiskMedium' },
  low = { '○', 'ThreadRiskLow' },
}

--- A review group's risk: `● high risk`, or short, `●`.
---@param risk string|nil
---@param short boolean|nil
---@return { [1]: string, [2]: string }|nil
function M.risk(risk, short)
  local r = RISK[risk]
  if not r then
    return nil
  end
  return { short and r[1] or (r[1] .. ' ' .. risk .. ' risk'), r[2] }
end

--- The verdict of a thread's latest message that has one, as a badge.
---@param thread thread.legacy.Thread
---@return { text: string, hl: string }|nil
function M.verdict_of(thread)
  for i = #thread.messages, 1, -1 do
    local m = thread.messages[i]
    if type(m.verdict) == 'string' and m.verdict ~= '' then
      return {
        text = m.verdict:upper() .. ((type(m.severity) == 'string' and m.severity ~= '') and (' · ' .. m.severity) or ''),
        hl = VERDICT_HL[m.verdict] or 'ThreadVerdictInfo',
      }
    end
  end
end

return M
