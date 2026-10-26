--- What a drawer returns: where each thing it drew landed in the sheet,
--- so a surface can tell what is under the cursor and act on it. Parts
--- nest, a link in a message in a step, and the innermost under the
--- cursor is the one meant; each carries what it is in.

local conversation = require 'thread.model.conversation'
local text = require 'thread.base.text'

local M = {}

---@alias thread.PartKind
---| 'review'   a review's line, or its overview
---| 'contract' a contract's row or its page: `contract` it
---| 'tour'
---| 'step'
---| 'note'
---| 'message'  `message` is its place in its conversation
---| 'chunk'    a chunk's code, `chunk` the chunk
---| 'line'     one line of code: `chunk` is that line, as a one-line chunk
---| 'change'   a chunk a message changed: `chunk`
---| 'link'     on its row, at its columns
---| 'name'     `code` that may name a place in the code, at its columns
---| 'excerpt'
---| 'diagram'
---| 'inline'   a tour or a contract placed in prose, which Tab folds: `fold` what folds it
---| 'heading'  a section's rule that is an item: `name` the section
---| 'section'  a heading's section of prose, an item j and k go to; never what is under the cursor
---| 'block'    a part of a page: `name` which
---| 'reply'    not a thing but a place: where your next message in `conversation` is written, after its row, its text in `cols`

---@class (exact) thread.Part
---@field kind thread.PartKind
---@field first integer  its rows, 0-based
---@field last integer
---@field s integer|nil  a link's or a name's byte columns on its row
---@field e integer|nil
---@field review thread.Review|nil
---@field contract thread.Contract|nil
---@field tour thread.Tour|nil
---@field step thread.Step|nil
---@field note thread.Note|nil
---@field conversation thread.Conversation|nil  a message's
---@field message integer|nil
---@field chunk thread.Chunk|nil
---@field link thread.Link|nil
---@field name string|nil
---@field excerpt thread.Excerpt|nil
---@field diagram thread.DrawnDiagram|nil  its boxes found by prose.diagram.at, with the row and byte column given here
---@field fold string|nil  an inline's: what folds it
---@field inline thread.FoldKind|nil  an inline's: a tour or a contract
---@field files table<string, true>|nil  a contract's source: the files the sides drawn are read from, to light beside it
---@field item boolean|nil  one of what the screen's j and k step through
---@field alone boolean|nil  an item lit over its own rows, not those after it up to the next
---@field cols { col: integer, width: integer }|nil  a message's text, or a reply's: the columns it takes
---@field span { from: integer, to: integer }|nil  an item lit across these columns alone, as a list beside other things
---@field bar boolean|nil  an item lit by its bar alone, its rows left as drawn: code with washes of its own
---@field wash string|nil  an item lit in this colour, not the item's: one washed in a colour of its own
---@field wide boolean|nil  drawn across the files beside the page too, which stop above it

--- What it is in, for parts drawn below a primitive.
---@class thread.PartOf
---@field review thread.Review|nil
---@field contract thread.Contract|nil
---@field tour thread.Tour|nil
---@field step thread.Step|nil
---@field note thread.Note|nil
---@field conversation thread.Conversation|nil
---@field message integer|nil

--- What an item is known by, so a screen can open it and find it again
--- once drawn anew: `step:3`, `message:note:2:1`.
---@param p thread.Part
---@return string
function M.key(p)
  if p.kind == 'message' then
    return 'message:' .. (p.conversation and p.conversation.name or '') .. ':' .. tostring(p.message)
  elseif p.kind == 'step' then
    return 'step:' .. (p.step and p.step.id or 0)
  elseif p.kind == 'note' then
    return 'note:' .. (p.note and p.note.id or 0)
  elseif p.kind == 'tour' then
    return 'tour:' .. (p.tour and p.tour.title or '')
  elseif p.kind == 'review' then
    return 'review:' .. (p.review and p.review.id or '')
  elseif p.kind == 'contract' then
    return 'contract:' .. (p.contract and p.contract.id or '')
  elseif p.kind == 'inline' then
    return 'inline:' .. tostring(p.fold)
  elseif p.kind == 'section' then
    return 'section:' .. p.first
  elseif p.kind == 'heading' or p.kind == 'block' then
    return p.kind .. ':' .. tostring(p.name)
  elseif p.kind == 'chunk' and p.chunk then
    return 'chunk:' .. p.chunk.id .. ':' .. p.chunk.file .. ':' .. p.chunk.line
  end
  return p.kind
