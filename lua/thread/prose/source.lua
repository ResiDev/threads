--- A contract itself, as its page and prose that places it both draw
--- it: as it is, what changed marked; against as it was, its two sides
--- as one diff, the words that changed lit, or as two blocks when most of
--- it changed; or the one side it has.

local chunk = require 'thread.model.chunk'
local code = require 'thread.base.code'
local git = require 'thread.base.git'
local review = require 'thread.model.review'
local text = require 'thread.base.text'

local M = {}

--- Where a chunk is, to head a side read from it.
---@alias thread.SourceWhere fun(c: thread.Chunk, at: thread.Located|nil): thread.Chunks

--- A row heading a side, and the chunk it is read from.
---@class (exact) thread.SourceHead
---@field row integer
---@field chunk thread.Chunk

-- More of it changed than this, and the sides are drawn as two blocks.
M.MOSTLY = 0.6

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

--- How many tokens two runs keep in common from each place on, by a
--- longest common run: `L[i][j]` for `A` from `i` and `B` from `j`.
---@param A string[]
---@param B string[]
---@return integer[][]
local function common(A, B)
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
  return L
end

--- How much of a line changed, from 0 to 1: its tokens the other version
--- does not keep. A signature is one line, so counting lines alone would
--- call any change to it most of it.
---@param a string
---@param b string
---@return number
local function share(a, b)
  local A, B = tokens(a), tokens(b)
  local most = math.max(#A, #B)
  return most == 0 and 0 or 1 - common(A, B)[1][1] / most
end

--- Two versions of a line, each as chunks, what the other has not lit:
--- the tokens either side kept in common by a longest common run.
---@param a string
---@param b string
---@return thread.Chunks before, thread.Chunks after
function M.marked(a, b)
  local A, B = tokens(a), tokens(b)
  local L = common(A, B)
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
      put(y, B[j], 'ThreadDiffAddWord')
      j = j + 1
    else
      put(x, A[i], 'ThreadDiffDeleteWord')
      i = i + 1
    end
  end
  return x, y
end

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
--- coloured as its language by `syntax`, the line's spans.
---@param P thread.Sheet
---@param sign string
---@param chunks thread.Chunks
---@param width integer
---@param indent integer
---@param syntax { [1]: integer, [2]: integer, [3]: string }[]|nil
---@return integer row
local function row_of(P, sign, chunks, width, indent, syntax)
  local wash = sign == '+' and 'ThreadDiffAdd' or sign == '-' and 'ThreadDiffDelete' or nil
  local line = { { sign .. ' ', sign == '+' and 'ThreadAdded' or sign == '-' and 'ThreadRemoved' or 'ThreadMeta' } } ---@type thread.Chunks
  for _, c in ipairs(chunks) do
    line[#line + 1] = { (c[1]:gsub('\t', '    ')), c[2] }
  end
  local row = P.chunks(text.fit_chunks(line, width), indent)
  if wash then
    P.hl(row, indent + 2, -1, wash, { hl_eol = true, priority = 5 })
  end
  local raw = {} ---@type string[]
  for _, c in ipairs(chunks) do
    raw[#raw + 1] = c[1]
  end
  local drawn, shift = code.untab(table.concat(raw))
  local col = indent + 2
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

--- How much of a contract to draw.
---@class (exact) thread.SourceOpts
---@field against boolean|nil  as it was too, not only as it is

--- Whether a contract has a side as it was to set it against: one
--- changed, not added or removed.
---@param c thread.Contract
---@return boolean
function M.before(c)
  return c.source.change == 'changed'
end

--- The contract itself. Alone, as it is, the lines the change added or
--- changed marked `+`, the words that changed lit unless most of it
--- changed. With `against`, as it was too: its sides as one
--- diff, `-` and `+` rows with the words that changed lit; or, when most
--- of it changed, the side as it was and then as it is. One added or
--- removed is the one side it has. Where each side is read from heads it,
--- `where` saying a chunk's place; the files of the sides drawn come back
--- too, none for one written out.
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
  local before, bwhere, bchunk, bfile = lines_of(r, s.before, where)
  local after, awhere, achunk, afile = lines_of(r, s.after, where)
  local bsyntax = before and code.syntax(before, assert(bfile)) or {}
  local asyntax = after and code.syntax(after, assert(afile)) or {}
  local files = {} ---@type table<string, true>
  if achunk then
    files[achunk.file] = true
  end
  if bchunk and (not after or o and o.against) then
    files[bchunk.file] = true
  end
  ---@param label string
  ---@param hl string
  ---@param at thread.Chunks|nil  where it is read from
  ---@param ch thread.Chunk|nil
  local function head(label, hl, at, ch)
    local said = { { label, hl } } ---@type thread.Chunks
    if at then
      said[#said + 1] = { '  ' }
      vim.list_extend(said, at)
    end
    local row = P.chunks(text.fit_chunks(said, width), indent)
    if ch then
      out[#out + 1] = { row = row, chunk = ch }
    end
  end
  ---@param list string[]
  ---@param sign string
  ---@param syntax table<integer, { [1]: integer, [2]: integer, [3]: string }[]>
  local function block(list, sign, syntax)
    for k, l in ipairs(list) do
      row_of(P, sign, { { l, 'ThreadCode' } }, width, indent, syntax[k])
    end
  end
  if not (before and after) then
    local only = after or before or {}
    head(after and 'as it is' or 'as it was', after and 'ThreadAdded' or 'ThreadRemoved', after and awhere or bwhere, after and achunk or bchunk)
    block(only, after and '+' or '-', after and asyntax or bsyntax)
    return out, files
  end
  local changes = git.changes(before, after)
  -- Lines, a line paired with its new version counting as much of it as
  -- changed.
  local changed = 0
  for _, h in ipairs(changes) do
    changed = changed + math.abs(h.old_count - h.new_count)
    for k = 0, math.min(h.old_count, h.new_count) - 1 do
      changed = changed + share(before[h.old_start + k], after[h.new_start + k])
    end
  end
  local mostly = changed > M.MOSTLY * math.max(#before, #after, 1)
  if not (o and o.against) then
    head('as it is', 'ThreadAdded', awhere, achunk)
    local j = 1
    for _, h in ipairs(changes) do
      local upto = h.new_count > 0 and h.new_start - 1 or h.new_start
      while j <= upto do
        row_of(P, ' ', { { after[j], 'ThreadCode' } }, width, indent, asyntax[j])
        j = j + 1
      end
      for k = 0, h.new_count - 1 do
        local y = { { after[h.new_start + k], 'ThreadCode' } } ---@type thread.Chunks
        -- Paired with the line it replaced, the words that changed; not
        -- when most of it changed, where the pairs say little.
        if k < h.old_count and not mostly then
          _, y = M.marked(before[h.old_start + k], after[h.new_start + k])
        end
        row_of(P, '+', y, width, indent, asyntax[h.new_start + k])
      end
      j = h.new_count > 0 and h.new_start + h.new_count or h.new_start + 1
    end
    while j <= #after do
      row_of(P, ' ', { { after[j], 'ThreadCode' } }, width, indent, asyntax[j])
      j = j + 1
    end
    return out, files
  end
  head('was', 'ThreadRemoved', bwhere, bchunk)
  if mostly then
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
      row_of(P, ' ', { { before[i], 'ThreadCode' } }, width, indent, bsyntax[i])
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
    for k = 1, pairs_ do
      olds[k], news[k] = M.marked(before[h.old_start + k - 1], after[h.new_start + k - 1])
    end
    for k, x in ipairs(olds) do
      row_of(P, '-', x, width, indent, bsyntax[h.old_start + k - 1])
    end
    for k, y in ipairs(news) do
      row_of(P, '+', y, width, indent, asyntax[h.new_start + k - 1])
    end
    i = h.old_count > 0 and h.old_start + h.old_count or h.old_start + 1
  end
  while i <= #before do
    row_of(P, ' ', { { before[i], 'ThreadCode' } }, width, indent, bsyntax[i])
    i = i + 1
  end
  return out, files
end

return M
