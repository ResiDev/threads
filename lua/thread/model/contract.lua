--- A contract: something other code relies on that the change touched, a
--- function's signature, a JSON field, a table, a key, a behaviour
--- callers count on. It holds the contract itself as it was and as it
--- is, each side a chunk where the code holds it in one place or written
--- out whole where none does; its prose; the code that depends on it,
--- each with how far the change reached it, its blast radius; and a
--- conversation. What touches it is worked out (thread.model.touch).

local fields = require 'thread.model.fields'
local message = require 'thread.model.message'
local prose = require 'thread.model.prose'

local M = {}

---@alias thread.Change 'added'|'changed'|'removed'

--- A contract no one place holds, written out whole as code.
---@class (exact) thread.Written
---@field lang string
---@field text string

--- One side of a contract: a chunk's id, or the contract written out.
---@alias thread.Side string|thread.Written

---@class (exact) thread.Source
---@field change thread.Change
---@field before thread.Side|nil  changed or removed
---@field after thread.Side|nil  added or changed

---@alias thread.Impact 'none'|'adapted'|'reworked'|'missed'

--- Code that depends on a contract, on the line that uses it, and how far
--- the change reached it.
---@class (exact) thread.Dependent
---@field chunk string
---@field impact thread.Impact
---@field text string|nil  what it had to do, and what it cost; only `none` may leave it out

---@class (exact) thread.Contract
---@field id integer
---@field name string  how it reads in the code, or a behaviour in a few words
---@field kind string  the agent's word for what sort of thing it is, shown as written
---@field source thread.Source
---@field why string|nil  what it is for, in a sentence: what the review's list shows
---@field prose thread.Prose  its page
---@field dependents thread.Dependent[]|nil
---@field messages thread.Message[]  a conversation about it

M.CHANGES = { 'added', 'changed', 'removed' }

--- How far a change reached a dependent, the furthest first: what a page
--- groups its blast radius by.
M.IMPACTS = { 'missed', 'reworked', 'adapted', 'none' }

local FIELDS = { 'id', 'name', 'kind', 'source', 'why', 'prose', 'dependents', 'messages' }

local GONE = {
  change = "what the change did to it is its `source`'s `change`",
  before = 'its sides are in its `source`',
  after = 'its sides are in its `source`',
  at = 'where it is defined is a side of its `source`, a chunk',
  shape = 'its sides are in its `source`; what changed is worked out from them',
  promises = 'what callers can count on goes in its `prose`',
  uses = 'the code that depends on it is its `dependents`',
  text = 'its page is its `prose`, `{ "text": "..." }`',
}

-- Which sides each change has.
local SIDES = { added = { after = true }, removed = { before = true }, changed = { before = true, after = true } }

---@param p thread.Problems
---@param where string
---@param raw table  the contract
---@param ctx thread.ParseContext
local function parse_source(p, where, raw, ctx)
  local at = where .. ', source'
  local s = raw.source
  if s == nil then
    fields.bad(p, where, 'no `source`: the contract as it was and as it is')
    return
  end
  if not fields.object(p, at, s, { 'change', 'before', 'after' }) then
    raw.source = nil
    return
  end
  local change = fields.one_of(p, at, s, 'change', M.CHANGES, true)
  for _, side in ipairs { 'before', 'after' } do
    local v = s[side]
    local want = change and SIDES[change][side]
    if v == nil and want then
      fields.bad(p, at, string.format('%s, so it has `%s`', change, side))
    elseif v ~= nil and change and not want then
      fields.bad(p, at, string.format('%s, so it has no `%s`', change, side))
    elseif type(v) == 'string' then
      ctx.refer(at, side, v)
    elseif v ~= nil and fields.object(p, at .. ', ' .. side, v, { 'lang', 'text' }) then
      fields.text(p, at .. ', ' .. side, v, 'lang', true)
      fields.text(p, at .. ', ' .. side, v, 'text', true)
    end
  end
end

