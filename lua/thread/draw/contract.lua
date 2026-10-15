--- A contract's page: what it is and why it changed, in as much prose as
--- the agent wants; its shape, block by block, what changed marked in
--- each, before and after side by side where both are written; what
--- callers can count on; each use and what the change means for it; the
--- tours and notes that touch it, worked out; and its conversation. Its
--- files down the right, as a review's are.

local chunk = require 'thread.model.chunk'
local chunk_draw = require 'thread.draw.chunk'
local contract = require 'thread.model.contract'
local draw = require 'thread.draw'
local labels = require 'thread.draw.labels'
local message = require 'thread.draw.message'
local prose = require 'thread.prose'
local review = require 'thread.model.review'
local side = require 'thread.draw.side'
local text = require 'thread.base.text'
local thread = require 'thread.model.thread'
local touch = require 'thread.model.touch'

local M = {}

---@class thread.ContractOpts
---@field width integer
---@field indent integer|nil  else the sheet's
---@field code boolean|nil  where it is defined, drawn as its code
---@field touches thread.Touches|nil  what touches what in the review, else worked out

-- What the change did, to the contract or to a row of it: a glyph and
-- its colour. A row as it was has none.
M.CHANGE = {
  added = { '+', 'ThreadAdded' },
  changed = { '~', 'ThreadFileModified' },
  removed = { '−', 'ThreadRemoved' },
  ['relied on'] = { '·', 'ThreadMeta' },
}

-- What a use's verdict says: a glyph, its colour, and in words.
M.VERDICT = {
  fine = { '✓', 'ThreadVerdictGood', 'still right' },
  updated = { '↻', 'ThreadVerdictInfo', 'changed with it' },
  check = { '?', 'ThreadVerdictWarn', 'to check' },
  broken = { '✗', 'ThreadVerdictBad', 'now wrong' },
}

-- Columns between a grid's cells; the widest prose reads well at.
local GAP, PROSE = 2, 100

---@param change string|nil
---@return string glyph, string hl
local function mark(change)
  local g = M.CHANGE[change or '']
  if not g then
    return ' ', 'ThreadMeta'
  end
  return g[1], g[2]
end

--- A cell: its text, wrapped to its column, and its colour.
---@alias thread.Cell { [1]: string, [2]: string }

