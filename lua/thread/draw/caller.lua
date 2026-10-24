--- A contract's caller, one of its dependents: the code around the line
--- that uses the contract, as the review's diff changed it, in the
--- page's view, and under it what the change cost it. A caller the
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
---@field kind 'same'|'del'|'add'
---@field old integer|nil
---@field new integer|nil
---@field text string
---@field pair string|nil  the line it was paired with across the change, for the words that changed

---@class thread.CallerOpts
---@field width integer
---@field indent integer
---@field view thread.SourceView
---@field plain boolean|nil  no colours read for its language: measuring how tall it is

-- Lines of context above and below the caller's own, and rows at most,
-- by view; split shows each side, so fewer. A long chunk shows its start.
local AROUND = { inline = { 4, 5, 12 }, is = { 4, 5, 12 }, side = { 4, 5, 12 }, split = { 2, 2, 7 } }

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
  local around = AROUND[view] or AROUND.inline
  local before, after, most = around[1], around[2], around[3]
  local room = most - (last - first + 1)
  if room < before + after then
    before = math.max(0, math.min(before, math.floor(room / 2)))
    after = math.max(0, room - before)
  end
  local from = math.max(1, first - before)
  local to = math.min(#all, last + after, from + most - 1)
  return vim.list_slice(all, from, to), first - from + 1, math.min(last, to) - from + 1
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

--- A caller's code in a view, then what the change cost it; the parts of
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
  if not (ch and lines) then
    P.chunks({ { text.fit((ch and ch.file or d.chunk) .. ' · its line is gone', o.width), 'ThreadBroken' } }, o.indent)
  else
    local said = dedent(lines)
    local changed = false
    local most = 0
    for _, l in ipairs(lines) do
      changed = changed or l.kind ~= 'same'
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
    ---@return thread.SourceCell
    local function cell(i, width, n, quiet)
      local l = lines[i]
      local own = i >= first and i <= last
      local c = { width = width, num = num(n, w, own, missed), chunks = { { said[i], 'ThreadCode' } }, syntax = syntax[i], dim = quiet } ---@type thread.SourceCell
      if own and missed then
        c.sign, c.wash = { '✗', 'ThreadMissedSign' }, 'ThreadMissedLine'
      elseif l.kind == 'del' then
        c.sign, c.wash, c.chunks = { '-', 'ThreadRemovedSign' }, 'ThreadDiffDelete', worded(i)
      elseif l.kind == 'add' then
        c.sign, c.wash, c.chunks = { '+', 'ThreadAddedSign' }, 'ThreadDiffAdd', worded(i)
      end
      return c
    end
    ---@param keep fun(l: thread.CallerLine): boolean
    local function rows(keep)
      for i, l in ipairs(lines) do
        if keep(l) then
          source.cells(P, { cell(i, o.width, l.new) }, o.indent)
        end
      end
    end
    local view = changed and o.view or 'inline'
    if view == 'inline' then
      rows(function()
        return true
      end)
    elseif view == 'is' then
      rows(function(l)
        return l.kind ~= 'del'
      end)
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
        if l.kind == 'same' then
          source.cells(P, { cell(i, half + source.GAP, l.old, true), cell(i, half, l.new, true) }, o.indent)
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
            source.cells(P, {
              a and cell(a, half + source.GAP, lines[a].old) or blank,
              b and cell(b, half, lines[b].new) or vim.tbl_extend('force', blank, { width = half }),
            }, o.indent)
          end
        end
      end
    end
  end
  if d.text and vim.trim(d.text) ~= '' then
    P.add ''
    draw.prose(prose.draw(P, d.text, o.width, { indent = o.indent, hl = missed and 'ThreadMissedText' or 'ThreadMeta', review = r }), out)
  end
  return out
end

return M
