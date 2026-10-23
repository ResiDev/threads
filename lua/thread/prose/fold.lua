--- How much a tour or a contract placed in prose shows, which Tab turns
--- through: a tour its steps' titles, then their text with where each
--- is, then their code inline; a contract itself as it is, what changed
--- marked, then against as it was, then one row. Kept by what it is, so
--- the same block folds alike wherever it is drawn, the screen or a card
--- in the code.

local M = {}

---@alias thread.FoldKind 'tour'|'contract'|'side'

--- Each kind's folds in the order Tab goes, the first how it opens. A
--- contract added or removed is a `side`: it has nothing to be set
--- against.
M.FOLDS = {
  tour = { 'titles', 'where', 'code' },
  contract = { 'source', 'against', 'row' },
  side = { 'source', 'row' },
}

local now = {} ---@type table<string, string>

--- What a block is known by, to fold it: its kind, its review and its
--- name there.
---@param kind thread.FoldKind
---@param review string|nil  its review's id
---@param name string
---@return string
function M.key(kind, review, name)
  return kind .. ':' .. (review or '') .. ':' .. name
end

--- How a block shows now.
---@param kind thread.FoldKind
---@param key string
---@return string
function M.get(kind, key)
  return now[key] or M.FOLDS[kind][1]
end

--- Turn a block on to its next fold, and say which.
---@param kind thread.FoldKind
---@param key string
---@return string
function M.turn(kind, key)
  local list = M.FOLDS[kind]
  local at = 1
  for i, f in ipairs(list) do
    if f == M.get(kind, key) then
      at = i
    end
  end
  now[key] = list[at % #list + 1]
  return now[key]
end

return M
