--- The files a review's or a contract's chunks are in, as a tree down
--- the right of the screen, beside what the main column says. Each file
--- has a mark for every part, a review's tours and its notes, lit in that
--- part's colour when the part has a chunk in it, so what goes with what
--- shows without moving the cursor. Worked out from the chunks; the agent
--- writes nothing per file.

local labels = require 'thread.draw.labels'
local text = require 'thread.base.text'

local M = {}

-- Columns the tree takes, and between it and the main column.
M.WIDTH, M.GAP = 34, 3

-- The narrowest the main column goes before the tree is left out.
M.MAIN = 64

--- A part a file's marks stand for: its colour, and the files it has a
--- chunk in.
---@class thread.SidePart
---@field hl string
---@field files table<string, true>

--- How a tab draws the files beside it where it does not as a review's
--- page: its head rows, its mark columns, which files the item under the
--- cursor lights and what follows each one's name for it, and rows under
--- the tree.
---@class thread.SidePane
---@field head thread.Chunks[]|nil  else a rule saying how many files
---@field parts thread.SidePart[]|nil  else those it is given
---@field lit (fun(p: thread.Part): table<string, true>|nil)|nil  else the files the item touches
---@field mark (fun(path: string, p: thread.Part): thread.Chunks|nil)|nil  right after a file's name
---@field foot thread.Chunks[]|nil  under the tree, a blank row between

--- How wide the main column is beside the tree in `width`; nil when the
--- tree leaves it too narrow.
---@param width integer
---@return integer|nil
function M.main(width)
  local w = width - M.WIDTH - M.GAP
  return w >= M.MAIN and w or nil
end

-- Lit files past an edge listed under its flag, at most.
M.LISTED = 3

---@class thread.SideDir
---@field dirs table<string, thread.SideDir>
---@field files string[]  their paths

--- A row of the tree: its chunks, and the path of a file's.
---@class thread.SideRow
---@field chunks thread.Chunks
---@field path string|nil
---@field lit boolean|nil  a file `lit` has

