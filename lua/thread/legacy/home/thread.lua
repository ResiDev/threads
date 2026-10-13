--- A thread opened in Home: its code with what changed since you sent it,
--- then its messages. Inside it (`o`) every part is a step for j/k: the
--- code, each paragraph, the code a name points to once opened, a
--- diagram, a change, each stop of the tour it leads to. Parts have names
--- that hold across redraws, so where you are survives code opening or
--- closing above it.

local anchor = require 'thread.base.anchor'
local blocks = require 'thread.legacy.blocks'
local code = require 'thread.base.code'
local look = require 'thread.ui.look'
local labels = require 'thread.legacy.labels'
local message = require 'thread.legacy.home.message'
local store = require 'thread.legacy.store'
local text = require 'thread.base.text'
local prose = require 'thread.legacy.prose'
local tour = require 'thread.legacy.tour'

local M = {}

-- How much code a thread shows: just its lines, a line either side, or the
-- whole function it is in.
M.CODE = { { name = 'its lines', around = 0, cap = 8 }, { name = 'around it', around = 1, cap = 8 }, { name = 'the whole function', cap = 60 } }
-- How many lines a name's code shows; + and - step through these.
M.REF_SIZES = message.REF_SIZES

--- Whether you are inside thread `t`, stepping through its parts.
local function inside(S, t)
  return S.inside ~= nil and S.inside.id == t.c.id
end

--- The notes of a thread's latest message that has any.
---@return thread.legacy.Note[]
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
  -- On a removed line: the lines removed there, its own numbered, and
  -- what replaced them.
  local own_old
  if t.c.side == 'old' then
    local at = require('thread.legacy.review.lines').old_place(store.active(), t.c)
    if at and at.line == t.line then
      local p = at.part
      removed_before[t.line] = p.old
      own_old = { first = p.old_start, line = at.old }
      for n = p.new_start, p.new_start + p.new_count - 1 do
        added[n] = true
      end
      hi = math.max(hi, p.new_start + p.new_count - 1)
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
        local own = own_old and own_old.first + j - 1 == own_old.line and num == t.line
        blocks.code_line(P, indent, { num = own and own_old.line or nil, sign = '-', line = o, spans = old_syntax[j], wash = 'ThreadDiffDelete' })
      end
    end
    local row = blocks.code_line(
      P,
      indent,
      { num = num, sign = added[num] and '+' or ' ', line = l, spans = new_syntax[i], wash = added[num] and 'ThreadDiffAdd' or nil }
    )
    local note = noted[num]
    if note then
      P.hl(row, indent + 5, -1, 'ThreadNoteLine', { hl_eol = true, priority = 8 })
      P.mark(
        row,
        0,
        { virt_text = { { '  ' .. note.num, 'ThreadNoteNum' }, { note.text ~= '' and (' ' .. note.text) or '', 'ThreadNote' } }, virt_text_pos = 'eol' }
      )
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

--- What a reply in a tour's stop is in: the stop, and what it says, in
--- full only when focused or inside the thread.
local function draw_stop_said(P, S, t, width)
  local batch = t.c.on and store.active()
  local owner, stop, n
  if batch then
    owner, stop, n = tour.owner(batch, t.c)
  end
  if not (owner and stop) then
    return
  end
  local where = string.format('in %s of %s · %s', tour.position(tour.of(owner), n), store.title(owner), tour.title(stop))
  P.chunks({ { '▶ ' .. where, 'ThreadLeads' } }, S.indent)
  local lines = prose.wrap(tour.body(stop), math.max(30, math.min(96, width - S.text_col - 2)))
  if not (S.single or inside(S, t)) and #lines > 2 then
    lines = { lines[1], { text = '⋯' } }
  end
  for _, l in ipairs(lines) do
    P.chunks(
      vim.tbl_map(function(c)
        return { c[1], c[2] == 'ThreadText' and 'ThreadMeta' or c[2] }
      end, prose.segments(l)),
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
    local armed = S.undo_armed == on.id
    local can_undo = not armed or (on.view and #on.view.hunks > 0)
    return some { { 'j/k', 'step' }, { '⏎', 'go there' }, can_undo and { 'u', armed and 'again to undo it' or 'undo it' } or false, back }
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
    return {
      { 'space', S.marked[t.c.id] and 'unmark' or 'mark' },
      { 'c', 'close or reopen ' .. marked },
      { 'r', 'reply to all ' .. marked },
      { 'Esc', 'unmark all' },
    }
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
    return some {
      { 'j/k', 'step' },
      #S.refs > 0 and { 'w/b', 'names' } or false,
      { 'o', 'back' },
      { 'r', 'reply' },
      close,
      on_intro and start or { '⏎', 'go there' },
    }
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
function M.draw(P, S, t, level, width, view)
  -- The parts of the thread you can step through once inside it.
  S.items, S.refs = {}, {}
  P.add ''
  -- Its verdict, as a badge, when the agent gave one.
  local verdict = labels.verdict_of(t.c)
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
  local messages = t.c.messages
  local shown = math.min(level, #messages)
  if shown < #messages then
    local n = #messages - shown
    P.chunks({ { string.format('⋯ %d earlier message%s · l shows more', n, n == 1 and '' or 's'), 'ThreadMeta' } }, S.indent)
  end
  -- New is what was unseen when you arrived, so it stays marked while you
  -- read it, though showing it marked it seen.
  local seen = S.seen_at[t.c.id] or 0
  local text_width = math.max(30, math.min(96, width - S.text_col - 2))
  for i = #messages - shown + 1, #messages do
    if i > #messages - shown + 1 then
      P.add ''
    end
    local parts, found = message.draw(P, S, t, messages[i], i, i > seen and messages[i].from ~= 'you', text_width)
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
