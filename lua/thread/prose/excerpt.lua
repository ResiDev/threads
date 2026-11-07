--- An excerpt: a chunk of the topic quoted in prose, `{{chunk:id}}` alone
--- on a line, its lines read from the file each time it is drawn, with
--- its file's colours: fifteen at most. On a hunk of the topic's diff,
--- it is drawn as what the change did to those lines. The names the prose
--- puts in backticks before it are lit where they stand in it. It is a
--- quotation, not something the topic is about: it adds no file and
--- cannot be accepted.

local chunk = require 'thread.model.chunk'
local code = require 'thread.base.code'
local git = require 'thread.base.git'
local text = require 'thread.base.text'

---@class (exact) thread.Excerpt
---@field id string  the chunk's, as written
---@field chunk thread.Chunk|nil  none: the topic has no chunk by that id
---@field spec thread.DiffSpec|nil  what its topic is about
---@field names string[]|nil  what the prose put in backticks since the last thing it placed

local M = {}

M.MOST = 15

-- A changed line wraps to this many rows at most, so what changed in a
-- long one is seen; the rest are cut at the width.
local WRAPS = 3

--- Where a line is split to wrap in `room` columns: each piece's first
--- byte and last, `most` pieces at most, never inside a character.
---@param s string
---@param room integer
---@param most integer
---@return { [1]: integer, [2]: integer }[]
local function pieces(s, room, most)
  local out, from = {}, 1
  while from <= #s and #out < most do
    local to = math.min(#s, from + room - 1)
    to = to + vim.str_utf_end(s, to)
    out[#out + 1] = { from, to }
    from = to + 1
  end
  return out
end

--- One line of code into a sheet in `width` columns: its number, its
--- sign when the excerpt is `signed`, then the line in its colours, a tab
--- drawn as four spaces. A removed or added line is washed as a diff
--- washes it and wraps, its number on its first row alone; any other is
--- cut at the width.
---@param P thread.Sheet
---@param indent integer
---@param width integer
---@param r thread.DiffRow
---@param signed boolean
---@param spans { [1]: integer, [2]: integer, [3]: string, [4]: table|nil }[]|nil
local function code_line(P, indent, width, r, signed, spans)
  local lead = string.format('%4d ', r.num) .. (signed and r.sign .. ' ' or ' ')
  local room = width - #lead
  local drawn, at = code.untab(r.line)
  local parts ---@type { [1]: integer, [2]: integer }[]
  if r.sign == ' ' or text.width(drawn) <= room then
    local body = text.fit(drawn, room)
    parts = { { 1, body == drawn and #body or #body - #'…', body } }
  else
    parts = pieces(drawn, room, WRAPS)
    local last = parts[#parts]
    if last[2] < #drawn then
      local body = text.fit(drawn:sub(last[1]), room)
      last[2], last[3] = last[1] + #body - #'…' - 1, body
    end
  end
  for k, piece in ipairs(parts) do
    local prefix = string.rep(' ', indent) .. (k == 1 and lead or string.rep(' ', #lead))
    local body = piece[3] or drawn:sub(piece[1], piece[2])
    local row = P.add(prefix .. (r.sign == ' ' and body or text.pad(body, room)))
    P.hl(row, indent, indent + 4, 'LineNr')
    if r.sign ~= ' ' then
      P.hl(row, indent + 5, #prefix + #text.pad(body, room), r.sign == '+' and 'ThreadDiffAdd' or 'ThreadDiffDelete')
      if k == 1 then
        P.hl(row, indent + 5, indent + 6, r.sign == '+' and 'ThreadAdded' or 'ThreadRemoved', { priority = 30 })
      end
    end
    for _, s in ipairs(spans or {}) do
      local from, to = math.max(at(s[1]), piece[1] - 1), math.min(at(s[2]), piece[2])
      if from < to then
        P.hl(row, #prefix + from - piece[1] + 1, #prefix + to - piece[1] + 1, s[3], s[4])
      end
    end
  end
end

--- Where a chunk is, `file:12–18`, then what is not the code now: said
--- as draw/chunk says it, which this layer is under.
---@param c thread.Chunk
---@param at thread.Located|nil  where it is now; nil when it is gone
---@return thread.Chunks
function M.where(c, at)
  if not at then
    return { { c.file .. ':' .. c.line, 'Directory' }, { ' · its line is gone', 'ThreadBroken' } }
  end
  local span = at.last > at.line and (at.line .. '–' .. at.last) or tostring(at.line)
  local where = { { c.file .. ':' .. span, 'Directory' } } ---@type thread.Chunks
  if at.side == 'base' then
    where[#where + 1] = { at.removed and ' · removed' or ' · as it was', 'ThreadMeta' }
  elseif at.rev == '' then
    where[#where + 1] = { ' · staged', 'ThreadMeta' }
  elseif at.rev and not at.side then
    where[#where + 1] = { ' · at ' .. git.short(at.rev), 'ThreadMeta' }
  end
  if at.confidence < 1 or not at.to then
    where[#where + 1] = { ' · not as quoted', 'ThreadBroken' }
  end
  return where
end

--- Where an excerpt is, and its lines: nil lines when the code no longer
--- has it. Where says what is not the code now: a chunk at the base, at a
--- commit, or found only by likeness.
---@param x thread.Excerpt
---@param width integer
---@return thread.Chunks where, string[]|nil lines, thread.Located|nil at
local function place(x, width)
  local c = x.chunk
  if not c then
    return text.fit_chunks({ { '{{chunk:' .. x.id .. '}}', 'ThreadCode' }, { ' · no chunk has that id', 'ThreadBroken' } }, width)
  end
  local lines, at = chunk.code(c, x.spec)
  if not (lines and at) then
    return text.fit_chunks(
      { { c.file .. ':' .. c.line, 'Directory' }, { ' · its line is gone: ', 'ThreadBroken' }, { vim.trim(c.from), 'ThreadCode' } },
      width
    )
  end
  return text.fit_chunks(M.where(c, at), width), lines, at
end

--- An excerpt's rows: its lines; on the topic's diff, what the change
--- did to them. At the head, its added lines marked, and the lines a
--- part of the diff removed above what replaced them, when the excerpt
--- holds all of that: a line it rewrote, not a block in a rewrite. At the
--- base, its removed lines marked.
---@param x thread.Excerpt
---@param lines string[]
---@param at thread.Located
---@return thread.DiffRow[]
local function rows_of(x, lines, at)
  local hunks = at.hunks or (at.hunk and { at.hunk })
  local signs, before = {}, {} ---@type table<integer, '+'|'-'>, table<integer, thread.DiffRow[]>
  for _, h in ipairs(x.spec and at.side and hunks or {}) do
    for _, p in ipairs(h.parts) do
      if at.side == 'base' then
        for k = p.old_start, p.old_start + p.old_count - 1 do
          signs[k] = '-'
        end
      else
        local last = p.new_start + p.new_count - 1
        for k = p.new_start, last do
          signs[k] = '+'
        end
        -- A removal alone hangs after its line, so before the next.
        local under = p.new_count > 0 and p.new_start or p.new_start + 1
        local held = p.new_count > 0 and at.line <= p.new_start and last <= at.last or p.new_count == 0 and under > at.line and under <= at.last
        if held then
          local rows = {} ---@type thread.DiffRow[]
          for k, l in ipairs(p.old) do
            rows[k] = { sign = '-', num = p.old_start + k - 1, line = l }
          end
          before[under] = vim.list_extend(before[under] or {}, rows)
        end
      end
    end
  end
  local out = {} ---@type thread.DiffRow[]
  for i, l in ipairs(lines) do
    local n = at.line + i - 1
    vim.list_extend(out, before[n] or {})
    out[#out + 1] = { sign = signs[n] or ' ', num = n, line = l }
  end
  return out
end

--- Where the names in `x` stand whole in a line, lit.
---@param x thread.Excerpt
---@param line string
---@return { [1]: integer, [2]: integer, [3]: string, [4]: table }[]
local function named(x, line)
  local out = {}
  for _, written in ipairs(x.names or {}) do
    for _, f in ipairs(text.forms(written)) do
      local found = text.whole(line, f)
      for _, s in ipairs(found) do
        out[#out + 1] = { s[1] - 1, s[2], 'ThreadNamed', { priority = 40 } }
      end
      if #found > 0 then
        break
      end
    end
  end
  return out
end

--- Draw an excerpt in `width` columns: where it is, then its rows,
--- numbered and coloured, fifteen at most and a row saying how many more.
---@param P thread.Sheet
---@param x thread.Excerpt
---@param indent integer
---@param width integer
---@return integer first, integer last  its rows
function M.draw(P, x, indent, width)
  local first = #P.lines
  local where, lines, at = place(x, width)
  if not (lines and at and x.chunk) then
    P.chunks(where, indent)
    return first, first
  end
  local rows = rows_of(x, lines, at)
  -- All of it new: the marks would say only that, so its place says it.
  if vim.iter(rows):all(function(r)
    return r.sign == '+'
  end) then
    for _, r in ipairs(rows) do
      r.sign = ' '
    end
    where = text.fit_chunks(vim.list_extend(where, { { ' · added', 'ThreadMeta' } }), width)
  end
  P.chunks(where, indent)
  local shown = vim.list_slice(rows, 1, M.MOST)
  local spans = code.syntax(
    vim.tbl_map(function(r)
      return r.line
    end, shown),
    x.chunk.file
  )
  local signed = vim.iter(rows):any(function(r)
    return r.sign ~= ' '
  end)
  for i, r in ipairs(shown) do
    code_line(P, indent, width, r, signed, vim.list_extend(spans[i] or {}, named(x, r.line)))
  end
  if #rows > #shown then
    P.chunks({ { string.format('      ⋯ %d more lines', #rows - #shown), 'ThreadMeta' } }, indent)
  end
  return first, #P.lines - 1
end

--- An excerpt in one row: where it is, as `draw` says it.
---@param P thread.Sheet
---@param x thread.Excerpt
---@param indent integer
---@param width integer
---@return integer row
function M.line(P, x, indent, width)
  return P.chunks((place(x, width)), indent)
end

return M
