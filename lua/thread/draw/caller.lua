--- A contract's caller, one of its dependents: the code around the line
--- that uses the contract, as the review's diff changed it, in the
--- page's view, and over it what the change cost it. A caller the
--- change missed has nothing to show changed: its code as it is, its line
--- washed red, since it needed a change it did not get. Line numbers are
--- the file's as it is; a removed line has none, but side by side, where
--- the left is the file as it was.

local chunk = require 'thread.model.chunk'
local code = require 'thread.base.code'
local diff = require 'thread.base.diff'
local draw = require 'thread.draw'
local prose = require 'thread.prose'
local review = require 'thread.model.review'
local source = require 'thread.prose.source'
local text = require 'thread.base.text'
local words = require 'thread.prose.words'

local M = {}

--- A line of a caller's file, as the diff has it: one both versions
--- share, or one it removed or added; its numbers in each.
---@class (exact) thread.CallerLine
---@field kind 'same'|'del'|'add'|'gap'  a gap: the function's lines left out
---@field old integer|nil
---@field new integer|nil
---@field text string
---@field pair string|nil  the line it was paired with across the change, for the words that changed

---@class thread.CallerOpts
---@field width integer
---@field indent integer
---@field view thread.SourceView
---@field plain boolean|nil  no colours read for its language: measuring how tall it is

-- Rows of a caller's function at most, by view; split shows each side,
-- so fewer. A longer function keeps its first line and the rows around
-- the caller's own.
local MOST = { is = 20, side = 20, split = 10 }
-- Outside any function, lines of context above and below the caller's
-- own, and rows at most.
local AROUND = { is = { 4, 5, 12 }, side = { 4, 5, 12 }, split = { 2, 2, 7 } }

