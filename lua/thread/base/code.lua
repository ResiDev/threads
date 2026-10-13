--- Code drawn outside its buffer, read with treesitter: its colours, and
--- the function around a line.

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

--- `source` parsed as the language of `file`: its tree's root, and the
--- language; nothing when treesitter cannot read it.
---@param source string
---@param file string
---@return TSNode|nil, string|nil
local function parse(source, file)
  local ft = vim.filetype.match { filename = file }
  local lang = ft and vim.treesitter.language.get_lang(ft)
  if not lang then
    return nil
  end
  local ok, parser = pcall(vim.treesitter.get_string_parser, source, lang)
  local parsed, trees = false, nil
  if ok then
    parsed, trees = pcall(parser.parse, parser)
  end
  if parsed and trees and trees[1] then
    return trees[1]:root(), lang
  end
end

--- Treesitter's colours for a few lines of code, out of their file.
---@param lines string[]
---@param file string  its name says the language
---@return table<integer, { [1]: integer, [2]: integer, [3]: string }[]>  line index -> byte spans
function M.syntax(lines, file)
  if #lines == 0 then
    return {}
  end
  local source = table.concat(lines, '\n')
  local root, lang = parse(source, file)
  local query = root and lang and vim.treesitter.query.get(lang, 'highlights')
  if not (root and query) then
    return {}
  end
  local spans = {}
  for id, node in query:iter_captures(root, source, 0, -1) do
    local name = query.captures[id]
    if name ~= 'spell' and name ~= 'nospell' and name:sub(1, 1) ~= '_' then
      local sr, sc, er, ec = node:range()
      for r = sr, er do
        local line = lines[r + 1]
        if line then
          spans[r + 1] = spans[r + 1] or {}
          table.insert(spans[r + 1], { r == sr and sc or 0, r == er and ec or #line, '@' .. name .. '.' .. lang })
        end
      end
    end
  end
  return spans
end

local scopes = {} -- file text -> { [lo .. ':' .. hi] = { lo, hi } | false }

--- A line of code with each tab drawn as four spaces, and where a byte
--- column of the line as read lands in it.
---@param line string
---@return string drawn, fun(col: integer): integer at
function M.untab(line)
  if not line:find '\t' then
    return line, function(col)
      return col
    end
  end
  return (line:gsub('\t', '    ')), function(col)
    local _, tabs = line:sub(1, col):gsub('\t', '')
    return col + 3 * tabs
  end
end

--- The function, method or class around lines `lo`..`hi` of a file's
--- `lines`; nothing when there is none.
---@param lines string[]
---@param file string
---@param lo integer
---@param hi integer
---@return integer|nil, integer|nil
function M.scope(lines, file, lo, hi)
  local source = table.concat(lines, '\n')
  local key = lo .. ':' .. hi
  scopes[source] = scopes[source] or {}
  if scopes[source][key] == nil then
    local root = parse(source, file)
    local slo, shi
    if root then
      slo, shi = M.enclosing(root, lo, hi)
    end
    scopes[source][key] = slo and { slo, shi } or false
  end
  local hit = scopes[source][key]
  if hit then
    return hit[1], hit[2]
  end
end

return M
