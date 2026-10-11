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

local blocks = require 'thread.blocks'
local code = require 'thread.code'
local diff = require 'thread.review.diff'
local float = require 'thread.float'
local look = require 'thread.look'
local review = require 'thread.review'
local sheet = require 'thread.sheet'
local store = require 'thread.store'
local text = require 'thread.text'
local tour = require 'thread.tour'

local M = {}

local ns = vim.api.nvim_create_namespace 'thread.review_page'
local sel_ns = vim.api.nvim_create_namespace 'thread.review_page.sel'
local PAD = 3
local HUNK_CAP = 40 -- lines of a hunk shown here; the code has the rest

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
---@return thread.Batch|nil, thread.Comment|nil, thread.ReviewWork|nil
local function current()
  local batch = store.active()
  local owner = batch and S and store.find(batch, S.owner)
  local rv = owner and review.of(owner)
  return batch, owner, rv and review.work(rv)
end

----------------------------------------------------------------------
-- Building the screen
----------------------------------------------------------------------

local STATE = {
  accepted = { '✓', 'ThreadAccepted' },
  partial = { '◑', 'ThreadLeads' },
  changed = { '◌', 'ThreadUnexplained' },
  open = { '○', 'ThreadMeta' },
}

local function state_of(batch, owner, group)
  local st, done, total = review.state(batch, owner, group)
  local said = st == 'accepted' and 'accepted'
    or st == 'changed' and 'changed since you accepted it'
    or st == 'partial' and string.format('%d of %d hunks accepted', done, total)
    or 'not accepted yet'
  return STATE[st], said
end

