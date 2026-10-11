--- Home: every thread in the current batch on one full screen, a line each,
--- like an inbox in conversation view. Tabs pick what shows: the
--- conversations, the tours, the review of a diff, what is closed. The
--- focused thread opens in place: its code, with what changed since you
--- sent it, and as much of its history as you ask for (h/l). You reply and
--- close from here; Enter goes to the code only when you want to.
---
--- Focused from the code, the same screen holds one thread in a float in
--- the middle (thread.home.single).
---
--- Everything shown is worked out from the batch file, the code and the
--- round's snapshot: whose turn it is, how long the thread is, how the code
--- around it changed. The agent only writes messages and a title.

local float = require 'thread.float'
local keys = require 'thread.home.keys'
local look = require 'thread.look'
local model = require 'thread.home.model'
local reply = require 'thread.home.reply'
local sheet = require 'thread.sheet'
local single = require 'thread.home.single'
local store = require 'thread.store'
local tabs = require 'thread.home.tabs'
local thread = require 'thread.home.thread'

local M = {}

local ns = vim.api.nvim_create_namespace 'thread.home'

---@class thread.HomeState
---@field win integer
---@field buf integer
---@field tab integer             the tab Home is on (thread.home.tabs)
---@field group integer           how threads are grouped (thread.home.model)
---@field focus any               the focused row: a thread's id, or a review's row
---@field focus_index integer|nil its place in `order`
---@field order any[]             rows as listed
---@field row_of table<any, integer>  row -> its line
---@field owner table<integer, any>   line -> its row
---@field levels table<integer, integer>  thread id -> messages shown
---@field seen_at table<integer, integer> thread id -> messages seen when you arrived
---@field code table<integer, integer>    thread id -> how much code: 0, 1, 2
---@field marked table<integer, boolean>  threads picked with space
---@field query string|nil        the search: only threads that mention it
---@field inside table|nil        the thread you are inside: { id, item, sel, ref }
---@field items table[]|nil       its parts
---@field refs table[]|nil        the names in it that point at code
---@field open_refs table<string, integer>  a name -> which of its places shows
---@field ref_size table<string, integer>
---@field reply table|nil         a reply being typed
---@field single integer|nil      focused from the code: only this thread, in a float
---@field others integer[]|nil    the other threads on that line, for tab
---@field src_win integer|nil     the code window it was focused from
---@field quick boolean|nil       opened to reply: back to the code once sent
---@field indent integer          where an open thread's lines start
---@field label integer           the width of a message's speaker
---@field text_col integer        where a message's text starts
---@type thread.HomeState|nil
local S

--- Home's keys, in the footer; the focused thread lists its own.
local KEYS = { { 'j/k', 'thread' }, { 'tab', 'next tab' }, { '?', 'help' }, { 'q', 'quit' } }

function M.is_open()
  return S ~= nil and vim.api.nvim_win_is_valid(S.win)
end

--- Bring the focused row and as much of its open thread as fits into view,
--- the cursor on it (or on the part or name you are on).
local function scroll()
  local row = S.focus and S.row_of[S.focus]
  if not row then
    return
  end
  local last = row
  while S.owner[last + 1] == S.focus do
    last = last + 1
  end
  local item = S.inside and S.items and S.items[S.inside.item]
  if item then
    row, last = item.first + 1, item.last + 1
  end
  -- On a name: it, and its code when open, in view, the cursor on it.
  local ref = thread.selected_ref(S)
  if ref then
    row = ref.first + 1
    last = row + (S.open_refs[ref.key] and (thread.REF_SIZES[S.ref_size[ref.key] or 2] + 4) or 0)
  end
  local height = vim.api.nvim_win_get_height(S.win)
  local top = vim.api.nvim_win_call(S.win, vim.fn.winsaveview).topline
  if row < top then
    top = math.max(1, row - 1)
  elseif last >= top + height then
    top = math.max(1, math.min(row - 2, last - height + 1))
  end
  local lnum = S.reply and S.reply.first and S.reply.first + 1 or row
  vim.api.nvim_win_call(S.win, function()
    vim.fn.winrestview { topline = top, lnum = lnum, col = ref and not S.reply and ref.s or 0 }
  end)
  for i, id in ipairs(S.order) do
    if id == S.focus then
      S.focus_index = i
    end
  end
