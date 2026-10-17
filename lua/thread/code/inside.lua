--- A card gone into: a float laid over the rows it hangs in above its
--- line, drawn the same but for the keys on its bottom edge, with a cursor
--- in it. `w` and `b` go between its links and the names it puts in
--- backticks, ⏎ follows the one under the cursor, `q` or `Esc` comes back
--- out to the code where you were. Leaving it, the walk moving on, or what
--- it is drawn from changing, closes it.

local draw = require 'thread.draw'
local float = require 'thread.ui.float'
local go = require 'thread.go'
local text = require 'thread.base.text'

local M = {}

local ns = vim.api.nvim_create_namespace 'thread.inside'

-- What ⏎ follows: what goes somewhere, not the step or a message itself.
local FOLLOWS = { link = true, name = true, excerpt = true, diagram = true, note = true, chunk = true, line = true, change = true }

---@class thread.Inside
---@field win integer   the float
---@field code integer  the window it lies over
---@field review thread.Review
---@field parts thread.Part[]  in the float's rows and byte columns
---@field group integer

local I ---@type thread.Inside|nil

--- Close it; `back`, the cursor to the code it lay over.
---@param back boolean|nil
function M.close(back)
  local i = I
  I = nil
  if not i then
    return
  end
  pcall(vim.api.nvim_del_augroup_by_id, i.group)
  if vim.api.nvim_win_is_valid(i.win) then
    vim.api.nvim_win_close(i.win, true)
  end
  if back and vim.api.nvim_win_is_valid(i.code) then
    vim.api.nvim_set_current_win(i.code)
  end
end

--- Where on screen the `n` rows above `line` are, the window scrolled
--- to show them whole first when they are not; cut to the window when
--- the card is taller than it.
---@param win integer
---@param line integer
---@param n integer
---@return { row: integer, col: integer, height: integer, width: integer }  editor rows and columns, 0-based
local function where(win, line, n)
  local info = vim.fn.getwininfo(win)[1]
  local first = info.winrow + info.winbar -- the window's first row of text, 1-based
  local last = info.winrow + info.height - 1
  local function top()
    local at = vim.fn.screenpos(win, line, 1).row
    return at > 0 and at - n or nil
  end
  local row = top()
  if not row or row < first then
    vim.api.nvim_win_call(win, function()
      vim.fn.winrestview { topline = line, topfill = n }
    end)
    vim.cmd.redraw()
    row = top() or first
  end
  row = math.max(row, first)
  return { row = row - 1, col = info.wincol - 1 + info.textoff, height = math.max(1, math.min(n, last - row + 1)), width = info.width - info.textoff }
end

--- The cursor to the next or previous link, `count` times.
---@param d 1|-1
function M.link(d)
  local i = assert(I)
  local cur = vim.api.nvim_win_get_cursor(i.win)
  local to = draw.link(i.parts, cur[1] - 1, cur[2], d, vim.v.count1)
  if to then
    vim.api.nvim_win_set_cursor(i.win, { to.first + 1, assert(to.s) })
  end
end

--- Follow what is under the cursor, coming out of the card to it.
local function follow()
  local i = assert(I)
  local cur = vim.api.nvim_win_get_cursor(i.win)
  local row, col = cur[1] - 1, cur[2]
  local part = draw.at(i.parts, row, col)
  if not (part and FOLLOWS[part.kind]) then
    return
  end
  local r = part.review or i.review
  M.close(true)
  local ok, why = go.press(r, part, row, col, 'code')
  if not ok and why then
    vim.notify('thread: ' .. why)
  end
end

---@class thread.InsideOpts
---@field win integer  the code window the card hangs in
---@field line integer  the line it hangs above
---@field review thread.Review
---@field lines thread.VirtChunk[][]  its rows, as paint.inside draws them
---@field parts thread.Part[]
---@field link boolean|nil  the cursor on its first link, rather than at its top
---@field keys table<string, fun()>|nil  more keys in it

--- Go into a card.
---@param o thread.InsideOpts
function M.open(o)
  M.close()
  local at = where(o.win, o.line, #o.lines)
  local rows, widest = {}, 0 ---@type string[], integer
  for _, chunks in ipairs(o.lines) do
    local line = ''
    for _, c in ipairs(chunks) do
      line = line .. c[1]
    end
    rows[#rows + 1] = line
    widest = math.max(widest, text.width(line))
  end
  local keys = {
    w = function()
      M.link(1)
    end,
    b = function()
      M.link(-1)
    end,
    ['<CR>'] = follow,
    q = function()
      M.close(true)
    end,
    ['<Esc>'] = function()
      M.close(true)
    end,
  }
  for lhs, fn in pairs(o.keys or {}) do
    keys[lhs] = fn
  end
  local win, buf = float.open {
    win = { row = at.row, col = at.col, width = math.min(widest, at.width), height = at.height, border = 'none', zindex = 40 },
    wo = { winhighlight = 'NormalFloat:Normal', wrap = false, cursorline = false, sidescrolloff = 0, scrolloff = 0 },
    keys = keys,
    on_leave = function()
      if I and vim.api.nvim_get_current_win() ~= I.win then
        M.close()
      end
    end,
  }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, rows)
  -- Each chunk's colours, the last of a stack on top.
  for row, chunks in ipairs(o.lines) do
    local col = 0
    for _, c in ipairs(chunks) do
      local hl = c[2]
      local groups = type(hl) == 'table' and hl or { hl }
      for n, group in ipairs(groups) do
        if #c[1] > 0 then
          vim.api.nvim_buf_set_extmark(buf, ns, row - 1, col, { end_col = col + #c[1], hl_group = group, priority = 100 + n })
        end
      end
      col = col + #c[1]
    end
  end
  vim.bo[buf].modifiable = false
  local group = vim.api.nvim_create_augroup('thread.inside', { clear = true })
  I = { win = win, code = o.win, review = o.review, parts = o.parts, group = group }
  -- The walk moving on, or what the card is drawn from changing, leaves
  -- it out of date.
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = { 'ThreadWalk', 'ThreadChanged' },
    callback = function()
      M.close()
    end,
  })
  local to = o.link and draw.link(o.parts, 0, -1, 1, 1)
  if to then
    vim.api.nvim_win_set_cursor(win, { to.first + 1, assert(to.s) })
    return
  end
  -- At its top: the first row with something written in it.
  for _, q in ipairs(o.parts) do
    local line = rows[q.first + 1] or ''
    local _, _, start = line:find '^%s*│%s*()%S'
    if start then
      vim.api.nvim_win_set_cursor(win, { q.first + 1, start - 1 })
      return
    end
  end
end

return M
