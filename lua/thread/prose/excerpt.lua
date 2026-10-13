--- An excerpt: code pulled live from a file into prose. The agent writes
--- one as a ```code fence holding a chunk, which is read and checked as
--- any chunk is, found where it is now and drawn with its file's colours:
--- six lines from the one it quotes unless it says, fifteen at most.

local chunk = require 'thread.model.chunk'
local code = require 'thread.base.code'
local fields = require 'thread.model.fields'
local git = require 'thread.base.git'
local text = require 'thread.base.text'

local M = {}

---@class (exact) thread.Excerpt
---@field lines string[]           the fence's lines, as written
---@field raw any                  what they decode to; nil when they are not JSON
---@field json string|nil          why they are not
---@field chunk thread.Chunk|nil   the chunk, when they are one

M.LINES, M.MOST = 6, 15

--- An excerpt from the lines inside its fence.
---@param lines string[]
---@return thread.Excerpt
function M.read(lines)
  local ok, raw = pcall(vim.json.decode, table.concat(lines, '\n'), { luanil = { object = true, array = true } })
  if not ok then
    return { lines = lines, json = (tostring(raw):gsub('^.-:%d+: ', '')) }
  end
  local x = { lines = lines, raw = raw } ---@type thread.Excerpt
  local p = fields.problems()
  if chunk.parse(p, 'excerpt', raw) and #p.errors == 0 then
    x.chunk = raw
  end
  return x
end

--- What is wrong with an excerpt, said for the agent: as a chunk, and
--- where it is in the code now.
---@param p thread.Problems
---@param where string
---@param x thread.Excerpt
---@param spec thread.DiffSpec|nil  what its review is about
function M.check(p, where, x, spec)
  if x.json then
    fields.bad(p, where, 'a ```code fence holds one chunk, as JSON, and this is not JSON: ' .. x.json)
    return
  end
  if not chunk.parse(p, where, x.raw) or not x.chunk then
    return
  end
  chunk.check(p, where, x.chunk, spec)
  if (x.chunk.lines or 0) > M.MOST then
    fields.warn(p, where, string.format('an excerpt shows %d lines at most, not %d', M.MOST, x.chunk.lines))
  end
end

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

--- Where an excerpt is, and its lines now: nil lines when the code no
--- longer has it.
---@param c thread.Chunk
---@param spec thread.DiffSpec|nil
---@param width integer
---@return thread.Chunks where, string[]|nil lines, integer|nil from
local function place(c, spec, width)
  local shown = vim.tbl_extend('force', c, { lines = math.min(M.MOST, c.lines or M.LINES) }) ---@type thread.Chunk
  local lines, at ---@type string[]|nil, thread.Located|nil
  if c.side ~= 'old' or spec then
    lines, at = chunk.code(shown, spec)
  end
  if not (lines and at) then
    local why = c.side == 'old' and not spec and ' · a removed line, with no diff to read it from: ' or ' · its line is gone: '
    return text.fit_chunks({ { c.file .. ':' .. c.line, 'Directory' }, { why, 'ThreadBroken' }, { vim.trim(c.text), 'ThreadCode' } }, width)
  end
  local from = at.old or at.line
  local where = { { c.file .. ':' .. from, 'Directory' } } ---@type thread.Chunks
  if at.old then
    where[#where + 1] = { ' · removed', 'ThreadMeta' }
  elseif c.rev then
    where[#where + 1] = { ' · at ' .. git.short(c.rev), 'ThreadMeta' }
  end
  if at.confidence < 1 then
    where[#where + 1] = { ' · not as quoted', 'ThreadBroken' }
  end
  return text.fit_chunks(where, width), lines, from
end

--- Draw an excerpt in `width` columns: where it is, then its lines from
--- the quoted one, numbered and coloured. Where says what is not the code
--- now: a removed line, one at a commit, one found only by likeness. One
--- the code no longer has says so; a fence that holds no chunk shows what
--- it says.
---@param P thread.Sheet
---@param x thread.Excerpt
---@param spec thread.DiffSpec|nil  what its review is about
---@param indent integer
---@param width integer
---@return integer first, integer last  its rows
function M.draw(P, x, spec, indent, width)
  local first = #P.lines
  local c = x.chunk
  if not c then
    for _, l in ipairs(x.lines) do
      P.chunks({ { text.fit((l:gsub('\t', '    ')), width), 'ThreadCode' } }, indent)
    end
    return first, #P.lines - 1
  end
  local where, lines, from = place(c, spec, width)
  P.chunks(where, indent)
  if not (lines and from) then
    return first, first
  end
  local spans = code.syntax(lines, c.file)
  for i, l in ipairs(lines) do
    code_line(P, indent, width, from + i - 1, l, spans[i])
  end
  return first, #P.lines - 1
end

--- An excerpt in one row: where it is, as `draw` says it; a fence that
--- holds no chunk, its first line.
---@param P thread.Sheet
---@param x thread.Excerpt
---@param spec thread.DiffSpec|nil
---@param indent integer
---@param width integer
---@return integer row
function M.line(P, x, spec, indent, width)
  if not x.chunk then
    return P.chunks({ { text.fit(((x.lines[1] or ''):gsub('\t', '    ')), width), 'ThreadCode' } }, indent)
  end
  return P.chunks((place(x.chunk, spec, width)), indent)
end

return M
