--- A thread opened in Home: its code with what changed since you sent it,
--- then its messages. Inside it (`o`) every part is a step for j/k: the
--- code, each paragraph, the code a name points to once opened, a
--- diagram, a change, each stop of the tour it leads to. Parts have names
--- that hold across redraws, so where you are survives code opening or
--- closing above it.

local anchor = require 'thread.anchor'
local blocks = require 'thread.blocks'
local code = require 'thread.code'
local look = require 'thread.look'
local model = require 'thread.home.model'
local refs = require 'thread.refs'
local store = require 'thread.store'
local text = require 'thread.text'
local tour = require 'thread.tour'

local M = {}

-- How much code a thread shows: just its lines, a line either side, or the
-- whole function it is in.
M.CODE = { { name = 'its lines', around = 0, cap = 8 }, { name = 'around it', around = 1, cap = 8 }, { name = 'the whole function', cap = 60 } }
-- How many lines a name's code shows; + and - step through these.
M.REF_SIZES = { 4, 8, 16, 32 }
local CHANGE_CAP = 16 -- rows of a change shown; the whole diff is on ⏎

--- Whether you are inside thread `t`, stepping through its parts.
local function inside(S, t)
  return S.inside ~= nil and S.inside.id == t.c.id
end

--- The notes of a thread's latest message that has any.
---@return thread.Note[]
local function notes_of(c)
  for i = #c.messages, 1, -1 do
    if c.messages[i].notes and #c.messages[i].notes > 0 then
      return c.messages[i].notes
    end
  end
  return {}
end

