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
---@return thread.Drawn[]  what in it goes somewhere
function M.draw(P, k, n, width, o)
  o = o or {}
  if not n.note or vim.trim(n.note) == '' then
    return {}
  end
  return prose.draw(P, n.note, width, { indent = o.indent, spec = o.spec, lead = { M.num(k) .. ' ', 'ThreadNoteNum' }, hl = 'ThreadNote' })
end

--- A note with its line: its number, where it is and its line as it
--- reads now, coloured, its mark picked out; then what it says, hung
--- under. One whose line is gone says so.
---@param P thread.Sheet
---@param k integer
---@param n thread.Note
---@param width integer
---@param o thread.ProseOpts|nil
---@return thread.Drawn[]  its line, then what in its text goes somewhere
function M.line(P, k, n, width, o)
  o = o or {}
  local indent = o.indent or P.indent
  local num = M.num(k) .. ' '
  local lines, at = chunk.code(n, o.spec)
  local head = { { num, 'ThreadNoteNum' }, { n.file .. ':' .. (at and (at.old or at.line) or n.line), 'Directory' } }
  local row
  local line = lines and lines[1]
  if not line then
    head[#head + 1] = { ' · its line is gone', 'ThreadBroken' }
    row = P.chunks(text.fit_chunks(head, width), indent)
  else
    head[#head + 1] = { '  ' }
    local lead = #line:match '^%s*'
    local shown = text.fit((line:sub(lead + 1):gsub('\t', '    ')), width - text.width(head))
    head[#head + 1] = { shown, 'ThreadCode' }
    row = P.chunks(head, indent)
    -- Its colours and mark, on the line as read: past a tab they move.
    local col = #P.lines[row + 1] - #shown
    if not line:find '\t' then
      for _, sp in ipairs(code.syntax({ line }, n.file)[1] or {}) do
        if sp[2] > lead then
          P.hl(row, col + math.max(0, sp[1] - lead), math.min(col + #shown, col + sp[2] - lead), sp[3], { priority = 20 })
        end
      end
      local s, e = M.mark(n, line)
      if s and e and e - lead <= #shown then
        P.hl(row, col + s - lead, col + e - lead, 'ThreadNoteMark', { priority = 40 })
      end
    end
  end
  local out = { { first = row, last = row, chunk = n } } ---@type thread.Drawn[]
  local hang = text.width(num)
  return vim.list_extend(out, prose.draw(P, n.note, width - hang, { indent = indent + hang, spec = o.spec, hl = 'ThreadNote' }))
end

return M
