--- A review on its own screen: the level above the code, where you read a
--- review and act on it. Two views fill the editor:
---
--- - **the groups**: the review's overview, then a line per group;
--- - **a group**: what it is for, then each of its hunks as a diff, then
---   the code it affects and its tests.
---
--- `j`/`k` go from one item to the next (the overview, a group, a hunk),
--- and every key acts on the item you are on: `a` accepts it, `r` replies
--- on it, `⏎` (or `J`) goes into it, `K` back out. `o` opens an item: a
--- hunk shown whole, the cursor let in to read it as text. `⏎` on a hunk
--- walks the group's hunks in the code; `K` there brings you back here,
--- on the hunk you were on. `q` closes it all.

local view = require 'thread.review.screen.view'
local float = require 'thread.float'
local look = require 'thread.look'
local review = require 'thread.review'
local sheet = require 'thread.sheet'
local store = require 'thread.store'
local text = require 'thread.text'

local M = {}

local ns = vim.api.nvim_create_namespace 'thread.review_page'
local sel_ns = vim.api.nvim_create_namespace 'thread.review_page.sel'
local PAD = view.PAD

---@class thread.ReviewItem: thread.Item
---@field kind 'intro'|'group'|'body'|'hunk'|'affected'|'tests'
---@field n integer|nil  its stop in the review's walk
---@field group thread.ReviewGroup|nil
---@field h thread.ReviewHunk|nil
---@field accepted boolean|nil

---@class thread.ReviewPageState
---@field win integer
---@field buf integer
---@field owner integer
---@field k integer|nil   the group shown; nil: the groups
---@field items thread.ReviewItem[]
---@field cur integer     the item you are on
---@field free boolean    the cursor is let into the item
---@field opened string|nil  the item opened with `o`, by its key
---@type thread.ReviewPageState|nil
local S

function M.is_open()
  return S ~= nil and vim.api.nvim_win_is_valid(S.win)
end

function M.close()
  if M.is_open() then
    float.close(S.win)
  end
  S = nil
end

--- The review open here: its thread, and its worked-out diff and groups.
---@return thread.Batch|nil, thread.Thread|nil, thread.ReviewWork|nil
local function current()
  local batch = store.active()
  local owner = batch and S and store.find(batch, S.owner)
  local rv = owner and review.of(owner)
  return batch, owner, rv and review.work(rv)
end

----------------------------------------------------------------------
-- Keys: what each does on the item you are on
----------------------------------------------------------------------

local function item()
  return S and S.items[S.cur]
end

