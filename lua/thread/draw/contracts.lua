--- Contracts as a list: a row each, what the change did to it, its name
--- and why, in a sentence; the first few, then how many more until the
--- list is opened, so a long one never buries what comes after it.

local contract = require 'thread.model.contract'
local conversation = require 'thread.model.conversation'
local labels = require 'thread.draw.labels'
local text = require 'thread.base.text'

local M = {}

---@class thread.ContractsOpts
---@field width integer
---@field indent integer|nil  else the sheet's
---@field all boolean|nil  every one, not only the first few
---@field review thread.Review|nil  theirs, for how their conversations stand

-- The rows a list shows until it is opened.
M.SOME = 6

-- What the change did to each, as its sign's colour.
M.COLOUR = { ['+'] = 'ThreadAdded', ['~'] = 'ThreadFileModified', ['−'] = 'ThreadRemoved' }

--- What the list's rule says: how many, and of each change.
---@param list thread.Contract[]
---@return string
local function counts(list)
  local n = {} ---@type table<string, integer>
  for _, c in ipairs(list) do
    local change = c.source and c.source.change or 'changed'
    n[change] = (n[change] or 0) + 1
  end
  local out = { 'contracts' }
  for _, change in ipairs(contract.CHANGES) do
    if n[change] then
      out[#out + 1] = n[change] .. ' ' .. change
    end
  end
  return table.concat(out, ' · ')
end

--- A rule saying how many, then a row a contract: its sign and its name
--- in a column, why it is; on the right whose move its conversation is.
--- Each row is an item; past the first few a row says how many more.
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
    local sign = contract.sign(c)
    local right = o.review and labels.count(o.review, { conversation.of_contract(c) }) or {}
    local left =
      { { sign .. ' ', M.COLOUR[sign] }, { text.pad(text.fit(c.name, name), name), 'ThreadContract' }, { '  ' .. (c.why or c.kind), 'ThreadSummary' } }
    local row
    if #right > 0 then
      local fitted = text.fit_chunks(left, math.max(1, o.width - text.width(right) - 2))
      fitted[#fitted + 1] = { string.rep(' ', math.max(2, o.width - text.width(fitted) - text.width(right))) }
      row = P.chunks(vim.list_extend(fitted, right), indent)
    else
      row = P.chunks(text.fit_chunks(left, o.width), indent)
    end
    out[#out + 1] = { kind = 'contract', first = row, last = row, contract = c, item = true }
  end
  if shown < #list then
    P.chunks({ { text.fit('… ' .. (#list - shown) .. ' more   ⇥ shows them all', o.width - 2), 'ThreadMeta' } }, indent + 2)
  end
  return out
end

return M
