--- A message: one turn of a conversation, yours or the agent's, its
--- prose, and the agent's the chunks it changed in answer. When it was
--- written is its state, with whether you have read it
--- (thread.model.conversation): yours says, the agent's is when it first
--- showed up.

local fields = require 'thread.model.fields'
local prose = require 'thread.model.prose'
local seen = require 'thread.store.seen'

local M = {}

---@class (exact) thread.Message
---@field from 'you'|'agent'
---@field at string|nil  yours, set by the plugin: when you wrote it
---@field prose thread.Prose
---@field changes string[]|nil  the agent's: the chunks it changed, by id

local FIELDS = { 'from', 'at', 'prose', 'changes' }

local GONE = {
  text = 'what it says is its `prose`, `{ "text": "..." }`',
  tours = "a review's `tours` walk the change; a message points at code with `{{chunk:id}}` and links",
}

---@param p thread.Problems
---@param where string
---@param raw any
---@param ctx thread.ParseContext
---@return thread.Message|nil
function M.parse(p, where, raw, ctx)
  if not fields.object(p, where, raw, FIELDS, GONE) then
    return nil
  end
  local from = fields.one_of(p, where, raw, 'from', { 'you', 'agent' }, true)
  local at = fields.text(p, where, raw, 'at')
  if at and not at:match '^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d$' then
    fields.bad(p, where, string.format('`at` is "%s": a time, `2026-10-13T10:00:00`', at))
  end
  if not prose.parse(p, where, raw, 'prose', ctx.file, true) then
    raw.prose = { text = '' }
  end
  local changes = fields.list(p, where, raw, 'changes')
  if changes and from == 'you' then
    fields.bad(p, where, "only the agent's messages have `changes`")
  end
  for i, c in ipairs(changes or {}) do
    ctx.refer(where, 'changes[' .. i .. ']', c)
  end
  return raw
end

--- A message's name in the .seen file: its conversation's, and its place
--- in it.
---@param c thread.Conversation
---@param i integer  its place in the conversation
---@return string
function M.name(c, i)
  return c.name .. ':' .. i
end

--- When a message was written: yours as you saved it; the agent's as it
--- first showed up.
---@param r thread.Review
---@param c thread.Conversation
---@param i integer
---@return string|nil  `2026-10-13T10:00:00`
function M.when(r, c, i)
  local m = c.messages[i]
  if not m then
    return nil
  elseif m.at then
    return m.at
  end
  return seen.heard(r.id, M.name(c, i))
end

return M
