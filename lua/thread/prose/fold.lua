--- How much a tour or a contract placed in prose shows, which Tab turns
--- through: a tour its steps' text with where each is, then their code
--- inline, then only their titles; a contract itself, then one row. Kept by what it is, so the same block
--- folds alike wherever it is drawn, the screen or a card in the code.

local M = {}

---@alias thread.FoldKind 'tour'|'contract'

--- Each kind's folds in the order Tab goes, the first how it opens.
M.FOLDS = {
  tour = { 'where', 'code', 'titles' },
  contract = { 'source', 'row' },
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
