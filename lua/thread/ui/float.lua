--- The floats screens are drawn in: a scratch buffer in a bordered window,
--- with its own keys, sized to the editor, and gone when you leave it if
--- the screen says so.

local M = {}

---@class thread.FloatOpts
---@field win table  for nvim_open_win; `relative`, `border` and `style` default to editor, rounded, minimal
---@field enter boolean|nil  focus it (default true)
---@field filetype string|nil
---@field wo table<string, any>|nil  window options
---@field keys table<string, fun()>|nil  normal-mode keys in it
---@field on_leave fun()|nil  the cursor went to another window

---@param o thread.FloatOpts
---@return integer win, integer buf
function M.open(o)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  if o.filetype then
    vim.bo[buf].filetype = o.filetype
  end
  local cfg = vim.tbl_extend('keep', o.win, { relative = 'editor', border = 'rounded', style = 'minimal', row = 0, col = 0, width = 1, height = 1 })
  local win = vim.api.nvim_open_win(buf, o.enter ~= false, cfg)
  for k, v in pairs(o.wo or {}) do
    vim.wo[win][k] = v
  end
  for lhs, fn in pairs(o.keys or {}) do
    vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true })
  end
  if o.on_leave then
    vim.api.nvim_create_autocmd('WinLeave', {
      buffer = buf,
      callback = function()
        vim.schedule(o.on_leave)
      end,
    })
  end
  return win, buf
end

--- The rows a float may take: the editor's, less the command line and a
--- border.
---@param margin integer|nil  rows to leave besides
function M.max_height(margin)
  return math.max(1, vim.o.lines - vim.o.cmdheight - 2 - (margin or 0))
end

--- Where a float `width` by `height` sits in the middle of the editor, its
--- height cut to what fits.
---@return { relative: string, row: integer, col: integer, width: integer, height: integer }
function M.centred(width, height)
  height = math.max(1, math.min(height, M.max_height()))
  return {
    relative = 'editor',
    row = math.max(0, math.floor((vim.o.lines - vim.o.cmdheight - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = height,
  }
end

--- The whole editor, inside a border.
function M.full()
  return { relative = 'editor', row = 0, col = 0, width = vim.o.columns - 2, height = math.max(5, M.max_height(1)) }
end

---@param win integer|nil
function M.close(win)
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

return M
