--- Contracts as a list: a row each, what the change did to it, its name
--- and what it is now; the first few, then how many more until the list
--- is opened, so a long one never buries what comes after it.

local labels = require 'thread.draw.labels'
local text = require 'thread.base.text'

local M = {}

---@class thread.ContractsOpts
---@field width integer
---@field indent integer|nil  else the sheet's
---@field all boolean|nil  every one, not only the first few

-- The rows a list shows until it is opened.
M.SOME = 6

-- What the change did to each, as a glyph and its colour.
local CHANGE = {
  added = { '+', 'ThreadAdded' },
  changed = { '~', 'ThreadFileModified' },
  removed = { '−', 'ThreadRemoved' },
  ['relied on'] = { '·', 'ThreadMeta' },
}

--- What the list's rule says: how many, and of each change.
---@param list thread.Contract[]
---@return string
local function counts(list)
  local n = {} ---@type table<string, integer>
  for _, c in ipairs(list) do
    n[c.change] = (n[c.change] or 0) + 1
  end
  local out = { 'contracts' }
  for _, change in ipairs { 'added', 'changed', 'removed', 'relied on' } do
    if n[change] then
      out[#out + 1] = n[change] .. ' ' .. change
    end
  end
  return table.concat(out, ' · ')
end

--- A rule saying how many, then a row a contract: `+` and its name in
--- a column, what it is now (what it was, when removed). Each row is an
--- item, `chunk` where it is defined; past the first few a row says how
--- many more.
---@param P thread.Sheet
---@param list thread.Contract[]
---@param o thread.ContractsOpts
---@return thread.Part[]
function M.draw(P, list, o)
  local indent = o.indent or P.indent
  local out = {} ---@type thread.Part[]
  if #list == 0 then
    return out
  end
  P.chunks(labels.rule(counts(list), o.width), indent)
  local shown = o.all and #list or math.min(#list, M.SOME)
  local name = 0
  for i = 1, shown do
    name = math.max(name, text.width(list[i].name))
  end
  name = math.min(name, math.floor(o.width * 0.4))
  for i = 1, shown do
    local c = list[i]
    local g = CHANGE[c.change] or CHANGE['relied on']
    local now = c.change == 'removed' and c.before or c.after or c.why or ''
    local row = P.chunks(
      text.fit_chunks({ { g[1] .. ' ', g[2] }, { text.pad(text.fit(c.name, name), name), 'ThreadContract' }, { '  ' .. now, 'ThreadSummary' } }, o.width),
      indent
    )
    out[#out + 1] = { kind = 'contract', first = row, last = row, contract = c, chunk = c.at, item = true }
  end
  if shown < #list then
    P.chunks({ { text.fit('… ' .. (#list - shown) .. ' more   ⇥ shows them all', o.width - 2), 'ThreadMeta' } }, indent + 2)
  end
  return out
end

return M
