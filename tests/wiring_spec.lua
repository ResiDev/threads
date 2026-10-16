-- Every function one module calls on another is there: a module that moves
-- or splits keeps every name its callers use.

local R = require 'tests.runner'
local H = require 'tests.helpers'

R.test('every module.field a file uses exists', function()
  local missing = {}
  local files = vim.fn.globpath(H.root, 'lua/**/*.lua', false, true)
  vim.list_extend(files, vim.fn.globpath(H.root, 'skills/**/*.lua', false, true))
  vim.list_extend(files, vim.fn.globpath(H.root, 'tests/*.lua', false, true))
  for _, path in ipairs(files) do
    local alias, code = {}, {}
    for _, l in ipairs(vim.fn.readfile(path)) do
      local name, mod = l:match "^local ([%w_]+) = require '(thread[%w%.]*)'"
      if name then
        alias[name] = mod
      end
      -- Strings and comments say names that are not calls.
      code[#code + 1] = l:gsub("require%('(thread[%w%.]*)'%)", '<%1>'):gsub("'[^']*'", "''"):gsub('"[^"]*"', '""'):gsub('%-%-.*$', '')
    end
    local src = table.concat(code, '\n')
    local function check(mod, field)
      local ok, m = pcall(require, mod)
      if ok and type(m) == 'table' and m[field] == nil then
        missing[#missing + 1] = string.format('%s uses %s.%s', vim.fs.basename(path), mod, field)
      end
    end
    for mod, field in src:gmatch '<(thread[%w%.]*)>%.([%w_]+)' do
      check(mod, field)
    end
    -- `x.chunk.line` is a field of x, not the chunk module's.
    for dot, name, field in src:gsub('<[^>]*>', '<>'):gmatch '(%.?)([%w_]+)%.([%w_]+)' do
      if dot == '' and alias[name] then
        check(alias[name], field)
      end
    end
  end
  R.eq(vim.fn.uniq(vim.fn.sort(missing)), {})
end)

-- A require run only on one path, `require('thread.walk')` in a key, fails
-- only when that path does; a spec that requires one fails as it loads.
R.test('every thread module the plugin and the skill require exists', function()
  local missing = {}
  local files = vim.fn.globpath(H.root, 'lua/**/*.lua', false, true)
  vim.list_extend(files, vim.fn.globpath(H.root, 'skills/**/*.lua', false, true))
  vim.list_extend(files, vim.fn.globpath(H.root, 'plugin/*.lua', false, true))
  for _, path in ipairs(files) do
    local src = table.concat(vim.fn.readfile(path), '\n')
    for mod in src:gmatch "require%s*%(?%s*'(thread[%w_%.]*)'" do
      local file = H.root .. '/lua/' .. mod:gsub('%.', '/')
      if not (vim.uv.fs_stat(file .. '.lua') or vim.uv.fs_stat(file .. '/init.lua')) then
        missing[#missing + 1] = string.format('%s requires %s', path:sub(#H.root + 2), mod)
      end
    end
  end
  R.eq(vim.fn.uniq(vim.fn.sort(missing)), {})
end)
