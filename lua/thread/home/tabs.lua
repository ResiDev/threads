--- Home's tabs: the conversations, the tours, the review of a diff, what is
--- closed. Whose move each conversation is shows in its glyph, and
--- grouping by turn (g) splits them. Each tab lists its rows and opens the
--- focused one under its row.

local look = require 'thread.look'
local model = require 'thread.home.model'
local review = require 'thread.review'
local store = require 'thread.store'
local text = require 'thread.text'
local thread = require 'thread.home.thread'
local tour = require 'thread.tour'

local M = {}

local function open(t)
  return t.status ~= 'closed' and t.status ~= 'info'
end

--- The tab Home is on, by what it shows; nil when focused from the code.
function M.view(S)
  return not S.single and M.TABS[S.tab].view or nil
end

--- How many messages a thread opens at: under its row its last one (l
--- shows more, o all); focused from the code its last two, or all that is
--- new.
function M.open_level(S, batch, t)
  if S.seen_at[t.c.id] == nil then
    S.seen_at[t.c.id] = store.seen_count(batch, t.c)
  end
  if S.inside and S.inside.id == t.c.id then
    return #t.c.messages
  end
  return S.levels[t.c.id] or (S.single and math.max(2, #t.c.messages - S.seen_at[t.c.id]) or 1)
end

--- Keep focus on a row still listed, else the nearest one.
local function keep_focus(S)
  if not vim.tbl_contains(S.order, S.focus) then
    S.focus = S.order[math.min(S.focus_index or 1, #S.order)]
  end
end

--- Draw a row's thread open under it, when it is the focused one.
local function open_under(P, S, batch, t, width, at_least)
  local level = M.open_level(S, batch, t)
  if level > 0 or at_least then
    thread.draw(P, S, t, math.max(level, 1), width, M.view(S))
  end
  S.focused_thread, S.focused_level = t, level
end

--- A thread's row: where, glyph, title, its last few messages, the change,
--- who spoke last and what they said.
local function row(P, S, batch, t, focused, cols)
  local chunks = {}
  local function put(s, hl)
    chunks[#chunks + 1] = { s, hl }
  end
  local last = t.c.messages[#t.c.messages]
  local where = t.line and tostring(t.line) or (t.anchored and '–' or '·')
  if cols.files and t.anchored then
    where = vim.fs.basename(t.c.file) .. ':' .. where
  end
  put(focused and '▌ ' or '  ', 'ThreadFocus')
  put(string.rep(' ', math.max(0, cols.where - text.width(where))) .. where .. '  ', focused and 'ThreadFocus' or 'LineNr')
  put(look.glyph(t.status, t.unseen, t.anchored and not t.line))
  -- ▶ when its answer leads somewhere: a walk.
  put(tour.leads(t.c) and ' ▶' or '  ', 'ThreadLeads')
  put(' ' .. text.pad(text.fit(store.title(t.c), cols.title), cols.title) .. '  ', (t.unseen or focused) and 'ThreadTitle' or nil)
  local dots = look.dots(t.c.messages, S.seen_at[t.c.id] or t.seen or 0)
  vim.list_extend(chunks, dots)
  put(string.rep(' ', look.DOTS_WIDTH + 1 - text.width(dots)))
  local add = (t.delta and t.delta.add > 0) and ('+' .. t.delta.add) or ''
  local del = (t.delta and t.delta.del > 0) and ('−' .. t.delta.del) or ''
  local both = add ~= '' and del ~= ''
  put(add, 'ThreadAdded')
  put(both and ' ' or '')
  put(del, 'ThreadRemoved')
  put(string.rep(' ', math.max(1, 9 - text.width(add .. del) - (both and 1 or 0))))
  if last then
    local label, label_hl = look.label(last)
    put(text.pad(label, 2), label_hl)
  else
    put '  '
  end
  -- A step of a tour says which tour.
  local head = t.c.on and tour.owner(batch, t.c)
  if head then
    put('in ' .. text.fit(store.title(head), 24) .. ' · ', 'ThreadCrumb')
  end
  put(text.fit(text.first_line(last and last.text), cols.total - text.width(chunks)), t.status == 'closed' and 'ThreadMeta' or nil)
  local r = P.chunks(chunks, 0)
  -- Marked with space: the whole row lifted, under its colours.
  if S.marked[t.c.id] then
    P.hl(r, 0, -1, 'ThreadMarked', { hl_eol = true, priority = 5 })
    P.mark(r, 0, { virt_text = { { focused and '▌' or '▐', 'ThreadMarkedBar' } }, virt_text_pos = 'overlay' })
  end
  return r
end

--- The threads tab and the closed one: grouped by file, turn or round; in
--- file and line order within a group.
local function threads(P, S, batch, list, width)
  local tab = M.TABS[S.tab]
  local grouping = model.GROUPS[S.group]
  local groups, order, label = {}, {}, {}
  for _, t in ipairs(list) do
    if tab.test(t) then
      local key, name = grouping.of(t, batch)
      if not groups[key] then
        groups[key], label[key] = {}, name
        order[#order + 1] = key
      end
      table.insert(groups[key], t)
    end
  end
  table.sort(order)
  local by_file = grouping.name == 'file'
  local title_w, where_w = 12, 4
  for _, t in ipairs(list) do
    title_w = math.max(title_w, text.width(store.title(t.c)))
    if not by_file then
      where_w = math.max(where_w, text.width(t.anchored and (vim.fs.basename(t.c.file) .. ':' .. (t.line or '–')) or '·'))
    end
  end
  local cols = { title = math.min(title_w, 36, math.floor(width * 0.3)), total = width - 2, files = not by_file, where = math.min(where_w, 24) }
  for _, key in ipairs(order) do
    table.sort(groups[key], model.by_place)
    for _, t in ipairs(groups[key]) do
      S.order[#S.order + 1] = t.c.id
    end
  end
  -- On opening, focus the first thread that needs you, in the order shown:
  -- something new, then your turn, then anything open.
  if S.pick_first then
    S.pick_first = false
    local by_id, rank = {}, math.huge
    for _, t in ipairs(list) do
      by_id[t.c.id] = t
    end
    for _, id in ipairs(S.order) do
      local t = by_id[id]
      local r = (t.status ~= 'closed' and t.unseen) and 1 or (t.status == 'answered' and 2) or (t.status ~= 'closed' and 3) or 4
      if r < rank then
        S.focus, rank = id, r
      end
    end
  end
  keep_focus(S)
  if #order == 0 then
    local why = (S.query and S.query ~= '') and ('Nothing mentions “' .. S.query .. '”. Esc clears the search.')
      or #list == 0 and ('Start a thread on a line with ' .. (look.key 'add' or ':Thread add') .. ', or ask with ' .. (look.key 'ask' or ':Thread ask') .. '.')
      or '2 shows the tours, 4 the closed ones.'
    P.add ''
    P.chunks({ { 'Nothing here. ' .. why, 'ThreadMeta' } }, 2)
  end
  for _, key in ipairs(order) do
    P.add ''
    P.chunks({ { label[key], by_file and 'Directory' or 'ThreadTitle' }, { '  ' .. #groups[key], 'ThreadMeta' } }, 2)
    for _, t in ipairs(groups[key]) do
      local focused = t.c.id == S.focus
      P.own(t.c.id)
      if focused then
        thread.divider(P, width)
      end
      S.row_of[t.c.id] = row(P, S, batch, t, focused, cols) + 1
      if focused then
        open_under(P, S, batch, t, width, S.reply and S.reply.id == t.c.id)
      end
      P.own(nil)
    end
  end
end

--- The tours tab: every tour by its head, answers to your questions first,
--- then standalone ones. The focused one opens: its overview and outline.
local function tours(P, S, batch, list, width)
  local by_id = {}
  for _, t in ipairs(list) do
    by_id[t.c.id] = t
  end
  local groups = { { name = 'answers that walk you through it', list = {} }, { name = 'standalone tours', list = {} } }
  for _, h in ipairs(tour.tours(batch)) do
    local t = not tour.is_review(h) and by_id[h.id]
    if t then
      table.insert(groups[store.talked(h) and 1 or 2].list, t)
    end
  end
  for _, g in ipairs(groups) do
    for _, t in ipairs(g.list) do
      S.order[#S.order + 1] = t.c.id
    end
  end
  keep_focus(S)
  if #S.order == 0 then
    P.add ''
    P.chunks({ { 'No tours yet. An answer that walks you through the code is one.', 'ThreadMeta' } }, 2)
    return
  end
  local name_w = math.min(40, math.floor(width * 0.35))
  for _, g in ipairs(groups) do
    if #g.list > 0 then
      P.add ''
      P.chunks({ { g.name, 'ThreadTitle' }, { '  ' .. #g.list, 'ThreadMeta' } }, 2)
      for _, t in ipairs(g.list) do
        local focused = t.c.id == S.focus
        P.own(t.c.id)
        if focused then
          thread.divider(P, width)
        end
        local stops = tour.of(t.c)
        local been = 0
        for n in ipairs(stops) do
          been = been + (store.visited(batch, t.c.id, n) and 1 or 0)
        end
        local talks = tour.talks(batch, t.c.id)
        local g_, ghl = look.glyph(t.status, t.unseen, t.anchored and not t.line)
        local where = t.anchored and (vim.fs.basename(t.c.file) .. ':' .. (t.line or '–')) or 'general'
        local r = P.chunks({
          { focused and '▌ ' or '  ', 'ThreadFocus' },
          { g_, ghl },
          { ' ▶', 'ThreadLeads' },
          { ' ' },
          { text.pad(text.fit(store.title(t.c), name_w), name_w) .. '  ', (focused or t.unseen) and 'ThreadTitle' or nil },
          {
            text.pad(tour.describe(stops), 22) .. text.pad(string.format('%d/%d seen', been, #stops), 12) .. text.pad(where, 24) .. (talks > 0 and string.format(' · %d with a conversation', talks) or ''),
            'ThreadMeta',
          },
        }, 0)
        S.row_of[t.c.id] = r + 1
        if focused then
          open_under(P, S, batch, t, width, true)
        end
        P.own(nil)
      end
    end
  end
end

--- With no review yet: the diff the batch asks for, file by file.
local function unreviewed(P, batch, width)
  local diff = require 'thread.review.diff'
  local spec = diff.spec(batch.data.diff)
  P.add ''
  if not spec then
    P.chunks({ { 'No review yet. d picks a diff to review (unstaged, staged, uncommitted, or from a commit); then ask the agent to review it.', 'ThreadMeta' } }, 2)
    return
  end
  local files = diff.files(spec)
  P.chunks({ { spec.label, 'ThreadTitle' }, { string.format('  %d files · no review yet: ask the agent to review it', #files), 'ThreadMeta' } }, 2)
  P.add ''
  local half = math.floor(width * 0.5)
  for _, f in ipairs(files) do
    P.chunks({
      { text.pad(text.fit(f.file, half), half) .. '  ', 'Directory' },
      { '+' .. f.add, 'ThreadAdded' },
      { ' ' },
      { '−' .. f.del, 'ThreadRemoved' },
      { '   ' .. text.plural(#f.hunks, 'hunk'), 'ThreadMeta' },
    }, 4)
  end
end

local STATE = {
  accepted = { '✓', 'ThreadSignDone' },
  changed = { '◌', 'ThreadUnexplained' },
  partial = { '◑', 'ThreadLeads' },
  open = { '○', 'ThreadMeta' },
}

--- A review's row: its name, its diff and how far you are through it.
local function review_head(P, S, batch, o, id, focused, width)
  local w = review.work(review.of(o))
  local add, del = 0, 0
  for _, f in ipairs(w.files) do
    add, del = add + f.add, del + f.del
  end
  local _, _, changed = review.progress(batch, o.id, w)
  local r = P.chunks({
    { focused and '▌ ' or '  ', 'ThreadFocus' },
    { store.title(o) .. '  ', 'ThreadTitle' },
    { (w.spec and w.spec.label or ('no diff: ' .. (w.err or '?'))) .. string.format(' · %d files ', #w.files), 'ThreadCrumbHere' },
    { '+' .. add, 'ThreadAdded' },
    { ' ' },
    { '−' .. del, 'ThreadRemoved' },
    { '   ' .. review.said(batch, o.id, w), changed > 0 and 'ThreadUnexplained' or 'ThreadMeta' },
  }, 0)
  S.row_of[id] = r + 1
  if focused then
    thread.keys_row(P, S, { { '⏎', 'open it' }, { 'J', 'walk its hunks from where you left off' }, { 'd', 'the diff' } }, width)
  end
end

--- A group's row: its state, risk, kind, title and size; focused, its
--- hunks a line each and where it is risky.
local function review_group(P, S, batch, o, n, e, id, focused, width)
  local rv = review.of(o)
  local w = review.work(rv)
  local group = review.group_of(rv, e)
  local g = group.g
  local loose = group.k == 0
  local mark
  if loose then
    local ok = 0
    for _, h in ipairs(w.loose) do
      ok = ok + (review.hunk_accepted(batch, o.id, h) and 1 or 0)
    end
    mark = ok == #w.loose and { '✓', 'ThreadSignDone' } or { '⚠', 'ThreadUnexplained' }
  else
    mark = STATE[review.state(batch, o.id, group)]
  end
  local risk = look.risk(g.risk, true) or { ' ', 'ThreadMeta' }
  local kind = look.kind_badge(g.kind) or { '', 'ThreadMeta' }
  local size = text.plural(#group.hunks, 'hunk')
  if #group.affected > 0 then
    size = size .. ' · ' .. #group.affected .. ' affected'
  end
  if #group.tests > 0 then
    size = size .. ' · ' .. text.plural(#group.tests, 'test')
  end
  local chunks = {
    { focused and '▌ ' or '  ', 'ThreadFocus' },
    { '  ' },
    mark,
    { ' ' },
    risk,
    { ' ' },
    -- Kinds padded to one width, so the titles line up.
    kind,
    { string.rep(' ', 11 - text.width(kind[1])) },
  }
  local name_w = math.max(10, width - text.width(chunks) - text.width(size) - 6)
  local title = text.fit(loose and 'not explained' or (g.title or ''), name_w)
  local quiet = mark[1] == '✓' or g.kind == 'chore' or g.kind == 'style' or g.kind == 'docs'
  vim.list_extend(chunks, {
    { title, loose and 'ThreadUnexplained' or (focused and 'ThreadTitle' or quiet and 'ThreadMeta' or 'ThreadText') },
    { string.rep(' ', name_w - text.width(title)) .. '  ' },
    { size, 'ThreadMeta' },
  })
  local talk = tour.thread_at(batch, o.id, n)
  if talk then
    local g_, ghl = look.glyph(store.status(talk), store.unseen(batch, talk), false)
    vim.list_extend(chunks, { { '  ' }, { g_, ghl } })
  end
  S.row_of[id] = P.chunks(chunks, 0) + 1
  if not focused then
    return
  end
  local indent = S.indent + 2
  if type(g.risk_why) == 'string' and g.risk_why ~= '' then
    P.chunks({ { text.fit(g.risk .. ' risk: ' .. g.risk_why, width - S.indent - 4), risk[2] } }, indent)
  end
  for j, x in ipairs(group.hunks) do
    if j > 8 then
      P.chunks({ { string.format('⋯ %d more · ⏎ shows them all', #group.hunks - 8), 'ThreadMeta' } }, indent)
      break
    end
    local h = x.h
    if h then
      local span = h.lo == h.hi and tostring(h.lo) or (h.lo .. '–' .. h.hi)
      local accepted = loose and (review.hunk_accepted(batch, o.id, h) and '✓ ' or '○ ') or ''
      local where = text.pad(accepted .. h.file .. ':' .. span, 36) .. '  '
      P.chunks({
        { where, 'Directory' },
        { '+' .. h.add, 'ThreadAdded' },
        { ' ' },
        { '−' .. h.del, 'ThreadRemoved' },
        { '   ' .. text.fit(x.ref and x.ref.note or '', math.max(10, width - indent - text.width(where) - 20)), 'ThreadNote' },
      }, indent)
    else
      P.chunks({ { '⚠ ' .. (x.ref and x.ref.file or '?') .. ': no longer in the diff', 'ThreadBroken' } }, indent)
    end
  end
  thread.keys_row(P, S, {
    { '⏎', 'open it' },
    { 'a', review.state(batch, o.id, group) == 'accepted' and 'unaccept it' or 'accept it' },
    { 'r', 'ask about it' },
  }, width)
end

--- The review tab: each review, how far you are through accepting it, and
--- under it its groups: what each is for, how risky, how big. The focused
--- group shows its hunks.
local function reviews(P, S, batch, _, width)
  local list = model.reviews(batch)
  if #list == 0 then
    return unreviewed(P, batch, width)
  end
  local rows = {}
  for _, o in ipairs(list) do
    rows[#rows + 1] = { id = 'v:' .. o.id, owner = o }
    for n, e in ipairs(tour.of(o)) do
      if tour.kind(e) == 'stage' then
        rows[#rows + 1] = { id = 'g:' .. o.id .. ':' .. n, owner = o, n = n, e = e }
      end
    end
  end
  for _, r in ipairs(rows) do
    S.order[#S.order + 1] = r.id
  end
  keep_focus(S)
  for _, r in ipairs(rows) do
    if not r.n then
      P.add ''
    end
    P.own(r.id)
    if r.n then
      review_group(P, S, batch, r.owner, r.n, r.e, r.id, S.focus == r.id, width)
    else
      review_head(P, S, batch, r.owner, r.id, S.focus == r.id, width)
    end
    P.own(nil)
  end
end

M.TABS = {
  { key = '1', name = 'threads', view = 'threads', test = open, draw = threads },
  { key = '2', name = 'tours', view = 'tours', draw = tours },
  { key = '3', name = 'review', view = 'review', draw = reviews },
  {
    key = '4',
    name = 'closed',
    view = 'closed',
    test = function(t)
      return t.status == 'closed'
    end,
    draw = threads,
  },
}

--- How many rows a tab lists.
local function count(tab, batch, list)
  if tab.view == 'tours' then
    return #vim.tbl_filter(function(c)
      return not tour.is_review(c)
    end, tour.tours(batch))
  elseif tab.view == 'review' then
    return #model.reviews(batch)
  end
  return #vim.tbl_filter(tab.test, list)
end

--- The tabs as a bar, the current one lifted out of the rule under them;
--- on the right, the search and the grouping, each with its key.
local function bar(P, S, batch, list, width)
  local new = 0
  for _, t in ipairs(list) do
    new = new + ((t.unseen and open(t)) and 1 or 0)
  end
  local chunks, at, under = { { '  ' } }, 2, { 0, 0 }
  for i, tab in ipairs(M.TABS) do
    local n = count(tab, batch, list)
    local s = string.format(' %s %s %d ', tab.key, tab.name, n)
    if tab.view == 'threads' and new > 0 then
      s = string.format(' %s %s %d · %d new ', tab.key, tab.name, n, new)
    end
    local on = i == S.tab
    if on then
      under = { at, text.width(s) }
    end
    vim.list_extend(chunks, { { s:sub(1, 2), on and 'ThreadTabKeyActive' or 'ThreadTabKey' }, { s:sub(3), on and 'ThreadTabActive' or 'ThreadTab' }, { ' ' } })
    at = at + text.width(s) + 1
  end
  local query = S.query and S.query ~= '' and S.query
  local right = look.hints({ { '/', query and ('“' .. query .. '”') or 'search' }, { 'g', 'by' } }, '   ')
  if query then
    right[2][2] = 'ThreadTitle'
  end
  right[#right + 1] = { ' ' }
  for i, g in ipairs(model.GROUPS) do
    right[#right + 1] = { ' ' .. g.name .. ' ', i == S.group and 'ThreadTabActive' or 'ThreadTab' }
  end
  chunks[#chunks + 1] = { string.rep(' ', math.max(2, width - text.width(chunks) - text.width(right) - 2)) }
  P.chunks(vim.list_extend(chunks, right), 0)
  P.chunks({
    { string.rep('─', under[1]), 'ThreadTabRule' },
    { string.rep('━', under[2]), 'ThreadTabUnder' },
    { string.rep('─', math.max(0, width - under[1] - under[2])), 'ThreadTabRule' },
  }, 0)
end

--- Home on its tabs: the bar, then the tab Home is on.
function M.draw(P, S, batch, width)
  local list = model.collect(batch, S.query)
  bar(P, S, batch, list, width)
  M.TABS[S.tab].draw(P, S, batch, list, width)
end

return M
