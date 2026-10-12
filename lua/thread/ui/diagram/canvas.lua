--- A grid of character cells that diagrams are drawn onto.
---
--- Two kinds of cell. A *glyph* cell holds one character outright: box borders,
--- labels, arrowheads. A *line* cell holds a set of connections -- north, east,
--- south, west -- and its character is derived from them when the canvas is
--- read out, so two lines meeting become a corner, a tee or a crossing without
--- either one knowing about the other.
---
--- Rows and columns are 0-indexed display columns. A double-width character
--- takes its cell and a placeholder in the next one.
---
--- Pure: nothing here touches the editor beyond measuring display width.

local M = {}

M.N, M.E, M.S, M.W = 1, 2, 4, 8

--- Step offsets for each direction bit.
M.delta = {
  [1] = { -1, 0 },
  [2] = { 0, 1 },
  [4] = { 1, 0 },
  [8] = { 0, -1 },
}

M.opposite = { [1] = 4, [2] = 8, [4] = 1, [8] = 2 }

--- Line glyphs by connection mask. Edges get rounded corners so they never
--- read as the corner of a box, which is square.
local GLYPH = {
  [0] = ' ',
  [1] = '│',
  [4] = '│',
  [5] = '│',
  [2] = '─',
  [8] = '─',
  [10] = '─',
  [6] = '╭',
  [12] = '╮',
  [3] = '╰',
  [9] = '╯',
  [7] = '├',
  [13] = '┤',
  [14] = '┬',
  [11] = '┴',
  [15] = '┼',
}

local DASHED = { [1] = '╎', [4] = '╎', [5] = '╎', [2] = '╌', [8] = '╌', [10] = '╌' }

---@param s string
---@return integer
local function width_of(s)
  return vim.fn.strdisplaywidth(s)
end
M.width_of = width_of

---@class tour.Canvas
---@field cells table<integer, table<integer, { ch: string, hl: string }|false>>
---@field lines table<integer, table<integer, { mask: integer, hl: string, dashed: boolean }>>
---@field w integer  one past the rightmost column written
---@field h integer  one past the bottom row written
local Canvas = {}
Canvas.__index = Canvas

---@return tour.Canvas
function M.new()
  return setmetatable({ cells = {}, lines = {}, w = 0, h = 0 }, Canvas)
end

function Canvas:_grow(r, c)
  if r + 1 > self.h then
    self.h = r + 1
  end
  if c + 1 > self.w then
    self.w = c + 1
  end
end

--- Put one character, of display width 1 or 2.
function Canvas:put(r, c, ch, hl)
  if r < 0 or c < 0 then
    return
  end
  self.cells[r] = self.cells[r] or {}
  self.cells[r][c] = { ch = ch, hl = hl }
  self:_grow(r, c)
  if width_of(ch) == 2 then
    self.cells[r][c + 1] = false -- covered by the wide character to its left
    self:_grow(r, c + 1)
  end
end

--- Write a string left to right; returns the column after it.
function Canvas:text(r, c, s, hl)
  for _, ch in ipairs(vim.fn.split(s, '\\zs')) do
    self:put(r, c, ch, hl)
    c = c + math.max(1, width_of(ch))
  end
  return c
end

---@param r integer
---@param c integer
---@return { ch: string, hl: string }|false|nil
function Canvas:glyph(r, c)
  return self.cells[r] and self.cells[r][c]
end

--- Connection mask of the line cell at (r, c), 0 when there is none.
function Canvas:mask(r, c)
  local cell = self.lines[r] and self.lines[r][c]
  return cell and cell.mask or 0
end

--- Add connections to a line cell.
function Canvas:link(r, c, bits, hl, dashed)
  if r < 0 or c < 0 then
    return
  end
  self.lines[r] = self.lines[r] or {}
  local cell = self.lines[r][c]
  if cell then
    cell.mask = bit.bor(cell.mask, bits)
    cell.dashed = cell.dashed and dashed
  else
    self.lines[r][c] = { mask = bits, hl = hl, dashed = dashed or false }
  end
  self:_grow(r, c)
end

--- Whether anything at all has been drawn at (r, c).
function Canvas:used(r, c)
  return self:glyph(r, c) ~= nil or self:mask(r, c) ~= 0
end

--- A box: `h` rows by `w` columns, top-left at (r, c), borders only.
function Canvas:box(r, c, h, w, hl, rounded)
  local tl, tr, bl, br = '┌', '┐', '└', '┘'
  if rounded then
    tl, tr, bl, br = '╭', '╮', '╰', '╯'
  end
  self:put(r, c, tl, hl)
  self:put(r, c + w - 1, tr, hl)
  self:put(r + h - 1, c, bl, hl)
  self:put(r + h - 1, c + w - 1, br, hl)
  for x = c + 1, c + w - 2 do
    self:put(r, x, '─', hl)
    self:put(r + h - 1, x, '─', hl)
  end
  for y = r + 1, r + h - 2 do
    self:put(y, c, '│', hl)
    self:put(y, c + w - 1, '│', hl)
  end
end

--- Read the canvas out as `virt_lines`-style chunk rows, every row padded to
--- the canvas width.
---@param from_col integer|nil first column to include (default 0)
---@param to_col integer|nil one past the last (default the canvas width)
---@return [string, string][][] rows
function Canvas:rows(from_col, to_col)
  from_col = from_col or 0
  to_col = to_col or self.w
  local out = {}
  for r = 0, self.h - 1 do
    local chunks = {}
    local function emit(ch, hl)
      local last = chunks[#chunks]
      if last and last[2] == hl then
        last[1] = last[1] .. ch
      else
        chunks[#chunks + 1] = { ch, hl }
      end
    end
    for c = from_col, to_col - 1 do
      local g = self:glyph(r, c)
      if g == false then
      -- the right half of a wide character: already emitted
      elseif g then
        emit(g.ch, g.hl)
      else
        local line = self.lines[r] and self.lines[r][c]
        if line and line.mask ~= 0 then
          local ch = (line.dashed and DASHED[line.mask]) or GLYPH[line.mask] or '┼'
          emit(ch, line.hl)
        else
          emit(' ', 'Normal')
        end
      end
    end
    out[#out + 1] = chunks
  end
  return out
end

--- The columns actually drawn on, for cropping margins away.
---@return integer|nil first, integer|nil last  inclusive
function Canvas:extent()
  local first, last
  for r = 0, self.h - 1 do
    for c = 0, self.w - 1 do
      if self:used(r, c) then
        first = (not first or c < first) and c or first
        last = (not last or c > last) and c or last
      end
    end
  end
  return first, last
end

--- The rows actually drawn on.
---@return integer|nil first, integer|nil last  inclusive
function Canvas:row_extent()
  local first, last
  for r = 0, self.h - 1 do
    for c = 0, self.w - 1 do
      if self:used(r, c) then
        first = first or r
        last = r
        break
      end
    end
  end
  return first, last
end

--- Plain text of every row, for tests and for the prose window.
---@return string[]
function Canvas:text_rows()
  return vim.tbl_map(function(chunks)
    return table.concat(vim.tbl_map(function(c)
      return c[1]
    end, chunks))
  end, self:rows())
end

return M
