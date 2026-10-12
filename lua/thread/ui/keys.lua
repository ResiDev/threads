--- Keys thread.nvim lays over yours, and gives back.

local M = {}

--- The global normal-mode mapping of `lhs`, as maparg() gives it, ignoring
--- any mapping the current buffer has of its own.
---@param lhs string
---@return table|nil
function M.global(lhs)
  local want = vim.keycode(lhs)
  for _, m in ipairs(vim.api.nvim_get_keymap 'n') do
    if vim.keycode(m.lhs) == want then
      return m
    end
  end
end

---@class thread.Overlay
---@field cover fun(buf: integer)  give a buffer the keys too
---@field restore fun()            put every key back as it was

--- Keys laid over the editor's for a while: set globally, and on any
--- buffer `cover` is given, since a buffer's own mapping wins over a global
--- one (the snacks dashboard's `L` opens Lazy). `restore` puts back the
--- mapping each key had, global or the buffer's.
---@param list { lhs: string, fn: fun(), desc: string }[]
---@return thread.Overlay
function M.overlay(list)
  local saved, bufs = {}, {}
  for _, k in ipairs(list) do
    saved[k.lhs] = M.global(k.lhs) or false
    vim.keymap.set('n', k.lhs, k.fn, { desc = k.desc })
  end
  local O = {}
  function O.cover(buf)
    if bufs[buf] or not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    bufs[buf] = {}
    for _, k in ipairs(list) do
      local old = vim.api.nvim_buf_call(buf, function()
        return vim.fn.maparg(k.lhs, 'n', false, true)
      end)
      bufs[buf][k.lhs] = (old and old.lhs and old.buffer == 1) and old or false
      vim.keymap.set('n', k.lhs, k.fn, { buffer = buf, desc = k.desc })
    end
  end
  function O.restore()
    for lhs, old in pairs(saved) do
      pcall(vim.keymap.del, 'n', lhs)
      if old then
        pcall(vim.fn.mapset, 'n', false, old)
      end
    end
    for buf, keys in pairs(bufs) do
      for lhs, old in pairs(vim.api.nvim_buf_is_valid(buf) and keys or {}) do
        pcall(vim.keymap.del, 'n', lhs, { buffer = buf })
        if old then
          vim.api.nvim_buf_call(buf, function()
            pcall(vim.fn.mapset, 'n', false, old)
          end)
        end
      end
    end
    saved, bufs = {}, {}
  end
  return O
end

-- lhs -> the mapping a zone key had before ours, kept across setup calls.
local before = {}

--- A key that acts on the thread the cursor is on (`here()` says whether
--- it is on one) and anywhere else does what it did before: what another
--- plugin mapped it to, else its own meaning.
---@param lhs string
---@param fn fun()
---@param desc string  starts `Thread: `, which is how a later setup knows it
---@param here fun(): boolean
function M.zone(lhs, fn, desc, here)
  local old = M.global(lhs)
  if old and (old.desc or ''):find '^Thread: ' then
    old = before[lhs]
  end
  before[lhs] = old
  local function fallback()
    if old and old.callback then
      if old.expr == 1 then
        return old.callback()
      end
      vim.schedule(old.callback)
      return ''
    elseif old and old.rhs and old.rhs ~= '' then
      return vim.keycode(old.rhs)
    end
    return vim.keycode(lhs)
  end
  vim.keymap.set('n', lhs, function()
    if not here() then
      return fallback()
    end
    vim.schedule(fn)
    return ''
  end, { expr = true, desc = desc })
end

return M
