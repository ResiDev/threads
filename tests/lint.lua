-- What make lint finds beyond formatting: every problem of
-- lua-language-server's loose check (.luarc.json, the whole repository);
-- of its strict one (.luarc.strict.json, lua/), those in the layers built
-- so far; and in those layers, a function on a module or a class with no
-- annotations at all, which lua-language-server lets pass.
--
--   nvim --clean -l tests/lint.lua <loose.json> <strict.json>
--
-- Run from the repository's root.

local L = require 'tests.layers'

local root = vim.uv.cwd() .. '/'
local found = {}

---@param rel string
---@param line integer  1-based
---@param col integer   1-based
---@param code string
---@param message string
local function report(rel, line, col, code, message)
  found[string.format('%s:%d:%d [%s] %s', rel, line, col, code, message)] = true
end

--- A check's results, file -> problems. lua-language-server writes no
--- file when it finds nothing.
---@param path string
---@return table<string, table[]>
local function results(path)
  local fd = io.open(path, 'r')
  if not fd then
    return {}
  end
  local out = vim.json.decode(fd:read '*a')
  fd:close()
  return out
end

---@param path string
---@param only_built boolean
local function take(path, only_built)
  for uri, problems in pairs(results(path)) do
    local rel = vim.uri_to_fname(uri):sub(#root + 1)
    if not only_built or L.is_built(rel) then
      for _, p in ipairs(problems) do
        local at = p.range.start
        report(rel, at.line + 1, at.character + 1, p.code, (p.message:gsub('\n.*', '')))
      end
    end
  end
end

--- Whether a function's own body returns a value: a nested function's
--- returns are its own.
---@param node TSNode
---@return boolean
local function returns_value(node)
  for child in node:iter_children() do
    local kind = child:type()
    if kind == 'return_statement' and child:named_child_count() > 0 then
      return true
    elseif kind ~= 'function_declaration' and kind ~= 'function_definition' and returns_value(child) then
      return true
    end
  end
  return false
end

--- Functions on a module or a class (`function M.x`, `function C:x`) at
--- the top of a file that take or return something with no annotation
--- above them saying what.
---@param rel string
local function unannotated(rel)
  local lines = vim.fn.readfile(rel)
  local source = table.concat(lines, '\n')
  local tree = vim.treesitter.get_string_parser(source, 'lua'):parse()[1]
  for node in tree:root():iter_children() do
    local name = node:type() == 'function_declaration' and node:field('name')[1]
    local kind = name and name:type()
    if kind == 'dot_index_expression' or kind == 'method_index_expression' then
      local row = node:start()
      local doc = row > 0 and lines[row]:match '^%-%-%-@' ~= nil
      local k = row
      while not doc and k > 0 and lines[k]:match '^%-%-%-' do
        doc = lines[k]:match '^%-%-%-@' ~= nil
        k = k - 1
      end
      local params = node:field('parameters')[1]
      local takes = params and params:named_child_count() > 0
      local body = node:field('body')[1]
      if not doc and (takes or (body and returns_value(body))) then
        local what = vim.treesitter.get_node_text(name, source)
        report(rel, row + 1, 1, 'missing-doc', what .. ' has no @param or @return')
      end
    end
  end
end

take(arg[1], false)
take(arg[2], true)
for _, rel in ipairs(vim.fn.globpath('.', 'lua/**/*.lua', false, true)) do
  rel = rel:gsub('^%./', '')
  if L.is_built(rel) then
    unannotated(rel)
  end
end

local lines = vim.tbl_keys(found)
table.sort(lines)
for _, line in ipairs(lines) do
  io.stdout:write(line .. '\n')
end
if #lines > 0 then
  io.stdout:write(string.format('lint: %d problem%s\n', #lines, #lines == 1 and '' or 's'))
  os.exit(1)
end
