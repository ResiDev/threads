--- The map, in the top right: kept open with `<leader>hm`, and shown for a
--- few seconds after `]h` / `[h`, the way comments.nvim does. Walking a
--- tour never shows it: the winbar says where you are.
--- Two kinds:
---
--- - **the batch**: every thread on a line, by file, with how many `]h` (or
---   `[h`) presses away each one where it is your move is.
--- - **the walk**: while walking, every stop of the tour, the steps of a
---   stage indented under it, `▸` where you are.
---
--- A letter jumps to a thread; `q` closes it.

local anchor = require 'thread.anchor'
local float = require 'thread.float'
local look = require 'thread.look'
local place = require 'thread.render.place'
local render = require 'thread.render'
local sheet = require 'thread.sheet'
local store = require 'thread.store'
local text = require 'thread.text'
local tour = require 'thread.tour'

local M = {}

local ns = vim.api.nvim_create_namespace 'thread.map'
local LETTERS = 'abcdefgimoprstuvwxyz' -- not h, j, k, l, n, q: those move, open and close

---@class thread.MapEntry
---@field comment thread.Comment|nil  in the batch
---@field line integer|nil  where it is now; nil when its line is gone or it has none
---@field item thread.OutlineItem|nil  in a walk

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

--- Your move: an answer to read.
function M.yours(comment)
  return store.status(comment) == 'answered'
end

