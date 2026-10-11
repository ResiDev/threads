--- Code drawn outside its buffer: the scope around a line.

local M = {}

--- Whether a syntax node holds a body of code: a function, method, class,
--- impl or struct, and not a call of one.
local function holds_code(ty)
  if ty:find 'call' or ty:find 'invocation' then
    return false
  end
  return ty:find 'function' or ty:find 'method' or ty:find 'class' or ty:find 'impl' or ty:find 'struct'
end

--- The lines (1-based) of the function, method or class around lines
--- `lo`..`hi` of the tree under `root`; nothing when there is none.
---@param root TSNode
---@param lo integer
---@param hi integer
---@return integer|nil, integer|nil
function M.enclosing(root, lo, hi)
  local node = root:named_descendant_for_range(lo - 1, 0, hi - 1, 0)
  while node do
    if holds_code(node:type()) then
      local sr, _, er, ec = node:range()
      return sr + 1, ec == 0 and er or er + 1
    end
    node = node:parent()
  end
end

return M