end

--- Draw Home again: the tabs, or the one thread focused from the code.
function M.draw()
  if not M.is_open() then
    return
  end
  S.rendering = true
  local batch = store.active()
  local width = vim.api.nvim_win_get_width(S.win)
  local P = sheet.new { priority = 15 }
  S.order, S.row_of, S.focused_thread = {}, {}, nil
  if not batch then
    P.add ''
    P.add('  No batch yet. Start a thread on a line with ' .. (look.key 'add' or ':Thread add') .. ', or press B for the batches.')
  elseif S.single then
    single.draw(P, S, batch, width)
  else
    tabs.draw(P, S, batch, width)
  end
  if S.single then
    vim.api.nvim_win_set_config(S.win, { title = single.title(S), title_pos = 'left', footer = single.footer(S), footer_pos = 'right' })
  else
    vim.api.nvim_win_set_config(S.win, { footer = look.footer(KEYS), footer_pos = 'right' })
  end
  P.apply(S.buf, ns)
  vim.bo[S.buf].modifiable = S.reply ~= nil
  S.owner = P.owner
  if S.single then
    single.place(S)
    single.strip(S)
  end
  if S.inside and S.inside.id ~= S.focus then
    S.inside = nil
  end
  scroll()
  -- Seen once every message you had not seen is on screen.
  local t = S.focused_thread
  local shown = t and math.min(#t.c.messages, S.focused_level or 0) or 0
  if shown > 0 and #t.c.messages - shown <= store.seen_count(batch, t.c) then
    store.mark_seen(batch, t.c)
  end
  S.rendering = false
end

function M.close()
  local src = S and S.single and S.src_win
  if S and S.strip then
    float.close(S.strip.win)
  end
  if S then
    float.close(S.win)
  end
  S = nil
  if src and vim.api.nvim_win_is_valid(src) then
    vim.api.nvim_set_current_win(src)
    -- What was new in it has been read now.
    require('thread.render').refresh()
  end
end

--- Redraw after the batch changed: our own edits or the agent's. A reply in
--- progress is never redrawn under you; it waits.
function M.refresh()
  if not M.is_open() then
    S = nil
  elseif not S.reply then
    M.draw()
  end
end

--- Moving onto another thread's lines by other means (G, a search, the
--- mouse) focuses it; inside a thread, the part under the cursor.
local function follow_cursor()
  if not S or S.rendering or S.reply then
    return
  end
  local lnum = vim.api.nvim_win_get_cursor(S.win)[1]
  local id = S.owner[lnum]
  if id and id ~= S.focus then
    S.focus, S.inside = id, nil
    return vim.schedule(M.draw)
  end
  if not (S.inside and id == S.focus) then
    return
  end
  -- The part already on when it still holds the line (a name's line is its
  -- message's too), else the first that holds it.
  local function holds(it)
    return it and lnum - 1 >= it.first and lnum - 1 <= it.last
  end
  if holds(S.items and S.items[S.inside.item]) then
    return
  end
  for n, it in ipairs(S.items or {}) do
    if holds(it) then
      thread.select(S, n)
      S.inside.ref = nil
      return vim.schedule(M.draw)
    end
  end
end

--- A new Home: its float, its state, its keys.
---@param opts { single: integer|nil, win: table, title: string }
local function start(opts)
  M.close()
  local indent = opts.single and 2 or 6
  local label = opts.single and 3 or 4
  local src = vim.api.nvim_get_current_win()
  -- which-key holds keys that start built-in commands, such as g, waiting
  -- for the rest, even over a buffer's own nowait mapping: keep it out.
  local wk = package.loaded['which-key.config']
  if wk and wk.disable and wk.disable.ft and not vim.tbl_contains(wk.disable.ft, 'thread-home') then
    table.insert(wk.disable.ft, 'thread-home')
  end
  local win, buf = float.open {
    filetype = 'thread-home',
    win = vim.tbl_extend('force', opts.win, { title = opts.title, title_pos = 'left', footer = ' ', footer_pos = 'right' }),
    wo = { wrap = true, linebreak = true, breakindent = true, breakindentopt = 'shift:' .. (indent + label), cursorline = false },
  }
  -- A reply is prose, not code: no completion menu over the threads.
  vim.b[buf].completion = false
  vim.b[buf].cmp_enabled = false
  S = {
    win = win,
    buf = buf,
    tab = 1,
    group = 2,
    levels = {},
    seen_at = {},
    marked = {},
    code = {},
    open_refs = {},
    ref_size = {},
    order = {},
    row_of = {},
    owner = {},
    pick_first = not opts.single,
    single = opts.single,
    src_win = opts.single and src or nil,
    indent = indent,
    label = label,
    text_col = indent + label,
  }
  keys.map(buf, function()
    return S
  end)
  local group = vim.api.nvim_create_augroup('thread.home', { clear = true })
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    group = group,
    buffer = buf,
    callback = function()
      reply.relabel(S)
    end,
  })
  vim.api.nvim_create_autocmd('CursorMoved', { group = group, buffer = buf, callback = follow_cursor })
  vim.api.nvim_create_autocmd('VimResized', {
    group = group,
    callback = function()
      if M.is_open() and not S.single then
        vim.api.nvim_win_set_config(S.win, float.full())
      end
      M.refresh()
    end,
  })
  vim.api.nvim_create_autocmd('WinLeave', {
    group = group,
    buffer = buf,
    callback = function()
      vim.schedule(function()
        if S and S.win == win and vim.api.nvim_get_current_win() ~= win and not S.helping then
          -- Gone elsewhere: no going back to where it was focused from.
          S.src_win = nil
          M.close()
        end
      end)
    end,
  })
