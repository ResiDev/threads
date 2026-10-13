--- A note: a line a message or a step points at, a word on it picked
--- out, and what it says. Where it is in the code is its chunk's; here is
--- what drawing it anywhere shares: its number, where its mark is on its
--- line, and what it says, listed under its number, with its line or
--- without.

local chunk = require 'thread.model.chunk'
local code = require 'thread.base.code'
local look = require 'thread.ui.look'
local prose = require 'thread.prose'
local text = require 'thread.base.text'

local M = {}

--- A note's number, `①`, by its place among its message's or step's.
---@param k integer
---@return string
function M.num(k)
  return look.num(k)
end

--- Where a note's mark is on its line: byte columns, from 0, its end not
--- in it. Nil with no mark, or one not on the line.
---@param n thread.Note
---@param line string  its line as it reads now
---@return integer|nil s, integer|nil e
function M.mark(n, line)
  if not n.mark or n.mark == '' then
    return nil
  end
  local s = line:find(n.mark, 1, true)
  if s then
    return s - 1, s - 1 + #n.mark
  end
end

--- What a note says, under its number: `① the only check`, wrapped to
--- `width` and hung under its text, an excerpt in it drawn as its code.
--- Nothing when it says nothing.
---@param P thread.Sheet
---@param k integer
---@param n thread.Note
---@param width integer
---@param o thread.ProseOpts|nil
---@return thread.Drawn[]  the note, all its rows, then what in it goes somewhere
function M.draw(P, k, n, width, o)
  o = o or {}
  if not n.note or vim.trim(n.note) == '' then
    return {}
  end
  local out = { { first = #P.lines, last = #P.lines, chunk = n } } ---@type thread.Drawn[]
  vim.list_extend(out, prose.draw(P, n.note, width, { indent = o.indent, spec = o.spec, lead = { M.num(k) .. ' ', 'ThreadNoteNum' }, hl = 'ThreadNote' }))
  out[1].last = #P.lines - 1
  return out
end

--- A note with its line: its number, where it is and its line as it
--- reads now, its indent dropped, coloured, its mark picked out; then what
--- it says, hung under. One whose line is gone says so.
---@param P thread.Sheet
---@param k integer
---@param n thread.Note
---@param width integer
---@param o thread.ProseOpts|nil
---@return thread.Drawn[]  the note, all its rows, then what in its text goes somewhere
function M.line(P, k, n, width, o)
  o = o or {}
  local indent = o.indent or P.indent
  local num = M.num(k) .. ' '
  local first = #P.lines
  local lines, at = chunk.code(n, o.spec)
  local head = { { num, 'ThreadNoteNum' }, { n.file .. ':' .. (at and (at.old or at.line) or n.line), 'Directory' } } ---@type thread.Chunks
  local line = lines and lines[1]
  if not line then
    head[#head + 1] = { ' · its line is gone', 'ThreadBroken' }
    P.chunks(text.fit_chunks(head, width), indent)
  else
    if at and at.old then
      head[#head + 1] = { ' · removed', 'ThreadMeta' }
    end
    head[#head + 1] = { '  ' }
    head = text.fit_chunks(head, width)
    local drawn, shift = code.untab(line)
    local skip = shift(#line:match '^%s*')
    local rest = drawn:sub(skip + 1)
    local shown = text.fit(rest, width - text.width(head))
    local kept = shown == rest and #shown or math.max(0, #shown - #'…')
    head[#head + 1] = { shown, 'ThreadCode' }
    local row = P.chunks(head, indent)
    local col = #P.lines[row + 1] - #shown
    -- Columns of the line as read, onto it as drawn.
    ---@param s integer
    ---@param e integer
    ---@param group string
    ---@param priority integer
    local function paint(s, e, group, priority)
      s, e = math.max(0, shift(s) - skip), math.min(shift(e) - skip, kept)
      if s < e then
        P.hl(row, col + s, col + e, group, { priority = priority })
      end
    end
    for _, sp in ipairs(code.syntax({ line }, n.file)[1] or {}) do
      paint(sp[1], sp[2], sp[3], 20)
    end
    local s, e = M.mark(n, line)
    if s and e then
      paint(s, e, 'ThreadNoteMark', 40)
    end
  end
  local out = { { first = first, last = first, chunk = n } } ---@type thread.Drawn[]
  local hang = text.width(num)
  vim.list_extend(out, prose.draw(P, n.note, width - hang, { indent = indent + hang, spec = o.spec, hl = 'ThreadNote' }))
  out[1].last = #P.lines - 1
  return out
end

return M