--- The batch: every thread on a line, with the line it is on now, by file
--- then line. The walk: every stop of the tour.
local function entries(mode)
  local batch = store.active()
  if not batch then
    return {}
  end
  local at = anchor.finder()
  local out = {}
  if mode == 'walk' then
    local w = require('thread.walk').state()
    local owner = w and store.find(batch, w.owner)
    for _, it in ipairs(owner and tour.outline(tour.of(owner) or {}) or {}) do
      out[#out + 1] = { item = it, line = it.kind == 'step' and at(it.e) or nil }
    end
    return out
  end
  for _, c in ipairs(batch.data.threads) do
    if store.anchored(c) then
      out[#out + 1] = { comment = c, line = at(c) }
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

function M.close()
  if S then
    float.close(S.win)
  end
  pcall(vim.api.nvim_del_augroup_by_name, 'thread.map')
  S = nil
end

function M.is_open()
  return S ~= nil and vim.api.nvim_win_is_valid(S.win)
end

--- Where you are, unless you are in the map itself.
local function find_here()
  if vim.api.nvim_get_current_win() == S.win then
    return
  end
  local where = anchor.of_buf(0)
  S.file = where and not where.rev and where.file or nil
  S.lnum = vim.api.nvim_win_get_cursor(0)[1]
  local placed = place.placed[vim.api.nvim_get_current_buf()]
  local h = S.file and placed and place.covering(placed, S.lnum) or {}
  S.here = h[1] and h[1].comment.id
end

local function letter(n)
  return S.pinned and LETTERS:sub(n, n) ~= '' and LETTERS:sub(n, n) or ' '
end

local function draw_batch(P, batch)
  local file, lnum, here = S.file or '', S.lnum or 0, S.here
  -- ]h counts: your-move threads after where you are, [h those before,
  -- in the order ]h walks them: file, then line.
  local ahead, behind = {}, {}
  for _, e in ipairs(S.entries) do
    if M.yours(e.comment) and e.line and not e.comment.rev and e.comment.id ~= here then
      if e.comment.file > file or (e.comment.file == file and e.line > lnum) then
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
  local shown_file
  for n, e in ipairs(S.entries) do
    local c = e.comment
    if c.file ~= shown_file then
      shown_file = c.file
      P.chunks({ { c.file, c.file == file and 'ThreadTitle' or 'Directory' } }, 1)
    end
    local status = store.status(c)
    local g, ghl = look.glyph(status, store.unseen(batch, c), not e.line)
    local title = text.fit(store.title(c), 28)
    P.own(e)
    P.chunks {
      { ' ' },
      { letter(n), 'ThreadKey' },
      { ' ' },
      { c.id == here and '▸' or ' ', 'ThreadFocus' },
      { ' ' },
      { g, ghl },
      { string.format(' %4s  ', e.line or '–'), c.id == here and 'ThreadFocus' or 'LineNr' },
      { title .. string.rep(' ', math.max(1, 30 - text.width(title))), status == 'closed' and 'ThreadSignDone' or (c.id == here and 'ThreadTitle' or nil) },
      { dist[c.id] or '', 'ThreadKey' },
    }
    P.own(nil)
  end
  if #P.lines == 0 then
    P.chunks({ { 'no threads on lines in this batch', 'ThreadMeta' } }, 2)
  end
  local function k(action)
    return look.key(action) or ''
  end
  return S.pinned and { { 'a–z', 'jump' }, { 'q', 'close' } } or { { k 'next' .. ' ' .. k 'prev', 'your move' }, { k 'next_all' .. ' ' .. k 'prev_all', 'all' } }
end

local function draw_walk(P, batch)
  local w = require('thread.walk').state()
  if not w then
    return {}
  end
  for n, e in ipairs(S.entries) do
    local it = e.item
    local here = it.n == w.n
    local talk = tour.thread_at(batch, w.owner, it.n)
    local g, ghl
    if talk then
      g, ghl = look.glyph(store.status(talk), store.unseen(batch, talk), false)
    elseif store.visited(batch, w.owner, it.n) and it.kind ~= 'stage' then
      g, ghl = '✓', 'ThreadSignDone'
    else
      g, ghl = it.kind == 'stage' and '▸' or '·', 'ThreadSignInfo'
    end
    local indent = (it.kind ~= 'stage' and it.stage > 0) and '  ' or ''
    local num = it.kind == 'stage' and (it.stage .. ' ') or it.kind == 'step' and (it.step .. ' ') or ''
    local title = text.fit(num .. tour.title(it.e), 34 - #indent)
    P.own(e)
    P.chunks {
      { ' ' },
      { letter(n), 'ThreadKey' },
      { ' ' },
      { here and '▸' or ' ', 'ThreadFocus' },
      { ' ' .. indent },
      { g, ghl },
      { ' ' },
      { title, here and 'ThreadCrumbHere' or (it.kind == 'stage' and 'ThreadTitle' or nil) },
      { string.rep(' ', math.max(1, 38 - text.width(title))) },
      { it.kind == 'step' and (vim.fs.basename(it.e.file) .. ':' .. (e.line or '–')) or '', 'LineNr' },
    }
    P.own(nil)
  end
  local wk = require('thread.config').options.walk
  local foot = S.pinned and { { 'a–z', 'jump' } } or {}
  for _, k in ipairs { { wk.next, 'next' }, { wk.prev, 'prev' }, { wk.quit, 'end' } } do
    if k[1] then
      foot[#foot + 1] = { look.show_key(k[1]), k[2] }
    end
  end
  return foot
end

local function draw()
  local batch = store.active()
  find_here()
  local P = sheet.new()
  local keys = batch and (S.mode == 'walk' and draw_walk or draw_batch)(P, batch) or {}
  if #P.lines == 0 then
    P.add '  nothing here'
  end
  P.apply(S.buf, ns)
  S.rows = P.owner
  local footer = #keys > 0 and look.footer(keys) or nil
  local width = footer and text.width(footer) + 2 or 0
  for _, l in ipairs(P.lines) do
    width = math.max(width, text.width(l) + 1)
  end
  local title
  local w = S.mode == 'walk' and batch and require('thread.walk').state()
  if w then
    local owner = store.find(batch, w.owner)
    title = { { ' ▶ ', 'ThreadLeads' }, { text.fit(owner and store.title(owner) or 'walk', 40) .. ' ', 'ThreadTitle' } }
  else
    title = { { ' ' .. (batch and batch.data.title or 'threads') .. ' ', 'ThreadTitle' } }
  end
  vim.api.nvim_win_set_config(S.win, {
    relative = 'editor',
    anchor = 'NE',
    row = 0,
    col = vim.o.columns,
    width = math.min(width, vim.o.columns - 6),
    height = math.max(1, math.min(#P.lines, float.max_height(3))),
    title = title,
    title_pos = 'left',
    footer = footer or '',
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
    return require('thread.walk').go(e.item.n)
  end
  require('thread.actions').jump(e.comment)
  render.cursor_moved()
  if M.is_open() then
    draw()
  end
end

local function open(pinned, mode)
  if M.is_open() and S.mode ~= mode then
    M.close()
  end
  if not M.is_open() then
    local keys = {
      ['<CR>'] = function()
        jump(S.rows[vim.api.nvim_win_get_cursor(0)[1]])
      end,
      q = M.close,
      ['<Esc>'] = function()
        vim.cmd 'wincmd p'
      end,
    }
    for i = 1, #LETTERS do
      keys[LETTERS:sub(i, i)] = function()
        local n = 0
        for row = 1, vim.api.nvim_buf_line_count(S.buf) do
          if S.rows[row] then
            n = n + 1
            if n == i then
              return jump(S.rows[row])
            end
          end
        end
      end
    end
    local win, buf = float.open {
      enter = false,
      filetype = 'thread-map',
      win = { anchor = 'NE', col = vim.o.columns, width = 30, title = ' ', title_pos = 'left', focusable = false, zindex = 45 },
      wo = { cursorline = false },
      keys = keys,
    }
    S = { win = win, buf = buf, pinned = false, rows = {}, mode = mode }
    vim.api.nvim_create_autocmd({ 'CursorMoved', 'BufEnter' }, {
      group = vim.api.nvim_create_augroup('thread.map', { clear = true }),
      callback = function()
        if M.is_open() and vim.api.nvim_get_current_win() ~= S.win then
          draw()
        end
      end,
    })
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

local timer

--- Show the batch map for a moment, after `]h` / `[h`. A map kept open
--- stays as it is.
function M.flash()
  if M.is_open() and S.pinned then
    return draw()
  end
  open(false, 'batch')
  timer = timer or vim.uv.new_timer()
  timer:stop()
  timer:start(
    3000,
    0,
    vim.schedule_wrap(function()
      if M.is_open() and not S.pinned then
        M.close()
      end
    end)
  )
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
  local first
  for row = 1, vim.api.nvim_buf_line_count(S.buf) do
    local e = S.rows[row]
    if e then
      first = first or row
      if (mode == 'walk' and w and e.item.n == w.n) or (mode ~= 'walk' and e.comment.id == S.here) then
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
