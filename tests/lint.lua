-- What lua-language-server found, for make lint: every problem of the
-- loose check (.luarc.json, the whole repository), and of the strict one
-- (.luarc.strict.json, lua/) those in the layers built so far.
--
--   nvim --clean -l tests/lint.lua <loose.json> <strict.json>

local L = dofile(vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h') .. '/layers.lua')

local root = vim.uv.cwd() .. '/'

-- The files of the layers built so far: a folder, or a file of its own.
local strict = {}
for i = 1, L.built do
  for _, m in ipairs(L.layers[i]) do
    strict[#strict + 1] = 'lua/' .. m:gsub('%.', '/')
  end
end

local function is_strict(rel)
  for _, p in ipairs(strict) do
    if rel == p .. '.lua' or vim.startswith(rel, p .. '/') then
      return true
    end
  end
  return false
end

--- A check's results, file -> problems. lua-language-server writes no
--- file when it finds nothing.
local function results(path)
  local fd = io.open(path, 'r')
  if not fd then
    return {}
  end
  local out = vim.json.decode(fd:read '*a')
  fd:close()
  return out
end

local found = {}
local function take(path, only_strict)
  for uri, problems in pairs(results(path)) do
    local rel = vim.uri_to_fname(uri):sub(#root + 1)
    if not only_strict or is_strict(rel) then
      for _, p in ipairs(problems) do
        local at = p.range.start
        local line = string.format('%s:%d:%d [%s] %s', rel, at.line + 1, at.character + 1, p.code, (p.message:gsub('\n.*', '')))
        found[line] = true
      end
    end
  end
end
take(arg[1], false)
take(arg[2], true)

local lines = vim.tbl_keys(found)
table.sort(lines)
for _, line in ipairs(lines) do
  io.stdout:write(line .. '\n')
end
if #lines > 0 then
  io.stdout:write(string.format('lint: %d problem%s\n', #lines, #lines == 1 and '' or 's'))
  os.exit(1)
end
