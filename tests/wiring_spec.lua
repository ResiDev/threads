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
    for name, field in src:gsub('<[^>]*>', '<>'):gmatch '([%w_]+)%.([%w_]+)' do
      if alias[name] then
        check(alias[name], field)
      end
    end
  end
  R.eq(vim.fn.uniq(vim.fn.sort(missing)), {})
end)
