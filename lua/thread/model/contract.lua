--- A contract: what other code relies on that a review's change touched,
--- a function's signature, a JSON field, a table, a key. The review lists
--- each once; which threads and files touch it is worked out from its
--- chunks, never written. Prose names one as `[[id]]`.

local chunk = require 'thread.model.chunk'
local fields = require 'thread.model.fields'

local M = {}

---@alias thread.Change 'added'|'changed'|'removed'|'relied on'

---@class (exact) thread.Contract
---@field id string  what prose names it by, `[[id]]`
---@field name string  how it reads in the code, or a behaviour in a few words
---@field kind string|nil  the agent's word for what sort of thing it is, shown as written
---@field change thread.Change
---@field before string|nil  what it was: a signature, a shape, a sentence
---@field after string|nil  what it is
---@field why string|nil  what it is for, in a sentence
---@field at thread.Chunk|nil  where it is defined; a behaviour may have none
---@field uses thread.Chunk[]|nil  the code that relies on it

M.CHANGES = { 'added', 'changed', 'removed', 'relied on' }

local FIELDS = { 'id', 'name', 'kind', 'change', 'before', 'after', 'why', 'at', 'uses' }

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
      if change == 'added' and c.before then
        fields.warn(p, where, 'added, so it has no `before`')
      elseif change == 'removed' and c.after then
        fields.warn(p, where, 'removed, so it has no `after`')
      end
      if c.at ~= nil then
        c.at = chunk.parse(p, where .. ', at', c.at)
      end
      c.uses = fields.list(p, where, c, 'uses')
      for k, u in ipairs(c.uses or {}) do
        chunk.parse(p, where .. ', use ' .. k, u)
      end
    end
  end
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