--- Rows of cells in columns of `widths`, each cell wrapped to its own; a
--- row as tall as its tallest cell.
---@param P thread.Sheet
---@param rows thread.Cell[][]
---@param widths integer[]
---@param indent integer
local function grid(P, rows, widths, indent)
  for _, cells in ipairs(rows) do
    local wrapped, tall = {}, 1 ---@type string[][], integer
    for k, cell in ipairs(cells) do
      wrapped[k] = cell[1] ~= '' and text.wrap(cell[1], widths[k]) or { '' }
      tall = math.max(tall, #wrapped[k])
    end
    for line = 1, tall do
      local out = {} ---@type thread.Chunks
      for k, cell in ipairs(cells) do
        local s = wrapped[k][line] or ''
        out[#out + 1] = { k < #cells and text.pad(s, widths[k] + GAP) or s, cell[2] }
      end
      P.chunks(out, indent)
    end
  end
end

--- Widths for columns of `cells`: each as wide as its widest cell, but
--- the last, up to its share of `width`; the last has the rest.
---@param rows thread.Cell[][]
---@param shares number[]  each column's most, a part of the width; the last's unused
---@param width integer
---@return integer[]
local function widths(rows, shares, width)
  local out, used = {}, 0 ---@type integer[], integer
  for k = 1, #shares - 1 do
    local w = 1
    for _, cells in ipairs(rows) do
      w = math.max(w, text.width(cells[k][1]))
    end
    out[k] = math.min(w, math.max(1, math.floor(width * shares[k])))
    used = used + out[k] + GAP
  end
  out[#shares] = math.max(8, width - used)
  return out
end

--- A word or a few in backticks reads as plain in a cell.
---@param s string|nil
---@return string
local function plain(s)
  return (string.gsub(s or '', '`', ''))
end

-- A run of text as tokens: words, spaces, and each other character.
---@param s string
---@return string[]
local function tokens(s)
  local out, i = {}, 1 ---@type string[], integer
  while i <= #s do
    local _, e = s:find('^[%w_]+', i)
    if not e then
      _, e = s:find('^%s+', i)
    end
    if not e then
      local b = s:byte(i)
      e = i + (b >= 0xF0 and 3 or b >= 0xE0 and 2 or b >= 0xC0 and 1 or 0)
    end
    out[#out + 1] = s:sub(i, e)
    i = e + 1
  end
  return out
end

--- Two versions of a line, each as chunks, what the other has not lit:
--- the tokens either side kept in common by a longest common run.
---@param a string
---@param b string
---@return thread.Chunks before, thread.Chunks after
function M.marked(a, b)
  local A, B = tokens(a), tokens(b)
  local L = {} ---@type integer[][]
  for i = #A + 1, 1, -1 do
    L[i] = {}
    for j = #B + 1, 1, -1 do
      if i > #A or j > #B then
        L[i][j] = 0
      elseif A[i] == B[j] then
        L[i][j] = L[i + 1][j + 1] + 1
      else
        L[i][j] = math.max(L[i + 1][j], L[i][j + 1])
      end
    end
  end
  local x, y = {}, {} ---@type thread.Chunks, thread.Chunks
  ---@param out thread.Chunks
  ---@param s string
  ---@param hl string
  local function put(out, s, hl)
    local last = out[#out]
    if last and last[2] == hl then
      last[1] = last[1] .. s
    else
      out[#out + 1] = { s, hl }
    end
  end
  local i, j = 1, 1
  while i <= #A or j <= #B do
    if i <= #A and j <= #B and A[i] == B[j] then
      put(x, A[i], 'ThreadCode')
      put(y, B[j], 'ThreadCode')
      i, j = i + 1, j + 1
    elseif j <= #B and (i > #A or L[i][j + 1] >= L[i + 1][j]) then
      put(y, B[j], 'ThreadDiffAdd')
      j = j + 1
    else
      put(x, A[i], 'ThreadDiffDelete')
      i = i + 1
    end
  end
  return x, y
end

---@param P thread.Sheet
---@param b thread.ShapeBlock
---@param width integer
---@param indent integer
local function signature(P, b, width, indent)
  local label = 6
  if b.before and b.after then
    local x, y = M.marked(b.before, b.after)
    table.insert(x, 1, { text.pad('was', label + 2), 'ThreadRemoved' })
    table.insert(y, 1, { text.pad('now', label + 2), 'ThreadAdded' })
    P.chunks(text.fit_chunks(x, width), indent)
    P.chunks(text.fit_chunks(y, width), indent)
  elseif b.before then
    P.chunks(text.fit_chunks({ { text.pad('was', label + 2), 'ThreadRemoved' }, { b.before, 'ThreadCode' } }, width), indent)
  else
    P.chunks({ { text.fit(b.after or '', width), 'ThreadCode' } }, indent)
  end
end

---@param P thread.Sheet
---@param b thread.ShapeBlock
---@param width integer
---@param indent integer
local function fields(P, b, width, indent)
  local rows = {} ---@type thread.Cell[][]
  for _, row in ipairs(b.rows or {}) do
    local g, hl = mark(row.change)
    local gone = row.change == 'removed'
    local name = row.name or row.value or ''
    local kind = row.was and ((row.was .. ' → ') .. (row.type or '?')) or row.type or ''
    if b.kind == 'values' and row.was then
      name = row.was .. ' → ' .. name
    end
    local cells = { { g, hl }, { name, gone and 'ThreadMeta' or row.change and 'ThreadTitle' or 'ThreadText' } } ---@type thread.Cell[]
    if b.kind == 'fields' then
      cells[#cells + 1] = { kind, gone and 'ThreadMeta' or 'ThreadCode' }
    end
    cells[#cells + 1] = { plain(row.note), 'ThreadMeta' }
    rows[#rows + 1] = cells
  end
  local shares = b.kind == 'fields' and { 0.05, 0.3, 0.3, 1 } or { 0.05, 0.35, 1 }
  grid(P, rows, widths(rows, shares, width), indent)
end

---@param P thread.Sheet
---@param b thread.ShapeBlock
---@param width integer
---@param indent integer
local function cases(P, b, width, indent)
  local before = false
  for _, row in ipairs(b.rows or {}) do
    before = before or row.before ~= nil
  end
  local head = { { ' ', 'ThreadMeta' }, { 'when', 'ThreadMeta' } } ---@type thread.Cell[]
  if before then
    head[#head + 1] = { 'before', 'ThreadMeta' }
  end
  head[#head + 1] = { before and 'after' or 'what happens', 'ThreadMeta' }
  local rows = { head } ---@type thread.Cell[][]
  for _, row in ipairs(b.rows or {}) do
    local g, hl = mark(row.change)
    local cells = { { g, hl }, { plain(row.when), 'ThreadText' } } ---@type thread.Cell[]
    local changed = row.change and row.before ~= row.after
    if before then
      cells[#cells + 1] = { plain(row.before or '—'), (changed and row.before) and 'ThreadRemoved' or 'ThreadMeta' }
    end
    local after = row.after and plain(row.after) or nil
    if after and row.note then
      after = after .. ' (' .. plain(row.note) .. ')'
    end
    cells[#cells + 1] = after and { after, changed and 'ThreadAdded' or 'ThreadText' } or { row.note and plain(row.note) or '—', 'ThreadMeta' }
    rows[#rows + 1] = cells
  end
  -- The situation as wide as it needs, up to a third; before and after
  -- share the rest alike.
  local room = width - 1 - (#head - 1) * GAP
  local when = 4
  for _, cells in ipairs(rows) do
    when = math.max(when, text.width(cells[2][1]))
  end
  local cols = { 1, math.min(when, math.floor(room / 3)) }
  local rest = room - cols[2]
  if before then
    cols[3] = math.floor(rest / 2)
    rest = rest - cols[3]
  end
  cols[#cols + 1] = math.max(8, rest)
  grid(P, rows, cols, indent)
end

---@param P thread.Sheet
---@param b thread.ShapeBlock
---@param width integer
---@param indent integer
local function example(P, b, width, indent)
  local inner = indent + 2
  local room = width - 2
  local function lines(s)
    return vim.split(s or '', '\n', { plain = true })
  end
  if b.before and b.after and room >= 2 * 28 + GAP then
    local col = math.floor((room - GAP) / 2)
    local x, y = lines(b.before), lines(b.after)
    P.chunks({ { text.pad('− before', col + GAP), 'ThreadRemoved' }, { '+ after', 'ThreadAdded' } }, inner)
    for i = 1, math.max(#x, #y) do
      P.chunks({ { text.pad(text.fit(x[i] or '', col), col + GAP), 'ThreadCode' }, { text.fit(y[i] or '', col), 'ThreadCode' } }, inner)
    end
    return
  end
  for _, half in ipairs { { 'before', '− before', 'ThreadRemoved' }, { 'after', '+ after', 'ThreadAdded' } } do
    local s = b[half[1]]
    if s then
      if b.before and b.after then
        P.chunks({ { half[2], half[3] } }, inner)
      end
      for _, line in ipairs(lines(s)) do
        P.chunks({ { text.fit(line, room), 'ThreadCode' } }, inner)
      end
    end
  end
end

--- One block of a contract's shape, under its title.
---@param P thread.Sheet
---@param r thread.Review
---@param b thread.ShapeBlock
---@param width integer
---@param indent integer
---@param out thread.Part[]
local function block(P, r, b, width, indent, out)
  local title = b.title or (b.kind == 'example' and 'example') or nil
  if title then
    local head = { { title, 'ThreadCrumb' } } ---@type thread.Chunks
    if b.lang then
      head[#head + 1] = { ' · ' .. b.lang, 'ThreadMeta' }
    end
    P.chunks(text.fit_chunks(head, width), indent)
  end
  if b.kind == 'signature' then
    signature(P, b, width, indent)
  elseif b.kind == 'fields' or b.kind == 'values' then
    fields(P, b, width, indent)
  elseif b.kind == 'cases' then
    cases(P, b, width, indent)
  elseif b.kind == 'example' then
    example(P, b, width, indent)
  else
    draw.prose(prose.draw(P, b.text, math.min(width, PROSE), { indent = indent, spec = chunk.spec(r.diff), names = contract.names(r) }), out)
  end
end

--- What the uses' verdicts come to: `1 now wrong · 2 changed with it`.
---@param uses thread.Use[]
---@return string
local function tally(uses)
  local n = {} ---@type table<string, integer>
  for _, u in ipairs(uses) do
    if u.verdict then
      n[u.verdict] = (n[u.verdict] or 0) + 1
    end
  end
  local out = {} ---@type string[]
  for _, v in ipairs { 'broken', 'check', 'updated', 'fine' } do
    if n[v] then
      out[#out + 1] = n[v] .. ' ' .. M.VERDICT[v][3]
    end
  end
  return table.concat(out, ' · ')
end

--- A section's rule, a blank row above it.
---@param P thread.Sheet
---@param label string
---@param width integer
---@param indent integer
local function rule(P, label, width, indent)
  P.add ''
  P.chunks(labels.rule(label, width), indent)
  P.add ''
end

--- The tours and notes, or format 2's threads, whose chunks touch it,
--- worked out: a row each, a tour with the ids of its steps that do.
---@param P thread.Sheet
---@param r thread.Review
---@param c thread.Contract
---@param T thread.Touches
---@param width integer
---@param indent integer
---@param out thread.Part[]
local function touched(P, r, c, T, width, indent, out)
  local by = T.touched[c] or {}
  local carrier = review.carrier(r)
  local any = false
  for place, x in ipairs(carrier and r.tours or {}) do
    if by[x] then
      local steps = vim.tbl_filter(function(s)
        return s.chunk ~= nil and contract.touches(c, { s.chunk })
      end, x.steps)
      local ids = vim.tbl_map(function(s)
        return '#' .. s.id
      end, steps)
      local hl = labels.colour(x.colour, place)
      local row = draw.row(P, { { '▌ ', hl }, { x.title, 'ThreadTitle' } }, { { table.concat(ids, ' '), 'ThreadMeta' } }, width, indent)
      out[#out + 1] = { kind = 'tour', first = row, last = row, thread = carrier, tour = x, step = steps[1], item = true }
      any = true
    end
  end
  for _, t in ipairs(r.threads) do
    if by[t] and not t.carrier then
      local named = thread.named(r, t) .. (t.title and (' · ' .. t.title) or '')
      local row = P.chunks(text.fit_chunks({ { '▌ ', 'ThreadSideNote' }, { named, 'ThreadText' } }, width), indent)
      out[#out + 1] = { kind = 'thread', first = row, last = row, thread = t, item = true }
      any = true
    end
  end
  if not any then
    P.chunks({ { text.fit('Nothing in the tours or the notes touches it.', width), 'ThreadMeta' } }, indent)
  end
end

--- A contract's page, whole.
---@param P thread.Sheet
---@param r thread.Review
---@param c thread.Contract
---@param o thread.ContractOpts
---@return thread.Part[]  the contract, then what in it goes somewhere
function M.page(P, r, c, o)
  local indent = o.indent or P.indent
  local top = #P.lines
  local main = side.main(o.width)
  local width = main or o.width
  local spec = chunk.spec(r.diff)
  local names = contract.names(r)
  local T = o.touches or touch.index(r)
  local g, hl = mark(c.change)
  local right = { { (c.kind and (c.kind .. ' · ') or '') .. c.change, 'ThreadMeta' } }
  local first = draw.row(P, { { g .. ' ', hl }, { c.name, 'ThreadContract' } }, right, width, indent)
  local out = { { kind = 'contract', first = first, last = first, contract = c, item = true } } ---@type thread.Part[]
  if c.why then
    draw.prose(prose.draw(P, c.why, math.min(width, PROSE), { indent = indent, hl = 'ThreadSummary', names = names }), out)
  end
  out[1].last = #P.lines - 1
  if c.text then
    P.add ''
    local at = #out + 1
    local row = #P.lines
    draw.prose(prose.draw(P, c.text, math.min(width, PROSE), { indent = indent, spec = spec, names = names }), out)
    table.insert(out, at, { kind = 'block', first = row, last = #P.lines - 1, name = 'text', item = true })
  end
  if c.at then
    P.add ''
    if o.code then
      local drawn = chunk_draw.draw(P, c.at, spec, { width = width, indent = indent })
      drawn[1].item = true
      vim.list_extend(out, drawn)
    else
      local where = { { 'at  ', 'ThreadMeta' } } ---@type thread.Chunks
      vim.list_extend(where, chunk_draw.where(c.at, chunk.locate(c.at, spec)))
      where[#where + 1] = { '  ' .. vim.trim(c.at.text), 'ThreadCode' }
      local row = P.chunks(text.fit_chunks(where, width), indent)
      out[#out + 1] = { kind = 'chunk', first = row, last = row, chunk = c.at, item = true }
    end
  end
  local shape = contract.shape(c)
  if #shape > 0 then
    rule(P, c.change == 'relied on' and 'its shape' or 'what it was, what it is', width, indent)
    for k, b in ipairs(shape) do
      if k > 1 then
        P.add ''
      end
      local at, row = #out + 1, #P.lines
      block(P, r, b, width, indent, out)
      table.insert(out, at, { kind = 'block', first = row, last = #P.lines - 1, name = 'shape:' .. k, item = true })
    end
  end
  if c.promises and #c.promises > 0 then
    rule(P, 'what callers can count on', width, indent)
    local row = #P.lines
    local at = #out + 1
    for _, x in ipairs(c.promises) do
      local pg, phl = mark(x.change)
      local lead = { pg == ' ' and '· ' or (pg .. ' '), pg == ' ' and 'ThreadMeta' or phl }
      local gone = x.change == 'removed'
      draw.prose(prose.draw(P, x.text, math.min(width, PROSE), { indent = indent, lead = lead, hl = gone and 'ThreadMeta' or nil, names = names }), out)
    end
    table.insert(out, at, { kind = 'block', first = row, last = #P.lines - 1, name = 'promises', item = true })
  end
  if c.uses and #c.uses > 0 then
    local said = tally(c.uses)
    rule(P, 'relied on by · ' .. #c.uses .. (said ~= '' and (' · ' .. said) or ''), width, indent)
    for k, u in ipairs(c.uses) do
      if k > 1 and u.note then
        P.add ''
      end
      local v = M.VERDICT[u.verdict or ''] or { '·', 'ThreadMeta' }
      local left = { { v[1] .. ' ', v[2] } } ---@type thread.Chunks
      vim.list_extend(left, chunk_draw.path(u, spec, math.min(40, math.floor(width / 2))))
      left[#left + 1] = { '  ' .. vim.trim(u.text), 'ThreadCode' }
      local row = P.chunks(text.fit_chunks(left, width), indent)
      local part = { kind = 'chunk', first = row, last = row, chunk = u, item = true } ---@type thread.Part
      out[#out + 1] = part
      if u.note then
        draw.prose(prose.draw(P, u.note, math.min(width, PROSE) - 2, { indent = indent + 2, hl = 'ThreadMeta', names = names }), out)
        part.last = #P.lines - 1
      end
    end
  end
  rule(P, 'touched by', width, indent)
  touched(P, r, c, T, width, indent, out)
  local carrier = review.carrier(r)
  if carrier then
    rule(P, 'conversation', width, indent)
    local conv = thread.about(carrier, c)
    if #conv.messages == 0 then
      P.chunks({ { text.fit('r asks or says something about it; the agent answers here.', width), 'ThreadMeta' } }, indent)
    end
    for i = 1, #conv.messages do
      if i > 1 then
        P.add ''
      end
      local drawn = message.draw(P, r, conv, i, { width = width, indent = indent })
      drawn[1].item = true
      vim.list_extend(out, drawn)
    end
    if thread.move(conv) == 'agent' then
      P.add ''
      P.chunks({ { 'waiting on the agent', 'ThreadMeta' } }, indent)
    end
  end
  if main then
    M.side(P, r, c, top, indent + main + side.GAP, T)
  end
  draw.within(out, 1, { review = r })
  return out
end

--- Its files down the right, from row `top`: where it is defined and
--- what uses it, each marked with the tours whose steps are in it.
---@param P thread.Sheet
---@param r thread.Review
---@param c thread.Contract
---@param top integer
---@param col integer
---@param T thread.Touches
function M.side(P, r, c, top, col, T)
  local all = contract.chunks(c)
  if #all == 0 then
    return
  end
  local parts = {} ---@type thread.SidePart[]
  local by = T.touched[c] or {}
  for place, x in ipairs(review.carrier(r) and r.tours or {}) do
    if by[x] then
      parts[#parts + 1] = { hl = (labels.colour(x.colour, place)), files = T.files[x] }
    end
  end
  side.beside(P, top, col, side.paths(all), parts)
end

return M