--- A hunk as a diff: its removed lines, its added ones, and the lines
--- between its parts as they are now.
local function draw_hunk(P, spec, h, cap)
  local new = diff.lines(spec, h.file, 'new') or {}
  local rows = {}
  local function add(first, sign, lines, wash)
    local spans = code.syntax(lines, h.file)
    for i, l in ipairs(lines) do
      rows[#rows + 1] = { num = first + i - 1, sign = sign, line = l, spans = spans[i], wash = wash }
    end
  end
  local prev_end
  for _, part in ipairs(h.parts) do
    if prev_end then
      add(prev_end + 1, ' ', vim.list_slice(new, prev_end + 1, part.new_start - (part.new_count > 0 and 1 or 0)))
    end
    add(part.old_start, '-', part.old, 'ThreadDiffDelete')
    add(part.new_start, '+', part.new, 'ThreadDiffAdd')
    prev_end = part.new_count > 0 and (part.new_start + part.new_count - 1) or part.new_start
  end
  for i, r in ipairs(rows) do
    if i > cap then
      P.chunks { { string.format('      ⋯ %s more · o shows it whole', text.plural(#rows - cap, 'line')), 'ThreadMeta' } }
      break
    end
    blocks.code_line(P, PAD, r)
  end
end

--- A group at a glance, in columns: its size in lines and hunks, how many
--- hunks you have accepted, and the conversations in it by whose move.
local function stats(batch, owner, w, group)
  local add, del = 0, 0
  for _, x in ipairs(group.hunks) do
    if x.h then
      add, del = add + x.h.add, del + x.h.del
    end
  end
  local _, done, total = review.state(batch, owner, group)
  local out = {
    { string.format('%6s', '+' .. add), 'ThreadAdded' },
    { string.format(' %-6s', '−' .. del), 'ThreadRemoved' },
    { string.format('%3d', #group.hunks), 'ThreadTitle' },
    { #group.hunks == 1 and ' hunk  ' or ' hunks ', 'ThreadMeta' },
    { string.format('  ✓ %2d/%-2d', done, total), done == total and total > 0 and 'ThreadAccepted' or done > 0 and 'ThreadLeads' or 'ThreadMeta' },
  }
  -- Conversations, by their glyph: whose move, read or not.
  local counts, order = {}, {}
  for n, e in ipairs(w.list) do
    local t = e.review.group == group.k and tour.thread_at(batch, owner, n)
    if t then
      local g, hl = look.glyph(store.status(t), store.unseen(batch, t), false)
      if not counts[g] then
        counts[g] = { 0, hl }
        order[#order + 1] = g
      end
      counts[g][1] = counts[g][1] + 1
    end
  end
  local talk = {}
  for _, g in ipairs(order) do
    talk[#talk + 1] = { ' ' .. g .. ' ' .. counts[g][1], counts[g][2] }
  end
  -- A fixed width, so the columns line up down the list.
  out[#out + 1] = { string.rep(' ', math.max(0, 12 - text.width(talk))) }
  return vim.list_extend(out, talk)
end

--- The groups: the review's overview as one item, then a line a group.
local function draw_groups(P, batch, owner, w, width)
  local m = owner.messages[select(2, tour.of(owner))]
  P.add ''
  P.item { kind = 'intro' }
  P.chunks { { store.title(owner), 'ThreadTitle' } }
  local add, del = 0, 0
  for _, f in ipairs(w.files) do
    add, del = add + f.add, del + f.del
  end
  if w.spec then
    P.chunks {
      { w.spec.label, 'ThreadCrumbHere' },
      { string.format(' · %s ', text.plural(#w.files, 'file')), 'ThreadMeta' },
      { '+' .. add, 'ThreadAdded' },
      { ' −' .. del, 'ThreadRemoved' },
    }
  else
    P.chunks { { 'this review names no diff it can read: ' .. (w.err or '?'), 'ThreadBroken' } }
  end
  P.add ''
  blocks.prose(P, m.text, width)
  if type(m.diagram) == 'table' then
    P.add ''
    blocks.diagram(P, m.diagram, width)
  end
  P.done()
  blocks.rule(P, 'groups · ' .. review.said(batch, owner.id, w), width)
  -- What the columns on the right are.
  P.spread({}, { string.format('%-13s%-10s%-10s%12s', '  lines', ' hunks', '  accepted', 'threads'), 'ThreadMeta' }, width)
  local groups = vim.list_extend({}, w.groups)
  groups[#groups + 1] = w.rest
  for _, group in ipairs(groups) do
    local g = group.g
    local loose = group.k == 0
    local mark = state_of(batch, owner.id, group)
    P.item { kind = 'group', group = group, n = w.index['g' .. group.k] }
    local chunks = { { mark[1] .. ' ', mark[2] } }
    if loose then
      vim.list_extend(chunks, { { '⚠ ', 'ThreadUnexplained' }, { string.rep(' ', 11) } })
    else
      local risk = look.risk(g.risk, true) or { ' ', 'ThreadMeta' }
      local kind = look.kind_badge(g.kind) or { '', 'ThreadMeta' }
      -- Kinds padded to one width, so the titles line up.
      vim.list_extend(chunks, { { risk[1] .. ' ', risk[2] }, kind, { string.rep(' ', 11 - text.width(kind[1])) } })
    end
    local right = stats(batch, owner.id, w, group)
    local quiet = mark[1] == '✓' or g.kind == 'chore' or g.kind == 'style' or g.kind == 'docs'
    local title = text.fit(loose and 'not explained' or (g.title or ''), width - text.width(chunks) - text.width(right) - 3)
    chunks[#chunks + 1] = { title, loose and 'ThreadUnexplained' or (quiet and 'ThreadMeta' or 'ThreadTitle') }
    chunks[#chunks + 1] = { string.rep(' ', math.max(2, width - text.width(chunks) - text.width(right))) }
    P.chunks(vim.list_extend(chunks, right))
    P.done()
  end
  if #groups == 0 then
    P.chunks { { 'Nothing changed in ' .. (w.spec and w.spec.label or 'this diff') .. '.', 'ThreadMeta' } }
  end
end

--- One group: what it is for, its hunks, the code it affects, its tests.
local function draw_group(P, batch, owner, w, group, width)
  local g = group.g
  local loose = group.k == 0
  local n = w.index['g' .. group.k]
  P.add ''
  P.item { kind = 'body', group = group, n = n }
  local head = { { loose and 'Not explained' or (g.title or ''), 'ThreadTitle' } }
  local kind, risk = look.kind_badge(g.kind), look.risk(g.risk)
  for _, badge in ipairs { kind or false, risk or false } do
    if badge then
      vim.list_extend(head, { { '  ' }, badge })
    end
  end
  P.chunks(head)
  if risk and type(g.risk_why) == 'string' and g.risk_why ~= '' then
    P.chunks { { 'why: ', risk[2] }, { g.risk_why, 'ThreadText' } }
  end
  local mark, said = state_of(batch, owner.id, group)
  P.chunks { { mark[1] .. ' ' .. said, mark[2] } }
  P.add ''
  blocks.prose(P, loose and 'Changes no group covers: most are too small to need words. Accept them a hunk at a time, or all at once from here.' or g.body, width)
  if type(g.diagram) == 'table' then
    P.add ''
    blocks.diagram(P, g.diagram, width)
  end
  local talk = n and tour.thread_at(batch, owner.id, n)
  if talk then
    blocks.talk(P, batch, talk, width)
  end
  P.done()

  local _, done = review.state(batch, owner.id, group)
  blocks.rule(P, string.format('changes · %s · %d accepted', text.plural(#group.hunks, 'hunk'), done), width)
  for j, x in ipairs(group.hunks) do
    P.add ''
    local hn = w.index['h' .. group.k .. ':' .. j]
    local ok = x.h and review.hunk_accepted(batch, owner.id, x.h)
    P.item { kind = 'hunk', group = group, h = x.h, n = hn, accepted = ok }
    if x.h then
      local chunks = {
        { ok and '✓ ' or '○ ', ok and 'ThreadAccepted' or 'ThreadMeta' },
        { x.h.file .. ':' .. (x.h.lo == x.h.hi and tostring(x.h.lo) or (x.h.lo .. '–' .. x.h.hi)), 'Directory' },
        { '  +' .. x.h.add, 'ThreadAdded' },
        { ' −' .. x.h.del, 'ThreadRemoved' },
      }
      for _, c in ipairs(review.origins(batch, w.spec, x.h)) do
        vim.list_extend(chunks, { { '   from ', 'ThreadMeta' }, { '#' .. c.id, 'ThreadLink' }, { ' ' .. text.fit(store.title(c), 30), 'ThreadMeta' } })
      end
      P.chunks(chunks)
      if x.ref and x.ref.note then
        P.chunks({ { x.ref.note, 'ThreadNote' } }, PAD + 2)
      end
      draw_hunk(P, w.spec, x.h, S.opened == 'hunk:' .. tostring(hn) and math.huge or HUNK_CAP)
    else
      P.chunks { { '⚠ ' .. (x.ref and x.ref.file or '?') .. ': this hunk is no longer in the diff', 'ThreadBroken' } }
    end
    local t = hn and tour.thread_at(batch, owner.id, hn)
    if t then
      blocks.talk(P, batch, t, width)
    end
    P.done()
  end
  for _, aside in ipairs { 'affected', 'tests' } do
    local items = group[aside]
    if #items > 0 then
      blocks.rule(P, (aside == 'tests' and 'tests' or 'affected, not changed') .. ' · ' .. #items, width)
      for j, it in ipairs(items) do
        local an = w.index[aside .. group.k .. ':' .. j]
        P.item { kind = aside, group = group, n = an }
        local where = vim.fs.basename(it.file or '?') .. ':' .. (it.line or '–')
        local t = an and tour.thread_at(batch, owner.id, an)
        local right = t and (look.glyph(store.status(t), store.unseen(batch, t), false) .. '  ' .. where) or where
        P.spread({ { text.fit(it.note or it.file or '', width - text.width(right) - 4), 'ThreadText' } }, { right, 'LineNr' }, width)
        if t then
          blocks.talk(P, batch, t, width)
        end
        P.done()
      end
    end
  end
  P.add ''
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
    draw_group(P, batch, owner, w, group, width)
  else
    draw_groups(P, batch, owner, w, width)
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
  local view = vim.api.nvim_win_call(S.win, vim.fn.winsaveview)
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
    vim.fn.winrestview(view)
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
    return owner and require('thread.home').focus { comment = owner, reply = true }
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
