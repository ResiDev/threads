--- A card gone into: a float laid over the rows it hangs in above its
--- line, drawn the same but for the keys on its bottom edge, with a cursor
--- in it, drawn whole. `j` and `k` go between its text, its messages and
--- the notes on its chunk, the one the cursor is in lit; `w` and `b`
--- between its links and the names it puts in backticks, ⏎ follows the
--- one under the cursor, `q` or `Esc` comes back
--- out to the code where you were; `r`, `e` and `d`, given by the code,
--- reply, edit and delete in the card. Leaving it, the walk moving on, or what
--- it is drawn from changing, closes it.

local conversation = require 'thread.model.conversation'
local draw = require 'thread.draw'
local float = require 'thread.ui.float'
local go = require 'thread.go'
local text = require 'thread.base.text'

local M = {}

local ns = vim.api.nvim_create_namespace 'thread.inside'
local ns_item = vim.api.nvim_create_namespace 'thread.inside.item'

-- What ⏎ follows: what goes somewhere, not the step or a message itself.
local FOLLOWS = { link = true, name = true, excerpt = true, diagram = true, note = true, chunk = true, line = true, change = true }

---@class thread.Inside
---@field win integer   the float
---@field code integer  the window it lies over
---@field review thread.Review
---@field parts thread.Part[]  in the float's rows and byte columns
---@field group integer
---@field on_close fun()|nil
---@field keys { row: integer, chunks: thread.VirtChunk[][] }|nil  its row of keys, 0-based, as it is off and on a message of yours
---@field yours boolean  which of the two it shows

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
  if i.on_close then
    i.on_close()
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

--- The part under the cursor in it, while it is open.
---@return thread.Part|nil
function M.here()
  local i = I
  if not (i and vim.api.nvim_win_is_valid(i.win)) then
    return nil
  end
  local cur = vim.api.nvim_win_get_cursor(i.win)
  return draw.at(i.parts, cur[1] - 1, cur[2])
end

