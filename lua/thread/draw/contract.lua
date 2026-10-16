--- A contract's page: the contract itself as a diff of its two sides, the
--- words that changed lit, or as two blocks when most of it changed; its
--- prose; its blast radius, the code that depends on it grouped by how
--- far the change reached it, `missed` first, with what each had to do;
--- the tours, steps and notes that touch it, worked out; and its
--- conversation. Its files down the right, as a review's are.

local chunk = require 'thread.model.chunk'
local chunk_draw = require 'thread.draw.chunk'
local code = require 'thread.base.code'
local contract = require 'thread.model.contract'
local contracts = require 'thread.draw.contracts'
local conversation = require 'thread.model.conversation'
local draw = require 'thread.draw'
local git = require 'thread.base.git'
local labels = require 'thread.draw.labels'
local message = require 'thread.draw.message'
local note_draw = require 'thread.draw.note'
local prose = require 'thread.prose'
local review = require 'thread.model.review'
local side = require 'thread.draw.side'
local text = require 'thread.base.text'
local touch = require 'thread.model.touch'

local M = {}

---@class thread.ContractOpts
---@field width integer
---@field indent integer|nil  else the sheet's
---@field touches thread.Touches|nil  what touches what in the review, else worked out

-- The widest prose reads well at.
local PROSE = 100

-- More of it changed than this, and the sides are drawn as two blocks.
M.MOSTLY = 0.6

-- How each impact is said, and its colour.
M.IMPACT = {
  missed = { '✗', 'ThreadVerdictBad', 'missed' },
  reworked = { '↻', 'ThreadVerdictWarn', 'reworked' },
  adapted = { '~', 'ThreadVerdictInfo', 'adapted' },
  none = { '·', 'ThreadMeta', 'not reached' },
}

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
---@param r thread.Review
---@param s thread.Side|nil
---@return string[]|nil lines, thread.Chunks|nil where, thread.Chunk|nil c, string|nil file
local function lines_of(r, s)
  if s == nil then
    return nil
  elseif type(s) == 'table' then
    return vim.split(s.text, '\n', { plain = true }), { { 'written out · ' .. s.lang, 'ThreadMeta' } }, nil, 'contract.' .. s.lang
  end
  ---@cast s string
  local c = review.chunk(r, s)
  if not c then
    return nil
  end
  local spec = chunk.spec(r.diff)
  local lines, at = chunk.code(c, spec)
  return lines or {}, chunk_draw.where(c, at), c, c.file
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

