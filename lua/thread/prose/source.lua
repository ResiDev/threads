--- A contract itself, as its page and prose that places it both draw
--- it: as it is, what changed marked; against as it was, its two sides
--- as one diff, the words that changed lit, or as two blocks when most of
--- it changed; side by side; or the one side it has. Its rows are cells
--- of code, which a caller's code is drawn in too (thread.draw.caller).

local chunk = require 'thread.model.chunk'
local code = require 'thread.base.code'
local git = require 'thread.base.git'
local review = require 'thread.model.review'
local text = require 'thread.base.text'
local words = require 'thread.prose.words'

local M = {}

--- Where a chunk is, to head a side read from it.
---@alias thread.SourceWhere fun(c: thread.Chunk, at: thread.Located|nil): thread.Chunks

--- A row heading a side, and the chunk it is read from.
---@class (exact) thread.SourceHead
---@field row integer
---@field chunk thread.Chunk

--- A side's lines, and where they come from: a chunk's as they read, or
--- the contract written out; and a file name that says its language.
---@param r thread.Review|nil
---@param s thread.Side|nil
---@param where thread.SourceWhere
---@return string[]|nil lines, thread.Chunks|nil where, thread.Chunk|nil c, string|nil file
local function lines_of(r, s, where)
  if s == nil then
    return nil
  elseif type(s) == 'table' then
    return vim.split(s.text, '\n', { plain = true }), { { 'written out · ' .. s.lang, 'ThreadMeta' } }, nil, 'contract.' .. s.lang
  end
  ---@cast s string
  local c = r and review.chunk(r, s)
  if not (r and c) then
    return nil
  end
  local spec = chunk.spec(r.diff)
  local lines, at = chunk.code(c, spec)
  return lines or {}, where(c, at), c, c.file
end

