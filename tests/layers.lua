-- The layers, bottom first (CODING_STANDARDS.md): each requires only
-- itself and the layers below it, and names no type declared above it. The
-- rebuild goes bottom-up, and `built` is how far it has got: the layers up
-- to it are held to those rules (independence_spec) and to every check
-- lua-language-server has (make lint). Above it is today's code, held to
-- neither.

local L = {}

L.built = 'store'

L.layers = {
  { name = 'base', 'thread.base', 'thread.config' },
  { name = 'ui', 'thread.ui' },
  { name = 'store', 'thread.store' },
  { name = 'model', 'thread.model' },
  { name = 'prose', 'thread.prose' },
  { name = 'draw', 'thread.draw' },
  { name = 'actions', 'thread.actions' },
  -- They open each other through thread.go, never directly.
  { name = 'surfaces', 'thread.go', 'thread.screen', 'thread.code', 'thread.walk', 'thread.focus', 'thread.page', 'thread.map', 'thread.compose' },
  { name = 'init', 'thread' },
}

--- A layer's place, bottom first, by its name.
---@param name string
---@return integer
function L.index(name)
  for i, layer in ipairs(L.layers) do
    if layer.name == name then
      return i
    end
  end
  error('no layer ' .. name)
end

--- The layer a module is in, and which entry of it: its folder or file.
---@param module string  `thread.base.anchor`
---@return integer|nil index, string|nil entry
function L.of_module(module)
  for i, layer in ipairs(L.layers) do
    for _, entry in ipairs(layer) do
      if module == entry or (entry ~= 'thread' and vim.startswith(module, entry .. '.')) then
        return i, entry
      end
    end
  end
end

--- The module a file is, from its path in the repository.
---@param rel string  `lua/thread/base/anchor.lua`
---@return string|nil
function L.module_of(rel)
  if not rel:match '^lua/.*%.lua$' then
    return nil
  end
  return (rel:gsub('^lua/', ''):gsub('%.lua$', ''):gsub('/init$', ''):gsub('/', '.'))
end

--- The layer a file is in, and which entry of it.
---@param rel string  `lua/thread/base/anchor.lua`
---@return integer|nil index, string|nil entry
function L.of_path(rel)
  local module = L.module_of(rel)
  if module then
    return L.of_module(module)
  end
end

--- Whether a file is in a layer the rebuild has built.
---@param rel string
---@return boolean
function L.is_built(rel)
  local i = L.of_path(rel)
  return i ~= nil and i <= L.index(L.built)
end

return L
