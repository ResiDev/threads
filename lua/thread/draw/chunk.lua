--- A chunk drawn: where it is, then its code as it is now. On a hunk of
--- its review's diff it is the hunk, as a diff, and the rows around the
--- chunk when the hunk is long; on plain code, its lines and a few either
--- side, washed; across hunks, each and the lines between. A bar marks
--- the chunk's own lines. One the code no
--- longer has says so.

local chunk = require 'thread.model.chunk'
local code = require 'thread.base.code'
local diff = require 'thread.base.diff'
local git = require 'thread.base.git'
local labels = require 'thread.draw.labels'
local text = require 'thread.base.text'

local M = {}

-- Rows of code at most, and lines either side of plain code.
M.ROWS, M.AROUND = 30, 2

---@class thread.ChunkOpts
---@field width integer
---@field indent integer|nil  else the sheet's
---@field around integer|nil  plain code: lines either side of it
---@field rows integer|nil  rows of code at most
---@field accepted boolean|nil  its state, shown when given

--- A row of code: its number in its side, its sign, and whether it is
--- one of the chunk's.
---@class thread.ChunkRow: thread.DiffRow
---@field on boolean

-- The bar, the number, the sign: the columns before the code.
local BAR, PREFIX = '▎', 8

--- What is not the code now about where a chunk is read: at the diff's
--- base, at a commit, in the index; found only by likeness.
---@param at thread.Located
---@return thread.Chunks
local function said(at)
  local out = {} ---@type thread.Chunks
  if at.side == 'base' then
    out[#out + 1] = { at.removed and ' · removed' or ' · as it was', 'ThreadMeta' }
  elseif at.rev == '' then
    out[#out + 1] = { ' · staged', 'ThreadMeta' }
  elseif at.rev and not at.side then
    out[#out + 1] = { ' · at ' .. git.short(at.rev), 'ThreadMeta' }
  end
  if at.confidence < 1 or not at.to then
    out[#out + 1] = { ' · not as quoted', 'ThreadBroken' }
  end
  return out
end

--- Where a chunk is: `file:12–18`, then what is not the code now.
---@param c thread.Chunk
---@param at thread.Located|nil  where it is now; nil when it is gone
---@return thread.Chunks
function M.where(c, at)
  if not at then
    return { { c.file .. ':' .. c.line, 'Directory' }, { ' · its line is gone', 'ThreadBroken' } }
  end
  local span = at.last > at.line and (at.line .. '–' .. at.last) or tostring(at.line)
  return vim.list_extend({ { c.file .. ':' .. span, 'Directory' } }, said(at))
end

--- Where a chunk is, its path as far as `room` lets it, for a block's
--- head: `draw/note.lua:134`, the file the brightest; a path cut short
--- loses its first directories, since many files share a name.
---@param c thread.Chunk
---@param spec thread.DiffSpec|nil
---@param room integer  columns at most
---@return thread.Chunks
function M.path(c, spec, room)
  local at = chunk.locate(c, spec)
  local tail = at and (':' .. at.line .. (at.removed and ' · removed' or '')) or ' · gone'
  local base = vim.fs.basename(c.file)
  local dir = c.file:sub(1, #c.file - #base)
  local left = room - text.width(base) - text.width(tail)
  if text.width(dir) > left then
    -- Whole directories off the front, then an ellipsis.
    local parts = vim.split(dir, '/', { trimempty = true })
    while #parts > 0 and text.width('…/' .. table.concat(parts, '/') .. '/') > left do
      table.remove(parts, 1)
    end
    dir = #parts > 0 and ('…/' .. table.concat(parts, '/') .. '/') or ''
  end
  return { { dir, 'ThreadMeta' }, { base, at and 'Directory' or 'ThreadBroken' }, { tail, at and 'ThreadMeta' or 'ThreadBroken' } }
end

--- Where a chunk is, short, for the right of a row: `note.lua:134`.
---@param c thread.Chunk
---@param spec thread.DiffSpec|nil
---@return { [1]: string, [2]: string }
function M.short(c, spec)
  local at = chunk.locate(c, spec)
  if not at then
    return { vim.fs.basename(c.file) .. ' · gone', 'ThreadBroken' }
  end
  return { vim.fs.basename(c.file) .. ':' .. at.line .. (at.removed and ' · removed' or ''), 'LineNr' }
end

--- A hunk's rows, the chunk's own `on`.
---@param spec thread.DiffSpec
---@param at thread.Located
---@param h thread.DiffHunk
---@return thread.ChunkRow[]
local function hunk_rows(spec, at, h)
  local base = at.side == 'base'
  return vim.tbl_map(function(r)
    return { num = r.num, sign = r.sign, line = r.line, on = ((r.sign == '-') == base) and r.num >= at.line and r.num <= at.last }
  end, diff.rows(spec, h))
end

--- The rows of every hunk a chunk is on, the unchanged lines between
--- two of them in between, so a chunk across hunks is drawn whole.
---@param c thread.Chunk
---@param spec thread.DiffSpec
---@param at thread.Located
---@return thread.ChunkRow[]
local function hunks_rows(c, spec, at)
  local base = at.side == 'base'
  local lines = chunk.lines(c, spec) or {}
  local rows, last = {}, nil ---@type thread.ChunkRow[], integer|nil
  for _, h in ipairs(at.hunks or { at.hunk }) do
    local these = hunk_rows(spec, at, h)
    -- Rows of its side: a removal's on the base, the rest on the head.
    local mine = vim.tbl_filter(function(r)
      return (r.sign == '-') == base
    end, these)
    if last and mine[1] then
      for n = last + 1, mine[1].num - 1 do
        rows[#rows + 1] = { num = n, sign = ' ', line = lines[n] or '', on = n >= at.line and n <= at.last }
      end
    end
    vim.list_extend(rows, these)
    last = mine[#mine] and mine[#mine].num or last
  end
  return rows
end

--- Plain code's rows: its lines, and `around` either side.
---@param c thread.Chunk
---@param spec thread.DiffSpec|nil
---@param at thread.Located
---@param around integer
---@return thread.ChunkRow[]
local function plain_rows(c, spec, at, around)
  local lines = chunk.lines(c, spec) or {}
  local rows = {} ---@type thread.ChunkRow[]
  for n = math.max(1, at.line - around), math.min(#lines, at.last + around) do
    rows[#rows + 1] = { num = n, sign = ' ', line = lines[n], on = n >= at.line and n <= at.last }
  end
  return rows
end

--- The rows to draw of `rows`, `cap` at most: from a few above the
--- chunk's first, as many as there is room for.
---@param rows thread.ChunkRow[]
---@param cap integer
---@return integer from, integer to
local function window(rows, cap)
  if #rows <= cap then
    return 1, #rows
  end
  local on = 1
  for i, r in ipairs(rows) do
    if r.on then
      on = i
      break
    end
  end
  local from = math.max(1, math.min(on - math.min(10, math.floor(cap / 4)), #rows - cap + 1))
  return from, from + cap - 1
end

--- Draw a chunk: where it is, then its code, `width` columns from
--- `indent`. One that is gone is one row.
---@param P thread.Sheet
---@param c thread.Chunk
---@param spec thread.DiffSpec|nil  what its review is about: a chunk on its diff is drawn as its hunk
---@param o thread.ChunkOpts
---@return thread.Part[]  the chunk, then each line of its code
function M.draw(P, c, spec, o)
  local indent = o.indent or P.indent
  local at = chunk.locate(c, spec)
  local rows = {} ---@type thread.ChunkRow[]
  if at then
    rows = (at.hunk and spec) and hunks_rows(c, spec, at) or plain_rows(c, spec, at, o.around or M.AROUND)
  end
  local from, to = window(rows, o.rows or M.ROWS)
  local where = {} ---@type thread.Chunks
  if o.accepted ~= nil then
    local g, hl = labels.accepted(o.accepted)
    where[#where + 1] = { g .. ' ', hl }
  end
  vim.list_extend(where, M.where(c, at))
  if at and at.hunk then
    local add, del = 0, 0
    for _, h in ipairs(at.hunks or { at.hunk }) do
      add, del = add + h.add, del + h.del
    end
    vim.list_extend(where, { { '  +' .. add, 'ThreadAdded' }, { ' −' .. del, 'ThreadRemoved' } })
    if to - from + 1 < #rows then
      where[#where + 1] = { string.format(' · %d of its %d rows', to - from + 1, #rows), 'ThreadMeta' }
    end
  end
  local first = P.chunks(text.fit_chunks(where, o.width), indent)
  local out = { { kind = 'chunk', first = first, last = first, chunk = c } } ---@type thread.Part[]
  if not at then
    return out
  end
  local gap = string.rep(' ', PREFIX)
  if from > 1 then
    P.chunks({ { gap }, { text.fit('⋯ ' .. text.plural(from - 1, 'line') .. ' above', o.width - PREFIX), 'ThreadMeta' } }, indent)
  end
  -- Colours, read from each side's lines in a run.
  local syntax = {} ---@type table<string, table<integer, { [1]: integer, [2]: integer, [3]: string }[]>>
  for _, side in ipairs { '-', ' ' } do
    local lines = {} ---@type string[]
    for i = from, to do
      if (rows[i].sign == '-') == (side == '-') then
        lines[#lines + 1] = rows[i].line
      end
    end
    syntax[side] = code.syntax(lines, c.file)
  end
  local seen = { ['-'] = 0, [' '] = 0 }
  for i = from, to do
    local r = rows[i]
    local side = r.sign == '-' and '-' or ' '
    seen[side] = seen[side] + 1
    local head = string.rep(' ', indent) .. (r.on and BAR or ' ') .. string.format('%4d', r.num) .. ' ' .. r.sign .. ' '
    local drawn, shift = code.untab(r.line)
    local body = text.fit(drawn, o.width - PREFIX)
    -- What of the line is shown: up to the `…` when it is cut.
    local kept = body == drawn and #body or #body - #'…'
    local row = P.add(head .. body)
    local col = #head
    if r.on then
      P.hl(row, indent, indent + #BAR, 'ThreadLeads')
    end
    local num_at = indent + (r.on and #BAR or 1)
    P.hl(row, num_at, num_at + 4, 'LineNr')
    if r.sign ~= ' ' then
      P.hl(row, num_at + 5, -1, r.sign == '+' and 'ThreadDiffAdd' or 'ThreadDiffDelete', { hl_eol = true, priority = 10 })
      P.hl(row, num_at + 5, num_at + 6, r.sign == '+' and 'ThreadAdded' or 'ThreadRemoved', { priority = 30 })
    elseif r.on and not at.hunk then
      P.hl(row, col, -1, 'ThreadRange', { hl_eol = true, priority = 10 })
    end
    ---@param s integer  in the line as read
    ---@param e integer
    ---@param group string
    ---@param priority integer
    local function paint(s, e, group, priority)
      s, e = shift(s), math.min(shift(e), kept)
      if s < e then
        P.hl(row, col + s, col + e, group, { priority = priority })
      end
    end
    for _, sp in ipairs(syntax[side][seen[side]] or {}) do
      paint(sp[1], sp[2], sp[3], 20)
    end
    local rev = r.sign == '-' and 'base' or (at.hunk and 'head') or c.rev
    local line = { id = c.id, file = c.file, line = r.num, from = r.line, rev = rev } ---@type thread.Chunk
    out[#out + 1] = { kind = 'line', first = row, last = row, chunk = line }
  end
  if to < #rows then
    P.chunks({ { gap }, { text.fit('⋯ ' .. text.plural(#rows - to, 'line') .. ' below', o.width - PREFIX), 'ThreadMeta' } }, indent)
  end
  out[1].last = #P.lines - 1
  return out
end

return M
