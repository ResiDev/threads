--- A contract: what other code relies on that a review's change touched,
--- a function's signature, a JSON field, a table, a key. The review lists
--- each once, and each has a page of its own: why it changed, its shape
--- as blocks, before and after where they differ, what callers can count
--- on, and each use with what the change means for it. Which tours,
--- steps and files touch it is worked out from its chunks, never
--- written. Prose names one as `[[id]]`.

local chunk = require 'thread.model.chunk'
local fields = require 'thread.model.fields'
local message = require 'thread.model.message'

local M = {}

---@alias thread.Change 'added'|'changed'|'removed'|'relied on'

--- What the change did to one row of a block, or a promise: none, as it was.
---@alias thread.RowChange 'added'|'changed'|'removed'

--- A row of a block: a field (`name`), a value (`value`) or a case
--- (`when`), each with what the change did to it.
---@class thread.ShapeRow
---@field name string|nil  fields: a column, a key, an argument
---@field value string|nil  values: one of the set
---@field when string|nil  cases: the situation
---@field type string|nil  fields: its type, as the code says it
---@field was string|nil  what it was, when changed
---@field before string|nil  cases: what happened
---@field after string|nil  cases: what happens now
---@field change thread.RowChange|nil
---@field note string|nil

--- A part of a contract's shape, drawn as its kind is: a signature, its
--- change marked inside the line; fields, values and cases as rows; an
--- example as code, before and after side by side; or prose.
---@class thread.ShapeBlock
---@field kind 'signature'|'fields'|'values'|'cases'|'example'|'text'
---@field title string|nil
---@field rows thread.ShapeRow[]|nil  fields, values, cases
---@field before string|nil  signature, example
---@field after string|nil
---@field lang string|nil  example: what its code is in
---@field text string|nil  text

--- What callers can count on, and what the change did to it.
---@class thread.Promise
---@field text string
---@field change thread.RowChange|nil

---@class (exact) thread.Contract
---@field id string  what prose names it by, `[[id]]`
---@field name string  how it reads in the code, or a behaviour in a few words
---@field kind string|nil  the agent's word for what sort of thing it is, shown as written
---@field change thread.Change
---@field before string|nil  what it was, a signature or a sentence: a signature block's, written short
---@field after string|nil  what it is
---@field why string|nil  what it is for, in a sentence: what a list of contracts shows
---@field text string|nil  its page's prose, as long as it needs: why it changed, what it costs, what to look at
---@field at thread.Chunk|nil  where it is defined; a behaviour may have none
---@field shape thread.ShapeBlock[]|nil  what it is, and what it was where that differs
---@field promises thread.Promise[]|nil  what callers can count on
---@field uses thread.Use[]|nil  the code that relies on it, each with what the change means for it
---@field messages thread.Message[]|nil  a conversation about it, as a note has

M.CHANGES = { 'added', 'changed', 'removed', 'relied on' }
M.ROW_CHANGES = { 'added', 'changed', 'removed' }
M.BLOCKS = { 'signature', 'fields', 'values', 'cases', 'example', 'text' }

local FIELDS = { 'id', 'name', 'kind', 'change', 'before', 'after', 'why', 'text', 'at', 'shape', 'promises', 'uses', 'messages' }
local BLOCK_FIELDS = { 'kind', 'title', 'rows', 'before', 'after', 'lang', 'text' }
local ROW_FIELDS = { 'name', 'value', 'when', 'type', 'was', 'before', 'after', 'change', 'note' }
local PROMISE_FIELDS = { 'text', 'change' }

-- What each kind of block has, beside its kind and title; and what each
-- of its rows must have.
local HAS = {
  signature = { before = true, after = true },
  fields = { rows = true },
  values = { rows = true },
  cases = { rows = true },
  example = { before = true, after = true, lang = true },
  text = { text = true },
}
local ROW = { fields = 'name', values = 'value', cases = 'when' }

---@param p thread.Problems
---@param where string
---@param b any
local function parse_block(p, where, b)
  if not fields.object(p, where, b, BLOCK_FIELDS) then
    return
  end
  local kind = fields.one_of(p, where, b, 'kind', M.BLOCKS, true)
  fields.text(p, where, b, 'title')
  if not kind then
    return
  end
  for _, k in ipairs { 'rows', 'before', 'after', 'lang', 'text' } do
    if b[k] ~= nil and not HAS[kind][k] then
      fields.bad(p, where, string.format('a %s block has no `%s`', kind, k))
    end
  end
  for _, k in ipairs { 'before', 'after', 'lang' } do
    fields.text(p, where, b, k)
  end
  fields.text(p, where, b, 'text', kind == 'text')
  if (kind == 'signature' or kind == 'example') and not (b.before or b.after) then
    fields.bad(p, where, string.format('a %s block has a `before`, an `after` or both', kind))
  end
  local key = ROW[kind]
  if not key then
    return
  end
  b.rows = fields.list(p, where, b, 'rows')
  if not b.rows then
    fields.bad(p, where, string.format('a %s block has `rows`, each with its `%s`', kind, key))
    return
  end
  for i, row in ipairs(b.rows) do
    local at = where .. ', row ' .. i
    if fields.object(p, at, row, ROW_FIELDS) then
      for _, k in ipairs(ROW_FIELDS) do
        if k ~= 'change' then
          fields.text(p, at, row, k, k == key)
        end
      end
      fields.one_of(p, at, row, 'change', M.ROW_CHANGES)
    end
  end