--- The files as a tree of directories.
---@param files string[]
---@return thread.SideDir
local function grow(files)
  local root = { dirs = {}, files = {} } ---@type thread.SideDir
  for _, path in ipairs(files) do
    local node = root
    local segs = vim.split(path, '/', { plain = true })
    for i = 1, #segs - 1 do
      node.dirs[segs[i]] = node.dirs[segs[i]] or { dirs = {}, files = {} }
      node = node.dirs[segs[i]]
    end
    node.files[#node.files + 1] = path
  end
  return root
end

--- How many files are in it and under it, and how many `lit` has.
---@param node thread.SideDir
---@param lit table<string, true>|nil
---@return integer all, integer lit
local function count(node, lit)
  local all, on = #node.files, 0
  for _, f in ipairs(node.files) do
    on = on + ((lit and lit[f]) and 1 or 0)
  end
  for _, child in pairs(node.dirs) do
    local a, l = count(child, lit)
    all, on = all + a, on + l
  end
  return all, on
end

--- A file's row: `label`, what the pane puts after it for the item `p`,
--- then a mark for each part with a chunk in it; lit or faded when
--- something is lit.
---@param side thread.SheetSide
---@param label string
---@param path string
---@param lit table<string, true>|nil
---@param p thread.Part|nil  the item under the cursor
---@return thread.SideRow
local function file_row(side, label, path, lit, p)
  local marks = #side.parts > 0 and #side.parts + 1 or 0
  local on = not lit or lit[path] == true
  local hl = not lit and 'ThreadSideFile' or on and 'ThreadSideLit' or 'ThreadSideFaded'
  local pane = side.pane --[[@as thread.SidePane|nil]]
  local after = pane and pane.mark and p and pane.mark(path, p) or nil
  local room = side.width - marks - (after and text.width(after) + 1 or 0)
  local row = { { text.fit(label, room), hl } } ---@type thread.Chunks
  if after then
    row[#row + 1] = { ' ' }
    vim.list_extend(row, after)
  end
  row[#row + 1] = { string.rep(' ', side.width - marks - text.width(row)) }
  if marks > 0 then
    row[#row + 1] = { ' ' }
  end
  for _, part in ipairs(side.parts) do
    row[#row + 1] = part.files[path] and { '▌', on and part.hl or 'ThreadSideFaded' } or { ' ' }
  end
  return { chunks = row, path = path, lit = lit and lit[path] or nil }
end

--- The tree's rows: each directory, a chain of lone ones on one row,
--- and its files set in under it. Folded once, a directory with none of
--- the lit files is one row: ▸, its name and how many files. Folded
--- twice, a directory shows only what holds a lit file, and one row
--- saying how many files besides are in it: `… 7 more`.
---@param side thread.SheetSide
---@param lit table<string, true>|nil
---@param fold 0|1|2|nil  how far; none, else lit
---@param p thread.Part|nil  the item under the cursor
---@return thread.SideRow[]
function M.tree(side, lit, fold, p)
  fold = lit and fold or 0
  local out = {} ---@type thread.SideRow[]
  ---@param node thread.SideDir
  ---@param depth integer
  local function walk(node, depth)
    local pad = string.rep(' ', depth * 2)
    local rest = 0
    local names = vim.tbl_keys(node.dirs)
    table.sort(names)
    for _, name in ipairs(names) do
      local child, label = node.dirs[name], name
      while #child.files == 0 and vim.tbl_count(child.dirs) == 1 do
        local only = next(child.dirs)
        label, child = label .. '/' .. only, child.dirs[only]
      end
      local all, on = count(child, lit)
      if fold == 2 and on == 0 then
        rest = rest + all
      elseif fold == 1 and on == 0 then
        local n = tostring(all)
        out[#out + 1] = {
          chunks = { { text.pad(text.fit(pad .. '▸ ' .. label .. '/', side.width - #n - 1), side.width - #n), 'ThreadSideFaded' }, { n, 'ThreadSideFaded' } },
        }
      else
        out[#out + 1] = { chunks = { { text.fit(pad .. label .. '/', side.width), lit and 'ThreadSideFaded' or 'ThreadSideDir' } } }
        walk(child, depth + 1)
      end
    end
    table.sort(node.files)
    for _, path in ipairs(node.files) do
      if fold == 2 and not (lit and lit[path]) then
        rest = rest + 1
      else
        out[#out + 1] = file_row(side, pad .. vim.fs.basename(path), path, lit, p)
      end
    end
    if rest > 0 then
      out[#out + 1] = { chunks = { { text.fit(pad .. '… ' .. rest .. ' more', side.width), 'ThreadSideFaded' } } }
    end
  end
  walk(grow(side.files), 0)
  return out
end

--- What an edge's flag takes: a row saying how many rows are past it and
--- how many of them are lit, and a row for each of those, a few at most.
---@param hidden integer
---@param lit integer[]
---@return integer
local function flag_rows(hidden, lit)
  return hidden > 0 and 1 + math.min(#lit, M.LISTED) or 0
end

--- An edge's flag: `▲` or `▼`, how many are past it and how many lit,
--- then the lit ones, by the end of their path.
---@param side thread.SheetSide
---@param rows thread.SideRow[]
---@param arrow string
---@param hidden integer
---@param list integer[]  the lit rows past it
---@param lit table<string, true>|nil
---@param p thread.Part|nil
---@return thread.Chunks[]
local function flag(side, rows, arrow, hidden, list, lit, p)
  if hidden == 0 then
    return {}
  end
  local say = arrow .. ' ' .. hidden .. ' more' .. (#list > 0 and (' · ' .. #list .. ' lit') or '')
  local out = { { { text.pad(text.fit(say, side.width), side.width), 'ThreadSideFlag' } } } ---@type thread.Chunks[]
  for i = 1, math.min(#list, M.LISTED) do
    local path = assert(rows[list[i]].path)
    local tail = path:match '([^/]+/[^/]+)$' or path
    out[#out + 1] = file_row(side, '  ' .. tail, path, lit, p).chunks
  end
  return out
end

--- What the column shows in `height` rows: its head, the tree, then its
--- foot. Too tall, every directory with none of the lit files folds;
--- still too tall, every directory shows only its lit files and how many
--- besides; still too tall, a stretch of it from the first lit file,
--- with a flag at each edge it is cut at. A flag takes rows of its own,
--- so it hides nothing.
---@param side thread.SheetSide
---@param lit table<string, true>|nil
---@param height integer
---@param p thread.Part|nil  the item under the cursor
---@return thread.Chunks[]
function M.fit(side, lit, height, p)
  local pane = side.pane --[[@as thread.SidePane|nil]]
  local out = vim.list_slice(pane and pane.head or { labels.rule('files · ' .. #side.files, side.width) }) ---@type thread.Chunks[]
  local foot = pane and pane.foot and vim.list_extend({ {} }, pane.foot) or {}
  local h = math.max(1, height - #out - #foot)
  -- Folded only as far as it takes to fit.
  local rows = M.tree(side, lit, 0, p)
  for fold = 1, 2 do
    if #rows <= h or not lit then
      break
    end
    rows = M.tree(side, lit, fold, p)
  end
  if #rows <= h then
    for _, r in ipairs(rows) do
      out[#out + 1] = r.chunks
    end
    return vim.list_extend(out, foot)
  end
  local lits = {} ---@type integer[]
  for i, r in ipairs(rows) do
    if r.lit then
      lits[#lits + 1] = i
    end
  end
  -- From the row above the first lit file, so its directory shows; each
  -- flag shrinks the stretch, which can move what is past either edge.
  local from, k = lits[1] and math.max(1, lits[1] - 1) or 1, h
  local above, below = {}, {} ---@type integer[], integer[]
  for _ = 1, 4 do
    from = math.max(1, math.min(from, #rows - k + 1))
    above, below = {}, {}
    for _, i in ipairs(lits) do
      if i < from then
        above[#above + 1] = i
      elseif i >= from + k then
        below[#below + 1] = i
      end
    end
    local want = math.max(1, h - flag_rows(from - 1, above) - flag_rows(#rows - (from + k - 1), below))
    if want == k then
      break
    end
    k = want
  end
  vim.list_extend(out, flag(side, rows, '▲', from - 1, above, lit, p))
  for i = from, math.min(#rows, from + k - 1) do
    out[#out + 1] = rows[i].chunks
  end
  vim.list_extend(out, flag(side, rows, '▼', math.max(0, #rows - (from + k - 1)), below, lit, p))
  return vim.list_extend(out, foot)
end

--- The tree down the right of the sheet from row `top`, at column `col`,
--- with a line between it and the main column; rows added below what is
--- drawn when the tree is the longer. The tree is left to M.paint, which
--- the screen calls as the cursor moves and the window scrolls, so it
--- stays in view and lights the item's files.
---@param P thread.Sheet
---@param top integer  0-based
---@param col integer
---@param files string[]
---@param parts thread.SidePart[]
---@param width integer|nil  else M.WIDTH
---@param pane thread.SidePane|nil  else as a review's page has them
function M.beside(P, top, col, files, parts, width, pane)
  P.side = { top = top, col = col, width = width or M.WIDTH, files = files, parts = pane and pane.parts or parts, pane = pane }
  local tall = #M.fit(P.side, nil, math.huge)
  while top + tall > #P.lines do
    P.add ''
  end
  for at = top, #P.lines - 1 do
    P.mark(at, 0, { virt_text = { { '│', 'ThreadPaneRule' } }, virt_text_win_col = col - M.GAP + 1 })
  end
end

--- The paths of `chunks`' files, each once, in the order they come.
---@param chunks thread.Chunk[]
---@return string[]
function M.paths(chunks)
  local seen, out = {}, {} ---@type table<string, true>, string[]
  for _, c in ipairs(chunks) do
    if not seen[c.file] then
      seen[c.file], out[#out + 1] = true, c.file
    end
  end
  return out
end

--- What a part stands for among what has chunks (thread.model.touch):
--- a contract, a tour, a step or a note.
---@param p thread.Part
---@return thread.Owner|nil
function M.owner(p)
  if p.kind == 'contract' then
    return p.contract
  elseif p.kind == 'tour' then
    return p.tour
  elseif p.kind == 'step' then
    return p.step
  elseif p.kind == 'note' then
    return p.note
  end
end

--- The files to light beside the item `p`: those the pane says, else
--- those it touches.
---@param side thread.SheetSide
---@param T thread.Touches
---@param p thread.Part
---@return table<string, true>|nil
function M.lit(side, T, p)
  local pane = side.pane --[[@as thread.SidePane|nil]]
  if pane and pane.lit then
    return pane.lit(p)
  end
  return M.of(T, p)
end

--- The files a part touches, to light beside it: its owner's, a
--- chunk's, or a contract's source's, which written out lights none, as
--- it is in none. Nil for what has no code, which leaves the tree as
--- drawn.
---@param T thread.Touches
---@param p thread.Part
---@return table<string, true>|nil
function M.of(T, p)
  if p.files then
    return p.files
  end
  local owner = M.owner(p)
  local files = owner and T.files[owner] or (p.chunk and { [p.chunk.file] = true })
  return files and next(files) and files or nil
end

--- The tree into `buf`, in `ns`, in the rows of the window `view`
--- shows from its top: with `lit`, those files lit and the rest faded.
---@param buf integer
---@param ns integer
---@param side thread.SheetSide
---@param lit table<string, true>|nil
---@param view { top: integer, bottom: integer }  the window's first and last rows, 0-based
---@param p thread.Part|nil  the item under the cursor
function M.paint(buf, ns, side, lit, view, p)
  local first = math.max(side.top, view.top)
  local height = view.bottom - first + 1
  local rows = M.fit(side, lit, height, p)
  -- Every row to the window's foot on the window's own background, from
  -- the line between the columns to its edge, so the lit item's wash
  -- stops at the main column.
  local from = side.col - M.GAP + 2
  for i = 1, height do
    local row = { { string.rep(' ', side.col - from) } } ---@type thread.Chunks
    vim.list_extend(row, rows[i] or {})
    row[#row + 1] = { string.rep(' ', math.max(0, side.col - from + side.width + 2 - text.width(row))) }
    local over = {} ---@type { [1]: string, [2]: string|string[] }[]
    for k, c in ipairs(row) do
      over[k] = { c[1], c[2] and { 'NormalFloat', c[2] } or 'NormalFloat' }
    end
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, first + i - 1, 0, { virt_text = over, virt_text_win_col = from })
  end
end

return M
