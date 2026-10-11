--- One message in a thread opened in Home: its speaker, its text wrapped
--- beside it, the names in it that point at code (their code under the
--- paragraph once opened), its diagram, what it changed and the tour it
--- leads to. Each is a part that j/k step through inside the thread.

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

-- How many lines a name's code shows; + and - step through these.
M.REF_SIZES = { 4, 8, 16, 32 }
local CHANGE_CAP = 16 -- rows of a change shown; the whole diff is on ⏎

--- Whether you are inside thread `t`, stepping through its parts.
local function inside(S, t)
  return S.inside ~= nil and S.inside.id == t.c.id
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
      rows[#rows + 1] =
        { num = h.new_start + j - 1, sign = '+', line = l, spans = new_syntax[j], wash = add[1], word_hl = add[2], words = h.words.new[h.new_start + j - 1] }
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
    local chunks = {
      { g, ghl },
      { ' ' },
      { text.fit(num .. tour.title(e), math.max(10, room)), here and 'ThreadCrumbHere' or (it.kind == 'stage' and 'ThreadTitle' or nil) },
    }
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
function M.draw(P, S, t, m, index, new, width)
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

return M