end

--- A review's contracts, checked; nil when it has none.
---@param p thread.Problems
---@param raw table  the review
function M.parse(p, raw)
  raw.contracts = fields.list(p, 'the review', raw, 'contracts')
  local ids = {} ---@type table<string, integer>
  for i, c in ipairs(raw.contracts or {}) do
    local where = 'the review, contract ' .. i
    if fields.object(p, where, c, FIELDS) then
      local id = fields.text(p, where, c, 'id', true)
      if id and not id:match '^[%w_.-]+$' then
        fields.bad(p, where, string.format('its `id` is "%s": letters, digits, `-`, `_` and `.` only, so `[[%s]]` finds it', id, id))
      elseif id and ids[id] then
        fields.bad(p, where, string.format('contract %d has the id "%s" too: each has its own', ids[id], id))
      elseif id then
        ids[id] = i
      end
      fields.text(p, where, c, 'name', true)
      fields.text(p, where, c, 'kind')
      local change = fields.one_of(p, where, c, 'change', M.CHANGES, true)
      fields.text(p, where, c, 'before')
      fields.text(p, where, c, 'after')
      fields.text(p, where, c, 'why')
      fields.text(p, where, c, 'text')
      if change == 'added' and c.before then
        fields.warn(p, where, 'added, so it has no `before`')
      elseif change == 'removed' and c.after then
        fields.warn(p, where, 'removed, so it has no `after`')
      end
      if c.at ~= nil then
        c.at = chunk.parse(p, where .. ', at', c.at)
      end
      c.shape = fields.list(p, where, c, 'shape')
      for k, b in ipairs(c.shape or {}) do
        parse_block(p, where .. ', block ' .. k, b)
      end
      c.promises = fields.list(p, where, c, 'promises')
      for k, x in ipairs(c.promises or {}) do
        local at = where .. ', promise ' .. k
        if fields.object(p, at, x, PROMISE_FIELDS) then
          fields.text(p, at, x, 'text', true)
          fields.one_of(p, at, x, 'change', M.ROW_CHANGES)
        end
      end
      c.uses = fields.list(p, where, c, 'uses')
      for k, u in ipairs(c.uses or {}) do
        chunk.parse_use(p, where .. ', use ' .. k, u)
      end
      c.messages = fields.list(p, where, c, 'messages') or {}
      for k, m in ipairs(c.messages) do
        local at = where .. ', message ' .. k
        if message.parse(p, at, m) and m.tours then
          fields.bad(p, at, "a contract's messages carry no tours: the review's `tours` walk the change")
        end
      end
    end
  end
end

--- Its shape: the blocks written, after a signature block made of its
--- `before` and `after` when it has them and no signature of its own.
---@param c thread.Contract
---@return thread.ShapeBlock[]
function M.shape(c)
  local out = {} ---@type thread.ShapeBlock[]
  local signed = false
  for _, b in ipairs(c.shape or {}) do
    signed = signed or b.kind == 'signature'
  end
  if (c.before or c.after) and not signed then
    out[1] = { kind = 'signature', before = c.before, after = c.after }
  end
  return vim.list_extend(out, c.shape or {})
end

--- A contract by its id.
---@param r thread.Review
---@param id string
---@return thread.Contract|nil
function M.find(r, id)
  for _, c in ipairs(r.contracts or {}) do
    if c.id == id then
      return c
    end
  end
end

--- Each contract's name, by its id: what `[[id]]` in prose reads as.
---@param r thread.Review
---@return table<string, string>
function M.names(r)
  local out = {} ---@type table<string, string>
  for _, c in ipairs(r.contracts or {}) do
    out[c.id] = c.name
  end
  return out
end

--- Its chunks: where it is defined, then what uses it.
---@param c thread.Contract
---@return thread.Chunk[]
function M.chunks(c)
  local out = {} ---@type thread.Chunk[]
  if c.at then
    out[1] = c.at
  end
  return vim.list_extend(out, c.uses or {})
end

--- Whether two chunks share a line, as written: the same file and side,
--- their lines overlapping.
---@param a thread.Chunk
---@param b thread.Chunk
---@return boolean
function M.overlap(a, b)
  if a.file ~= b.file or a.side ~= b.side then
    return false
  end
  local a2, b2 = a.line + (a.lines or 1) - 1, b.line + (b.lines or 1) - 1
  return a.line <= b2 and b.line <= a2
end

--- Whether any of a contract's chunks shares a line with one of `list`.
---@param c thread.Contract
---@param list thread.Chunk[]
---@return boolean
function M.touches(c, list)
  for _, mine in ipairs(M.chunks(c)) do
    for _, other in ipairs(list) do
      if M.overlap(mine, other) then
        return true
      end
    end
  end
  return false
end

--- The review's contracts that any of `list` touches, in the review's
--- order.
---@param r thread.Review
---@param list thread.Chunk[]
---@return thread.Contract[]
function M.touched(r, list)
  return vim.tbl_filter(function(c)
    return M.touches(c, list)
  end, r.contracts or {})
end

return M
