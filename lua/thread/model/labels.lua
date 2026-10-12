--- Labels on a thread or a step: a verdict and its severity, a risk and
--- why, and a kind. Drawing them is thread.draw.labels.

local fields = require 'thread.model.fields'

local M = {}

---@alias thread.Verdict 'bug'|'flaw'|'risk'|'trade-off'|'decision'|'how it works'|'fine'
---@alias thread.Level 'low'|'medium'|'high'
---@alias thread.Kind 'feat'|'fix'|'refactor'|'perf'|'test'|'docs'|'chore'|'style'

---@class (exact) thread.Labels
---@field verdict thread.Verdict|nil
---@field severity thread.Level|nil
---@field risk thread.Level|nil
---@field risk_why string|nil
---@field kind thread.Kind|nil

M.VERDICTS = { 'bug', 'flaw', 'risk', 'trade-off', 'decision', 'how it works', 'fine' }
M.LEVELS = { 'low', 'medium', 'high' }
M.KINDS = { 'feat', 'fix', 'refactor', 'perf', 'test', 'docs', 'chore', 'style' }

--- The fields a primitive with labels has for them.
M.FIELDS = { 'verdict', 'severity', 'risk', 'risk_why', 'kind' }

---@param p thread.Problems
---@param where string
---@param raw table  a thread or a step
function M.parse(p, where, raw)
  fields.one_of(p, where, raw, 'verdict', M.VERDICTS)
  fields.one_of(p, where, raw, 'severity', M.LEVELS)
  local risk = fields.one_of(p, where, raw, 'risk', M.LEVELS)
  local why = fields.text(p, where, raw, 'risk_why')
  fields.one_of(p, where, raw, 'kind', M.KINDS)
  if risk and risk ~= 'low' and not (why and vim.trim(why) ~= '') then
    fields.warn(p, where, string.format('a %s risk with no `risk_why`', risk))
  end
end

return M
