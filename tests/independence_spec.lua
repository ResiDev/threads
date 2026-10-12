-- thread.nvim stands alone: it requires only its own modules and Neovim's.
-- The one exception is the optional CodeDiff adapter.

local R = require 'tests.runner'
local H = require 'tests.helpers'

-- File -> module prefixes it may require besides thread's and vim's.
local ALLOWED = {
  ['lua/thread/base/codediff.lua'] = { 'codediff.' },
  -- Reads which-key's table, if loaded, to keep it off Home. Kept by the
  -- owner's decision; it loads nothing.
  ['lua/thread/home/init.lua'] = { 'which-key.config' },
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

-- The layers, bottom first (CODING_STANDARDS.md): each requires only
-- itself and the layers below it. The rebuild goes bottom-up, so the
-- layers up to BUILT are checked; above it is today's code, which nothing
-- here asks anything of.
local LAYERS = {
  { 'thread.base', 'thread.config' },
  { 'thread.ui' },
  { 'thread.store' },
  { 'thread.model' },
  { 'thread.prose' },
  { 'thread.draw' },
  { 'thread.actions' },
  { 'thread.go', 'thread.screen', 'thread.code', 'thread.walk', 'thread.focus', 'thread.page', 'thread.map', 'thread.compose' },
  { 'thread' },
}
local BUILT = 2
local SURFACES = 8

-- The layer a module is in, and which entry of it: its folder or file.
local function layer_of(name)
  for i, layer in ipairs(LAYERS) do
    for _, m in ipairs(layer) do
      if name == m or (m ~= 'thread' and vim.startswith(name, m .. '.')) then
        return i, m
      end
    end
  end
end

local function module_of(rel)
  return (rel:gsub('^lua/', ''):gsub('%.lua$', ''):gsub('/init$', ''):gsub('/', '.'))
end

R.test('each layer requires only the layers below it', function()
  local bad = {}
  for _, path in ipairs(vim.fn.globpath(H.root, 'lua/**/*.lua', false, true)) do
    local rel = path:sub(#H.root + 2)
    local at, unit = layer_of(module_of(rel))
    if at and at <= BUILT then
      for n, line in ipairs(vim.fn.readfile(path)) do
        if not line:match '^%s*%-%-' then
          for _, name in ipairs(required(line)) do
            if name == 'thread' or name:match '^thread%.' then
              local to, its = layer_of(name)
              local where = string.format('%s:%d requires %s', rel, n, name)
              if not to then
                bad[#bad + 1] = where .. ', which is in no layer'
              elseif to > at then
                bad[#bad + 1] = where .. ', a layer above it'
              elseif at == SURFACES and to == SURFACES and its ~= unit and its ~= 'thread.go' then
                -- Surfaces reach each other through go, never directly.
                bad[#bad + 1] = where .. ': surfaces open each other through go'
              end
            end
          end
        end
      end
    end
  end
  R.ok(#bad == 0, '\n  ' .. table.concat(bad, '\n  '))
end)
