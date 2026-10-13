--- A chunk drawn: where it is, then its code as it is now. On a hunk of
--- its review's diff it is the hunk, as a diff, and the rows around the
--- chunk when the hunk is long; on plain code, its lines and a few either
--- side, washed. A bar marks the chunk's own lines, and the numbers of
--- the notes on a line end it. One the code no longer has says so.

local chunk = require 'thread.model.chunk'
local code = require 'thread.base.code'
local diff = require 'thread.base.diff'
local git = require 'thread.base.git'
local labels = require 'thread.draw.labels'
local note = require 'thread.prose.note'
local source = require 'thread.base.source'
local text = require 'thread.base.text'

local M = {}

-- Rows of code at most, and lines either side of plain code.
M.ROWS, M.AROUND = 40, 2

---@class thread.ChunkOpts
---@field width integer
---@field indent integer|nil  else the sheet's
---@field around integer|nil  plain code: lines either side of it
---@field rows integer|nil  rows of code at most
---@field notes thread.Note[]|nil  numbered on their lines, where drawn
---@field accepted boolean|nil  its state in its thread, shown when given

--- A row of code: its number in its side, its sign, and whether it is
--- one of the chunk's.
---@class thread.ChunkRow: thread.DiffRow
---@field on boolean

-- The bar, the number, the sign: the columns before the code.
local BAR, PREFIX = '▎', 8

--- Where a chunk is: `file:12–18`, then what is not the code now.
---@param c thread.Chunk
---@param at thread.Located|nil  where it is now; nil when it is gone
---@return thread.Chunks
function M.where(c, at)
  if not at then
    return { { c.file .. ':' .. c.line, 'Directory' }, { ' · its line is gone', 'ThreadBroken' } }
  end
  local first = at.old or at.line
  local span = (c.lines or 1) > 1 and (first .. '–' .. (first + c.lines - 1)) or tostring(first)
  local out = { { c.file .. ':' .. span, 'Directory' } } ---@type thread.Chunks
  if at.old then
    out[#out + 1] = { ' · removed', 'ThreadMeta' }
  elseif c.rev then
    out[#out + 1] = { ' · at ' .. git.short(c.rev), 'ThreadMeta' }
  end
  if at.confidence < 1 then
    out[#out + 1] = { ' · not as quoted', 'ThreadBroken' }
  end
  return out
end

--- Where a chunk is, short, for the right of a row: `thread.lua:134`.
---@param c thread.Chunk
---@param spec thread.DiffSpec|nil
---@return { [1]: string, [2]: string }
function M.short(c, spec)
  local at = chunk.locate(c, spec)
  if not at then
    return { vim.fs.basename(c.file) .. ' · gone', 'ThreadBroken' }
  end
  return { vim.fs.basename(c.file) .. ':' .. (at.old or at.line) .. (at.old and ' · removed' or ''), 'LineNr' }
end

--- A hunk's rows, the chunk's own `on`.
---@param spec thread.DiffSpec
---@param c thread.Chunk
---@param at thread.Located
---@param h thread.DiffHunk
---@return thread.ChunkRow[]
local function hunk_rows(spec, c, at, h)
  local first = at.old or at.line
  local last = first + (c.lines or 1) - 1
  return vim.tbl_map(function(r)
    return { num = r.num, sign = r.sign, line = r.line, on = ((r.sign == '-') == (at.old ~= nil)) and r.num >= first and r.num <= last }
  end, diff.rows(spec, h))
end

--- Plain code's rows: its lines, and `around` either side.
---@param c thread.Chunk
---@param at thread.Located
---@param around integer
---@return thread.ChunkRow[]
local function plain_rows(c, at, around)
  local lines = source.lines_of(c) or {}
  local last = at.line + (c.lines or 1) - 1
  local rows = {} ---@type thread.ChunkRow[]
  for n = math.max(1, at.line - around), math.min(#lines, last + around) do
    rows[#rows + 1] = { num = n, sign = ' ', line = lines[n], on = n >= at.line and n <= last }
  end
  return rows
end

--- The notes on each row that would show them, by the row's key: `-12`
--- a removed line, `12` any other.
---@param c thread.Chunk
---@param notes thread.Note[]
---@param spec thread.DiffSpec|nil
---@return table<string, integer[]>  row key -> the notes' numbers
local function noted(c, notes, spec)
  local out = {} ---@type table<string, integer[]>
  for k, n in ipairs(notes) do
    if n.file == c.file and n.rev == c.rev then
      local at = chunk.locate(n, spec)
      if at then
        local key = at.old and ('-' .. at.old) or tostring(at.line)
        out[key] = out[key] or {}
        table.insert(out[key], k)
      end
    end
  end
  return out
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
    rows = (at.hunk and spec) and hunk_rows(spec, c, at, at.hunk) or plain_rows(c, at, o.around or M.AROUND)
  end
  local from, to = window(rows, o.rows or M.ROWS)
  local where = {} ---@type thread.Chunks
  if o.accepted ~= nil then
    local g, hl = labels.accepted(o.accepted)
    where[#where + 1] = { g .. ' ', hl }
  end
  vim.list_extend(where, M.where(c, at))
  if at and at.hunk then
    vim.list_extend(where, { { '  +' .. at.hunk.add, 'ThreadAdded' }, { ' −' .. at.hunk.del, 'ThreadRemoved' } })
    if to - from + 1 < #rows then
      where[#where + 1] = { string.format(' · %d of its %d rows', to - from + 1, #rows), 'ThreadMeta' }
    end
  end
  local first = P.chunks(text.fit_chunks(where, o.width), indent)
  local out = { { kind = 'chunk', first = first, last = first, chunk = c } } ---@type thread.Part[]
  if not at then
    return out
  end
  local nums = noted(c, o.notes or {}, spec)
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
    local ks = nums[(r.sign == '-' and '-' or '') .. r.num]
    local tail = ks and ('  ' .. table.concat(vim.tbl_map(note.num, ks))) or ''
    local head = string.rep(' ', indent) .. (r.on and BAR or ' ') .. string.format('%4d', r.num) .. ' ' .. r.sign .. ' '
    local drawn, shift = code.untab(r.line)
    local body = text.fit(drawn, o.width - PREFIX - text.width(tail))
    -- What of the line is shown: up to the `…` when it is cut.
    local kept = body == drawn and #body or #body - #'…'
    local row = P.add(head .. body .. tail)
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
    if ks then
      P.hl(row, col + #body, -1, 'ThreadNoteNum', { priority = 30 })
      for _, k in ipairs(ks) do
        local s, e = note.mark((o.notes or {})[k], r.line)
        if s and e then
          paint(s, e, 'ThreadNoteMark', 40)
        end
      end
    end
    local line = { file = c.file, line = r.num, text = r.line, side = r.sign == '-' and 'old' or nil, rev = r.sign ~= '-' and c.rev or nil } ---@type thread.Chunk
    out[#out + 1] = { kind = 'line', first = row, last = row, chunk = line }
  end
  if to < #rows then
    P.chunks({ { gap }, { text.fit('⋯ ' .. text.plural(#rows - to, 'line') .. ' below', o.width - PREFIX), 'ThreadMeta' } }, indent)
  end
  out[1].last = #P.lines - 1
  return out
end

return M
