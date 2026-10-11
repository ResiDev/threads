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

local anchor = require 'thread.anchor'
local look = require 'thread.look'
local render = require 'thread.render'
local review = require 'thread.review'
local store = require 'thread.store'
local tour = require 'thread.tour'

local M = {}

local ns = vim.api.nvim_create_namespace 'thread.review_page'
local sel_ns = vim.api.nvim_create_namespace 'thread.review_page.sel'
local width_of = vim.fn.strdisplaywidth
local PAD = 3
local HUNK_CAP = 40 -- lines of a hunk shown here; the code has the rest

---@class thread.ReviewItem
---@field kind 'intro'|'group'|'body'|'hunk'|'affected'|'tests'
---@field first integer  its first row, 1-based
---@field last integer
---@field n integer|nil  its stop in the review's walk
---@field group thread.ReviewGroup|nil
---@field h thread.ReviewHunk|nil

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
    vim.api.nvim_win_close(S.win, true)
  end
  S = nil
end

local function fit(s, w)
  if w <= 1 then
    return ''
  end
  if width_of(s) <= w then
    return s
  end
  local out = vim.fn.strcharpart(s, 0, w - 1)
  while width_of(out) > w - 1 do
    out = vim.fn.strcharpart(out, 0, vim.fn.strchars(out) - 1)
  end
  return out .. '…'
end

local function plural(n, one, many)
  return n .. ' ' .. (n == 1 and one or (many or one .. 's'))
end

----------------------------------------------------------------------
-- Building the screen
----------------------------------------------------------------------