--- One row of a side: its sign, then its text, lit as `chunks` say and
--- coloured as its language by `syntax`, the line's spans. A sign given
--- with its colour is a mark in the margin alone, the row not washed.
---@param P thread.Sheet
---@param sign string|{ [1]: string, [2]: string }
---@param chunks thread.Chunks
---@param width integer
---@param indent integer
---@param syntax { [1]: integer, [2]: integer, [3]: string }[]|nil
---@param bound boolean|nil  washed only as wide as `width`, its sign too
---@return integer row
local function row_of(P, sign, chunks, width, indent, syntax, bound)
  local wash = sign == '+' and 'ThreadDiffAdd' or sign == '-' and 'ThreadDiffDelete' or nil
  local mark = sign == '+' and (bound and 'ThreadAddedSign' or 'ThreadAdded')
    or sign == '-' and (bound and 'ThreadRemovedSign' or 'ThreadRemoved')
    or 'ThreadMeta'
  if type(sign) == 'table' then
    sign, mark = sign[1], sign[2]
  end
  local line = { { sign .. ' ', mark } } ---@type thread.Chunks
  for _, c in ipairs(chunks) do
    line[#line + 1] = { (c[1]:gsub('\t', '    ')), c[2] }
  end
  local row = P.chunks(text.fit_chunks(line, width), indent)
  if wash and bound then
    local w = text.width(P.lines[row + 1]) - indent
    P.hl(row, indent + 1, -1, wash, { priority = 5 })
    if w < width then
      P.mark(row, 0, { virt_text = { { string.rep(' ', width - w), wash } }, virt_text_win_col = indent + w, priority = 5 })
    end
  elseif wash then
    P.hl(row, indent + 2, -1, wash, { hl_eol = true, priority = 5 })
  end
  local raw = {} ---@type string[]
  for _, c in ipairs(chunks) do
    raw[#raw + 1] = c[1]
  end
  local drawn, shift = code.untab(table.concat(raw))
  local col = indent + #sign + 1
  -- What of the line is shown: up to the `…` when it is cut.
  local kept = #P.lines[row + 1] - col
  if kept < #drawn then
    kept = kept - #'…'
  end
  for _, sp in ipairs(syntax or {}) do
    local s, e = shift(sp[1]), math.min(shift(sp[2]), kept)
    if s < e then
      P.hl(row, col + s, col + e, sp[3], { priority = 20 })
    end
  end
  return row
end

--- A cell of a row of code: a line's number, its sign, then the code,
--- `width` columns; washed from its sign when `wash`, quiet when `dim`.
---@class (exact) thread.SourceCell
---@field width integer
---@field chunks thread.Chunks  the code, lit where it changed
---@field num thread.Chunks|nil  before its sign, never washed
---@field sign { [1]: string, [2]: string }|nil  else a space
---@field wash string|nil
---@field syntax { [1]: integer, [2]: integer, [3]: string }[]|nil  the line's spans, in bytes of its code
---@field dim boolean|nil  unchanged, beside what changed: its colours left out

--- A row of cells side by side, each cut or padded to its width, the
--- last washed only as wide as its width by a mark, so no row ends in
--- spaces.
---@param P thread.Sheet
---@param cells thread.SourceCell[]
---@param indent integer
---@return integer row
function M.cells(P, cells, indent)
  local line = {} ---@type thread.Chunks
  local at = {} ---@type { s: integer, e: integer, code: integer, kept: integer, col: integer, w: integer }[]
  local byte, col = indent, 0
  for i, c in ipairs(cells) do
    local lead = vim.deepcopy(c.num or {})
    local sign = c.sign or { ' ' }
    local s_byte = byte + #table.concat(vim.tbl_map(function(x)
      return x[1]
    end, lead))
    lead[#lead + 1] = { sign[1], sign[2] }
    lead[#lead + 1] = { ' ' }
    local lead_bytes = #table.concat(vim.tbl_map(function(x)
      return x[1]
    end, lead))
    local all = vim.list_extend({}, lead)
    for _, x in ipairs(c.chunks) do
      all[#all + 1] = { (x[1]:gsub('\t', '    ')), c.dim and 'ThreadMeta' or x[2] }
    end
    local fitted = text.fit_chunks(all, c.width)
    local drawn = table.concat(vim.tbl_map(function(x)
      return x[1]
    end, fitted))
    local kept = #drawn - lead_bytes
    if text.width(drawn) < text.width(all) then
      kept = kept - #'…'
    end
    local w = text.width(drawn)
    if i < #cells and w < c.width then
      fitted[#fitted + 1] = { string.rep(' ', c.width - w) }
    end
    vim.list_extend(line, fitted)
    local first = byte
    for _, x in ipairs(fitted) do
      byte = byte + #x[1]
    end
    at[i] = { s = s_byte, e = byte, code = first + lead_bytes, kept = math.max(0, kept), col = col, w = w }
    col = col + (i < #cells and c.width or w)
  end
  local row = P.chunks(line, indent)
  for i, c in ipairs(cells) do
    local a = at[i]
    if c.wash then
      P.hl(row, a.s, i < #cells and a.e or -1, c.wash, { priority = 5 })
      if i == #cells and a.w < c.width then
        P.mark(row, 0, { virt_text = { { string.rep(' ', c.width - a.w), c.wash } }, virt_text_win_col = indent + a.col + a.w, priority = 5 })
      end
    end
    if not c.dim then
      local raw = table.concat(vim.tbl_map(function(x)
        return x[1]
      end, c.chunks))
      local _, shift = code.untab(raw)
      for _, sp in ipairs(c.syntax or {}) do
        local s, e = shift(sp[1]), math.min(shift(sp[2]), a.kept)
        if s < e then
          P.hl(row, a.code + s, a.code + e, sp[3], { priority = 20 })
        end
      end
    end
  end
  return row
end

--- How much of a contract to draw, and how.
---@class (exact) thread.SourceOpts
---@field against boolean|nil  as it was too, not only as it is
---@field head string|nil  the colour of `was` and `is`, set one over the other; else the sign's
---@field bound boolean|nil  each row washed only as wide as it is drawn, not to the window's edge
---@field most integer|nil  rows of code at most, each side's when drawn apart; past them a row says how many more
---@field view thread.SourceView|nil  a page's view of it, its heads only when split; else as `against` says

--- How a page shows a change: as it was, then as it is; the two side by
--- side; or as it is alone, what changed marked in the margin.
---@alias thread.SourceView 'split'|'side'|'is'

-- Columns between the two sides set side by side.
M.GAP = 3

--- Whether a contract has a side as it was to set it against: one
--- changed, not added or removed.
---@param c thread.Contract
---@return boolean
function M.before(c)
  return c.source.change == 'changed'
end

--- Two sides beside each other, a line beside the line it became: the
--- lines they share quiet on both, a run that changed `-` on the left and
--- `+` on the right, a line beside the one it became, its words that
--- changed lit; past
--- `most` rows, a row says how many more.
---@param P thread.Sheet
---@param before string[]
---@param after string[]
---@param changes thread.LineChange[]
---@param syntax { [1]: table<integer, { [1]: integer, [2]: integer, [3]: string }[]>, [2]: table<integer, { [1]: integer, [2]: integer, [3]: string }[]> }
---@param o { width: integer, indent: integer, most: integer|nil }
local function side_by_side(P, before, after, changes, syntax, o)
  local half = math.floor((o.width - M.GAP) / 2)
  local rows = {} ---@type { [1]: thread.SourceCell, [2]: thread.SourceCell }[]
  ---@param sign string|nil
  ---@param chunks thread.Chunks|nil
  ---@param spans { [1]: integer, [2]: integer, [3]: string }[]|nil
  ---@param left boolean
  ---@return thread.SourceCell
  local function cell(sign, chunks, spans, left)
    local w = left and half + M.GAP or half
    if not chunks then
      return { width = w, chunks = {}, sign = { ' ' } }
    end
    if sign == ' ' then
      return { width = w, chunks = chunks, dim = true }
    end
    local add = sign == '+'
    return {
      width = w,
      chunks = chunks,
      syntax = spans,
      sign = { sign, add and 'ThreadAddedSign' or 'ThreadRemovedSign' },
      wash = add and 'ThreadDiffAdd' or 'ThreadDiffDelete',
    }
  end
  local i, j = 1, 1
  ---@param upto_i integer
  ---@param upto_j integer
  local function same(upto_i, upto_j)
    while i <= upto_i or j <= upto_j do
      local a, b = before[i], after[j]
      rows[#rows + 1] = {
        cell(' ', a and { { a, 'ThreadCode' } }, nil, true),
        cell(' ', b and { { b, 'ThreadCode' } }, nil, false),
      }
      i, j = i + 1, j + 1
    end
  end
  for _, h in ipairs(changes) do
    same(h.old_count > 0 and h.old_start - 1 or h.old_start, h.new_count > 0 and h.new_start - 1 or h.new_start)
    local olds = vim.list_slice(before, h.old_start, h.old_start + h.old_count - 1)
    local news = vim.list_slice(after, h.new_start, h.new_start + h.new_count - 1)
    for _, row in ipairs(words.aligned(h.old_count > 0 and olds or {}, h.new_count > 0 and news or {})) do
      local a, b = row.a and olds[row.a], row.b and news[row.b]
      local x, y = a and { { a, 'ThreadCode' } }, b and { { b, 'ThreadCode' } }
      if a and b and row.paired then
        x, y = words.marked(a, b)
      end
      rows[#rows + 1] = {
        cell('-', x, a and syntax[1][h.old_start + row.a - 1], true),
        cell('+', y, b and syntax[2][h.new_start + row.b - 1], false),
      }
    end
    i = h.old_count > 0 and h.old_start + h.old_count or h.old_start + 1
    j = h.new_count > 0 and h.new_start + h.new_count or h.new_start + 1
  end
  same(#before, #after)
  local shown = o.most and math.min(o.most, #rows) or #rows
  for k = 1, shown do
    M.cells(P, rows[k], o.indent)
  end
  if shown < #rows then
    P.chunks({ { text.fit('… ' .. text.plural(#rows - shown, 'more line'), o.width), 'ThreadMeta' } }, o.indent)
  end
end

--- The contract itself. Alone, as it is, the lines the change added or
--- changed marked `+`, the words that changed lit unless most of it
--- changed. With `against`, as it was too: its sides as one
--- diff, `-` and `+` rows with the words that changed lit; or, when most
--- of it changed, the side as it was and then as it is. One added or
--- removed is the one side it has. Where each side is read from heads it,
--- `where` saying a chunk's place; the files of the sides drawn come back
--- too, none for one written out. A page's `view` says which of those it
--- is, or the two sides beside each other, the lines they share quiet.
---@param P thread.Sheet
---@param r thread.Review|nil
---@param c thread.Contract
---@param width integer
---@param indent integer
---@param where thread.SourceWhere
---@param o thread.SourceOpts|nil  none: as it is, alone
---@return thread.SourceHead[]  the rows that head a side read from a chunk
---@return table<string, true> files  those the sides drawn are read from
function M.draw(P, r, c, width, indent, where, o)
  local out = {} ---@type thread.SourceHead[]
  local s = c.source
  local bound = o and o.bound
  local view = o and o.view
  local against = o and (o.against or (view ~= nil and view ~= 'is'))
  local before, bwhere, bchunk, bfile = lines_of(r, s.before, where)
  local after, awhere, achunk, afile = lines_of(r, s.after, where)
  local bsyntax = before and code.syntax(before, assert(bfile)) or {}
  local asyntax = after and code.syntax(after, assert(afile)) or {}
  local files = {} ---@type table<string, true>
  if achunk then
    files[achunk.file] = true
  end
  if bchunk and (not after or against) then
    files[bchunk.file] = true
  end
  ---@param label string
  ---@param hl string
  ---@param at thread.Chunks|nil  where it is read from
  ---@param ch thread.Chunk|nil
  local function head(label, hl, at, ch)
    if view and view ~= 'split' then
      return
    end
    local said = { { o and o.head and text.pad(label, 3) or label, o and o.head or hl } } ---@type thread.Chunks
    if at then
      said[#said + 1] = { '  ' }
      vim.list_extend(said, at)
    end
    local row = P.chunks(text.fit_chunks(said, width), indent)
    if ch then
      out[#out + 1] = { row = row, chunk = ch }
    end
  end
  local left, past = o and o.most, 0
  --- A row of code, while there is room for it.
  ---@param sign string|{ [1]: string, [2]: string }
  ---@param chunks thread.Chunks
  ---@param syntax { [1]: integer, [2]: integer, [3]: string }[]|nil
  local function put(sign, chunks, syntax)
    if left and left <= 0 then
      past = past + 1
      return
    end
    left = left and left - 1
    row_of(P, sign, chunks, width, indent, syntax, bound)
  end
  --- How many rows there was no room for, said; room again.
  local function more()
    if past > 0 then
      P.chunks({ { text.fit('… ' .. text.plural(past, 'more line'), width), 'ThreadMeta' } }, indent)
    end
    left, past = o and o.most, 0
  end
  ---@param list string[]
  ---@param sign string|{ [1]: string, [2]: string }
  ---@param syntax table<integer, { [1]: integer, [2]: integer, [3]: string }[]>
  local function block(list, sign, syntax)
    for k, l in ipairs(list) do
      put(sign, { { l, 'ThreadCode' } }, syntax[k])
    end
    more()
  end
  if not (before and after) then
    local only = after or before or {}
    -- Set beside the other kind of contract, `was` or `is` alone.
    local label = o and o.head and (after and 'is' or 'was') or (after and 'as it is' or 'as it was')
    head(label, after and 'ThreadAdded' or 'ThreadRemoved', after and awhere or bwhere, after and achunk or bchunk)
    -- Read as it is on a page, added: a green bar in the margin, no wash.
    local sign = after and (view == 'is' and { '▎', 'ThreadSignAdded' } or '+') or '-'
    block(only, sign, after and asyntax or bsyntax)
    return out, files
  end
  local changes = git.changes(before, after)
  -- Lines, a line paired with its new version counting as much of it as
  -- changed.
  local changed = 0
  for _, h in ipairs(changes) do
    changed = changed + math.abs(h.old_count - h.new_count)
    for k = 0, math.min(h.old_count, h.new_count) - 1 do
      changed = changed + words.share(before[h.old_start + k], after[h.new_start + k])
    end
  end
  local mostly = changed > words.MOSTLY * math.max(#before, #after, 1)
  if view == 'side' then
    side_by_side(P, before, after, changes, { bsyntax, asyntax }, { width = width, indent = indent, most = o and o.most })
    return out, files
  end
  if not against then
    head('as it is', 'ThreadAdded', awhere, achunk)
    local j = 1
    for _, h in ipairs(changes) do
      local upto = h.new_count > 0 and h.new_start - 1 or h.new_start
      while j <= upto do
        put(' ', { { after[j], 'ThreadCode' } }, asyntax[j])
        j = j + 1
      end
      -- On a page, each line paired with the one most like it.
      local from = {} ---@type table<integer, integer>
      if view then
        local p =
          words.pair(vim.list_slice(before, h.old_start, h.old_start + h.old_count - 1), vim.list_slice(after, h.new_start, h.new_start + h.new_count - 1))
        for k, to in pairs(p) do
          from[to - 1] = k - 1
        end
      end
      for k = 0, h.new_count - 1 do
        local y = { { after[h.new_start + k], 'ThreadCode' } } ---@type thread.Chunks
        if view then
          -- On a page, read as it is: a bar in the margin, blue where a
          -- line changed, green where one was added; no wash, no words.
          put({ '▎', from[k] and 'ThreadSignChanged' or 'ThreadSignAdded' }, y, asyntax[h.new_start + k])
        else
          -- The line it replaced, the words that changed; not when most of
          -- it changed, where the pairs say little.
          if k < h.old_count and not mostly then
            _, y = words.marked(before[h.old_start + k], after[h.new_start + k])
          end
          put('+', y, asyntax[h.new_start + k])
        end
      end
      j = h.new_count > 0 and h.new_start + h.new_count or h.new_start + 1
    end
    while j <= #after do
      put(' ', { { after[j], 'ThreadCode' } }, asyntax[j])
      j = j + 1
    end
    more()
    return out, files
  end
  head('was', 'ThreadRemoved', bwhere, bchunk)
  if view == 'split' or (not view and mostly) then
    block(before, '-', bsyntax)
    head('is', 'ThreadAdded', awhere, achunk)
    block(after, '+', asyntax)
    return out, files
  end
  head('is', 'ThreadAdded', awhere, achunk)
  local i = 1
  for _, h in ipairs(changes) do
    local upto = h.old_count > 0 and h.old_start - 1 or h.old_start
    while i <= upto do
      put(' ', { { before[i], 'ThreadCode' } }, bsyntax[i])
      i = i + 1
    end
    local pairs_ = math.min(h.old_count, h.new_count)
    local olds, news = {}, {} ---@type thread.Chunks[], thread.Chunks[]
    for k = 0, h.old_count - 1 do
      olds[k + 1] = { { before[h.old_start + k], 'ThreadCode' } }
    end
    for k = 0, h.new_count - 1 do
      news[k + 1] = { { after[h.new_start + k], 'ThreadCode' } }
    end
    if view then
      -- A page pairs each line with the one most like it, however much
      -- of it changed.
      local p =
        words.pair(vim.list_slice(before, h.old_start, h.old_start + h.old_count - 1), vim.list_slice(after, h.new_start, h.new_start + h.new_count - 1))
      for k, to in pairs(p) do
        olds[k], news[to] = words.marked(before[h.old_start + k - 1], after[h.new_start + to - 1])
      end
      pairs_ = 0
    end
    for k = 1, mostly and 0 or pairs_ do
      olds[k], news[k] = words.marked(before[h.old_start + k - 1], after[h.new_start + k - 1])
    end
    for k, x in ipairs(olds) do
      put('-', x, bsyntax[h.old_start + k - 1])
    end
    for k, y in ipairs(news) do
      put('+', y, asyntax[h.new_start + k - 1])
    end
    i = h.old_count > 0 and h.old_start + h.old_count or h.old_start + 1
  end
  while i <= #before do
    put(' ', { { before[i], 'ThreadCode' } }, bsyntax[i])
    i = i + 1
  end
  more()
  return out, files
end

return M
