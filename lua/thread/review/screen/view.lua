--- What the review screen shows: the groups, a line each under the
--- review's overview; or one group, its hunks drawn as diffs.

local anchor = require 'thread.anchor'
local blocks = require 'thread.blocks'
local code = require 'thread.code'
local diff = require 'thread.review.diff'
local on_lines = require 'thread.review.lines'
local look = require 'thread.look'
local review = require 'thread.review'
local store = require 'thread.store'
local text = require 'thread.text'
local tour = require 'thread.tour'

local PAD = 3
local HUNK_CAP = 40 -- lines of a hunk shown here; the code has the rest
local ASIDE_CAP = 6 -- lines of an affected place or a test shown here; o shows its function
local ASIDE_AROUND = 15 -- opened, lines either side of one in no function

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
--- between its parts as they are now. Under a line, the threads on it
--- (`talks`, by line: thread.review.lines); one on a line not drawn here
--- comes after, under its line. `it` learns what each row is: a line, by
--- its side and number, or a thread's.
local function draw_hunk(P, batch, spec, h, cap, indent, talks, it, width, whole)
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
  local function key(r)
    return (r.sign == '-' and 'old:' or 'new:') .. r.num
  end
  -- A thread's bar under the code's text, its words two columns in.
  local at = indent + 9
  local drawn = {}
  local function line(r)
    local row = blocks.code_line(P, indent, r)
    it.rows[row] = { side = r.sign == '-' and 'old' or 'new', num = r.num, text = r.line }
    local k = key(r)
    if talks[k] and not drawn[k] then
      drawn[k] = true
      for _, c in ipairs(talks[k]) do
        local a, b =
          blocks.talk(P, batch, c, width - (at - P.indent), { indent = at, line = true, whole = whole, more = not whole and ' · o shows it all' or nil })
        for x = a, b do
          it.rows[x] = { thread = c }
        end
      end
    end
  end
  for i, r in ipairs(rows) do
    if i > cap then
      P.chunks({ { string.format('      ⋯ %s more · o shows it whole', text.plural(#rows - cap, 'line')), 'ThreadMeta' } }, indent)
      break
    end
    line(r)
  end
  -- Threads on lines not drawn: past the cap, or beside the hunk.
  local left = {}
  for k in pairs(talks) do
    if not drawn[k] then
      left[#left + 1] = k
    end
  end
  table.sort(left, function(a, b)
    local sa, na = a:match '^(%a+):(%d+)$'
    local sb, nb = b:match '^(%a+):(%d+)$'
    if sa ~= sb then
      return sa == 'old'
    end
    return tonumber(na) < tonumber(nb)
  end)
  for _, k in ipairs(left) do
    local r
    for _, x in ipairs(rows) do
      if key(x) == k then
        r = x
      end
    end
    local n = tonumber(k:match '%d+$')
    line(r or { num = n, sign = ' ', line = new[n] or '', spans = code.syntax({ new[n] or '' }, h.file)[1] })
  end
end

--- A group at a glance, in columns: its size in lines and hunks, how many
--- hunks you have accepted, and the conversations in it by whose move: in
--- its stops, and on its hunks' lines (`talks_of`: thread.review.lines).
local function stats(batch, owner, w, group, show_gone, talks_of)
  local add, del, found = 0, 0, 0
  for _, x in ipairs(group.hunks) do
    if x.h then
      add, del, found = add + x.h.add, del + x.h.del, found + 1
    end
  end
  local gone = #group.hunks - found
  local _, done, total = review.state(batch, owner, group)
  -- Padded by what they show, not their bytes: − is three of them.
  local out = {
    { string.format('%7s', '+' .. add), 'ThreadAdded' },
    { ' ' .. text.pad('−' .. del, 7), 'ThreadRemoved' },
    { string.format('%3d', found), 'ThreadTitle' },
    { found == 1 and ' hunk  ' or ' hunks ', 'ThreadMeta' },
  }
  if show_gone then
    out[#out + 1] = { gone > 0 and string.format('%3d gone', gone) or string.rep(' ', 8), 'ThreadBroken' }
  end
  out[#out + 1] =
    { string.format('  ✓ %2d/%-2d', done, total), done == total and total > 0 and 'ThreadAccepted' or done > 0 and 'ThreadLeads' or 'ThreadMeta' }
  -- Conversations, by their glyph: whose move, read or not.
  local counts, order = {}, {}
  local function count(t)
    local g, hl = look.glyph(store.status(t), store.unseen(batch, t), false)
    if not counts[g] then
      counts[g] = { 0, hl }
      order[#order + 1] = g
    end
    counts[g][1] = counts[g][1] + 1
  end
  for n, e in ipairs(w.list) do
    local t = e.review.group == group.k and tour.thread_at(batch, owner, n)
    if t then
      count(t)
    end
  end
  local lined = {}
  for _, x in ipairs(group.hunks) do
    for _, list in pairs(x.h and talks_of[x.h.key] or {}) do
      vim.list_extend(lined, list)
    end
  end
  table.sort(lined, function(a, b)
    return a.id < b.id
  end)
  vim.iter(lined):each(count)
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
  -- Left behind by the code: said before anything it says.
  local health = review.health(w)
  if health.stale then
    P.add ''
    P.chunks { { ' OUT OF DATE ', 'ThreadVerdictWarn' } }
    for _, l in ipairs(text.wrap(review.why_stale(w) .. ' What it says is about code that has changed since. c closes it.', width)) do
      P.chunks { { l.text, 'ThreadUnexplained' } }
    end
  elseif review.moved(health) then
    P.chunks { { '⚠ the code has moved on since: ' .. review.moved(health), 'ThreadUnexplained' } }
  end
  P.add ''
  blocks.prose(P, m.text, width)
  if type(m.diagram) == 'table' then
    P.add ''
    blocks.diagram(P, m.diagram, width)
  end
  P.done()
  blocks.rule(P, 'groups · ' .. review.said(batch, owner.id, w), width)
  -- What the columns on the right are; gone only when some hunks are.
  local show_gone = health.gone > 0
  P.spread({}, {
    string.format('%-15s%-10s%s%-10s%12s', '   lines', ' hunks', show_gone and '        ' or '', '  accepted', 'threads'),
    'ThreadMeta',
  }, width)
  local groups = vim.list_extend({}, w.groups)
  groups[#groups + 1] = w.rest
  local talks_of = on_lines.line_threads(batch, owner.id, w)
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
    local right = stats(batch, owner.id, w, group, show_gone, talks_of)
    -- Every hunk it named gone: what it says is about code that is not there.
    local all_gone = #group.hunks > 0 and #vim.tbl_filter(function(x)
      return x.h ~= nil
    end, group.hunks) == 0
    local quiet = mark[1] == '✓' or g.kind == 'chore' or g.kind == 'style' or g.kind == 'docs' or all_gone
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

--- What the agent says of a hunk, an affected place or a test, as its
--- heading: wrapped, bold, its `code` in code's colour; `right` on the right
--- of its first line.
local function heading(P, note, width, right)
  for i, l in ipairs(text.wrap(note, width - 4)) do
    local chunks = vim.tbl_map(function(c)
      return { c[1], (c[2] == 'ThreadCode' and 'ThreadInlineCode') or (c[2] == 'ThreadText' and 'ThreadTitle') or c[2] }
    end, text.segments(l))
    if i == 1 and right and right[1] ~= '' then
      P.spread(chunks, right, width)
    else
      P.chunks(chunks)
    end
  end
end

--- An affected place or a test. What the agent says of it comes first, as
--- its heading; then, quieter, where it is and the function it is in (a
--- test's is its name); then its code as it is now, the quoted line lifted.
--- A few lines of it; opened, the whole function.
---@param right table  a chunk for the right edge
local function draw_aside(P, it, opened, width, right)
  local lines = type(it.file) == 'string' and anchor.lines_of { file = it.file }
  local loc = lines and anchor.locate(it, lines)
  local first = loc and loc.line
  local last = first and math.min(#lines, first + math.max(1, tonumber(it.lines) or 1) - 1)
  local lo, hi
  if first then
    lo, hi = code.scope(lines, it.file, first, last)
  end
  local where = { { (it.file or '?') .. ':' .. (first or it.line or '–'), 'ThreadCrumb' } }
  if lo and lo < first then
    where[#where + 1] = { ' · in ' .. text.fit(vim.trim(lines[lo]), math.max(10, width - text.width(where) - 8)), 'ThreadMeta' }
  end
  local note = type(it.note) == 'string' and it.note ~= '' and it.note
  if note then
    heading(P, note, width, right)
  else
    -- Nothing said of it: where it is, as its heading.
    local at = table.remove(where, 1)
    heading(P, at[1], width, right)
    if where[1] then
      where[1][1] = where[1][1]:gsub('^ · ', '')
    end
  end
  if #where > 0 then
    P.chunks(where, PAD + 2)
  end
  if not first then
    P.chunks({ { lines and 'its line is not in the file now' or 'the file is not there now', 'ThreadBroken' } }, PAD + 2)
    return
  end
  -- What can be shown: its function, else the lines around it.
  local top = lo or math.max(1, first - ASIDE_AROUND)
  local bottom = hi or math.min(#lines, last + ASIDE_AROUND)
  local a, b = top, bottom
  if not opened then
    a = math.max(top, first - 2)
    b = math.min(bottom, a + ASIDE_CAP - 1)
  end
  blocks.code(P, PAD + 2, it.file, lines, a, b, first)
  local more = (a - top) + (bottom - b)
  if more > 0 then
    local what = lo and 'more lines of its function' or 'more lines around it'
    P.chunks { { string.format('        ⋯ %d %s · o shows them', more, what), 'ThreadMeta' } }
  end
end

--- One group: what it is for, its hunks, the code it affects, its tests.
--- `opened`: the item opened whole with `o`, by its key.
local function draw_group(P, batch, owner, w, group, width, opened)
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
  blocks.prose(
    P,
    loose and 'Changes no group covers: most are too small to need words. Accept them a hunk at a time, or all at once from here.' or g.body,
    width
  )
  if type(g.diagram) == 'table' then
    P.add ''
    blocks.diagram(P, g.diagram, width)
  end
  local talk = n and tour.thread_at(batch, owner.id, n)
  if talk then
    blocks.talk(P, batch, talk, width, { whole = opened == 'body:' .. tostring(n) })
  end
  P.done()

  local talks_of = on_lines.line_threads(batch, owner.id, w)
  local _, done = review.state(batch, owner.id, group)
  blocks.rule(P, string.format('changes · %s · %d accepted', text.plural(#group.hunks, 'hunk'), done), width)
  for j, x in ipairs(group.hunks) do
    P.add ''
    local hn = w.index['h' .. group.k .. ':' .. j]
    local ok = x.h and review.hunk_accepted(batch, owner.id, x.h)
    local it = P.item { kind = 'hunk', group = group, h = x.h, n = hn, accepted = ok, rows = {} }
    local whole = opened == 'hunk:' .. tostring(hn)
    local t = hn and tour.thread_at(batch, owner.id, hn)
    if x.h then
      local talks = talks_of[x.h.key] or {}
      -- Its own threads: the one on it, and those on its lines.
      local own = { t }
      for _, list in pairs(talks) do
        vim.list_extend(own, list)
      end
      -- What the agent says of it first; where it is, and how big, under.
      local note = x.ref and type(x.ref.note) == 'string' and x.ref.note ~= '' and x.ref.note
      local where = x.h.file .. ':' .. (x.h.lo == x.h.hi and tostring(x.h.lo) or (x.h.lo .. '–' .. x.h.hi))
      local chunks = {
        { ok and '✓ ' or '○ ', ok and 'ThreadAccepted' or 'ThreadMeta' },
        { where, note and 'ThreadCrumb' or 'ThreadTitle' },
        { '  +' .. x.h.add, 'ThreadAdded' },
        { ' −' .. x.h.del, 'ThreadRemoved' },
      }
      -- Changed in answer to one of its threads, and yours to look at
      -- until you accept it.
      local fixed = not ok and vim.iter(own):any(on_lines.answered_with_change)
      if fixed then
        chunks[#chunks + 1] = { '   ◆ changed in answer to you · look again', 'ThreadLeads' }
      end
      for _, c in ipairs(review.origins(batch, w.spec, x.h)) do
        if not (fixed and vim.tbl_contains(own, c)) then
          vim.list_extend(chunks, { { '   from ', 'ThreadMeta' }, { '#' .. c.id, 'ThreadLink' }, { ' ' .. text.fit(store.title(c), 30), 'ThreadMeta' } })
        end
      end
      if note then
        heading(P, note, width)
        P.chunks(chunks, PAD + 2)
      else
        P.chunks(chunks)
      end
      draw_hunk(P, batch, w.spec, x.h, whole and math.huge or HUNK_CAP, PAD + 2, talks, it, width, whole)
    else
      P.chunks { { '⚠ ' .. (x.ref and x.ref.file or '?') .. ': this hunk is no longer in the diff', 'ThreadBroken' } }
    end
    if t then
      local a, b = blocks.talk(P, batch, t, width, { whole = whole, more = not whole and ' · o shows it all' or nil })
      for row = a, b do
        it.rows[row] = { thread = t }
      end
    end
    P.done()
  end
  for _, aside in ipairs { 'affected', 'tests' } do
    local items = group[aside]
    if #items > 0 then
      blocks.rule(P, (aside == 'tests' and 'tests' or 'affected, not changed') .. ' · ' .. #items, width)
      for j, it in ipairs(items) do
        local an = w.index[aside .. group.k .. ':' .. j]
        P.add ''
        P.item { kind = aside, group = group, n = an }
        local t = an and tour.thread_at(batch, owner.id, an)
        local right = t and { look.glyph(store.status(t), store.unseen(batch, t), false) } or { '' }
        local whole = opened == aside .. ':' .. tostring(an)
        draw_aside(P, it, whole, width, right)
        if t then
          blocks.talk(P, batch, t, width, { whole = whole, more = not whole and ' · o shows it all' or nil })
        end
        P.done()
      end
    end
  end
  P.add ''
end

return { PAD = PAD, groups = draw_groups, group = draw_group }
