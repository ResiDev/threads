--- What the review screen shows: the groups, a line each under the
--- review's overview; or one group, its hunks drawn as diffs.

local anchor = require 'thread.anchor'
local blocks = require 'thread.blocks'
local code = require 'thread.code'
local diff = require 'thread.review.diff'
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

--- An affected place or a test: where it is and the function it is in
--- (a test's is its name), the agent's note, then its code as it is now,
--- the quoted line lifted. A few lines of it; opened, the whole function.
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
  local head = { { (it.file or '?') .. ':' .. (first or it.line or '–'), 'Directory' } }
  if lo and lo < first then
    local room = width - text.width(head) - text.width(right[1]) - 7
    head[#head + 1] = { ' · ' .. text.fit(vim.trim(lines[lo]), math.max(10, room)), 'ThreadMeta' }
  end
  if right[1] ~= '' then
    P.spread(head, right, width)
  else
    P.chunks(head)
  end
  if type(it.note) == 'string' and it.note ~= '' then
    P.chunks({ { it.note, 'ThreadNote' } }, PAD + 2)
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
  blocks.code(P, PAD, it.file, lines, a, b, first)
  local more = (a - top) + (bottom - b)
  if more > 0 then
    local where = lo and 'more lines of its function' or 'more lines around it'
    P.chunks { { string.format('      ⋯ %d %s · o shows them', more, where), 'ThreadMeta' } }
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
      draw_hunk(P, w.spec, x.h, opened == 'hunk:' .. tostring(hn) and math.huge or HUNK_CAP)
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
        P.add ''
        P.item { kind = aside, group = group, n = an }
        local t = an and tour.thread_at(batch, owner.id, an)
        local right = t and { look.glyph(store.status(t), store.unseen(batch, t), false) } or { '' }
        draw_aside(P, it, opened == aside .. ':' .. tostring(an), width, right)
        if t then
          blocks.talk(P, batch, t, width)
        end
        P.done()
      end
    end
  end
  P.add ''
end

return { PAD = PAD, groups = draw_groups, group = draw_group }