end

--- The conversation a part is in, or is: a message's, else its own
--- kind's when it is a step, a note or a contract, else the innermost
--- that holds it.
---@param p thread.Part
---@return thread.Conversation|nil
function M.conversation(p)
  if p.conversation then
    return p.conversation
  elseif p.kind == 'contract' and p.contract then
    return conversation.of_contract(p.contract)
  elseif p.kind == 'note' and p.note then
    return conversation.of_note(p.note)
  elseif p.step then
    return conversation.of_step(p.step, p.tour)
  elseif p.note then
    return conversation.of_note(p.note)
  elseif p.contract then
    return conversation.of_contract(p.contract)
  end
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

--- `glyph` at column `col` of each row from `first` to `last`, over
--- what is there: a tour's bar or tree down its side.
---@param P thread.Sheet
---@param first integer
---@param last integer
---@param glyph string
---@param hl string
---@param col integer
function M.gutter(P, first, last, glyph, hl, col)
  for row = first, last do
    P.mark(row, 0, { virt_text = { { glyph, hl } }, virt_text_win_col = col })
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
    local kind = d.section and 'section'
      or d.link and 'link'
      or d.name and 'name'
      or d.diagram and 'diagram'
      or d.fold and 'inline'
      or d.step and 'step'
      or d.tour and 'tour'
      or 'excerpt'
    out[#out + 1] = {
      kind = kind,
      first = d.first,
      last = d.last,
      s = d.s,
      e = d.e,
      link = d.link,
      name = d.name,
      excerpt = d.excerpt,
      diagram = d.diagram,
      fold = d.fold,
      inline = d.inline,
      tour = d.tour,
      step = d.step,
      span = d.span,
      item = d.section and true or nil,
      alone = d.section and true or nil,
    }
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
    p.contract = p.contract or of.contract
    p.tour = p.tour or of.tour
    p.step = p.step or of.step
    p.note = p.note or of.note
    p.conversation = p.conversation or of.conversation
    p.message = p.message or of.message
  end
end

--- Whether a part is one `w` and `b` go between: a link, or a name in
--- backticks.
---@param p thread.Part
---@return boolean
function M.goes(p)
  return p.kind == 'link' or p.kind == 'name'
end

--- The link, or name in backticks, `n` on from a row and a byte column,
--- forward or back, as `w` and `b` go between words; or as far as there
--- are; nil when there are none that way.
---@param parts thread.Part[]
---@param row integer  0-based
---@param col integer  0-based, in bytes
---@param d 1|-1
---@param n integer
---@return thread.Part|nil
function M.link(parts, row, col, d, n)
  local seen, list = {}, {} ---@type table<string, true>, thread.Part[]
  for _, p in ipairs(parts) do
    local key = p.s and (p.first .. ':' .. p.s)
    if key and M.goes(p) and not seen[key] then
      seen[key] = true
      list[#list + 1] = p
    end
  end
  table.sort(list, function(a, b)
    return a.first < b.first or (a.first == b.first and a.s < b.s)
  end)
  ---@param p thread.Part
  ---@return boolean
  local function past(p)
    if d > 0 then
      return p.first > row or (p.first == row and p.s > col)
    end
    return p.first < row or (p.first == row and p.s < col)
  end
  local to ---@type thread.Part|nil
  for _ = 1, n do
    local from, upto = d > 0 and 1 or #list, d > 0 and #list or 1
    local found = nil ---@type thread.Part|nil
    for i = from, upto, d do
      if past(list[i]) then
        found = list[i]
        break
      end
    end
    if not found then
      break
    end
    to, row, col = found, found.first, assert(found.s)
  end
  return to
end

--- The tour or contract placed in prose that a row is in, the innermost
--- when one holds another.
---@param parts thread.Part[]
---@param row integer  0-based
---@return thread.Part|nil
function M.inline_at(parts, row)
  local best ---@type thread.Part|nil
  for _, p in ipairs(parts) do
    if p.kind == 'inline' and row >= p.first and row <= p.last and (not best or p.last - p.first < best.last - best.first) then
      best = p
    end
  end
  return best
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
    if p.kind ~= 'reply' and p.kind ~= 'section' and row >= p.first and row <= p.last and (not p.s or (col >= p.s and col < (p.e or p.s))) then
      if not best or (p.s and not best.s) or ((p.s == nil) == (best.s == nil) and p.last - p.first <= best.last - best.first) then
        best = p
      end
    end
  end
  return best
end

return M
