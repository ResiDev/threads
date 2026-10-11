-- thread.nvim stands alone: it requires only its own modules and Neovim's.
-- The one exception is the optional CodeDiff adapter.

local R = require 'tests.runner'
local H = require 'tests.helpers'

-- File -> module prefixes it may require besides thread's and vim's.
local ALLOWED = {
  ['lua/thread/codediff.lua'] = { 'codediff.' },
  -- Reads which-key's table, if loaded, to keep it off Home. Kept by the
  -- owner's decision; it loads nothing.
  ['lua/thread/home.lua'] = { 'which-key.config' },
}

local function required(line)
  local out = {}
  for name in line:gmatch 'require%s*%(?%s*[\'"]([^\'"]+)[\'"]' do
    out[#out + 1] = name
  end
  for name in line:gmatch 'pcall%(%s*require%s*,%s*[\'"]([^\'"]+)[\'"]' do
    out[#out + 1] = name
  end
  for name in line:gmatch 'package%.loaded%[%s*[\'"]([^\'"]+)[\'"]' do
    out[#out + 1] = name
  end
  return out
end

R.test('thread.nvim requires no other plugin', function()
  for _, path in ipairs(vim.fn.globpath(H.root, 'lua/**/*.lua', false, true)) do
    local rel = path:sub(#H.root + 2)
    for n, line in ipairs(vim.fn.readfile(path)) do
      if not line:match '^%s*%-%-' then
        for _, name in ipairs(required(line)) do
          local fine = name == 'thread' or name:match '^thread%.' or name:match '^vim%.'
          for _, prefix in ipairs(ALLOWED[rel] or {}) do
            fine = fine or name:sub(1, #prefix) == prefix
          end
          R.ok(fine, string.format('%s:%d requires %s', rel, n, name))
        end
      end
    end
  end
end)
