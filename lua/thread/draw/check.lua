--- A check: what the agent ran to confirm something works. Whole, what it
--- says, then the line it ran, which a key gives you to run; as a line,
--- the first line of what it says.

local draw = require 'thread.draw'
local prose = require 'thread.prose'
local text = require 'thread.base.text'

local M = {}

---@class thread.CheckOpts
---@field width integer
---@field indent integer|nil  else the sheet's

--- A check in one row: `$ ` and what it says, cut to the width.
---@param P thread.Sheet
---@param c thread.Check
---@param o thread.CheckOpts
---@return thread.Part
function M.line(P, c, o)
  local row = P.chunks(text.fit_chunks({ { '$ ', 'ThreadMeta' }, { prose.first_line(c.text), 'ThreadText' } }, o.width), o.indent)
  return { kind = 'check', first = row, last = row, check = c }
end

--- A check whole: what it says, then `$ ` and the line it ran.
---@param P thread.Sheet
---@param c thread.Check
---@param o thread.CheckOpts
---@return thread.Part[]  the check, then what in its text goes somewhere
function M.draw(P, c, o)
  local indent = o.indent or P.indent
  local out = { { kind = 'check', first = #P.lines, last = #P.lines, check = c } } ---@type thread.Part[]
  draw.prose(prose.draw(P, c.text, o.width, { indent = indent }), out)
  local run = text.fit((c.run:gsub('\n', ' ')), o.width - 2)
  out[1].last = P.chunks({ { '$ ', 'ThreadMeta' }, { run, 'ThreadCode' } }, indent)
  return out
end

return M
