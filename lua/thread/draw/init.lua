--- What a drawer returns: where each thing it drew landed in the sheet,
--- so a surface can tell what is under the cursor and act on it. Parts
--- nest, a link in a message in a step, and the innermost under the
--- cursor is the one meant; each carries what it is in.

local text = require 'thread.base.text'

local M = {}

---@alias thread.PartKind
---| 'review'   a review's line, or its overview
---| 'thread'
---| 'tour'
---| 'step'
---| 'message'  `message` is its place in its conversation
---| 'check'
---| 'chunk'    a chunk's code, `chunk` the chunk
---| 'line'     one line of code: `chunk` is that line, as a one-line chunk
---| 'change'   a place a message changed: `chunk`
---| 'note'     a note's line, then what it says: `chunk` is the note
---| 'link'     on its row, at its columns
---| 'name'     `code` that may name a place in the code, at its columns
---| 'excerpt'
---| 'diagram'
---| 'file'     a file in the file view: `file` its path, `chunks` what is on it

---@class (exact) thread.Part
---@field kind thread.PartKind
---@field first integer  its rows, 0-based
---@field last integer
---@field s integer|nil  a link's or a name's byte columns on its row
---@field e integer|nil
---@field review thread.Review|nil
---@field thread thread.Thread|nil
---@field tour thread.Tour|nil
---@field step thread.Step|nil
---@field message integer|nil
---@field check thread.Check|nil
---@field chunk thread.Chunk|nil
---@field link thread.Link|nil
---@field name string|nil
---@field excerpt thread.Excerpt|nil
---@field diagram thread.DrawnDiagram|nil  its boxes found by prose.diagram.at, with the row and byte column given here
---@field file string|nil  a file's path
---@field chunks thread.Chunk[]|nil  a file's chunks, in its order
---@field item boolean|nil  one of what the screen's j and k step through

--- What it is in, for parts drawn below a primitive.
---@class thread.PartOf
---@field review thread.Review|nil
---@field thread thread.Thread|nil
---@field tour thread.Tour|nil
---@field step thread.Step|nil
---@field message integer|nil

--- What an item is known by, so a screen can open it and find it again
--- once drawn anew: `step:3`, `file:lua/a.lua`, `message:0:2`.
---@param p thread.Part
---@return string
function M.key(p)
  if p.kind == 'file' then
    return 'file:' .. tostring(p.file)
  elseif p.kind == 'message' then
    return 'message:' .. (p.step and p.step.id or 0) .. ':' .. tostring(p.message)
  elseif p.kind == 'step' then
    return 'step:' .. (p.step and p.step.id or 0) .. (p.file and (':' .. p.file) or '')
  elseif p.kind == 'thread' then
    return 'thread:' .. (p.review and p.review.id or '') .. ':' .. (p.thread and p.thread.id or 0)
  elseif p.kind == 'tour' then
    return 'tour:' .. (p.tour and p.tour.title or '')
  elseif p.kind == 'review' then
    return 'review:' .. (p.review and p.review.id or '')
  elseif p.kind == 'chunk' and p.chunk then
    return 'chunk:' .. p.chunk.file .. ':' .. p.chunk.line
  end
  return p.kind
end

--- A bar down the left of rows `first` to `last`, two columns left of
--- `indent`: an accepted chunk's. Drawn over blank rows as well.
---@param P thread.Sheet
---@param first integer
---@param last integer
---@param indent integer
---@param hl string
function M.bar(P, first, last, indent, hl)
  if indent < 2 then
    return
  end
  for row = first, last do
    P.mark(row, 0, { virt_text = { { '▌', hl } }, virt_text_win_col = indent - 2 })
  end
end

--- A row: `left` cut to leave room for `right`, and `right` ending at
--- the width, two columns after it at least.
---@param P thread.Sheet
---@param left thread.Chunks
---@param right thread.Chunks
---@param width integer
---@param indent integer|nil  else the sheet's
---@return integer row
function M.row(P, left, right, width, indent)
  if #right == 0 then
    return P.chunks(text.fit_chunks(left, width), indent)
  end
  -- Narrow, the right gives way: half the row at most.
  if text.width(right) > math.floor(width / 2) then
    right = text.fit_chunks(right, math.floor(width / 2))
  end
  local rw = text.width(right)
  local row = text.fit_chunks(left, math.max(1, width - rw - 2))
  row[#row + 1] = { string.rep(' ', math.max(2, width - text.width(row) - rw)) }
  return P.chunks(vim.list_extend(row, right), indent)
end

--- What prose drew, as parts, added to `out`.
---@param drawn thread.Drawn[]
---@param out thread.Part[]
function M.prose(drawn, out)
  for _, d in ipairs(drawn) do
    local kind = d.link and 'link' or d.name and 'name' or d.excerpt and 'excerpt' or 'note'
    out[#out + 1] = { kind = kind, first = d.first, last = d.last, s = d.s, e = d.e, link = d.link, name = d.name, excerpt = d.excerpt, chunk = d.chunk }
  end
end

--- Say what the parts from `from` on are in, where they do not say.
---@param parts thread.Part[]
---@param from integer
---@param of thread.PartOf
function M.within(parts, from, of)
  for i = from, #parts do
    local p = parts[i]
    p.review = p.review or of.review
    p.thread = p.thread or of.thread
    p.tour = p.tour or of.tour
    p.step = p.step or of.step
    p.message = p.message or of.message
  end
end

--- The part under a row and a byte column: a link or a name when the
--- column is on it, else of the parts the row falls in the one with the
--- fewest rows, the last drawn of those.
---@param parts thread.Part[]
---@param row integer  0-based
---@param col integer  0-based, in bytes
---@return thread.Part|nil
function M.at(parts, row, col)
  local best ---@type thread.Part|nil
  for _, p in ipairs(parts) do
    if row >= p.first and row <= p.last and (not p.s or (col >= p.s and col < (p.e or p.s))) then
      if not best or (p.s and not best.s) or ((p.s == nil) == (best.s == nil) and p.last - p.first <= best.last - best.first) then
        best = p
      end
    end
  end
  return best
end

return M
