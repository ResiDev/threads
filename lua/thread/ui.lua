--- A list in a float, for the batches menu: lines with highlights, an
--- item behind each line, keys, and a redraw that keeps the cursor on the
--- same item.

local M = {}

local ns = vim.api.nvim_create_namespace 'thread.list'

---@class thread.List
---@field win integer
---@field buf integer
---@field items table<integer, any>  line -> item
---@field render fun(): { lines: string[], hls: table[], items: table<integer, any>, title: string }

---@param opts { render: fun(): table, footer: string, keys: table<string, fun(list: thread.List, item: any)> }
---@return thread.List
function M.open(opts)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  local width = math.min(110, vim.o.columns - 8)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    row = 2,
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = 3,
    border = 'rounded',
    style = 'minimal',
    footer = ' ' .. opts.footer .. ' ',
    footer_pos = 'right',
  })
  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false
  local list = { win = win, buf = buf, items = {}, render = opts.render }

  function list.is_open()
    return vim.api.nvim_win_is_valid(list.win)
  end

  function list.close()
    if vim.api.nvim_win_is_valid(list.win) then
      vim.api.nvim_win_close(list.win, true)
    end
  end

  function list.item()
    return list.items[vim.api.nvim_win_get_cursor(list.win)[1]]
  end

  function list.redraw()
    if not list.is_open() then
      return
    end
    local keep = list.item()
    local r = list.render()
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, r.lines)
    vim.bo[buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for _, h in ipairs(r.hls) do
      local len = #(r.lines[h[1] + 1] or '')
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, h[1], math.min(h[2], len), {
        end_col = (h[3] < 0 or h[3] > len) and len or h[3],
        hl_group = h[4],
      })
    end
    list.items = r.items
    local height = math.max(3, math.min(#r.lines, vim.o.lines - 8))
    vim.api.nvim_win_set_config(list.win, { height = height, title = ' ' .. r.title .. ' ', title_pos = 'left' })
    -- Stay on the same item; else the first line that has one.
    local target
    for lnum, item in pairs(list.items) do
      if keep and (item == keep or (type(item) == 'table' and item.id ~= nil and item.id == keep.id)) then
        target = lnum
      end
    end
    if not target then
      local cur = vim.api.nvim_win_get_cursor(list.win)[1]
      if list.items[cur] then
        return
      end
      for lnum = 1, #r.lines do
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

  for lhs, fn in pairs(opts.keys) do
    vim.keymap.set('n', lhs, function()
      fn(list, list.item())
    end, { buffer = buf, nowait = true })
  end
  vim.keymap.set('n', 'q', list.close, { buffer = buf, nowait = true })
  vim.keymap.set('n', '<Esc>', list.close, { buffer = buf, nowait = true })
  vim.api.nvim_create_autocmd('WinLeave', {
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(list.close)
    end,
  })
  list.redraw()
  return list
end

return M
