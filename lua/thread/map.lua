--- The map, in the top right, opened with `<leader>hm` and never on its own.
--- Two kinds:
---
--- - **the batch**: every thread on a line, by file, with how many `]h` (or
---   `[h`) presses away each one where it is your move is.
--- - **the walk**: while walking, the thread the walk started from and every
---   thread in it, stages with their steps indented under them, `▸` where
---   you are.
---
--- A letter jumps to a thread; `q` closes it.

local anchor = require 'thread.anchor'
local render = require 'thread.render'
local store = require 'thread.store'
local tree = require 'thread.tree'

local M = {}

local ns = vim.api.nvim_create_namespace 'thread.map'
local LETTERS = 'abcdefgimoprstuvwxyz' -- not h, j, k, l, n, q: those move, open and close

local width_of = vim.fn.strdisplaywidth

---@class thread.MapEntry
---@field comment thread.Comment
---@field line integer|nil  where it is now; nil when its line is gone or it has none
---@field depth integer|nil in a walk, how deep under its head

---@class thread.MapState
---@field win integer
---@field buf integer
---@field pinned boolean
---@field mode 'batch'|'walk'
---@field entries thread.MapEntry[]
---@field rows table<integer, thread.MapEntry>  map line -> entry
---@field file string|nil   where you are, kept while you are in the map
---@field lnum integer|nil
---@field here integer|nil
local S

local function fit(s, w)
  if width_of(s) <= w then
    return s
  end
  local out = vim.fn.strcharpart(s, 0, w - 1)
  while width_of(out) > w - 1 do
    out = vim.fn.strcharpart(out, 0, vim.fn.strchars(out) - 1)
  end
  return out .. '…'
end

--- Your move: a draft to send or an answer to read.
function M.yours(comment)
  local s = store.status(comment)
  return s == 'draft' or s == 'answered'
end

local function line_of(files, c)
  if not store.anchored(c) then
    return nil
  end
  local key = (c.rev or '') .. ':' .. c.file
  if files[key] == nil then
    files[key] = anchor.lines_of(c) or false
  end
  local lines = files[key]
  local loc = lines and anchor.locate(c, lines)
  return loc and loc.line
end

