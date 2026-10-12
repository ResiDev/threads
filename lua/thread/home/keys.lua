--- Home's keys: moving between threads and inside one, opening, replying,
--- closing, the tabs, and in the review tab acting on a group. Each takes
--- Home's state and the count typed before it.

local actions = require 'thread.actions'
local help = require 'thread.home.help'
local model = require 'thread.home.model'
local reply = require 'thread.home.reply'
local review = require 'thread.review'
local store = require 'thread.store'
local tabs = require 'thread.home.tabs'
local text = require 'thread.text'
local thread = require 'thread.home.thread'
local tour = require 'thread.tour'

local M = {}

local function home()
  return require 'thread.home'
end

local function draw()
  home().draw()
end

local function focused(S)
  local batch = store.active()
  return batch, batch and S.focus and store.find(batch, S.focus)
end

--- The next (or previous) thread.
local function move(S, n)
  if #S.order == 0 then
    return
  end
  local i = math.max(1, math.min(#S.order, (S.focus_index or 1) + n))
  if S.order[i] ~= S.focus then
    S.seen_at = {}
  end
  S.focus = S.order[i]
  draw()
end

--- More (or less) of the focused thread's history.
local function level(S, n)
  local _, c = focused(S)
  if not c then
    return
  end
  local cur = S.levels[S.focus] or S.focused_level or 2
  S.levels[S.focus] = math.max(0, math.min(#c.messages, cur + n))
  draw()
end

--- Go into the focused thread: its whole history, stepped through part by
--- part. You land on the first message you had not seen, else the last.
function M.enter(S)
  if not S.focus or S.inside then
    return
  end
  local batch, c = focused(S)
  if not c then
    return
  end
  local seen = S.seen_at[c.id] or store.seen_count(batch, c)
  S.inside = { id = c.id, index = #c.messages }
  for i, m in ipairs(c.messages) do
    if i > seen and m.from ~= 'you' then
      S.inside.index = i
      break
    end
  end
  draw()
  -- Parts are only known once drawn: find the one for that message.
  for n, it in ipairs(S.items or {}) do
    if it.kind == 'message' and it.index == S.inside.index then
      thread.select(S, n)
      break
    end
  end
  draw()
end

local function leave(S)
  if S.single then
    home().close()
  elseif S.inside then
    S.inside = nil
    draw()
  end
end

--- Inside a thread: the next (or previous) part of it.
local function step(S, n)
  local count = #(S.items or {})
  if count > 0 then
    thread.select(S, math.max(1, math.min(count, (S.inside.item or count) + n)))
    S.inside.ref, S.undo_armed = nil, nil
    draw()
  end
end

--- j/k: the next thread, or inside one its next part.
local function down(S, n)
  if S.inside then
    step(S, n)
  else
    move(S, n)
  end
end

--- Inside a thread: the next (or previous) name that points at code, across
--- its messages; the message it is in becomes the one you are on.
local function ref_step(S, n)
  local list = S.inside and S.refs or {}
  if #list == 0 then
    return
  end
  local at
  for i, r in ipairs(list) do
    if r.key == S.inside.ref then
      at = i + n
    end
  end
  if not at then
    -- From a message: its first name going on, the one before it going back.
    local item = S.inside.item or 1
    for i = n > 0 and 1 or #list, n > 0 and #list or 1, n do
      if (n > 0 and list[i].item >= item) or (n < 0 and list[i].item < item) then
        at = i
        break
      end
    end
  end
  local r = at and list[at]
  if r then
    S.inside.ref = r.key
    thread.select(S, r.item)
    draw()
  end
end

--- Show more or less of the focused thread's code; on a name whose code is
--- open, or on that code, it grows or shrinks.
local function code(S, n)
  local ref = thread.current_ref(S)
  if ref and S.open_refs[ref.key] then
    S.ref_size[ref.key] = math.max(1, math.min(#thread.REF_SIZES, (S.ref_size[ref.key] or 2) + n))
  elseif S.focus then
    S.code[S.focus] = math.max(0, math.min(#thread.CODE - 1, (S.code[S.focus] or 1) + n))
  end
  draw()
end

--- Narrow the threads to those that mention what you type, as you type it.
local function search(S)
  local before = S.query
  local group = vim.api.nvim_create_augroup('thread.home.search', { clear = true })
  vim.api.nvim_create_autocmd('CmdlineChanged', {
    group = group,
    callback = function()
      S.query = vim.fn.getcmdline()
      draw()
      vim.cmd.redraw()
    end,
  })
  local ok, q = pcall(vim.fn.input, { prompt = '/', default = before or '', cancelreturn = '\0' })
  vim.api.nvim_del_augroup_by_id(group)
  if not home().is_open() then
    return
  end
  if not ok or q == '\0' then
    S.query = before
  else
    S.query = q ~= '' and q or nil
  end
  draw()
end

--- o in the review tab: into the focused review, where j/k go through its
--- groups, from the first one not accepted; o again, back to the reviews.
local function review_in(S)
  local batch = store.active()
  local owner, n = model.review_row(batch, S.focus)
  if not owner then
    return
  end
  if n then
    S.focus, S.in_review = 'v:' .. owner.id, nil
    return draw()
  end
  local rows = model.group_rows(owner)
  if #rows == 0 then
    return
  end
  local rv = review.of(owner)
  S.focus = rows[1].id
  for _, g in ipairs(rows) do
    if review.state(batch, owner.id, review.group_of(rv, g.e)) ~= 'accepted' then
      S.focus = g.id
      break
    end
  end
  S.in_review = owner.id
  draw()
end

--- ⏎ in the review tab: the review's screen, on the group if on one.
local function open_review(S)
  local owner, n = model.review_row(store.active(), S.focus)
  if owner then
    home().close()
    require('thread.review.screen').open { owner = owner.id, n = n }
  end
end

--- ⏎: go to what you are on. A link, a stop to walk from, a tour's start,
--- a diagram's box, a name's code, a change's diff; else the thread's line.
local function go(S)
  local id, n = text.link_at(vim.api.nvim_get_current_line(), vim.api.nvim_win_get_cursor(S.win)[2])
  if id and store.find(store.active(), id) then
    home().close()
    return actions.follow_link(id, n)
  end
  if tabs.view(S) == 'review' then
    return open_review(S)
  end
  local batch, c = focused(S)
  if not c then
    return
  end
  local item = S.inside and S.items and S.items[S.inside.item]
  local function walk(from)
    home().close()
    require('thread.walk').start(c.id, from)
  end
  -- On a stop of the tour an answer leads to: walk from it.
  if item and item.kind == 'stop' then
    return walk(item.n)
  end
  -- A tour's own row, its overview or the message that leads to it:
  -- walk it from its first stop.
  local _, at = tour.of(c)
  if
    at
    and (
      tabs.view(S) == 'tours' and not S.inside
      or (item and item.kind == 'message' and item.index == at)
      or (S.single and not S.inside and not store.anchored(c))
    )
  then
    return walk(1)
  end
  -- On a diagram: the box under the cursor, its code.
  if item and item.kind == 'diagram' then
    local cur = vim.api.nvim_win_get_cursor(S.win)
    local vcol = vim.fn.virtcol { cur[1], cur[2] + 1 } - 1
    local node = item.drawn and require('thread.diagram').hit(item.drawn, cur[1] - 1 - item.first, vcol - S.text_col)
    if node and node.file then
      home().close()
      actions.jump { id = 0, file = node.file, text = node.text, line = node.line }
    elseif at and item.index == at then
      -- The tour's diagram, off its boxes with code: the tour.
      walk(1)
    else
      vim.notify('thread: put the cursor on a box with code behind it', vim.log.levels.INFO)
    end
    return
  end
  local ref = thread.current_ref(S)
  -- A thread about no line: from the list, its page; on the page, nothing.
  if not store.anchored(c) and not (item and item.kind == 'change') and not ref then
    if not S.single then
      home().close()
      home().focus { thread = store.find(store.active(), c.id) }
    end
    return
  end
  -- On a name, its code opens or closes under its paragraph; on that code,
  -- it closes, and you are back on the name.
  if ref then
    if S.open_refs[ref.key] then
      S.open_refs[ref.key] = nil
      S.inside.ref, S.inside.sel = ref.key, ref.part
    else
      S.open_refs[ref.key] = 1
    end
    return draw()
  end
  -- On a change, its whole diff; else the thread's line.
  home().close()
  if item and item.kind == 'change' then
    actions.changes(batch, c, { change = item.change, index = item.index })
  else
    actions.jump(c)
  end
end

--- Focused from the code: the next of the threads on that line.
local function other(S, n)
  local list = S.others or {}
  if #list < 2 then
    return
  end
  local at = 1
  for i, id in ipairs(list) do
    if id == S.single then
      at = i
    end
  end
  S.single = list[(at - 1 + n) % #list + 1]
  S.inside, S.seen_at = nil, {}
  draw()
  M.enter(S)
end

--- The next (or previous) tab; focused from the code, the next thread on
--- its line.
local function tab(S, n)
  if S.single then
    return other(S, n)
  end
  S.tab = (S.tab - 1 + n) % #tabs.TABS + 1
  draw()
end

--- h and l: less or more of the history; focused from the code, the
--- threads either side.
local function side(S, n, more)
  if S.single then
    local to = n < 0 and S.prev or S.next
    return home().go(to and to.c.id)
  end
  level(S, more)
end

M.KEYS = {
  j = function(S, count)
    down(S, count)
  end,
  k = function(S, count)
    down(S, -count)
  end,
  ['<Down>'] = function(S)
    down(S, 1)
  end,
  ['<Up>'] = function(S)
    down(S, -1)
  end,
  -- o opens the thread: all of it, stepped through with j/k; o again or
  -- Esc comes back out. In the review tab, the same with a review's groups.
  o = function(S)
    if tabs.view(S) == 'review' then
      review_in(S)
    elseif S.inside then
      leave(S)
    else
      M.enter(S)
    end
  end,
  l = function(S)
    side(S, 1, 1)
  end,
  h = function(S)
    side(S, -1, -1)
  end,
  -- H and L: the tab to the left or right; focused from the code, the
  -- threads either side, as h and l.
  L = function(S)
    if S.single then
      return side(S, 1, 1)
    end
    tab(S, 1)
  end,
  H = function(S)
    if S.single then
      return side(S, -1, -1)
    end
    tab(S, -1)
  end,
  -- Walk the tour its answer leads to, or the one it is a reply in; in the
  -- review tab, the review's hunks.
  J = function(S)
    local owner
    if tabs.view(S) == 'review' then
      owner = model.review_row(store.active(), S.focus)
    else
      local _, c = focused(S)
      owner = c and (tour.leads(c) or c.on) and c
    end
    if owner then
      home().close()
      require('thread.walk').start(owner.id)
    end
  end,
  a = function(S)
    local batch = store.active()
    if tabs.view(S) ~= 'review' or not batch then
      return
    end
    local owner, n = model.review_row(batch, S.focus)
    if owner and n then
      local rv = review.of(owner)
      review.toggle(batch, owner.id, review.group_of(rv, tour.of(owner)[n]))
      draw()
    end
  end,
  d = function(S)
    if tabs.view(S) == 'review' then
      actions.pick_diff()
    end
  end,
  r = function(S)
    if tabs.view(S) ~= 'review' then
      return reply.start(S)
    end
    -- On a group: ask about it, in a thread on it.
    local owner, n = model.review_row(store.active(), S.focus)
    if owner and n then
      home().close()
      actions.reply_stop(owner.id, n)
    end
  end,
  c = function(S)
    if tabs.view(S) == 'review' then
      -- The review you are on, or whose groups you are in: closed, as a
      -- thread is. It goes to the closed tab, where c opens it again.
      local batch = store.active()
      local owner = batch and model.review_row(batch, S.focus)
      if owner then
        S.in_review = nil
        actions.toggle_closed(batch, owner)
        vim.notify('thread: closed ' .. store.title(owner) .. '; 4 shows it, and c there opens it again')
      end
      return
    end
    local batch, c = focused(S)
    if next(S.marked) and batch then
      -- Close them all, or reopen them all if every one is closed.
      local ids, all_closed = vim.tbl_keys(S.marked), true
      for _, id in ipairs(ids) do
        local m = store.find(batch, id)
        all_closed = all_closed and m ~= nil and store.status(m) == 'closed'
      end
      S.marked = {}
      store.set_status_all(batch, ids, all_closed and 'open' or 'closed')
    elseif c then
      actions.toggle_closed(batch, c)
    end
  end,
  ['<Space>'] = function(S)
    if S.focus then
      S.marked[S.focus] = not S.marked[S.focus] or nil
      move(S, 1)
    end
  end,
  n = function(S)
    local ref = thread.current_ref(S)
    local open = ref and S.open_refs[ref.key]
    if open then
      S.open_refs[ref.key] = open % #ref.places + 1
      draw()
    end
  end,
  w = function(S)
    ref_step(S, 1)
  end,
  b = function(S)
    ref_step(S, -1)
  end,
  g = function(S)
    S.group = S.group % #model.GROUPS + 1
    draw()
  end,
  ['/'] = search,
  ['+'] = function(S)
    code(S, 1)
  end,
  ['='] = function(S)
    code(S, 1)
  end,
  ['-'] = function(S)
    code(S, -1)
  end,
  ['<CR>'] = go,
  u = function(S)
    local it = S.inside and S.items and S.items[S.inside.item]
    if not (it and it.kind == 'change' and it.view and #it.view.hunks > 0) then
      return
    end
    -- Twice: the first press only says what the second will do.
    if S.undo_armed ~= it.id then
      S.undo_armed = it.id
      return draw()
    end
    S.undo_armed = nil
    actions.undo_change(it.change.file, it.view)
    draw()
  end,
  B = function()
    home().close()
    require('thread.menu').open()
  end,
  q = function()
    home().close()
  end,
  ['<Esc>'] = function(S)
    if S.inside then
      leave(S)
    elseif tabs.view(S) == 'review' and S.in_review then
      review_in(S)
    elseif next(S.marked) then
      S.marked = {}
      draw()
    elseif S.query then
      S.query = nil
      draw()
    else
      home().close()
    end
  end,
  ['?'] = function(S)
    -- Home stays open behind it, and gets the focus back.
    S.helping = true
    help.open(S.single ~= nil, function()
      S.helping = false
      if vim.api.nvim_win_is_valid(S.win) then
        vim.api.nvim_set_current_win(S.win)
      end
    end)
  end,
  ['<Tab>'] = function(S)
    tab(S, 1)
  end,
  ['<S-Tab>'] = function(S)
    tab(S, -1)
  end,
}
-- Numbers switch tabs here, so the ones without a tab must not start a
-- count, and Home is not text to edit outside a reply: these do nothing.
for _, lhs in ipairs { '5', '6', '7', '8', '9', '0', 'A', 'i', 'I', 'O', 'S', 'C', 'D', 'R', 'x', 'X', 'p', 'P', 'V', '<C-r>', '.' } do
  M.KEYS[lhs] = function() end
end
-- Focused from the code there is one thread and nothing to filter, group
-- or mark.
local NOT_SINGLE = { g = true, ['/'] = true, ['<Space>'] = true }
for i, t in ipairs(tabs.TABS) do
  NOT_SINGLE[t.key] = true
  M.KEYS[t.key] = function(S)
    S.tab = i
    draw()
  end
end

--- Home's keys in its buffer. While a reply is being typed, normal mode is
--- for editing it: every key does what it always does.
---@param buf integer
---@param state fun(): table|nil  Home's state, while it is open
function M.map(buf, state)
  for lhs, fn in pairs(M.KEYS) do
    vim.keymap.set('n', lhs, function()
      local S = state()
      if S and S.reply then
        return lhs
      end
      if S and S.single and NOT_SINGLE[lhs] then
        return ''
      end
      local count = vim.v.count1
      vim.schedule(function()
        -- Gone in the meantime (a key that closed it came first).
        local now = state()
        if now and vim.api.nvim_win_is_valid(now.win) then
          fn(now, count)
        end
      end)
      return ''
    end, { buffer = buf, nowait = true, expr = true, replace_keycodes = true })
  end
  for lhs, save in pairs { ['<C-s>'] = true, ['<C-c>'] = false } do
    vim.keymap.set({ 'n', 'i' }, lhs, function()
      local S = state()
      if S and S.reply then
        reply.finish(S, save)
      end
    end, { buffer = buf })
  end
end

return M
