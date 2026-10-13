-- thread.nvim stands alone: it requires only its own modules and Neovim's.
-- The one exception is the optional CodeDiff adapter. And inside it, the
-- layers built so far hold (tests/layers.lua).

local R = require 'tests.runner'
local H = require 'tests.helpers'
local L = require 'tests.layers'

-- File -> module prefixes it may require besides thread's and vim's.
local ALLOWED = {
  ['lua/thread/base/codediff.lua'] = { 'codediff.' },
  -- Reads which-key's table, if loaded, to keep it off Home. Kept by the
  -- owner's decision; it loads nothing.
  ['lua/thread/legacy/home/init.lua'] = { 'which-key.config' },
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
  local paths = vim.fn.globpath(H.root, 'lua/**/*.lua', false, true)
  vim.list_extend(paths, vim.fn.globpath(H.root, 'skills/**/*.lua', false, true))
  for _, path in ipairs(paths) do
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

-- Every Lua file of the plugin, with its path in the repository.
local function files()
  local out = {}
  for _, path in ipairs(vim.fn.globpath(H.root, 'lua/**/*.lua', false, true)) do
    out[#out + 1] = { path = path, rel = path:sub(#H.root + 2) }
  end
  return out
end

local BUILT = L.index(L.built)
local SURFACES = L.index 'surfaces'

R.test('each layer requires only the layers below it', function()
  local bad = {}
  for _, f in ipairs(files()) do
    local at, unit = L.of_path(f.rel)
    if at and at <= BUILT then
      for n, line in ipairs(vim.fn.readfile(f.path)) do
        if not line:match '^%s*%-%-' then
          for _, name in ipairs(required(line)) do
            if name == 'thread' or name:match '^thread%.' then
              local to, its = L.of_module(name)
              local where = string.format('%s:%d requires %s', f.rel, n, name)
              if not to then
                bad[#bad + 1] = where .. ', which is in no layer'
              elseif to > at then
                bad[#bad + 1] = where .. ', a layer above it'
              elseif at == SURFACES and to == SURFACES and its ~= unit and its ~= 'thread.go' then
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

-- The types a line declares: a ---@class's or ---@alias's name.
local function declared(line)
  return line:match '^%s*%-%-%-@class%s+%b()%s*([%w_.]+)' or line:match '^%s*%-%-%-@class%s+([%w_.]+)' or line:match '^%s*%-%-%-@alias%s+([%w_.]+)'
end

-- The names a line uses as types: in an annotation (less a parameter's or
-- field's own name, or a class's), and in an inline `--[[@as T]]`. Only
-- dotted names: every type of thread.nvim's is one, and Lua's are not.
local TAGS = { param = true, field = true, ['return'] = true, type = true, cast = true, class = true, alias = true }
local function used(line)
  local text = {}
  for t in line:gmatch '%-%-%[%[@as%s+(.-)%]%]' do
    text[#text + 1] = t
  end
  local tag, rest = line:match '^%s*%-%-%-@(%a+)%s+(.*)$'
  if TAGS[tag] then
    if tag == 'param' or tag == 'field' or tag == 'cast' then
      rest = rest:gsub('^[%w_.]+%??%s*', '', 1)
    elseif tag == 'class' or tag == 'alias' then
      rest = rest:gsub('^%b()%s*', '', 1):gsub('^[%w_.]+', '', 1)
    end
    text[#text + 1] = rest
  end
  local out = {}
  for name in table.concat(text, ' '):gmatch '[%a_][%w_]*%.[%w_.]*[%w_]' do
    out[#out + 1] = name
  end
  return out
end

R.test('each layer names only the types of the layers below it', function()
  -- Type -> the layer of the file declaring it; false for a file in none.
  local owner = {}
  local all = files()
  for _, f in ipairs(all) do
    f.lines = vim.fn.readfile(f.path)
    local at = L.of_path(f.rel)
    for _, line in ipairs(f.lines) do
      local name = declared(line)
      if name then
        owner[name] = at or false
      end
    end
  end
  local bad = {}
  for _, f in ipairs(all) do
    local at = L.of_path(f.rel)
    if at and at <= BUILT then
      for n, line in ipairs(f.lines) do
        for _, name in ipairs(used(line)) do
          local its = owner[name]
          local where = string.format('%s:%d names %s', f.rel, n, name)
          if its == false then
            bad[#bad + 1] = where .. ', declared in no layer'
          elseif its and its > at then
            bad[#bad + 1] = where .. ', declared a layer above it'
          end
        end
      end
    end
  end
  R.ok(#bad == 0, '\n  ' .. table.concat(bad, '\n  '))
end)

-- The skill reads reviews as the model does, and draws nothing: what it
-- says waits is what the editor says waits.
R.test("the skill's scripts require only base/, store/ and model/", function()
  local may = { [L.index 'base'] = true, [L.index 'store'] = true, [L.index 'model'] = true }
  local bad = {}
  for _, path in ipairs(vim.fn.globpath(H.root, 'skills/**/*.lua', false, true)) do
    local rel = path:sub(#H.root + 2)
    for n, line in ipairs(vim.fn.readfile(path)) do
      if not line:match '^%s*%-%-' then
        for _, name in ipairs(required(line)) do
          if (name == 'thread' or name:match '^thread%.') and not may[L.of_module(name) or 0] then
            bad[#bad + 1] = string.format('%s:%d requires %s', rel, n, name)
          end
        end
      end
    end
  end
  R.ok(#bad == 0, '\n  ' .. table.concat(bad, '\n  '))
end)
