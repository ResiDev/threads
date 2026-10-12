--- A list in a float, for the batches menu: a sheet whose rows each own an
--- item, keys that act on the item under the cursor, and a redraw that
--- keeps the cursor on the same item.

local float = require 'thread.ui.float'
local sheet = require 'thread.ui.sheet'

local M = {}

local ns = vim.api.nvim_create_namespace 'thread.list'

---@class thread.List
---@field win integer
---@field buf integer
---@field items table<integer, any>  line -> item

---@class thread.ListOpts
---@field render fun(P: thread.Sheet): string  draws the rows (P.own(item) before each), returns the title
---@field footer string
---@field keys table<string, fun(list: thread.List, item: any)>

---@param opts thread.ListOpts
---@return thread.List
function M.open(opts)
  local list = { items = {} }
  local keys = {}
  for lhs, fn in pairs(opts.keys) do
    keys[lhs] = function()
      fn(list, list.item())
    end
  end
  keys.q = function()
    list.close()
  end
  keys['<Esc>'] = keys.q
  local width = math.min(110, vim.o.columns - 8)
  list.win, list.buf = float.open {
    win = { row = 2, col = math.floor((vim.o.columns - width) / 2), width = width, height = 3, footer = ' ' .. opts.footer .. ' ', footer_pos = 'right' },
    wo = { cursorline = true, wrap = false },
    keys = keys,
    on_leave = function()
      list.close()
    end,
  }

  function list.is_open()
    return vim.api.nvim_win_is_valid(list.win)
  end

  function list.close()
    float.close(list.win)
  end

  function list.item()
    return list.items[vim.api.nvim_win_get_cursor(list.win)[1]]
  end

  function list.redraw()
    if not list.is_open() then
      return
    end
    local keep = list.item()
    local P = sheet.new()
    local title = opts.render(P)
    P.apply(list.buf, ns)
    list.items = P.owner
    vim.api.nvim_win_set_config(list.win, { height = math.max(3, math.min(#P.lines, vim.o.lines - 8)), title = ' ' .. title .. ' ', title_pos = 'left' })
    -- Stay on the same item; else the first line that has one.
    local target
    for lnum, item in pairs(list.items) do
      if keep and (item == keep or (type(item) == 'table' and item.id ~= nil and item.id == keep.id)) then
        target = lnum
      end
    end
    if not target then
      if list.item() then
        return
      end
      for lnum = 1, #P.lines do
        if list.items[lnum] then
          target = lnum
          break
        end
      end
    end
    if target then
      vim.api.nvim_win_set_cursor(list.win, { target, 0 })
    end
  end

  list.redraw()
  return list
end

return M