--- The code under an open thread, with what changed since it was sent and
--- its notes on their lines.
local function draw_code(P, S, t)
  local lines = t.lines
  local size = M.CODE[(S.code[t.c.id] or 1) + 1]
  local lo, hi
  if size.around then
    lo, hi = math.max(1, t.line - size.around), math.min(#lines, t.to + size.around)
  else
    lo, hi = code.scope(lines, t.c.file, t.line, t.to)
    if not lo then
      lo, hi = math.max(1, t.line - 12), math.min(#lines, t.to + 12)
    end
  end
  local cap = size.cap
  -- Its notes: every noted line shown, numbered, the note after it.
  local noted = {}
  for k, n in ipairs(notes_of(t.c)) do
    local note = vim.tbl_extend('keep', n, { file = t.c.file })
    local loc = note.file == t.c.file and anchor.locate(note, lines)
    if loc then
      noted[loc.line] = { num = look.num(k), text = type(note.note) == 'string' and note.note or '', mark = note.mark }
      if math.abs(loc.line - t.line) < 40 then
        lo, hi = math.min(lo, loc.line), math.max(hi, loc.line)
        cap = math.max(cap, 30)
      end
    end
  end
  local added, removed_before = {}, {}
  for _, h in ipairs(t.delta and t.delta.hunks or {}) do
    local old = vim.list_slice(t.delta.old, h.old_start, h.old_start + h.old_count - 1)
    if h.new_count == 0 then
      removed_before[h.new_start + 1] = old
      lo, hi = math.min(lo, math.max(1, h.new_start)), math.max(hi, math.min(#lines, h.new_start + 1))
    else
      removed_before[h.new_start] = old
      for n = h.new_start, h.new_start + h.new_count - 1 do
        added[n] = true
      end
      lo, hi = math.min(lo, h.new_start), math.max(hi, h.new_start + h.new_count - 1)
    end
  end
  -- Enough code to place the thread, not a page of it: + or ⏎ for the rest.
  local cut
  if hi - lo + 1 > cap then
    hi, cut = lo + cap - 1, hi - lo + 1 - cap
  end

  local first = #P.lines
  local indent = S.indent
  local new_lines = vim.list_slice(lines, lo, hi)
  local new_syntax = code.syntax(new_lines, t.c.file)
  for i, l in ipairs(new_lines) do
    local num = lo + i - 1
    local old = removed_before[num]
    if old then
      local old_syntax = code.syntax(old, t.c.file)
      for j, o in ipairs(old) do
        blocks.code_line(P, indent, { sign = '-', line = o, spans = old_syntax[j], wash = 'ThreadDiffDelete' })
      end
    end
    local row = blocks.code_line(P, indent, { num = num, sign = added[num] and '+' or ' ', line = l, spans = new_syntax[i], wash = added[num] and 'ThreadDiffAdd' or nil })
    local note = noted[num]
    if note then
      P.hl(row, indent + 5, -1, 'ThreadNoteLine', { hl_eol = true, priority = 8 })
      P.mark(row, 0, { virt_text = { { '  ' .. note.num, 'ThreadNoteNum' }, { note.text ~= '' and (' ' .. note.text) or '', 'ThreadNote' } }, virt_text_pos = 'eol' })
      local at = type(note.mark) == 'string' and note.mark ~= '' and not l:find '\t' and l:find(note.mark, 1, true)
      if at then
        P.hl(row, indent + 7 + at - 1, indent + 7 + at - 1 + #note.mark, 'ThreadNoteMark', { priority = 40 })
      end
    end
  end
  if cut then
    local more = (S.code[t.c.id] or 1) < #M.CODE - 1 and ' · + shows more' or ''
    P.chunks({ { '⋯ ' .. text.plural(cut, 'more line', 'more lines') .. more, 'ThreadMeta' } }, indent + 7)
  end
  return first, #P.lines - 1
end

--- The name you are on inside a thread, if any.
function M.selected_ref(S)
  if not (S and S.inside and S.inside.ref) then
    return nil
  end
  for _, r in ipairs(S.refs or {}) do
    if r.key == S.inside.ref then
      return r
    end
  end
end

--- The name whose code you are on or at: the selected name, or the code
--- part you are on.
function M.current_ref(S)
  local ref = M.selected_ref(S)
  if ref then
    return ref
  end
  local it = S and S.inside and S.items and S.items[S.inside.item]
  if it and it.kind == 'excerpt' then
    for _, r in ipairs(S.refs or {}) do
      if r.key == it.key then
        return r
      end
    end
  end
end

--- Be on part `n` of the thread you are inside, remembered by its name.
function M.select(S, n)
  local it = S.items and S.items[n]
  S.inside.item, S.inside.sel = n, it and it.id
end

--- After a redraw, find the part you were on again by its name. When it is
--- gone: closed code goes back to its name; a part merged away goes to the
--- one before it in the same message; failing that, the same position.
local function resolve_selection(S)
  local items, sel = S.items or {}, S.inside.sel
  local function find(id)
    for n, it in ipairs(items) do
      if it.id == id then
        return n
      end
    end
  end
  local n = sel and find(sel)
  if not n and sel then
    local key = sel:match '^x:(.*)$'
    for _, r in ipairs(key and S.refs or {}) do
      if r.key == key then
        n, S.inside.ref = r.item, key
      end
    end
    local msg, part = sel:match '^m:(%d+):(%d+)$'
    for p = tonumber(part or 0) - 1, 1, -1 do
      n = n or find('m:' .. msg .. ':' .. p)
    end
  end
  n = n or math.max(1, math.min(#items, S.inside.item or #items))
  S.inside.item = n
  S.inside.sel = items[n] and items[n].id
end

--- The code a name points to, under the paragraph that names it: a few
--- lines around the place, the place itself lifted.
local function draw_ref_code(P, S, places, n, size)
  local place = places[n]
  local lines = place and anchor.lines_of { file = place.file }
  if not lines then
    return nil
  end
  local lo = math.max(1, place.line - math.floor(size / 4))
  local hi = math.min(#lines, lo + size - 1)
  local more = #places > 1 and string.format('   %d of %d · n next', n, #places) or ''
  local first = P.chunks({ { place.file .. ':' .. place.line, 'Directory' }, { more, 'ThreadMeta' } }, S.text_col)
  local _, last = blocks.code(P, S.text_col, place.file, lines, lo, hi, place.line)
  P.add ''
  return first, last
end

--- A change under its message: where, then its hunks, coloured the way
--- CodeDiff colours them when it is installed and the way Vim's diff mode
--- does when not.
---@return integer first, integer last, table|nil view
local function draw_change(P, S, t, index, ch)
  local batch = store.active()
  local view = batch and model.change(batch, t.c, index, ch)
  local where = ch.file .. ':' .. (view and view.line or ch.line or '?')
  local none = view and #view.hunks == 0 and ' · no change there now' or ''
  local first = P.chunks({ { 'changed ', 'ThreadMeta' }, { where, 'Directory' }, { none, 'ThreadMeta' } }, S.text_col)
  if not view or #view.hunks == 0 then
    return first, first, view
  end
  local add = view.words and { 'CodeDiffLineInsert', 'CodeDiffCharInsert' } or { 'ThreadDiffAdd' }
  local del = view.words and { 'CodeDiffLineDelete', 'CodeDiffCharDelete' } or { 'ThreadDiffDelete' }
  local rows = {}
  for i, h in ipairs(view.hunks) do
    if i > 1 then
      rows[#rows + 1] = { sign = ' ', line = '⋯' }
    end
    local old = vim.list_slice(view.old, h.old_start, h.old_start + h.old_count - 1)
    local new = vim.list_slice(view.new, h.new_start, h.new_start + h.new_count - 1)
    local old_syntax, new_syntax = code.syntax(old, ch.file), code.syntax(new, ch.file)
    for j, l in ipairs(old) do
      rows[#rows + 1] = { sign = '-', line = l, spans = old_syntax[j], wash = del[1], word_hl = del[2], words = h.words.old[h.old_start + j - 1] }
    end
    for j, l in ipairs(new) do
      rows[#rows + 1] = { num = h.new_start + j - 1, sign = '+', line = l, spans = new_syntax[j], wash = add[1], word_hl = add[2], words = h.words.new[h.new_start + j - 1] }
    end
  end
  for i = 1, math.min(#rows, CHANGE_CAP) do
    blocks.code_line(P, S.text_col, rows[i])
  end
  if #rows > CHANGE_CAP then
    P.chunks({ { '⋯ ' .. text.plural(#rows - CHANGE_CAP, 'more line', 'more lines') .. ' · ⏎ the whole diff', 'ThreadMeta' } }, S.text_col + 7)
  end
  return first, #P.lines - 1, view
end

--- The tour a message leads to: every stop, a part to step to, the steps
--- of a stage indented under it.
---@return table[] parts
local function draw_stops(P, S, t, m, width)
  local batch = store.active()
  if not batch then
    return {}
  end
  local items = tour.outline(m.walk)
  P.chunks({ { '▶ leads to ' .. tour.describe(m.walk), 'ThreadLeads' } }, S.text_col)
  local w = require('thread.walk').state()
  local at = anchor.finder()
  local parts = {}
  -- Under a row, the first few stops and a line saying how many more;
  -- inside the thread (o), every one.
  local cap = inside(S, t) and math.huge or 8
  for k, it in ipairs(items) do
    if k > cap then
      P.chunks({ { string.format('⋯ %d more stop%s · o shows them all', #items - cap, #items - cap == 1 and '' or 's'), 'ThreadMeta' } }, S.text_col + 2)
      break
    end
    local e = it.e
    local talk = tour.thread_at(batch, t.c.id, it.n)
    local g, ghl
    if talk then
      g, ghl = look.glyph(store.status(talk), store.unseen(batch, talk), false)
    elseif store.visited(batch, t.c.id, it.n) and it.kind ~= 'stage' then
      g, ghl = '✓', 'ThreadSignDone'
    else
      g, ghl = it.kind == 'stage' and '▸' or '·', 'ThreadSignInfo'
    end
    local indent = S.text_col + 2 + ((it.kind ~= 'stage' and it.stage > 0) and 4 or 0)
    local num = it.kind == 'stage' and (it.stage .. ' ') or it.kind == 'step' and (it.step .. ' ') or ''
    local where = it.kind == 'step' and (vim.fs.basename(e.file) .. ':' .. (at(e) or '–')) or ''
    local verdict = e.verdict and look.verdict_of { messages = { e } }
    local room = width - indent - 2 - text.width(where) - 4 - (verdict and (text.width(verdict.text) + 3) or 0)
    local here = w and w.owner == t.c.id and w.n == it.n
    local chunks = { { g, ghl }, { ' ' }, { text.fit(num .. tour.title(e), math.max(10, room)), here and 'ThreadCrumbHere' or (it.kind == 'stage' and 'ThreadTitle' or nil) } }
    if verdict then
      vim.list_extend(chunks, { { '  ' }, { ' ' .. verdict.text .. ' ', verdict.hl } })
    end
    chunks[#chunks + 1] = { string.rep(' ', math.max(2, width - indent - text.width(chunks) - text.width(where))) }
    chunks[#chunks + 1] = { where, 'LineNr' }
    local row = P.chunks(chunks, indent)
    parts[#parts + 1] = { kind = 'stop', n = it.n, id = 'k:' .. it.n, first = row, last = row }
  end
  return parts
end

--- Files a thread names, which its references most likely mean.
local function mentioned(t)
  local out = {}
  if t.anchored then
    out[t.c.file] = true
  end
  for _, m in ipairs(t.c.messages) do
    for _, ch in ipairs(m.changes or {}) do
      out[ch.file] = true
    end
  end
  return out
end

--- One message: its speaker in the label column, its text wrapped beside it.
--- An agent's `names` that point at code are underlined, and the ones opened
--- show their code under their paragraph, which splits the message there:
--- its parts, text and code in turn, are what j/k step through inside.
---@return table[] parts, table[] refs
local function draw_message(P, S, t, m, index, new, width)
  local label, label_hl = look.label(m, new)
  local batch = store.active()
  local time = batch and text.ago(store.when(batch, t.c, index))
  if m.from == 'you' then
    -- Yours on the right, as in a chat, when it was on its left.
    local first = #P.lines
    for _, r in ipairs(blocks.chat(m.text, width + S.label, S.label, time)) do
      P.chunks(
        vim.tbl_map(function(c)
          return { c[1], c[2] == 'ThreadCode' and 'ThreadInlineCode' or c[2] ~= 'ThreadText' and c[2] or nil }
        end, r),
        S.indent
      )
    end
    return { { kind = 'message', index = index, id = 'm:' .. index .. ':1', first = first, last = #P.lines - 1 } }, {}
  end
  -- The agent's text stops short on the right, as yours does on the left.
  local rows = text.wrap(m.text or '', blocks.side(width + S.label, S.label))
  if #rows == 0 then
    rows = { { text = '' } }
  end
  -- Under its row in Home, a long message trails off; o reads it all.
  local MAX = 8
  local under_row = not S.single and not inside(S, t)
  if under_row and #rows > MAX then
    rows = vim.list_slice(rows, 1, MAX)
    while #rows > 1 and rows[#rows].text == '' do
      rows[#rows] = nil
    end
    rows[#rows + 1] = { text = '⋯ o reads it all' }
  end
  local ctx = { file = t.c.file, line = t.line, mentioned = mentioned(t), near = refs.near(m.text) }
  local found, pending, k = {}, {}, 0
  local parts, part_first, part_n = {}, #P.lines, 1
  local function close_part(last)
    if part_first and last >= part_first then
      parts[#parts + 1] = { kind = 'message', index = index, id = 'm:' .. index .. ':' .. part_n, first = part_first, last = last }
      part_n = part_n + 1
    end
    part_first = nil
  end
  local skip_blank = false
  for i, l in ipairs(rows) do
    -- After code, its own blank line already parts it from the next paragraph.
    if skip_blank and l.text == '' then
      skip_blank = false
      goto next_row
    end
    skip_blank = false
    if l.excerpt then
      part_first = part_first or #P.lines
      blocks.excerpt(P, l.excerpt, { indent = S.text_col, lit = true })
      goto next_row
    end
    do
      local head = i == 1 and text.pad(label, S.label) or string.rep(' ', S.label)
      -- Columns are counted in bytes: the label's shape is one cell but
      -- several bytes.
      local pieces, col, spans = {}, S.indent + #head, {}
      for _, chunk in ipairs(text.segments(l)) do
        pieces[#pieces + 1] = chunk[1]
        if chunk[2] == 'ThreadCode' and not l.code then
          spans[#spans + 1] = { col, col + #chunk[1], chunk[1] }
        end
        col = col + #chunk[1]
      end
      local row = P.add(string.rep(' ', S.indent) .. head .. table.concat(pieces))
      part_first = part_first or row
      if i == 1 then
        P.hl(row, S.indent, S.indent + #label, label_hl)
        -- When, on the right, past where the text stops.
        local line = P.lines[row + 1]
        local at = S.text_col + width - text.width(time or '')
        if time and at > text.width(line) + 2 then
          P.lines[row + 1] = line .. string.rep(' ', at - text.width(line)) .. time
          P.hl(row, #P.lines[row + 1] - #time, -1, 'ThreadMeta')
        end
      end
      for _, sp in ipairs(spans) do
        local at = (m.text or ''):find('`' .. sp[3] .. '`', 1, true)
        local places = refs.resolve(sp[3], ctx, at and m.text:sub(at + #sp[3] + 2, at + #sp[3] + 60))
        if #places > 0 then
          k = k + 1
          local key = t.c.id .. ':' .. index .. ':' .. k
          P.hl(row, sp[1], sp[2], 'ThreadRef')
          found[#found + 1] = { kind = 'ref', key = key, places = places, first = row, last = row, s = sp[1], e = sp[2], part = 'm:' .. index .. ':' .. part_n }
          if S.open_refs[key] then
            pending[#pending + 1] = { places, S.open_refs[key], M.REF_SIZES[S.ref_size[key] or 2], key }
          end
        else
          P.hl(row, sp[1], sp[2], 'ThreadInlineCode')
        end
      end
      -- The end of a paragraph: the code its opened names point to, each a
      -- part of its own, and the text so far a part before them.
      if #pending > 0 and (not rows[i + 1] or rows[i + 1].text == '') then
        close_part(#P.lines - 1)
        P.add ''
        for _, o in ipairs(pending) do
          local a, b = draw_ref_code(P, S, o[1], o[2], o[3])
          if a then
            parts[#parts + 1] = { kind = 'excerpt', index = index, key = o[4], id = 'x:' .. o[4], first = a, last = b }
          end
        end
        pending = {}
        skip_blank = true
      end
    end
    ::next_row::
  end
  -- Code drawn last leaves a blank line behind it; the part ends before.
  local last = #P.lines - 1
  while part_first and last >= part_first and P.lines[last + 1] == '' do
    last = last - 1
  end
  close_part(last)
  -- Its diagram, a part of its own: ⏎ on a box goes to its code. Under its
  -- row, a diagram is one line; o shows it.
  if type(m.diagram) == 'table' then
    P.add ''
    if under_row then
      local n = #(m.diagram.nodes or m.diagram.participants or {})
      P.chunks({ { string.format('▸ %s diagram%s · o shows it', m.diagram.kind or '', n > 0 and (', ' .. n .. ' boxes') or ''), 'ThreadMeta' } }, S.text_col)
    else
      local a, b, drawn = blocks.diagram(P, m.diagram, math.max(30, width), S.text_col)
      parts[#parts + 1] = { kind = 'diagram', index = index, drawn = drawn, id = 'd:' .. index, first = a, last = b }
    end
  end
  -- What it changed, each place a part of its own.
  for j, ch in ipairs(m.changes or {}) do
    local a, b, view = draw_change(P, S, t, index, ch)
    parts[#parts + 1] = { kind = 'change', index = index, change = ch, view = view, id = 'c:' .. index .. ':' .. j, first = a, last = b }
  end
  -- The tour it leads to, each stop a part of its own.
  if type(m.walk) == 'table' and #m.walk > 0 then
    P.add ''
    vim.list_extend(parts, draw_stops(P, S, t, m, S.text_col + width))
  end
  return parts, found
end

--- What a reply in a tour's stop is in: the stop, and what it says, in
--- full only when focused or inside the thread.
local function draw_stop_said(P, S, t, width)
  local batch = t.c.on and store.active()
  local owner, stop
  if batch then
    owner, stop = tour.owner(batch, t.c)
  end
  if not (owner and stop) then
    return
  end
  local where = string.format('in %s of %s · %s', tour.position(tour.of(owner), t.c.on.step), store.title(owner), tour.title(stop))
  P.chunks({ { '▶ ' .. where, 'ThreadLeads' } }, S.indent)
  local lines = text.wrap(tour.body(stop), math.max(30, math.min(96, width - S.text_col - 2)))
  if not (S.single or inside(S, t)) and #lines > 2 then
    lines = { lines[1], { text = '⋯' } }
  end
  for _, l in ipairs(lines) do
    P.chunks(
      vim.tbl_map(function(c)
        return { c[1], c[2] == 'ThreadText' and 'ThreadMeta' or c[2] }
      end, text.segments(l)),
      S.text_col
    )
  end
  P.add ''
end

--- The keys an open thread lists, for the part you are on.
local function keys_for(S, t, view)
  local function some(list)
    return vim.tbl_filter(function(k)
      return k ~= false
    end, list)
  end
  local close = { 'c', t.status == 'closed' and 'reopen' or 'close' }
  local marked = vim.tbl_count(S.marked)
  local cur = M.current_ref(S)
  local on = S.inside and S.items and S.items[S.inside.item]
  local back = { S.single and 'q' or 'o', 'back' }
  -- The message a tour hangs on: ⏎ walks it from the start.
  local _, intro = tour.of(t.c)
  local on_intro = intro and on and on.index == intro
  local start = { '⏎', 'walk from the start' }
  local leads = tour.leads(t.c) or t.c.on ~= nil
  if on and on.kind == 'stop' then
    return { { 'j/k', 'step' }, { '⏎', 'walk from here' }, back }
  elseif on and on.kind == 'diagram' then
    return { { 'j/k', 'step' }, { '⏎', on_intro and 'on a box: its code, else walk' or 'on a box: its code' }, back }
  elseif on and on.kind == 'change' then
    local can_undo = on.view and #on.view.hunks > 0
    return some { { 'j/k', 'step' }, { '⏎', 'the whole diff' }, can_undo and { 'u', S.undo_armed == on.id and 'again to undo it' or 'undo it' } or false, back }
  elseif S.single and not cur then
    return some {
      { 'j/k', 'step' },
      (S.prev or S.next) and { 'h/l', 'threads' } or false,
      intro and not t.anchored and start or false,
      leads and { 'J', 'resume' } or false,
      #S.refs > 0 and { 'w/b', 'names' } or false,
      t.line and { '+/-', 'code' } or false,
      { 'r', 'reply' },
      close,
      t.anchored and { '⏎', 'go there' } or false,
      #(S.others or {}) > 1 and { 'tab', 'next here' } or false,
      { 'q', 'back' },
    }
  elseif marked > 0 then
    return { { 'space', S.marked[t.c.id] and 'unmark' or 'mark' }, { 'c', 'close or reopen ' .. marked }, { 'r', 'reply to all ' .. marked }, { 'Esc', 'unmark all' } }
  elseif cur then
    local open = S.open_refs[cur.key]
    return some {
      { 'j/k', 'step' },
      { 'w/b', 'names' },
      { '⏎', open and 'hide the code' or 'show the code' },
      #cur.places > 1 and open and { 'n', 'next match' } or false,
      open and { '+/-', 'lines' } or false,
      { S.single and 'Esc' or 'o', 'back' },
    }
  elseif S.inside then
    return some { { 'j/k', 'step' }, #S.refs > 0 and { 'w/b', 'names' } or false, { 'o', 'back' }, { 'r', 'reply' }, close, on_intro and start or { '⏎', 'go there' } }
  end
  local tours = view == 'tours' and intro
  return some {
    { 'o', 'open' },
    { 'h/l', 'history' },
    tours and start or false,
    leads and { 'J', 'resume' } or false,
    { 'r', 'reply' },
    close,
    not tours and { '⏎', t.anchored and 'go there' or 'read it' } or false,
  }
end

--- Keys and what they do as a row of their own, ending at the right edge.
function M.keys_row(P, S, keys, width)
  local chunks = look.hints(keys, '   ')
  return P.chunks(chunks, math.max(S.indent, width - 2 - text.width(chunks)))
end

--- A rule across Home above and below the thread that is open, so you can
--- see where it ends.
function M.divider(P, width)
  P.chunks({ { string.rep('─', math.max(4, width - 4)), 'ThreadTabRule' } }, 2)
end

--- The focused thread, opened: its code, then the last `level` messages.
--- `view` is the tab it is drawn in.
function M.draw(P, S, batch, t, level, width, view)
  -- The parts of the thread you can step through once inside it.
  S.items, S.refs = {}, {}
  P.add ''
  -- Its verdict, as a badge, when the agent gave one.
  local verdict = look.verdict_of(t.c)
  if verdict then
    P.chunks({ { ' ' .. verdict.text .. ' ', verdict.hl } }, S.indent)
    P.add ''
  end
  if t.line then
    local a, b = draw_code(P, S, t)
    S.items[#S.items + 1] = { kind = 'code', id = 'code', first = a, last = b }
    P.add ''
  elseif t.anchored and t.status ~= 'closed' then
    P.chunks({ { 'The line this was on is gone: the quote no longer matches the file.', 'DiagnosticWarn' } }, S.indent)
    P.add ''
  end
  draw_stop_said(P, S, t, width)
  local thread = t.c.messages
  local shown = math.min(level, #thread)
  if shown < #thread then
    local n = #thread - shown
    P.chunks({ { string.format('⋯ %d earlier message%s · l shows more', n, n == 1 and '' or 's'), 'ThreadMeta' } }, S.indent)
  end
  -- New is what was unseen when you arrived, so it stays marked while you
  -- read it, though showing it marked it seen.
  local seen = S.seen_at[t.c.id] or 0
  local text_width = math.max(30, math.min(96, width - S.text_col - 2))
  for i = #thread - shown + 1, #thread do
    if i > #thread - shown + 1 then
      P.add ''
    end
    local parts, found = draw_message(P, S, t, thread[i], i, i > seen and thread[i].from ~= 'you', text_width)
    local at_part = {}
    for _, part in ipairs(parts) do
      S.items[#S.items + 1] = part
      at_part[part.id] = #S.items
    end
    -- Inside a thread, the names in it, in reading order, for w and b.
    if inside(S, t) then
      for _, r in ipairs(found) do
        r.item = at_part[r.part] or #S.items
        S.refs[#S.refs + 1] = r
      end
    end
  end
  if inside(S, t) then
    resolve_selection(S)
    -- Inside, a bar beside the part you are on.
    local at = S.items[S.inside.item]
    if at then
      for r = at.first, at.last do
        P.mark(r, math.max(0, S.indent - 2), { virt_text = { { '▎', 'ThreadFocus' } }, virt_text_pos = 'overlay' })
      end
    end
  end
  local ref = M.selected_ref(S)
  if ref then
    P.hl(ref.first, ref.s, ref.e, 'ThreadRefFocus', { priority = 40 })
  end
  if S.reply and S.reply.id == t.c.id then
    S.reply.first = #P.lines -- 0-based row of the first reply line
    P.add ''
    local to = S.reply.ids and (' · goes to all ' .. #S.reply.ids .. ' marked') or ''
    S.reply.hint = P.chunks({ { '<C-s> save · <C-c> cancel' .. to, 'ThreadMeta' } }, S.text_col)
  else
    local keys = keys_for(S, t, view)
    if S.single then
      -- Focused, the keys sit in the float's border, always in sight.
      S.single_keys = keys
    else
      P.add ''
      M.keys_row(P, S, keys, width)
    end
  end
  if not S.single then
    M.divider(P, width)
  end
end

return M