--- Every line of a file as the diff has it, from its hunks: those both
--- sides share, and in each change its removed lines then its added.
---@param new string[]
---@param f thread.DiffFile|nil
---@return thread.CallerLine[]
local function whole(new, f)
  local out = {} ---@type thread.CallerLine[]
  local o, n = 1, 1
  ---@param upto integer  the last new line to take
  local function same(upto)
    while n <= upto do
      out[#out + 1] = { kind = 'same', old = o, new = n, text = new[n] }
      o, n = o + 1, n + 1
    end
  end
  for _, h in ipairs(f and f.hunks or {}) do
    for _, p in ipairs(h.parts) do
      same(p.new_count > 0 and p.new_start - 1 or p.new_start)
      local to, from = words.pair(p.old, p.new), {} ---@type table<integer, integer>, table<integer, integer>
      for k, j in pairs(to) do
        from[j] = k
      end
      for k, l in ipairs(p.old) do
        out[#out + 1] = { kind = 'del', old = o, text = l, pair = to[k] and p.new[to[k]] or nil }
        o = o + 1
      end
      for k, l in ipairs(p.new) do
        out[#out + 1] = { kind = 'add', new = n, text = l, pair = from[k] and p.old[from[k]] or nil }
        n = n + 1
      end
    end
  end
  same(#new)
  return out
end

--- A caller's lines around its own, and which of them are its own: the
--- file as the diff has it, or, missed or with no diff, as it is.
---@param r thread.Review
---@param d thread.Dependent
---@param view thread.SourceView
---@return thread.CallerLine[]|nil lines, integer first, integer last  its own, among them
function M.lines(r, d, view)
  local ch = review.chunk(r, d.chunk)
  local spec = chunk.spec(r.diff)
  local at = ch and chunk.locate(ch, spec)
  if not (ch and at) then
    return nil, 0, 0
  end
  local all ---@type thread.CallerLine[]
  local first, last ---@type integer|nil, integer|nil
  if spec and at.side and d.impact ~= 'missed' then
    all = whole(diff.lines(spec, ch.file, 'new') or {}, diff.file(spec, ch.file))
    -- Read at the base, its lines are known by their numbers there.
    local key, line = at.side == 'base' and 'old' or 'new', at.line
    for i, l in ipairs(all) do
      if l[key] == line then
        first = first or i
      end
      if l[key] == at.last then
        last = i
      end
    end
  else
    local lines = chunk.lines(ch, spec) or {}
    -- Missed, read at the base: as it is now, where that line went.
    local from, to = at.line, at.last
    if spec and at.side == 'base' and at.new then
      lines = diff.lines(spec, ch.file, 'new') or lines
      from, to = at.new, at.new + (at.last - at.line)
    end
    all = {}
    for i, l in ipairs(lines) do
      all[i] = { kind = 'same', new = i, text = l }
    end
    first, last = from, to
  end
  if not first then
    return nil, 0, 0
  end
  ---@cast first integer
  last = math.max(first, last or first)
  local most = MOST[view] or MOST.is
  local fn = M.function_of(all, ch.file, first, last, most)
  if not fn then
    local around = AROUND[view] or AROUND.is
    local before, after = around[1], around[2]
    most = around[3]
    local room = most - (last - first + 1)
    if room < before + after then
      before = math.max(0, math.min(before, math.floor(room / 2)))
      after = math.max(0, room - before)
    end
    local from = math.max(1, first - before)
    local to = math.min(#all, last + after, from + most - 1)
    return vim.list_slice(all, from, to), first - from + 1, math.min(last, to) - from + 1
  end
  local top, bottom = fn[1], fn[2]
  if bottom - top + 1 <= most then
    return vim.list_slice(all, top, bottom), first - top + 1, last - top + 1
  end
  -- Too long: from its start when the caller's lines and a few after
  -- them fit; else its first line, a gap, then the rows around them.
  local rows = most - 2
  local from = math.max(top + 1, first - 4)
  if from + rows - 1 > bottom then
    from = math.max(top + 1, bottom - rows + 1)
  end
  if from == top + 1 or math.min(bottom, last + 4) <= top + most - 1 then
    local out = vim.list_slice(all, top, top + most - 1)
    return out, first - top + 1, math.min(last, top + most - 1) - top + 1
  end
  local out = { all[top], { kind = 'gap', text = '' } }
  vim.list_extend(out, vim.list_slice(all, from, math.min(bottom, from + rows - 1)))
  return out, first - from + 3, math.min(last, from + rows - 1) - from + 3
end

--- The function a caller's lines sit in, by their places among `all`:
--- the widest that fits in `most` rows, else the narrowest; nil outside
--- any, or treesitter cannot read its language.
---@param all thread.CallerLine[]
---@param file string
---@param first integer
---@param last integer
---@param most integer
---@return { [1]: integer, [2]: integer }|nil
function M.function_of(all, file, first, last, most)
  -- Read as it is now; a removed line is where the line after it is.
  local new, at = {}, {} ---@type string[], table<integer, integer>
  for i, l in ipairs(all) do
    if l.new then
      new[l.new], at[l.new] = l.text, i
    end
  end
  local row
  for i = first, #all do
    row = row or all[i].new
  end
  local fns = row and code.enclosing(new, file, row) or {}
  local pick ---@type { [1]: integer, [2]: integer }|nil
  for _, f in ipairs(fns) do
    -- Its lines among all, the removed ones inside it too.
    local top, bottom = at[f[1]], at[f[2]]
    while top and all[top].kind == 'add' and top > 1 and all[top - 1].kind == 'del' do
      top = top - 1
    end
    if top and bottom and top <= first and bottom >= last then
      if not pick or bottom - top + 1 <= most then
        pick = { top, bottom }
      end
      if bottom - top + 1 > most then
        break
      end
    end
  end
  return pick
end

--- The lines with as much of their indent dropped as they all share.
---@param lines thread.CallerLine[]
---@return string[]
local function dedent(lines)
  local out, cut = {}, math.huge ---@type string[], integer
  for i, l in ipairs(lines) do
    out[i] = (code.untab(l.text))
    if out[i]:find '%S' then
      cut = math.min(cut, #out[i]:match '^ *')
    end
  end
  if cut == math.huge or cut == 0 then
    return out
  end
  for i, l in ipairs(out) do
    out[i] = l:sub(cut + 1)
  end
  return out
end

--- Its own line's number lit, a missed one red; the rest quiet. A line
--- with no number in this version a blank as wide.
---@param n integer|nil
---@param w integer
---@param own boolean
---@param missed boolean
---@return thread.Chunks
local function num(n, w, own, missed)
  local hl = own and (missed and 'ThreadImpactMissed' or 'ThreadLineHere') or 'ThreadLineNr'
  return { { n and string.format('%' .. w .. 'd', n) or string.rep(' ', w), hl }, { ' ' } }
end

-- Rows a line of code wraps to at most; past them it is cut.
local WRAP = 3

---@param chunks thread.Chunks
---@return string
local function joined(chunks)
  return table.concat(vim.tbl_map(function(x)
    return x[1]
  end, chunks))
end

--- The bytes of `s` from `from` that fit in `room` columns: where they
--- end, at the last space past half of them when there is one, and
--- where the next row starts, past that space.
---@param s string
---@param from integer  0-based
---@param room integer
---@return integer to, integer next  0-based, past the last byte kept
local function broken(s, from, room)
  local w, at, space = 0, from, nil ---@type integer, integer, integer|nil
  for ch in s:sub(from + 1):gmatch '[%z\1-\127\194-\244][\128-\191]*' do
    w = w + text.width(ch)
    if w > room then
      break
    end
    at = at + #ch
    if ch == ' ' and w > room / 2 then
      space = at
    end
  end
  if space then
    return space - 1, space
  end
  at = math.max(from + 1, at)
  return at, at
end

--- A cell's code from byte `s` to byte `e`, its colours with it, moved
--- right by `pad` spaces.
---@param c thread.SourceCell
---@param s integer  0-based
---@param e integer
---@param pad integer
---@return thread.Chunks, { [1]: integer, [2]: integer, [3]: string }[]|nil
local function piece(c, s, e, pad)
  local out = pad > 0 and { { string.rep(' ', pad) } } or {} ---@type thread.Chunks
  local at = 0
  for _, x in ipairs(c.chunks) do
    local a, b = math.max(s, at), math.min(e, at + #x[1])
    if a < b then
      out[#out + 1] = { x[1]:sub(a - at + 1, b - at), x[2] }
    end
    at = at + #x[1]
  end
  local syntax ---@type { [1]: integer, [2]: integer, [3]: string }[]|nil
  if c.syntax then
    syntax = {}
    for _, sp in ipairs(c.syntax) do
      local a, b = math.max(s, sp[1]), math.min(e, sp[2])
      if a < b then
        syntax[#syntax + 1] = { a - s + pad, b - s + pad, sp[3] }
      end
    end
  end
  return out, syntax
end

--- A cell as the rows it wraps to, each after the first under its code,
--- hung two past its indent, with no number or sign and the same wash.
---@param c thread.SourceCell
---@param spare integer  columns at its right kept clear
---@return thread.SourceCell[]
local function wrap(c, spare)
  local numw = text.width(joined(c.num or {}))
  local room = c.width - spare - numw - 2
  local s = joined(c.chunks)
  if room < 12 or text.width(s) <= room then
    return { c }
  end
  local hang = math.min(#s:match '^ *' + 2, math.floor(room / 3))
  local out = {} ---@type thread.SourceCell[]
  local from = 0
  while from < #s do
    local first = #out == 0
    local avail = first and room or room - hang
    local to, next = #s, #s
    if #out < WRAP - 1 then
      to, next = broken(s, from, avail)
    end
    local chunks, syntax = piece(c, from, to, first and 0 or hang)
    out[#out + 1] = {
      width = c.width,
      num = first and c.num or { { string.rep(' ', numw) } },
      sign = first and c.sign or nil,
      wash = c.wash,
      dim = c.dim,
      chunks = chunks,
      syntax = syntax,
    }
    from = next
  end
  return out
end

--- A row of cells side by side, each wrapped, the shorter filled out
--- with blank rows as wide and washed as it.
---@param P thread.Sheet
---@param cells thread.SourceCell[]
---@param indent integer
local function put(P, cells, indent)
  local each, rows = {}, 0
  for i, c in ipairs(cells) do
    each[i] = wrap(c, i < #cells and source.GAP or 0)
    rows = math.max(rows, #each[i])
  end
  for k = 1, rows do
    local row = {} ---@type thread.SourceCell[]
    for i, c in ipairs(cells) do
      row[i] = each[i][k] or { width = c.width, num = { { string.rep(' ', text.width(joined(c.num or {}))) } }, chunks = {}, wash = c.wash }
    end
    source.cells(P, row, indent)
  end
end

--- What the change cost a caller, then its code in a view; the parts of
--- that prose.
---@param P thread.Sheet
---@param r thread.Review
---@param d thread.Dependent
---@param o thread.CallerOpts
---@return thread.Part[]
function M.draw(P, r, d, o)
  local out = {} ---@type thread.Part[]
  local ch = review.chunk(r, d.chunk)
  local lines, first, last = M.lines(r, d, o.view)
  local missed = d.impact == 'missed'
  if d.text and vim.trim(d.text) ~= '' then
    draw.prose(prose.draw(P, d.text, o.width, { indent = o.indent, hl = missed and 'ThreadMissedText' or 'ThreadMeta', review = r }), out)
    P.add ''
  end
  if not (ch and lines) then
    P.chunks({ { text.fit((ch and ch.file or d.chunk) .. ' · its line is gone', o.width), 'ThreadBroken' } }, o.indent)
  else
    local said = dedent(lines)
    local changed = false
    local most = 0
    for _, l in ipairs(lines) do
      changed = changed or l.kind == 'del' or l.kind == 'add'
      most = math.max(most, l.new or 0, o.view == 'side' and l.old or 0)
    end
    local w = math.max(3, #tostring(most))
    -- Each line's colours, read in the version it is from.
    local syntax = {} ---@type table<integer, { [1]: integer, [2]: integer, [3]: string }[]>
    if not o.plain then
      for _, kind in ipairs { 'new', 'old' } do
        local idx, frag = {}, {} ---@type integer[], string[]
        for i, l in ipairs(lines) do
          if (kind == 'old') == (l.kind == 'del') then
            idx[#idx + 1], frag[#frag + 1] = i, said[i]
          end
        end
        for k, spans in pairs(code.syntax(frag, ch.file)) do
          syntax[idx[k]] = spans
        end
      end
    end
    ---@param i integer
    ---@return thread.Chunks
    local function worded(i)
      local l, pair = lines[i], lines[i].pair
      if not pair then
        return { { said[i], 'ThreadCode' } }
      end
      -- The line it pairs with, its indent cut as far as this one's was.
      local cut = #(code.untab(l.text)) - #said[i]
      local other = (code.untab(pair)):gsub('^' .. string.rep(' ?', cut), '')
      if l.kind == 'del' then
        return (words.marked(said[i], other))
      end
      local _, y = words.marked(other, said[i])
      return y
    end
    ---@param i integer
    ---@param width integer
    ---@param n integer|nil  its number here
    ---@param quiet boolean|nil  beside a change, unchanged
    ---@param bare boolean|nil  read as it is: a line added or changed a bar in the margin, not washed
    ---@return thread.SourceCell
    local function cell(i, width, n, quiet, bare)
      local l = lines[i]
      local own = i >= first and i <= last
      local c = { width = width, num = num(n, w, own, missed), chunks = { { said[i], 'ThreadCode' } }, syntax = syntax[i], dim = quiet } ---@type thread.SourceCell
      if l.kind == 'gap' then
        c.chunks, c.syntax = { { '⋯', 'ThreadMeta' } }, nil
      elseif own and missed then
        c.sign, c.wash = { '✗', 'ThreadMissedSign' }, 'ThreadMissedLine'
      elseif l.kind == 'del' then
        c.sign, c.wash, c.chunks = { '-', 'ThreadRemovedSign' }, 'ThreadDiffDelete', worded(i)
      elseif l.kind == 'add' and bare then
        c.sign = { '▎', l.pair and 'ThreadSignChanged' or 'ThreadSignAdded' }
      elseif l.kind == 'add' then
        c.sign, c.wash, c.chunks = { '+', 'ThreadAddedSign' }, 'ThreadDiffAdd', worded(i)
      end
      return c
    end
    ---@param keep fun(l: thread.CallerLine): boolean
    ---@param bare boolean|nil
    local function rows(keep, bare)
      for i, l in ipairs(lines) do
        if keep(l) then
          put(P, { cell(i, o.width, l.new, nil, bare) }, o.indent)
        end
      end
    end
    -- Unchanged, as missed is, its lines as they are in any view.
    local view = changed and o.view or 'is'
    if view == 'is' then
      rows(function(l)
        return l.kind ~= 'del'
      end, true)
    elseif view == 'split' then
      -- A side the window holds nothing of, all added or all removed, is
      -- left out, label and all.
      local was, is = false, false
      for _, l in ipairs(lines) do
        was, is = was or l.kind == 'del', is or l.kind == 'add'
      end
      if was then
        P.chunks({ { 'was', 'ThreadMetaHi' } }, o.indent + w + 1)
        rows(function(l)
          return l.kind ~= 'add'
        end)
      end
      if is then
        P.chunks({ { 'is', 'ThreadMetaHi' } }, o.indent + w + 1)
        rows(function(l)
          return l.kind ~= 'del'
        end)
      end
    else
      -- Side by side: the file as it was on the left, numbered as it was.
      local half = math.floor((o.width - source.GAP) / 2)
      local i = 1
      while i <= #lines do
        local l = lines[i]
        if l.kind == 'same' or l.kind == 'gap' then
          put(P, { cell(i, half + source.GAP, l.old, true), cell(i, half, l.new, true) }, o.indent)
          i = i + 1
        else
          local dels, adds = {}, {} ---@type integer[], integer[]
          while lines[i] and lines[i].kind == 'del' do
            dels[#dels + 1], i = i, i + 1
          end
          while lines[i] and lines[i].kind == 'add' do
            adds[#adds + 1], i = i, i + 1
          end
          local olds = vim.tbl_map(function(k)
            return lines[k].text
          end, dels)
          local news = vim.tbl_map(function(k)
            return lines[k].text
          end, adds)
          for _, row in ipairs(words.aligned(olds, news)) do
            local a, b = row.a and dels[row.a], row.b and adds[row.b]
            local blank = { width = half + source.GAP, chunks = {}, num = num(nil, w, false, false) } ---@type thread.SourceCell
            put(P, {
              a and cell(a, half + source.GAP, lines[a].old) or blank,
              b and cell(b, half, lines[b].new) or vim.tbl_extend('force', blank, { width = half }),
            }, o.indent)
          end
        end
      end
    end
  end
  return out
end

return M
