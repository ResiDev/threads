--- An excerpt: a chunk of the review quoted in prose, `{{chunk:id}}` alone
--- on a line, its lines read from the file each time it is drawn, with
--- its file's colours: fifteen at most. It is a quotation, not something
--- the review is about: it adds no file and cannot be accepted.

local chunk = require 'thread.model.chunk'
local code = require 'thread.base.code'
local git = require 'thread.base.git'
local text = require 'thread.base.text'

local M = {}

---@class (exact) thread.Excerpt
---@field id string  the chunk's, as written
---@field chunk thread.Chunk|nil  none: the review has no chunk by that id
---@field spec thread.DiffSpec|nil  what its review is about

M.MOST = 15

--- One line of code into a sheet, cut to `width`: its number, then the
--- line in its colours, a tab drawn as four spaces.
---@param P thread.Sheet
---@param indent integer
---@param width integer
---@param num integer
---@param line string
---@param spans { [1]: integer, [2]: integer, [3]: string }[]|nil
local function code_line(P, indent, width, num, line, spans)
  local prefix = string.rep(' ', indent) .. string.format('%4d  ', num)
  local drawn, at = code.untab(line)
  local body = text.fit(drawn, width - 6)
  local kept = body == drawn and #body or #body - #'…'
  local row = P.add(prefix .. body)
  P.hl(row, indent, indent + 4, 'LineNr')
  for _, s in ipairs(spans or {}) do
    local from, to = at(s[1]), math.min(at(s[2]), kept)
    if from < to then
      P.hl(row, #prefix + from, #prefix + to, s[3])
    end
  end
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
  -- Said as draw/chunk says it, which this layer is under.
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
  return text.fit_chunks(where, width), lines, at
end

--- Draw an excerpt in `width` columns: where it is, then its lines,
--- numbered and coloured, fifteen at most and a row saying how many more.
---@param P thread.Sheet
---@param x thread.Excerpt
---@param indent integer
---@param width integer
---@return integer first, integer last  its rows
function M.draw(P, x, indent, width)
  local first = #P.lines
  local where, lines, at = place(x, width)
  P.chunks(where, indent)
  if not (lines and at and x.chunk) then
    return first, first
  end
  local shown = vim.list_slice(lines, 1, M.MOST)
  local spans = code.syntax(shown, x.chunk.file)
  for i, l in ipairs(shown) do
    code_line(P, indent, width, at.line + i - 1, l, spans[i])
  end
  if #lines > #shown then
    P.chunks({ { string.format('      ⋯ %d more lines', #lines - #shown), 'ThreadMeta' } }, indent)
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