--- Every thread on a line, with the line it is on now, by file then line.
--- Quiet tour steps are left out: they belong to their walk.
local function collect(batch)
  local out, files = {}, {}
  for _, c in ipairs(batch.data.threads) do
    if store.anchored(c) and (store.talked(c) or not tree.in_tour(batch, c.id)) then
      out[#out + 1] = { comment = c, line = line_of(files, c) }
    end
  end
  table.sort(out, function(a, b)
    if a.comment.file ~= b.comment.file then
      return a.comment.file < b.comment.file
    end
    return (a.line or math.huge) < (b.line or math.huge)
  end)
  return out
end

--- The walk going on: its head, then every thread in it.
local function collect_walk(batch)
  local w = require('thread.walk').state()
  local head = w and store.find(batch, w.head)
  if not head then
    return {}, nil
  end
  local out, files = {}, {}
  for _, item in ipairs(tree.walk(batch, head)) do
    out[#out + 1] = { comment = item.c, line = line_of(files, item.c), depth = item.depth }
  end
  return out, head
end

function M.close()
  if S and vim.api.nvim_win_is_valid(S.win) then
    vim.api.nvim_win_close(S.win, true)
  end
  pcall(vim.api.nvim_del_augroup_by_name, 'thread.map')
  S = nil
end

function M.is_open()
  return S ~= nil and vim.api.nvim_win_is_valid(S.win)
end

local function k(action)
  return render.key(action) or ''
end

--- Where you are, unless you are in the map itself.
local function find_here()
  if vim.api.nvim_get_current_win() == S.win then
    return
  end
  local where = anchor.of_buf(0)
  S.file = where and not where.rev and where.file or nil
  S.lnum = vim.api.nvim_win_get_cursor(0)[1]
  local placed = render.placed[vim.api.nvim_get_current_buf()]
  local h = S.file and placed and render.covering(placed, S.lnum) or {}
  S.here = h[1] and h[1].comment.id
end

local function draw_batch(batch, lines, hls)
  local file, lnum = S.file or '', S.lnum or 0
  local here = S.here
  -- ]h counts: your-move threads after where you are, [h those before,
  -- in the order ]h walks them: file, then line.
  local ahead, behind = {}, {}
  for _, e in ipairs(S.entries) do
    if M.yours(e.comment) and e.line and not e.comment.rev and e.comment.id ~= here then
      local after = e.comment.file > file or (e.comment.file == file and e.line > lnum)
      if after then
        ahead[#ahead + 1] = e.comment.id
      else
        table.insert(behind, 1, e.comment.id)
      end
    end
  end
  local dist = {}
  for i, id in ipairs(ahead) do
    dist[id] = i .. '↓'
  end
  for i, id in ipairs(behind) do
    dist[id] = i .. '↑'
  end

  local title_w = 28
  local shown_file
  local n = 0
  for _, e in ipairs(S.entries) do
    local c = e.comment
    if c.file ~= shown_file then
      shown_file = c.file
      lines[#lines + 1] = ' ' .. c.file
      hls[#hls + 1] = { #lines - 1, 0, -1, c.file == file and 'ThreadTitle' or 'Directory' }
    end
    n = n + 1
    local status = store.status(c)
    local g, ghl = render.glyph(status, batch and store.unseen(batch, c), not e.line)
    local letter = S.pinned and LETTERS:sub(n, n) or ''
    local mark = c.id == here and '▸' or ' '
    local title = store.title(c)
    local d = dist[c.id] or ''
    local left = string.format(' %s %s %s %4s  ', letter ~= '' and letter or ' ', mark, g, e.line or '–')
    local text = left .. fit(title, title_w)
    text = text .. string.rep(' ', math.max(1, width_of(left) + title_w + 2 - width_of(text))) .. d
    lines[#lines + 1] = text
    local row = #lines - 1
    S.rows[#lines] = e
    hls[#hls + 1] = { row, 1, 2, 'ThreadKey' }
    local col = 3
    hls[#hls + 1] = { row, col, col + #mark, 'ThreadFocus' }
    col = col + #mark + 1
    hls[#hls + 1] = { row, col, col + #g, ghl }
    col = col + #g
    hls[#hls + 1] = { row, col, #left, c.id == here and 'ThreadFocus' or 'LineNr' }
    hls[#hls + 1] = { row, #left, #text - #d, status == 'closed' and 'ThreadSignDone' or (c.id == here and 'ThreadTitle' or nil) }
    hls[#hls + 1] = { row, #text - #d, #text, 'ThreadKey' }
  end
  if #lines == 0 then
    lines[1] = '  no threads on lines in this batch'
    hls[#hls + 1] = { 0, 0, -1, 'ThreadMeta' }
  end
  return S.pinned and { { ' a–z', 'ThreadKey' }, { ' jump  ', 'ThreadKeyLabel' }, { 'q', 'ThreadKey' }, { ' close ', 'ThreadKeyLabel' } }
    or { { ' ' .. k 'next' .. ' ' .. k 'prev', 'ThreadKey' }, { ' your move  ', 'ThreadKeyLabel' }, { k 'next_all' .. ' ' .. k 'prev_all', 'ThreadKey' }, { ' all ', 'ThreadKeyLabel' } }
end

local function draw_walk(batch, lines, hls)
  local w = require('thread.walk').state()
  local head = w and store.find(batch, w.head)
  if not head then
    return {}
  end
  -- What the walk started from: your question, in your words.
  for _, m in ipairs(head.messages) do
    if m.from == 'you' then
      local q = vim.split(vim.trim(m.text or ''), '\n', { plain = true })[1] or ''
      lines[#lines + 1] = ' you  ' .. fit(q, 40)
      hls[#hls + 1] = { #lines - 1, 1, 4, 'ThreadYou' }
      hls[#hls + 1] = { #lines - 1, 4, -1, 'ThreadMeta' }
      lines[#lines + 1] = ''
      break
    end
  end
  local n, step = 0, 0
  for _, e in ipairs(S.entries) do
    local c = e.comment
    n = n + 1
    local here = c.id == w.id
    local status = store.status(c)
    local g, ghl = render.glyph(status, store.unseen(batch, c), store.anchored(c) and not e.line)
    local letter = S.pinned and LETTERS:sub(n, n) or ' '
    local indent = string.rep('  ', (e.depth or 1) - 1)
    local num = ''
    if store.anchored(c) then
      step = step + 1
      num = step .. ' '
    end
    local mark = here and '▸' or ' '
    local talk = store.talked(c) and ' ●' or ''
    local left = string.format(' %s %s %s%s ', letter, mark, indent, g)
    local title = (store.anchored(c) and num or '') .. store.title(c)
    local where = store.anchored(c) and (vim.fs.basename(c.file) .. ':' .. (e.line or '–')) or ''
    local text = left .. fit(title, 34 - #indent) .. talk
    text = text .. string.rep(' ', math.max(1, width_of(left) + 38 - width_of(text))) .. where
    lines[#lines + 1] = text
    local row = #lines - 1
    S.rows[#lines] = e
    hls[#hls + 1] = { row, 1, 2, 'ThreadKey' }
    hls[#hls + 1] = { row, 3, 3 + #mark, 'ThreadFocus' }
    local gcol = #(string.format(' %s %s %s', letter, mark, indent))
    hls[#hls + 1] = { row, gcol, gcol + #g, ghl }
    local tcol = #left
    hls[#hls + 1] = { row, tcol, tcol + #(fit(title, 34 - #indent)), here and 'ThreadCrumbHere' or (not store.anchored(c) and 'ThreadTitle' or nil) }
    if talk ~= '' then
      local s = text:find(talk, tcol, true)
      if s then
        hls[#hls + 1] = { row, s - 1, s - 1 + #talk, 'ThreadDotYou' }
      end
    end
    hls[#hls + 1] = { row, #text - #where, #text, 'LineNr' }
  end
  local wk = require('thread.config').options.walk
  local foot = {}
  local function add(key, label)
    key = key and render.show_key(key)
    if key and key ~= '' then
      foot[#foot + 1] = { ' ' .. key, 'ThreadKey' }
      foot[#foot + 1] = { ' ' .. label .. ' ', 'ThreadKeyLabel' }
    end
  end
  if S.pinned then
    add('a–z', 'jump')
  end
  add(wk.next, 'next')
  add(wk.prev, 'prev')
  add(wk.up, 'up')
  add(k 'stop', 'end')
  return foot
end

local function draw()
  local batch = store.active()
  find_here()
  local lines, hls = {}, {}
  S.rows = {}
  local footer = {}
  if batch then
    footer = S.mode == 'walk' and draw_walk(batch, lines, hls) or draw_batch(batch, lines, hls)
  end
  if #lines == 0 then
    lines[1] = '  nothing here'
  end

  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, width_of(l) + 1)
  end
  vim.bo[S.buf].modifiable = true
  vim.api.nvim_buf_set_lines(S.buf, 0, -1, false, lines)
  vim.bo[S.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(S.buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    if h[4] then
      local len = #lines[h[1] + 1]
      pcall(vim.api.nvim_buf_set_extmark, S.buf, ns, h[1], math.min(h[2], len), { end_col = (h[3] < 0 or h[3] > len) and len or h[3], hl_group = h[4] })
    end
  end
  local footer_w = 0
  for _, c in ipairs(footer) do
    footer_w = footer_w + width_of(c[1])
  end
  width = math.max(width, footer_w + 2)
  local title
  if S.mode == 'walk' and batch then
    local w = require('thread.walk').state()
    local head = w and store.find(batch, w.head)
    title = { { ' ▶ ', 'ThreadLeads' }, { fit(head and store.title(head) or 'walk', 40) .. ' ', 'ThreadTitle' } }
  else
    title = { { ' ' .. (batch and batch.data.title or 'threads') .. ' ', 'ThreadTitle' } }
  end
  vim.api.nvim_win_set_config(S.win, {
    relative = 'editor',
    anchor = 'NE',
    row = 0,
    col = vim.o.columns,
    width = math.min(width, vim.o.columns - 6),
    height = math.max(1, math.min(#lines, vim.o.lines - vim.o.cmdheight - 5)),
    title = title,
    title_pos = 'left',
    footer = #footer > 0 and footer or '',
    footer_pos = 'right',
  })
end

local function jump(e)
  if not e then
    return
  end
  if vim.api.nvim_get_current_win() == S.win then
    vim.cmd 'wincmd p'
  end
  if vim.api.nvim_get_current_win() == S.win then
    return
  end
  if S.mode == 'walk' then
    return require('thread.walk').go(e.comment.id)
  end
  require('thread.actions').jump(e.comment)
  render.cursor_moved()
  if M.is_open() then
    draw()
  end
end

local function entries(mode)
  local batch = store.active()
  if not batch then
    return {}
  end
  if mode == 'walk' then
    return (collect_walk(batch))
  end
  return collect(batch)
end

local function open(pinned, mode)
  if M.is_open() and S.mode ~= mode then
    M.close()
  end
  if not M.is_open() then
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].filetype = 'thread-map'
    local win = vim.api.nvim_open_win(buf, false, {
      relative = 'editor',
      anchor = 'NE',
      row = 0,
      col = vim.o.columns,
      width = 30,
      height = 1,
      border = 'rounded',
      style = 'minimal',
      title = ' ',
      title_pos = 'left',
      focusable = false,
      zindex = 45,
    })
    vim.wo[win].cursorline = false
    S = { win = win, buf = buf, pinned = false, rows = {}, mode = mode, entries = entries(mode) }
    local group = vim.api.nvim_create_augroup('thread.map', { clear = true })
    vim.api.nvim_create_autocmd({ 'CursorMoved', 'BufEnter' }, {
      group = group,
      callback = function()
        if M.is_open() and vim.api.nvim_get_current_win() ~= S.win then
          draw()
        end
      end,
    })
    local function map(lhs, fn)
      vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true })
    end
    map('<CR>', function()
      jump(S.rows[vim.api.nvim_win_get_cursor(0)[1]])
    end)
    map('q', M.close)
    map('<Esc>', function()
      vim.cmd 'wincmd p'
    end)
    for i = 1, #LETTERS do
      map(LETTERS:sub(i, i), function()
        local n = 0
        for row = 1, vim.api.nvim_buf_line_count(buf) do
          if S.rows[row] then
            n = n + 1
            if n == i then
              return jump(S.rows[row])
            end
          end
        end
      end)
    end
  end
  S.pinned = S.pinned or pinned
  S.entries = entries(mode)
  draw()
end

--- The batch changed: find every thread again.
function M.refresh()
  if M.is_open() then
    S.entries = entries(S.mode)
    draw()
  end
end

--- Keep the map open and go into it, to jump by letter; from inside it, it
--- goes.
function M.pin()
  local mode = require('thread.walk').state() and 'walk' or 'batch'
  if M.is_open() and S.pinned and vim.api.nvim_get_current_win() == S.win then
    return M.close()
  end
  open(true, mode)
  vim.api.nvim_win_set_config(S.win, { focusable = true })
  vim.api.nvim_set_current_win(S.win)
  -- On the thread you are on, else the first.
  local w = require('thread.walk').state()
  local here = mode == 'walk' and w and w.id or S.here
  local first
  for row = 1, vim.api.nvim_buf_line_count(S.buf) do
    local e = S.rows[row]
    if e then
      first = first or row
      if e.comment.id == here then
        first = row
        break
      end
    end
  end
  if first then
    vim.api.nvim_win_set_cursor(S.win, { first, 0 })
  end
end

return M