---@param p thread.Problems
---@param where string
---@param raw table  the contract
---@param ctx thread.ParseContext
local function parse_dependents(p, where, raw, ctx)
  raw.dependents = fields.list(p, where, raw, 'dependents')
  for i, d in ipairs(raw.dependents or {}) do
    local at = string.format('%s, dependent %d', where, i)
    if fields.object(p, at, d, { 'chunk', 'impact', 'text' }) then
      if d.chunk == nil then
        fields.bad(p, at, 'no `chunk`: the line that uses the contract')
      else
        ctx.refer(at, 'chunk', d.chunk)
      end
      local impact = fields.one_of(p, at, d, 'impact', M.IMPACTS, true)
      local text = fields.text(p, at, d, 'text')
      if impact and impact ~= 'none' and not (text and vim.trim(text) ~= '') then
        fields.bad(p, at, string.format('%s, so it says in `text` what it had to do and what it cost', impact))
      end
    end
  end
end

--- A review's contracts, checked.
---@param p thread.Problems
---@param raw table  the review
---@param ctx thread.ParseContext
function M.parse(p, raw, ctx)
  raw.contracts = fields.list(p, 'the review', raw, 'contracts') or {}
  local ids = {} ---@type table<integer, integer>  an id -> the contract that has it
  for i, c in ipairs(raw.contracts) do
    local id = type(c) == 'table' and c.id or nil ---@type any
    local where = type(id) == 'number' and ('contract ' .. id) or ('the contract at place ' .. i)
    if fields.object(p, where, c, FIELDS, GONE) then
      id = fields.count(p, where, c, 'id', true)
      if id and ids[id] then
        fields.bad(p, where, 'its id is used twice: each contract has its own')
      elseif id then
        ids[id] = i
      end
      fields.text(p, where, c, 'name', true)
      fields.text(p, where, c, 'kind', true)
      fields.text(p, where, c, 'why')
      parse_source(p, where, c, ctx)
      if not prose.parse(p, where, c, 'prose', ctx.file, true) then
        c.prose = { text = '' }
      end
      parse_dependents(p, where, c, ctx)
      c.messages = fields.list(p, where, c, 'messages') or {}
      for k, m in ipairs(c.messages) do
        message.parse(p, where .. ', message ' .. k, m, ctx)
      end
    end
  end
end

local named = setmetatable({}, { __mode = 'k' }) ---@type table<table, table<integer, string>>

--- Each contract's name, by its id: what `#contract:3` in prose reads as.
---@param r { contracts: thread.Contract[] }  the review
---@return table<integer, string>
function M.names(r)
  local out = named[r]
  if not out then
    out = {}
    for _, c in ipairs(r.contracts) do
      out[c.id] = c.name
    end
    named[r] = out
  end
  return out
end

--- Its name in the .seen file, its conversation's: `contract:3`.
---@param c thread.Contract
---@return string
function M.name(c)
  return 'contract:' .. c.id
end

--- What the change did to it, as a sign: `+` added, `~` changed, `−`
--- removed.
---@param c thread.Contract
---@return string
function M.sign(c)
  local change = c.source and c.source.change
  return change == 'added' and '+' or change == 'removed' and '−' or '~'
end

--- The chunks it names, by id: its sides', then its dependents', each
--- once.
---@param c thread.Contract
---@return string[]
function M.chunks(c)
  local out, seen = {}, {} ---@type string[], table<string, true>
  ---@param id any
  local function add(id)
    if type(id) == 'string' and not seen[id] then
      seen[id] = true
      out[#out + 1] = id
    end
  end
  local s = c.source or {}
  add(s.before)
  add(s.after)
  for _, d in ipairs(c.dependents or {}) do
    add(d.chunk)
  end
  return out
end

--- Its dependents by impact, the furthest reached first; an impact none
--- has is left out.
---@param c thread.Contract
---@return { impact: thread.Impact, dependents: thread.Dependent[] }[]
function M.radius(c)
  local out = {}
  for _, impact in ipairs(M.IMPACTS) do
    local list = vim.tbl_filter(function(d)
      return d.impact == impact
    end, c.dependents or {})
    if #list > 0 then
      out[#out + 1] = { impact = impact, dependents = list }
    end
  end
  return out
end

return M