local function keys_for(it, batch, owner)
  local list = { { 'j/k', S.k and 'items' or 'groups' } }
  local function add(k, label)
    list[#list + 1] = { k, label }
  end
  if it then
    if it.kind == 'intro' then
      add('⏎', 'the first group')
    elseif it.kind == 'group' then
      add('⏎', 'open it')
      add('a', review.state(batch, owner, it.group) == 'accepted' and 'unaccept it' or 'accept it')
    elseif it.kind == 'body' then
      add('⏎', 'walk its hunks')
      add('a', review.state(batch, owner, it.group) == 'accepted' and 'unaccept them all' or 'accept them all')
    elseif it.kind == 'hunk' then
      add('⏎', 'walk from here')
      if it.h then
        add('a', review.hunk_accepted(batch, owner, it.h) and 'unaccept' or 'accept')
      end
    else
      add('⏎', 'go through them in the code')
    end
    add('r', 'reply')
    if it.kind == 'intro' or it.kind == 'body' or it.kind == 'hunk' then
      add('o', 'open')
    end
  end
  if S.k then
    add('L/H', 'groups')
  end
  add('K', S.k and 'the groups' or 'Home (reviews)')
  add('q', 'close')
  return list
end

local function footer()
  if S.free then
    return look.footer { { 'o/Esc', 'close it' } }
  end
  local batch = store.active()
  return look.footer(keys_for(item(), batch, S.owner))
end

--- Light up the item you are on, and bring it into view.
local function select(i, keep)
  if not M.is_open() or #S.items == 0 then
    return
  end
  S.cur = math.max(1, math.min(#S.items, i))
  local it = S.items[S.cur]
  vim.api.nvim_buf_clear_namespace(S.buf, sel_ns, 0, -1)
  for row = it.first, it.last do
    pcall(vim.api.nvim_buf_set_extmark, S.buf, sel_ns, row, 0, {
      virt_text = { { '▌', 'ThreadFocus' } },
      virt_text_pos = 'overlay',
      line_hl_group = 'ThreadZone',
    })
  end
  if not keep then
    -- The end first, then the start: as much of it on screen as fits.
    pcall(vim.api.nvim_win_set_cursor, S.win, { math.min(vim.api.nvim_buf_line_count(S.buf), it.last + 2), 0 })
    pcall(vim.api.nvim_win_set_cursor, S.win, { it.first + 1, PAD })
  end
  vim.api.nvim_win_set_config(S.win, { footer = footer(), footer_pos = 'right' })
end

local function draw()
  local batch, owner, w = current()
  if not w then
    return M.close()
  end
  local group = S.k and (S.k == 0 and w.rest or w.groups[S.k])
  if S.k and not group then
    S.k = nil
  end
  local cfg = float.full()
  local width = cfg.width - PAD * 2
  local P = sheet.new { indent = PAD }
  if group then
    view.group(P, batch, owner, w, group, width, S.opened)
  else
    view.groups(P, batch, owner, w, width)
  end
  P.add ''
  -- An accepted hunk has a green bar down its side.
  P.done()
  for _, it in ipairs(P.items) do
    if it.accepted then
      for row = it.first, it.last do
        if P.lines[row + 1] ~= '' then
          P.mark(row, 1, { virt_text = { { '▐', 'ThreadAccepted' } }, virt_text_pos = 'overlay' })
        end
      end
    end
  end
  P.apply(S.buf, ns)
  S.items = P.items
  local pos = not group and 'the groups' or group.k == 0 and 'not explained' or string.format('group %d/%d', group.k, #w.groups)
  cfg.title = { { ' ▶ ', 'ThreadLeads' }, { text.fit(store.title(owner), 60), 'ThreadTitle' }, { ' · ' .. pos .. ' ', 'ThreadCrumb' } }
  vim.api.nvim_win_set_config(S.win, cfg)
end

--- Draw again, staying on the same item.
function M.refresh()
  if not M.is_open() then
    return
  end
  local it = item()
  local key = it and (it.kind .. ':' .. tostring(it.n))
  local saved = vim.api.nvim_win_call(S.win, vim.fn.winsaveview)
  draw()
  if not M.is_open() then
    return
  end
  local at = S.cur
  for i, x in ipairs(S.items) do
    if key == x.kind .. ':' .. tostring(x.n) then
      at = i
    end
  end
  vim.api.nvim_win_call(S.win, function()
    vim.fn.winrestview(saved)
  end)
  select(at, true)
end

--- Show the groups, or group `k`, on the item for stop `n` if given; a
--- group starts on its first hunk.
local function show(k, n)
  S.k, S.free, S.opened = k, false, nil
  draw()
  local at = 1
  for i, it in ipairs(S.items) do
    if (n and it.n == n) or (not n and k and it.kind == 'hunk') then
      at = i
      break
    end
  end
  vim.api.nvim_win_set_cursor(S.win, { 1, 0 })
  select(at)
  if S.items[at] and S.items[at].first + 6 <= vim.api.nvim_win_get_height(S.win) then
    -- Its start fits with the top of the screen in view: keep the group's
    -- words on screen.
    vim.api.nvim_win_call(S.win, function()
      vim.fn.winrestview { topline = 1 }
    end)
  end
end

local function step_group(d)
  local _, _, w = current()
  if not (w and S.k) then
    return
  end
  local order = {}
  for _, g in ipairs(w.groups) do
    order[#order + 1] = g.k
  end
  if w.rest then
    order[#order + 1] = 0
  end
  for i, k in ipairs(order) do
    if k == S.k then
      local to = order[i + d]
      if to == nil then
        return vim.notify(d > 0 and 'thread: the last group' or 'thread: the first group')
      end
      return show(to)
    end
  end
end

local function enter()
  local batch, owner, w = current()
  if not w then
    return
  end
  local id, at = text.link_at(vim.api.nvim_get_current_line(), vim.api.nvim_win_get_cursor(S.win)[2])
  if id and store.find(batch, id) then
    M.close()
    return require('thread.actions').follow_link(id, at)
  end
  local it = item()
  if not it then
    return
  elseif it.kind == 'intro' then
    local first = w.groups[1] or w.rest
    return first and show(first.k)
  elseif it.kind == 'group' then
    return show(it.group.k)
  end
  local n = it.kind == 'body' and w.index['h' .. it.group.k .. ':1'] or it.n
  if n then
    M.close()
    require('thread.walk').start(owner.id, n)
  end
end

local function accept()
  local batch, owner = current()
  local it = item()
  if not (owner and it) then
    return
  end
  if it.kind == 'hunk' and it.h then
    local on = review.toggle_hunk(batch, owner.id, it.group, it.h)
    M.refresh()
    if on then
      -- On to the next hunk, as you would after reading one.
      for i = S.cur + 1, #S.items do
        if S.items[i].kind == 'hunk' then
          select(i)
          break
        end
      end
    end
  elseif it.kind == 'group' or it.kind == 'body' then
    review.toggle(batch, owner.id, it.group)
    M.refresh()
    if it.kind == 'group' then
      select(S.cur + 1)
    end
  else
    return vim.notify 'thread: on a hunk, a accepts it; on a group, all of its hunks'
  end
  require('thread.home').refresh()
end

local function reply()
  local it = item()
  if it and it.kind == 'intro' then
    local _, owner = current()
    M.close()
    return owner and require('thread.home').focus { thread = owner, reply = true }
  end
  if it and it.n then
    require('thread.actions').reply_stop(S.owner, it.n)
  end
end

--- `K`: from a group to the groups, from the groups to Home's review tab.
local function up()
  if S.free then
    return
  end
  if not S.k then
    local owner = S.owner
    M.close()
    return require('thread.home').open { view = 'review', focus = 'v:' .. owner }
  end
  local k = S.k
  show(nil)
  for i, it in ipairs(S.items) do
    if it.kind == 'group' and it.group.k == k then
      select(i)
    end
  end
end

--- `o`: open the item you are on: a hunk shown whole, and the cursor let
--- in to read it as text. Again (or Esc), closed.
local function free(on)
  S.free = on
  if on then
    local it = item()
    if it and it.kind == 'hunk' then
      S.opened = 'hunk:' .. tostring(it.n)
      M.refresh()
      it = item()
    end
    vim.api.nvim_buf_clear_namespace(S.buf, sel_ns, 0, -1)
    if it then
      pcall(vim.api.nvim_win_set_cursor, S.win, { it.first + 1, PAD })
    end
    vim.api.nvim_win_set_config(S.win, { footer = footer(), footer_pos = 'right' })
    return
  end
  -- Back to the item the cursor is in, closed again.
  local row = vim.api.nvim_win_get_cursor(S.win)[1] - 1
  for i, x in ipairs(S.items) do
    if row >= x.first and row <= x.last then
      S.cur = i
    end
  end
  if S.opened then
    S.opened = nil
    M.refresh()
  end
  select(S.cur)
end

--- j and k step through the items; in an item let in with `o`, they move
--- the cursor as ever.
local function stepper(lhs, d)
  return function()
    if S.free then
      return lhs
    end
    local count = vim.v.count1
    vim.schedule(function()
      select(S.cur + d * count)
    end)
    return ''
  end
end

--- Open a review's screen: its groups, or the group stop `n` is in, on
--- that stop's item.
---@param opts { owner: integer, n: integer|nil }
function M.open(opts)
  local batch = store.active()
  local owner = batch and store.find(batch, opts.owner)
  local rv = owner and review.of(owner)
  if not rv then
    return
  end
  require('thread.page').close()
  if M.is_open() then
    vim.api.nvim_set_current_win(S.win)
  else
    local win, buf = float.open {
      filetype = 'thread-review',
      win = vim.tbl_extend('force', float.full(), { title = ' ', footer = ' ', zindex = 50 }),
      wo = { wrap = false, cursorline = false, winhighlight = 'NormalFloat:Normal,FloatBorder:ThreadBorderInfo' },
      keys = {
        o = function()
          free(not S.free)
        end,
        ['<Esc>'] = function()
          if S.free then
            free(false)
          else
            M.close()
          end
        end,
        q = M.close,
        K = up,
        ['<BS>'] = up,
        ['<CR>'] = enter,
        J = enter,
        a = accept,
        r = reply,
        L = function()
          step_group(1)
        end,
        H = function()
          step_group(-1)
        end,
      },
    }
    vim.keymap.set('n', 'j', stepper('j', 1), { buffer = buf, nowait = true, expr = true })
    vim.keymap.set('n', 'k', stepper('k', -1), { buffer = buf, nowait = true, expr = true })
    vim.api.nvim_create_autocmd('VimResized', { buffer = buf, callback = M.refresh })
    S = { win = win, buf = buf, items = {}, cur = 1, free = false }
  end
  S.owner = opts.owner
  local e = opts.n and review.work(rv).list[opts.n]
  if e and e.review then
    show(e.review.group, opts.n)
  else
    show(nil)
  end
end

--- The review open here, and the stop of the item you are on.
function M.state()
  if not M.is_open() then
    return nil
  end
  local it = item()
  return { owner = S.owner, k = S.k, n = it and it.n }
end

return M