local function builder()
  local P = { lines = {}, hls = {}, items = {} }
  function P.add(text)
    P.lines[#P.lines + 1] = text
    return #P.lines - 1
  end
  function P.hl(row, s, e, group)
    P.hls[#P.hls + 1] = { row, s, e, group }
  end
  function P.chunks(chunks, indent)
    local text = string.rep(' ', indent or PAD)
    local spans = {}
    for _, c in ipairs(chunks) do
      spans[#spans + 1] = { #text, #text + #c[1], c[2] }
      text = text .. c[1]
    end
    local row = P.add(text)
    for _, sp in ipairs(spans) do
      if sp[3] then
        P.hl(row, sp[1], sp[2], sp[3])
      end
    end
    return row
  end
  --- Chunks on the left, and one more pushed to the right edge.
  function P.spread(chunks, right, width)
    local used = PAD
    for _, c in ipairs(chunks) do
      used = used + width_of(c[1])
    end
    if right then
      chunks[#chunks + 1] = { string.rep(' ', math.max(2, width + PAD - used - width_of(right[1]))) .. right[1], right[2] }
    end
    return P.chunks(chunks)
  end
  --- Start an item at the next row; `P.done()` closes it.
  function P.item(it)
    it.first = #P.lines + 1
    P.items[#P.items + 1] = it
    P.open = it
  end
  function P.done()
    if P.open then
      P.open.last = math.max(P.open.first, #P.lines)
      P.open = nil
    end
  end
  function P.rule(label, width)
    P.add ''
    P.chunks { { '── ' .. label .. ' ', 'ThreadCrumb' }, { string.rep('─', math.max(2, width - width_of(label) - 4)), 'ThreadTabRule' } }
  end
  return P
end

--- Prose, wrapped, with `code`, **bold** and links picked out, and
--- excerpts drawn as the code they point at.
local function prose(P, text, width)
  for _, l in ipairs(require('thread.text').wrap(text or '', width)) do
    if l.excerpt then
      local a = l.excerpt
      local lines = anchor.lines_of { file = a.file }
      local loc = lines and anchor.locate({ file = a.file, text = a.text or '', line = a.line }, lines)
      if not loc then
        P.chunks { { '▤ ' .. a.file .. ' · its line is gone', 'ThreadBroken' } }
      else
        local count = math.max(1, math.min(15, tonumber(a.lines) or 6))
        local lo, hi = loc.line, math.min(#lines, loc.line + count - 1)
        P.chunks { { a.file .. ':' .. lo, 'Directory' } }
        local slice = vim.list_slice(lines, lo, hi)
        local spans = require('thread.home').syntax(slice, a.file)
        for i, code in ipairs(slice) do
          local prefix = string.rep(' ', PAD) .. string.format('%4d  ', lo + i - 1)
          local row = P.add(prefix .. code:gsub('\t', '    '))
          P.hl(row, PAD, PAD + 4, 'LineNr')
          if not code:find '\t' then
            for _, sp in ipairs(spans[i] or {}) do
              P.hl(row, #prefix + sp[1], #prefix + sp[2], sp[3])
            end
          end
        end
      end
    else
      P.chunks(require('thread.text').segments(l))
    end
  end
end

local function draw_diagram(P, raw, width)
  local d, err = require('thread.diagram').validate(raw)
  if not d then
    P.chunks { { 'diagram: ' .. (err or '?'), 'ThreadBroken' } }
    return
  end
  local drawn = require('thread.diagram').render(d, { max_width = width })
  for _, chunks in ipairs(drawn.rows) do
    local row = P.chunks(chunks)
    P.lines[row + 1] = P.lines[row + 1]:gsub('%s+$', '')
  end
end

--- The conversation on an item, if you have started one: a chat, as in
--- the float.
local function draw_talk(P, batch, c, width)
  local g, ghl = look.glyph(store.status(c), store.unseen(batch, c), false)
  P.add ''
  P.chunks { { g .. ' ', ghl }, { 'your thread here · ' .. store.status(c), 'ThreadMeta' } }
  for i, m in ipairs(c.messages) do
    local time = require('thread.text').ago(store.when(batch, c, i))
    if m.from ~= 'you' then
      local label = look.label(m)
      for j, l in ipairs(require('thread.text').wrap(m.text or '', render.side(width, 3))) do
        local chunks = { { j == 1 and (label .. string.rep(' ', 3 - width_of(label))) or '   ', 'ThreadAgent' } }
        vim.list_extend(chunks, require('thread.text').segments(l))
        if j == 1 and time then
          local used = 0
          for _, ch in ipairs(chunks) do
            used = used + width_of(ch[1])
          end
          chunks[#chunks + 1] = { string.rep(' ', math.max(2, width - used - width_of(time))) .. time, 'ThreadMeta' }
        end
        P.chunks(chunks)
      end
    else
      for _, r in ipairs(render.chat(m.text, width, 3, time)) do
        P.chunks(r)
      end
    end
  end
  store.mark_seen(batch, c)
end

--- A group's kind, padded so the titles after it line up.
local function kind_chunk(g)
  local kind = look.kind_badge(g.kind) or { '', 'ThreadMeta' }
  return { kind[1], kind[2] }, { string.rep(' ', 11 - width_of(kind[1])) }
end

local STATE = {
  accepted = { '✓', 'ThreadAccepted' },
  partial = { '◑', 'ThreadLeads' },
  changed = { '◌', 'ThreadUnexplained' },
  open = { '○', 'ThreadMeta' },
}

local function state_of(batch, owner, group)
  local st, done, total = review.state(batch, owner, group)
  local mark = STATE[st]
  local said = st == 'accepted' and 'accepted'
    or st == 'changed' and 'changed since you accepted it'
    or st == 'partial' and string.format('%d of %d hunks accepted', done, total)
    or 'not accepted yet'
  return mark, said, st
end

local function hunk_span(h)
  return h.file .. ':' .. (h.lo == h.hi and tostring(h.lo) or (h.lo .. '–' .. h.hi))
end

--- A hunk as a diff: its removed lines, its added ones, and the lines
--- between its parts as they are now.
local function draw_hunk(P, batch, spec, h, cap)
  local syntax = require('thread.home').syntax
  local new = review.lines(spec, h.file, 'new') or {}
  local rows = {}
  local prev_end
  for _, part in ipairs(h.parts) do
    if prev_end then
      local between = vim.list_slice(new, prev_end + 1, part.new_start - (part.new_count > 0 and 1 or 0))
      local spans = syntax(between, h.file)
      for i, l in ipairs(between) do
        rows[#rows + 1] = { prev_end + i, ' ', l, nil, spans[i] }
      end
    end
    local old_spans = syntax(part.old, h.file)
    for i, l in ipairs(part.old) do
      rows[#rows + 1] = { part.old_start + i - 1, '-', l, 'ThreadDiffDelete', old_spans[i] }
    end
    local new_spans = syntax(part.new, h.file)
    for i, l in ipairs(part.new) do
      rows[#rows + 1] = { part.new_start + i - 1, '+', l, 'ThreadDiffAdd', new_spans[i] }
    end
    prev_end = part.new_count > 0 and (part.new_start + part.new_count - 1) or part.new_start
  end
  for i, r in ipairs(rows) do
    if i > cap then
      P.chunks { { string.format('      ⋯ %s more · o shows it whole', plural(#rows - cap, 'line')), 'ThreadMeta' } }
      break
    end
    local prefix = string.rep(' ', PAD) .. string.format('%4d %s ', r[1], r[2])
    local text = (r[3]:gsub('\t', '    '))
    local row = P.add(prefix .. text)
    P.hl(row, PAD, PAD + 4, 'LineNr')
    if r[4] then
      P.hl(row, PAD + 5, -1, r[4])
    end
    if not r[3]:find '\t' then
      for _, sp in ipairs(r[5] or {}) do
        P.hl(row, #prefix + sp[1], #prefix + sp[2], sp[3])
      end
    end
  end
end

--- A group at a glance, in columns: its size in lines and hunks, how many
--- hunks you have accepted, and the conversations in it by whose move.
local function stats(batch, owner, w, group)
  local add, del, hunks = 0, 0, 0
  for _, x in ipairs(group.hunks) do
    if x.h then
      add, del, hunks = add + x.h.add, del + x.h.del, hunks + 1
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
    if e.review.group == group.k then
      local t = tour.thread_at(batch, owner, n)
      if t then
        local g, hl = look.glyph(store.status(t), store.unseen(batch, t), false)
        if not counts[g] then
          counts[g] = { 0, hl }
          order[#order + 1] = g
        end
        counts[g][1] = counts[g][1] + 1
      end
    end
  end
  local talk = ''
  local talk_chunks = {}
  for _, g in ipairs(order) do
    local piece = ' ' .. g .. ' ' .. counts[g][1]
    talk = talk .. piece
    talk_chunks[#talk_chunks + 1] = { piece, counts[g][2] }
  end
  -- A fixed width, so the columns line up down the list.
  out[#out + 1] = { string.rep(' ', math.max(0, 12 - width_of(talk))) }
  vim.list_extend(out, talk_chunks)
  return out
end

--- The groups: the review's overview as one item, then a line a group.
local function draw_groups(P, batch, owner, w, width)
  local rv = review.of(owner)
  local _, index = tour.of(owner)
  local m = owner.messages[index]
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
      { string.format(' · %s ', plural(#w.files, 'file')), 'ThreadMeta' },
      { '+' .. add, 'ThreadAdded' },
      { ' −' .. del, 'ThreadRemoved' },
    }
  else
    P.chunks { { 'this review names no diff it can read: ' .. (w.err or '?'), 'ThreadBroken' } }
  end
  P.add ''
  prose(P, m.text, width)
  if type(m.diagram) == 'table' then
    P.add ''
    draw_diagram(P, m.diagram, width)
  end
  P.done()
  P.rule('groups · ' .. review.said(batch, owner.id, w), width)
  -- What the columns on the right are.
  P.spread({}, { string.format('%-13s%-10s%-10s%12s', '  lines', ' hunks', '  accepted', 'threads'), 'ThreadMeta' }, width)
  local groups = vim.list_extend({}, w.groups)
  if w.rest then
    groups[#groups + 1] = w.rest
  end
  for _, group in ipairs(groups) do
    local g = group.g
    local loose = group.k == 0
    local mark = state_of(batch, owner.id, group)
    local n = w.index['g' .. group.k]
    P.item { kind = 'group', group = group, n = n }
    local chunks = { { mark[1] .. ' ', mark[2] } }
    if loose then
      chunks[#chunks + 1] = { '⚠ ', 'ThreadUnexplained' }
      chunks[#chunks + 1] = { string.rep(' ', 11) }
    else
      local risk = look.risk(g.risk, true) or { ' ', 'ThreadMeta' }
      chunks[#chunks + 1] = { risk[1] .. ' ', risk[2] }
      local kind, gap = kind_chunk(g)
      chunks[#chunks + 1] = kind
      chunks[#chunks + 1] = gap
    end
    local right = stats(batch, owner.id, w, group)
    local used = PAD
    for _, c in ipairs(chunks) do
      used = used + width_of(c[1])
    end
    local right_w = 0
    for _, c in ipairs(right) do
      right_w = right_w + width_of(c[1])
    end
    local quiet = mark[1] == '✓' or g.kind == 'chore' or g.kind == 'style' or g.kind == 'docs'
    local title = fit(loose and 'not explained' or (g.title or ''), width + PAD - used - right_w - 3)
    chunks[#chunks + 1] = { title, loose and 'ThreadUnexplained' or (quiet and 'ThreadMeta' or 'ThreadTitle') }
    chunks[#chunks + 1] = { string.rep(' ', math.max(2, width + PAD - used - width_of(title) - right_w)) }
    vim.list_extend(chunks, right)
    P.chunks(chunks)
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
  local kind = look.kind_badge(g.kind)
  if kind then
    head[#head + 1] = { '  ' }
    head[#head + 1] = kind
  end
  local risk = look.risk(g.risk)
  if risk then
    head[#head + 1] = { '  ' }
    head[#head + 1] = risk
  end
  P.chunks(head)
  if risk and type(g.risk_why) == 'string' and g.risk_why ~= '' then
    P.chunks { { 'why: ', risk[2] }, { g.risk_why, 'ThreadText' } }
  end
  local mark, said = state_of(batch, owner.id, group)
  P.chunks { { mark[1] .. ' ' .. said, mark[2] } }
  P.add ''
  if loose then
    prose(P, 'Changes no group covers: most are too small to need words. Accept them a hunk at a time, or all at once from here.', width)
  else
    prose(P, g.body, width)
  end
  if type(g.diagram) == 'table' then
    P.add ''
    draw_diagram(P, g.diagram, width)
  end
  local talk = n and tour.thread_at(batch, owner.id, n)
  if talk then
    draw_talk(P, batch, talk, width)
  end
  P.done()

  local _, done, total = review.state(batch, owner.id, group)
  P.rule(string.format('changes · %s · %d accepted', plural(#group.hunks, 'hunk'), done), width)
  for j, x in ipairs(group.hunks) do
    P.add ''
    local hn = w.index['h' .. group.k .. ':' .. j]
    P.item { kind = 'hunk', group = group, h = x.h, n = hn }
    local ok = x.h and review.hunk_accepted(batch, owner.id, x.h)
    P.open.accepted = ok
    if x.h then
      local chunks = {
        { ok and '✓ ' or '○ ', ok and 'ThreadAccepted' or 'ThreadMeta' },
        { hunk_span(x.h), 'Directory' },
        { '  +' .. x.h.add, 'ThreadAdded' },
        { ' −' .. x.h.del, 'ThreadRemoved' },
      }
      for _, c in ipairs(review.origins(batch, w.spec, x.h)) do
        chunks[#chunks + 1] = { '   from ', 'ThreadMeta' }
        chunks[#chunks + 1] = { '#' .. c.id, 'ThreadLink' }
        chunks[#chunks + 1] = { ' ' .. fit(store.title(c), 30), 'ThreadMeta' }
      end
      P.chunks(chunks)
      if x.ref and x.ref.note then
        P.chunks({ { x.ref.note, 'ThreadNote' } }, PAD + 2)
      end
      draw_hunk(P, batch, w.spec, x.h, S.opened == 'hunk:' .. tostring(hn) and math.huge or HUNK_CAP)
    else
      P.chunks { { '⚠ ' .. (x.ref and x.ref.file or '?') .. ': this hunk is no longer in the diff', 'ThreadBroken' } }
    end
    local t = hn and tour.thread_at(batch, owner.id, hn)
    if t then
      draw_talk(P, batch, t, width)
    end
    P.done()
  end
  for _, aside in ipairs { 'affected', 'tests' } do
    local items = group[aside]
    if #items > 0 then
      P.rule((aside == 'tests' and 'tests' or 'affected, not changed') .. ' · ' .. #items, width)
      for j, it in ipairs(items) do
        local an = w.index[aside .. group.k .. ':' .. j]
        P.item { kind = aside, group = group, n = an }
        local where = vim.fs.basename(it.file or '?') .. ':' .. (it.line or '–')
        local t = an and tour.thread_at(batch, owner.id, an)
        local right = where
        if t then
          right = look.glyph(store.status(t), store.unseen(batch, t), false) .. '  ' .. where
        end
        P.spread({ { fit(it.note or it.file or '', width - width_of(right) - 4), 'ThreadText' } }, { right, 'LineNr' }, width)
        if t then
          draw_talk(P, batch, t, width)
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
  local list = {}
  local function add(k, label)
    list[#list + 1] = { k, label }
  end
  add('j/k', S.k and 'items' or 'groups')
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

local function footer(batch, owner)
  local out = { { ' ' } }
  for _, k in ipairs(keys_for(item(), batch, owner)) do
    out[#out + 1] = { k[1], 'ThreadKey' }
    out[#out + 1] = { ' ' .. k[2] .. '  ', 'ThreadKeyLabel' }
  end
  if S.free then
    out = { { ' ' }, { 'o', 'ThreadKey' }, { ' or ', 'ThreadKeyLabel' }, { 'Esc', 'ThreadKey' }, { ' close it  ', 'ThreadKeyLabel' } }
  end
  return out
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
    pcall(vim.api.nvim_buf_set_extmark, S.buf, sel_ns, row - 1, 0, {
      virt_text = { { '▌', 'ThreadFocus' } },
      virt_text_pos = 'overlay',
      line_hl_group = 'ThreadZone',
    })
  end
  if not keep then
    -- The end first, then the start: as much of it on screen as fits.
    local count = vim.api.nvim_buf_line_count(S.buf)
    pcall(vim.api.nvim_win_set_cursor, S.win, { math.min(count, it.last + 1), 0 })
    pcall(vim.api.nvim_win_set_cursor, S.win, { it.first, PAD })
  end
  local batch = store.active()
  local owner = batch and store.find(batch, S.owner)
  if owner then
    vim.api.nvim_win_set_config(S.win, { footer = footer(batch, owner.id), footer_pos = 'right' })
  end
end

local function draw()
  local batch = store.active()
  local owner = batch and store.find(batch, S.owner)
  local rv = owner and review.of(owner)
  if not rv then
    return M.close()
  end
  local w = review.work(rv)
  local group = S.k and (S.k == 0 and w.rest or w.groups[S.k])
  if S.k and not group then
    S.k = nil
  end
  local cols = vim.o.columns - 2
  local width = cols - PAD * 2
  local P = builder()
  if group then
    draw_group(P, batch, owner, w, group, width)
  else
    draw_groups(P, batch, owner, w, width)
  end
  P.add ''
  S.items = P.items
  vim.bo[S.buf].modifiable = true
  vim.api.nvim_buf_set_lines(S.buf, 0, -1, false, P.lines)
  vim.bo[S.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(S.buf, ns, 0, -1)
  for _, h in ipairs(P.hls) do
    local len = #(P.lines[h[1] + 1] or '')
    pcall(vim.api.nvim_buf_set_extmark, S.buf, ns, h[1], math.min(h[2], len), { end_col = (h[3] < 0 or h[3] > len) and len or h[3], hl_group = h[4] })
  end
  -- An accepted hunk has a green bar down its side.
  for _, it in ipairs(S.items) do
    if it.accepted then
      for row = it.first, it.last do
        if (P.lines[row] or '') ~= '' then
          pcall(vim.api.nvim_buf_set_extmark, S.buf, ns, row - 1, 1, { virt_text = { { '▐', 'ThreadAccepted' } }, virt_text_pos = 'overlay' })
        end
      end
    end
  end
  local title = { { ' ▶ ', 'ThreadLeads' }, { fit(store.title(owner), 60), 'ThreadTitle' } }
  if group then
    local pos = group.k == 0 and 'not explained' or string.format('group %d/%d', group.k, #w.groups)
    title[#title + 1] = { ' · ' .. pos .. ' ', 'ThreadCrumb' }
  else
    title[#title + 1] = { ' · the groups ', 'ThreadCrumb' }
  end
  vim.api.nvim_win_set_config(S.win, {
    relative = 'editor',
    row = 0,
    col = 0,
    width = cols,
    height = vim.o.lines - vim.o.cmdheight - 3,
    title = title,
  })
end

--- Draw again, staying on the same item.
function M.refresh()
  if not M.is_open() then
    return
  end
  local it = item()
  local key = it and (it.kind .. ':' .. tostring(it.n))
  local view = vim.fn.winsaveview()
  draw()
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

--- Show the groups, or group `k`, on the item for stop `n` if given.
local function show(k, n, kind)
  S.k, S.free, S.opened = k, false, nil
  draw()
  local at = 1
  for i, it in ipairs(S.items) do
    if (n and it.n == n) or (kind and it.kind == kind and not n) then
      at = i
      break
    end
  end
  if not n and not kind and k then
    -- A group: start on its first hunk, the body above it in view.
    for i, it in ipairs(S.items) do
      if it.kind == 'hunk' then
        at = i
        break
      end
    end
  end
  vim.api.nvim_win_set_cursor(S.win, { 1, 0 })
  select(at)
  if S.items[at] and S.items[at].first + 5 <= vim.api.nvim_win_get_height(S.win) then
    -- Its start fits with the top of the screen in view: keep the group's
    -- words on screen.
    vim.api.nvim_win_call(S.win, function()
      vim.fn.winrestview { topline = 1 }
    end)
  end
end

local function step_group(d)
  local batch = store.active()
  local owner = batch and store.find(batch, S.owner)
  local w = owner and review.work(review.of(owner))
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
  local batch = store.active()
  local owner = batch and store.find(batch, S.owner)
  if not owner then
    return
  end
  local id, at = require('thread.text').link_at(vim.api.nvim_get_current_line(), vim.api.nvim_win_get_cursor(S.win)[2])
  if id and store.find(batch, id) then
    M.close()
    return render.follow_link(id, at)
  end
  local it = item()
  if not it then
    return
  end
  local w = review.work(review.of(owner))
  if it.kind == 'intro' then
    local first = w.groups[1] or w.rest
    return first and show(first.k)
  elseif it.kind == 'group' then
    return show(it.group.k)
  end
  local n = it.n
  if it.kind == 'body' then
    n = w.index['h' .. it.group.k .. ':1']
  end
  if not n then
    return
  end
  M.close()
  require('thread.walk').start(owner.id, n)
end

local function accept()
  local batch = store.active()
  local owner = batch and store.find(batch, S.owner)
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
  pcall(function()
    require('thread.home').refresh()
  end)
end

local function reply()
  local it = item()
  if not it then
    return
  end
  if it.kind == 'intro' then
    local batch = store.active()
    local owner = batch and store.find(batch, S.owner)
    M.close()
    return owner and require('thread.home').focus { comment = owner, reply = true }
  end
  if it.n then
    require('thread.actions').reply_stop(S.owner, it.n)
  end
end

--- `K`: from a group to the groups, from the groups to Home's review tab.
local function up()
  if S.free then
    return
  end
  if S.k then
    local k = S.k
    show(nil)
    for i, it in ipairs(S.items) do
      if it.kind == 'group' and it.group.k == k then
        select(i)
      end
    end
  else
    local owner = S.owner
    M.close()
    require('thread.home').open { view = 'review', focus = 'v:' .. owner }
  end
end

--- `o`: open the item you are on: a hunk shown whole, and the cursor let
--- in to read it as text. Again (or Esc), closed.
local function free(on)
  S.free = on
  local it = item()
  if on then
    if it and it.kind == 'hunk' then
      S.opened = 'hunk:' .. tostring(it.n)
      M.refresh()
      it = item()
    end
    vim.api.nvim_buf_clear_namespace(S.buf, sel_ns, 0, -1)
    if it then
      pcall(vim.api.nvim_win_set_cursor, S.win, { it.first, PAD })
    end
    local batch = store.active()
    vim.api.nvim_win_set_config(S.win, { footer = footer(batch, S.owner), footer_pos = 'right' })
    return
  end
  -- Back to the item the cursor is in, closed again.
  local row = vim.api.nvim_win_get_cursor(S.win)[1]
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
  if not M.is_open() then
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].filetype = 'thread-review'
    local win = vim.api.nvim_open_win(buf, true, {
      relative = 'editor',
      row = 0,
      col = 0,
      width = vim.o.columns - 2,
      height = vim.o.lines - vim.o.cmdheight - 3,
      border = 'rounded',
      style = 'minimal',
      title = ' ',
      footer = ' ',
      zindex = 50,
    })
    vim.wo[win].wrap = false
    vim.wo[win].cursorline = false
    vim.wo[win].winhighlight = 'NormalFloat:Normal,FloatBorder:ThreadBorderInfo'
    S = { win = win, buf = buf, owner = opts.owner, items = {}, cur = 1, free = false }
    -- In an item, j/k and h move the cursor as ever.
    vim.keymap.set('n', 'j', function()
      if S.free then
        return 'j'
      end
      vim.schedule(function()
        select(S.cur + vim.v.count1)
      end)
      return ''
    end, { buffer = buf, nowait = true, expr = true })
    vim.keymap.set('n', 'k', function()
      if S.free then
        return 'k'
      end
      vim.schedule(function()
        select(S.cur - vim.v.count1)
      end)
      return ''
    end, { buffer = buf, nowait = true, expr = true })
    vim.keymap.set('n', 'o', function()
      free(not S.free)
    end, { buffer = buf, nowait = true })
    vim.keymap.set('n', '<Esc>', function()
      if S.free then
        free(false)
      else
        M.close()
      end
    end, { buffer = buf, nowait = true })
    vim.keymap.set('n', 'q', M.close, { buffer = buf, nowait = true })
    vim.keymap.set('n', 'K', up, { buffer = buf, nowait = true })
    vim.keymap.set('n', '<BS>', up, { buffer = buf, nowait = true })
    vim.keymap.set('n', '<CR>', enter, { buffer = buf, nowait = true })
    vim.keymap.set('n', 'J', enter, { buffer = buf, nowait = true })
    vim.keymap.set('n', 'a', accept, { buffer = buf, nowait = true })
    vim.keymap.set('n', 'r', reply, { buffer = buf, nowait = true })
    vim.keymap.set('n', 'L', function()
      step_group(1)
    end, { buffer = buf, nowait = true })
    vim.keymap.set('n', 'H', function()
      step_group(-1)
    end, { buffer = buf, nowait = true })
    vim.api.nvim_create_autocmd('VimResized', {
      buffer = buf,
      callback = M.refresh,
    })
  else
    vim.api.nvim_set_current_win(S.win)
    S.owner = opts.owner
  end
  local n = opts.n
  local w = review.work(rv)
  local e = n and w.list[n]
  if e and e.review then
    show(e.review.group, n)
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