end

--- Open Home; `opts.view` picks a tab by what it shows (`review`), and
--- `opts.focus` the row to be on.
---@param opts { view: string|nil, focus: any }|nil
function M.open(opts)
  opts = opts or {}
  if not (M.is_open() and not S.single) then
    local batch = store.active()
    start { win = float.full(), title = ' Home · ' .. (batch and batch.data.title or 'no batch') .. ' ' }
  else
    vim.api.nvim_set_current_win(S.win)
    if not (opts.view or opts.focus) then
      return
    end
  end
  for i, t in ipairs(tabs.TABS) do
    if opts.view and t.view == opts.view then
      S.tab = i
    end
  end
  S.focus = opts.focus or S.focus
  M.draw()
end

---@class thread.FocusOpts
---@field comment thread.Comment
---@field others integer[]|nil  every thread on that line, in order, for tab
---@field reply boolean|nil     straight into a reply, and back to the code once sent

--- One thread, focused from the code: a float in the middle with its code
--- and the whole thread, and Home's keys. Esc goes back to the code.
---@param opts thread.FocusOpts
function M.focus(opts)
  start { single = opts.comment.id, win = { row = 1, col = 1, width = math.min(vim.o.columns - 8, 110), height = 3 }, title = ' ' }
  S.quick = opts.reply
  S.others = opts.others or { opts.comment.id }
  M.draw()
  keys.enter(S)
  if opts.reply then
    reply.start(S)
  end
end

--- Focused from the code: another thread, in place of this one. Stepping
--- between threads, the strip of them shows under the float.
---@param id integer|nil
function M.go(id)
  if not (S and S.single and id) then
    return
  end
  S.single, S.others = id, { id }
  S.inside, S.seen_at = nil, {}
  M.draw()
  keys.enter(S)
  S.strip_on = true
  single.strip(S)
end

--- The thread before (`dir` -1) or after `id`, in the order h and l go
--- through them, round the ends.
---@param id integer
---@param dir 1|-1
---@return thread.Comment|nil
function M.neighbour(id, dir)
  local batch = store.active()
  return batch and model.neighbour(batch, id, dir)
end

M._state = function()
  return S
end

return M