--- The contract itself: its sides as one diff, `-` and `+` rows with the
--- words that changed lit; or, when most of it changed, the side as it
--- was and then as it is; or the one side it has. Where each side is
--- read from heads it, an item that goes there.
---@param P thread.Sheet
---@param r thread.Review
---@param c thread.Contract
---@param width integer
---@param indent integer
---@param out thread.Part[]
local function source(P, r, c, width, indent, out)
  local s = c.source
  local before, bwhere, bchunk, bfile = lines_of(r, s.before)
  local after, awhere, achunk, afile = lines_of(r, s.after)
  local bsyntax = before and code.syntax(before, assert(bfile)) or {}
  local asyntax = after and code.syntax(after, assert(afile)) or {}
  ---@param label string
  ---@param hl string
  ---@param where thread.Chunks|nil
  ---@param ch thread.Chunk|nil
  local function head(label, hl, where, ch)
    local said = { { label, hl } } ---@type thread.Chunks
    if where then
      said[#said + 1] = { '  ' }
      vim.list_extend(said, where)
    end
    local row = P.chunks(text.fit_chunks(said, width), indent)
    if ch then
      out[#out + 1] = { kind = 'chunk', first = row, last = row, chunk = ch, item = true }
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
    return
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
  head('was', 'ThreadRemoved', bwhere, bchunk)
  if changed > M.MOSTLY * math.max(#before, #after, 1) then
    block(before, '-', bsyntax)
    head('is', 'ThreadAdded', awhere, achunk)
    block(after, '+', asyntax)
    return
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

--- The blast radius: the code that depends on it, by how far the change
--- reached it, the furthest first; each dependent where it is and its
--- line, what it had to do under it.
---@param P thread.Sheet
---@param r thread.Review
---@param c thread.Contract
---@param width integer
---@param indent integer
---@param out thread.Part[]
local function radius(P, r, c, width, indent, out)
  local groups = contract.radius(c)
  local said = vim.tbl_map(function(g)
    return #g.dependents .. ' ' .. M.IMPACT[g.impact][3]
  end, groups)
  rule(P, 'blast radius · ' .. #(c.dependents or {}) .. (#said > 0 and (' · ' .. table.concat(said, ' · ')) or ''), width, indent)
  if #groups == 0 then
    P.chunks({ { text.fit('Nothing depends on it, as the agent found.', width), 'ThreadMeta' } }, indent)
    return
  end
  local spec = chunk.spec(r.diff)
  for k, g in ipairs(groups) do
    if k > 1 then
      P.add ''
    end
    local mark = M.IMPACT[g.impact]
    P.chunks({ { mark[1] .. ' ' .. mark[3] .. ' · ' .. #g.dependents, mark[2] } }, indent)
    for _, d in ipairs(g.dependents) do
      local ch = review.chunk(r, d.chunk)
      local left = {} ---@type thread.Chunks
      local lines = ch and chunk.code(ch, spec)
      if ch then
        vim.list_extend(left, chunk_draw.path(ch, spec, math.min(40, math.floor(width / 2))))
        left[#left + 1] = { '  ' .. vim.trim(lines and lines[1] or ch.from), 'ThreadCode' }
      end
      local row = P.chunks(text.fit_chunks(left, width - 2), indent + 2)
      local part = { kind = 'chunk', first = row, last = row, chunk = ch, item = true } ---@type thread.Part
      out[#out + 1] = part
      if d.text then
        draw.prose(prose.draw(P, d.text, math.min(width, PROSE) - 4, { indent = indent + 4, hl = 'ThreadMeta', review = r }), out)
        part.last = #P.lines - 1
      end
    end
  end
end

--- The tours, steps and notes whose chunks touch it, worked out: a tour
--- a row with the ids of its steps that do, a note a row.
---@param P thread.Sheet
---@param r thread.Review
---@param c thread.Contract
---@param T thread.Touches
---@param width integer
---@param indent integer
---@param out thread.Part[]
local function touched(P, r, c, T, width, indent, out)
  local by = T.touched[c] or {}
  local any = false
  for place, x in ipairs(r.tours) do
    if by[x] then
      local steps = vim.tbl_filter(function(s)
        return by[s] == true
      end, x.steps)
      local ids = vim.tbl_map(function(s)
        return 'step ' .. s.id
      end, steps)
      local hl = labels.colour(x.colour, place)
      local row = draw.row(P, { { '▌ ', hl }, { x.title, 'ThreadTitle' } }, { { table.concat(ids, ' · '), 'ThreadMeta' } }, width, indent)
      out[#out + 1] = { kind = 'tour', first = row, last = row, tour = x, step = steps[1], item = true }
      any = true
    end
  end
  for _, n in ipairs(r.notes) do
    if by[n] then
      out[#out + 1] = note_draw.row(P, r, n, { width = width, indent = indent, label = true })
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
  local T = o.touches or touch.index(r)
  local sign = contract.sign(c)
  local right = { { c.kind .. ' · ' .. c.source.change, 'ThreadMeta' } }
  local first = draw.row(P, { { sign .. ' ', contracts.COLOUR[sign] }, { c.name, 'ThreadContract' } }, right, width, indent)
  local out = { { kind = 'contract', first = first, last = first, contract = c, item = true } } ---@type thread.Part[]
  if c.why then
    draw.prose(prose.draw(P, c.why, math.min(width, PROSE), { indent = indent, hl = 'ThreadSummary', review = r }), out)
  end
  P.add ''
  local at, row = #out + 1, #P.lines
  source(P, r, c, width, indent, out)
  table.insert(out, at, { kind = 'block', first = row, last = #P.lines - 1, name = 'source', item = true })
  if c.prose.text ~= '' then
    P.add ''
    at, row = #out + 1, #P.lines
    draw.prose(prose.draw(P, c.prose, math.min(width, PROSE), { indent = indent, review = r }), out)
    table.insert(out, at, { kind = 'block', first = row, last = #P.lines - 1, name = 'prose', item = true })
  end
  radius(P, r, c, width, indent, out)
  rule(P, 'touched by', width, indent)
  touched(P, r, c, T, width, indent, out)
  rule(P, 'conversation', width, indent)
  local conv = conversation.of_contract(c)
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
  if conversation.move(conv) == 'agent' then
    P.add ''
    P.chunks({ { 'waiting on the agent', 'ThreadMeta' } }, indent)
  end
  if main then
    M.side(P, r, c, top, indent + main + side.GAP, T)
  end
  draw.within(out, 1, { review = r, contract = c })
  return out
end

--- Its files down the right, from row `top`: its sides' and its
--- dependents', each marked with the tours whose steps are in it.
---@param P thread.Sheet
---@param r thread.Review
---@param c thread.Contract
---@param top integer
---@param col integer
---@param T thread.Touches
function M.side(P, r, c, top, col, T)
  local all = T.chunks[c] or {}
  if #all == 0 then
    return
  end
  local parts = {} ---@type thread.SidePart[]
  local by = T.touched[c] or {}
  for place, x in ipairs(r.tours) do
    if by[x] then
      parts[#parts + 1] = { hl = (labels.colour(x.colour, place)), files = T.files[x] }
    end
  end
  side.beside(P, top, col, side.paths(all), parts)
end

return M
