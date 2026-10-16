--- A note: anything in a review that is not walked, on a chunk or on no
--- line. Its first message says what it is, the rest are its
--- conversation. Each kind asks something different of you and has its
--- own statuses: an issue to fix or dismiss, a decision to agree with or
--- reverse, a suggestion to take or decline, a question to answer, a fix
--- to check, and a comment, which asks nothing and has none. Either of
--- you can write any kind.

local fields = require 'thread.model.fields'
local message = require 'thread.model.message'

local M = {}

---@alias thread.NoteKind 'issue'|'decision'|'suggestion'|'question'|'fix'|'comment'

---@class (exact) thread.Note
---@field id integer
---@field kind thread.NoteKind
---@field title string
---@field chunk string|nil  its chunk's id; none: on no line
---@field status string|nil  one of its kind's; a comment has none
---@field issue 'bug'|'flaw'|'risk'|nil  an issue's
---@field severity 'low'|'medium'|'high'|nil  an issue's
---@field messages thread.Message[]  the first says what it is

--- The kinds, in the order a review lists them: what asks most of you
--- first.
M.KINDS = { 'issue', 'decision', 'question', 'suggestion', 'fix', 'comment' }

--- Each kind's statuses, open first; a comment has none.
---@type table<thread.NoteKind, string[]>
M.STATUSES = {
  issue = { 'open', 'fixed', "won't fix", 'not a problem' },
  decision = { 'open', 'agreed', 'reversed' },
  suggestion = { 'open', 'taken', 'declined' },
  question = { 'open', 'answered' },
  fix = { 'open', 'checked' },
  comment = {},
}

M.ISSUES = { 'bug', 'flaw', 'risk' }
M.SEVERITIES = { 'low', 'medium', 'high' }

local FIELDS = { 'id', 'kind', 'title', 'chunk', 'status', 'issue', 'severity', 'messages' }

---@param p thread.Problems
---@param raw any
---@param n integer  its place in the review's list
---@param ctx thread.ParseContext
---@return thread.Note|nil
function M.parse(p, raw, n, ctx)
  local id = type(raw) == 'table' and raw.id
  local where = type(id) == 'number' and ('note ' .. id) or string.format('the note at place %d', n)
  if not fields.object(p, where, raw, FIELDS) then
    return nil
  end
  fields.count(p, where, raw, 'id', true)
  local kind = fields.one_of(p, where, raw, 'kind', M.KINDS, true)
  fields.text(p, where, raw, 'title', true)
  if raw.chunk ~= nil then
    ctx.refer(where, 'chunk', raw.chunk)
  end
  if kind == 'comment' then
    if raw.status ~= nil then
      fields.bad(p, where, 'a comment asks for nothing, so it has no `status`')
      raw.status = nil
    end
  elseif kind then
    raw.status = fields.one_of(p, where, raw, 'status', M.STATUSES[kind], true) or 'open'
  end
  if kind == 'issue' then
    fields.one_of(p, where, raw, 'issue', M.ISSUES, true)
    fields.one_of(p, where, raw, 'severity', M.SEVERITIES, true)
  elseif kind then
    for _, k in ipairs { 'issue', 'severity' } do
      if raw[k] ~= nil then
        fields.bad(p, where, string.format('only an issue has `%s`; this is a %s', k, kind))
        raw[k] = nil
      end
    end
  end
  local messages = fields.list(p, where, raw, 'messages')
  if not messages or #messages == 0 then
    fields.bad(p, where, 'no `messages`: the first says what it is')
  end
  raw.messages = messages or {}
  for i, m in ipairs(raw.messages) do
    message.parse(p, where .. ', message ' .. i, m, ctx)
  end
  return raw
end

--- Whether it is settled: a status other than open. A comment never is.
---@param n thread.Note
---@return boolean
function M.closed(n)
  return n.status ~= nil and n.status ~= 'open'
end

--- Whether it asks something of you and has not had it: open, and not a
--- comment.
---@param n thread.Note
---@return boolean
function M.open(n)
  return n.status == 'open'
end

--- Its name in the .seen file, its conversation's: `note:12`.
---@param n thread.Note
---@return string
function M.name(n)
  return 'note:' .. n.id
end

--- Its kind as a person says it, a count of them: `issue`, `2 issues`,
--- `3 fixes`.
---@param kind thread.NoteKind
---@param n integer|nil
---@return string
function M.noun(kind, n)
  if not n then
    return kind
  end
  return n .. ' ' .. kind .. (n == 1 and '' or kind == 'fix' and 'es' or 's')
end

return M