--- What j and k go between: its text, each message, each note on its
--- chunk; not the card itself, the first part.
---@param parts thread.Part[]
---@return thread.Part[]  by row, one a row
local function items(parts)
  local out, seen = {}, {} ---@type thread.Part[], table<integer, true>
  for n, p in ipairs(parts) do
    local item = p.kind == 'message' or (p.kind == 'note' and n > 1) or (p.kind == 'block' and p.name == 'prose')
    if item and not seen[p.first] then
      seen[p.first] = true
      out[#out + 1] = p
    end
  end
  table.sort(out, function(a, b)
    return a.first < b.first
  end)
  return out
end

--- The cursor on a row's first written column, past the frame's edge.
---@param win integer
---@param row integer  0-based
local function land(win, row)
  local buf = vim.api.nvim_win_get_buf(win)
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
  local _, _, start = line:find '^%s*│%s*()%S'
  vim.api.nvim_win_set_cursor(win, { row + 1, start and (start - 1) or 0 })
end

--- A row written into the float, in its colours, the last of a stack on top.
---@param buf integer
---@param row integer  0-based
---@param chunks thread.VirtChunk[]
local function put(buf, row, chunks)
  local col = 0
  for _, c in ipairs(chunks) do
    local hl = c[2]
    local groups = type(hl) == 'table' and hl or { hl }
    for n, group in ipairs(groups) do
      if #c[1] > 0 then
        vim.api.nvim_buf_set_extmark(buf, ns, row, col, { end_col = col + #c[1], hl_group = group, priority = 100 + n })
      end
    end
    col = col + #c[1]
  end
end

---@param chunks thread.VirtChunk[]
---@return string
local function joined(chunks)
  local line = ''
  for _, c in ipairs(chunks) do
    line = line .. c[1]
  end
  return line
end

--- Its keys saying e and d only while the cursor is on a message of
--- yours you can edit or delete.
local function keys_here()
  local i = I
  if not (i and i.keys and vim.api.nvim_win_is_valid(i.win)) then
    return
  end
  local p = M.here()
  local yours = p ~= nil and p.conversation ~= nil and p.message ~= nil and conversation.editable(p.conversation, p.message)
  if yours == i.yours then
    return
  end
  i.yours = yours
  local buf = vim.api.nvim_win_get_buf(i.win)
  local row = i.keys.row
  local chunks = i.keys.chunks[yours and 2 or 1]
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, row, row + 1, false, { joined(chunks) })
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns, row, row + 1)
  put(buf, row, chunks)
end

--- The item the cursor is in lit, as the screen lights the one it is on.
local function light()
  local i = I
  if not (i and vim.api.nvim_win_is_valid(i.win)) then
    return
  end
  local buf = vim.api.nvim_win_get_buf(i.win)
  vim.api.nvim_buf_clear_namespace(buf, ns_item, 0, -1)
  local row = vim.api.nvim_win_get_cursor(i.win)[1] - 1
  local list = items(i.parts)
  for n, p in ipairs(list) do
    local next_first = list[n + 1] and list[n + 1].first or math.huge
    if row >= p.first and row < next_first and row <= p.last then
      for r = p.first, p.last do
        vim.api.nvim_buf_set_extmark(buf, ns_item, r, 0, { line_hl_group = 'ThreadItem', priority = 50 })
      end
    end
  end
end

--- The cursor to the next or previous item, `count` times.
---@param d 1|-1
function M.item(d)
  local i = assert(I)
  local row = vim.api.nvim_win_get_cursor(i.win)[1] - 1
  local list = items(i.parts)
  local to ---@type thread.Part|nil
  for _ = 1, vim.v.count1 do
    local found = nil ---@type thread.Part|nil
    for n = d > 0 and 1 or #list, d > 0 and #list or 1, d do
      local p = list[n]
      if (d > 0 and p.first > row) or (d < 0 and p.first < row) then
        found = p
        break
      end
    end
    if not found then
      break
    end
    to, row = found, found.first
  end
  if to then
    land(i.win, to.first)
  end
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
---@field mine { row: integer, chunks: thread.VirtChunk[] }|nil  its row of keys while the cursor is on a message of yours, and which row it is, 0-based
---@field link boolean|nil  the cursor on its first link, rather than at its top
---@field keys table<string, fun()>|nil  more keys in it
---@field on_close fun()|nil  when it closes

--- Go into a card.
---@param o thread.InsideOpts
function M.open(o)
  M.close()
  local at = where(o.win, o.line, #o.lines)
  local rows, widest = {}, 0 ---@type string[], integer
  for _, chunks in ipairs(o.lines) do
    local line = joined(chunks)
    rows[#rows + 1] = line
    widest = math.max(widest, text.width(line))
  end
  local keys = {
    j = function()
      M.item(1)
    end,
    k = function()
      M.item(-1)
    end,
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
  -- The code's cursor stays on the card while you are in it.
  vim.w[win].thread_card = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, rows)
  for row, chunks in ipairs(o.lines) do
    put(buf, row - 1, chunks)
  end
  vim.bo[buf].modifiable = false
  local group = vim.api.nvim_create_augroup('thread.inside', { clear = true })
  I = { win = win, code = o.win, review = o.review, parts = o.parts, group = group, on_close = o.on_close, yours = false }
  if o.mine then
    I.keys = { row = o.mine.row, chunks = { o.lines[o.mine.row + 1], o.mine.chunks } }
  end
  vim.api.nvim_create_autocmd('CursorMoved', {
    group = group,
    buffer = buf,
    callback = function()
      light()
      keys_here()
    end,
  })
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
    light()
    keys_here()
    return
  end
  -- At its top: the first row with something written in it.
  for _, q in ipairs(o.parts) do
    local line = rows[q.first + 1] or ''
    local _, _, start = line:find '^%s*│%s*()%S'
    if start then
      vim.api.nvim_win_set_cursor(win, { q.first + 1, start - 1 })
      break
    end
  end
  light()
  keys_here()
end

return M
