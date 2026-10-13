--- A diagram in prose: a message's or a step's, checked where the model
--- reads it, laid out to the room there is and drawn into a sheet, with
--- where each box landed so a key can follow it to its code.

local layout = require 'thread.ui.diagram'
local text = require 'thread.base.text'

local M = {}

---@class thread.DrawnDiagram
---@field first integer  its rows in the sheet, 0-based
---@field last integer
---@field indent integer  the column it starts at
---@field render thread.DiagramRender  where each box landed, in its own rows

--- Draw a diagram, `width` columns at most. Its own colour is the
--- window's; one drawn simpler than asked says why under it.
---@param P thread.Sheet
---@param d table  checked (thread.model.diagram)
---@param width integer
---@param indent integer|nil  else the sheet's
---@return thread.DrawnDiagram
function M.draw(P, d, width, indent)
  indent = indent or P.indent
  local drawn = layout.render(d, { max_width = width })
  local first = #P.lines
  for _, chunks in ipairs(drawn.rows) do
    local row = P.chunks(
      vim.tbl_map(function(c)
        return { c[1], c[2] ~= 'Normal' and c[2] or nil }
      end, chunks),
      indent
    )
    P.lines[row + 1] = P.lines[row + 1]:gsub('%s+$', '')
  end
  local last = #P.lines - 1
  if drawn.degraded then
    last = P.chunks({ { text.fit('(' .. drawn.degraded .. ')', width), 'ThreadMeta' } }, indent)
  end
  return { first = first, last = last, indent = indent, render = drawn }
end

--- The box of a drawn diagram at a row and a byte column of the sheet,
--- as the cursor gives them, if any.
---@param drawn thread.DrawnDiagram
---@param row integer  0-based
---@param col integer  0-based, in bytes
---@return table|nil node
function M.at(drawn, row, col)
  local chunks = drawn.render.rows[row - drawn.first + 1]
  if not chunks then
    return nil
  end
  local line = string.rep(' ', drawn.indent) .. table.concat(vim.tbl_map(function(c)
    return c[1]
  end, chunks))
  return layout.hit(drawn.render, row - drawn.first, text.width(line:sub(1, col)) - drawn.indent)
end

return M
