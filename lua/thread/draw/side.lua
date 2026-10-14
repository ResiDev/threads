--- The files a review's or a thread's chunks are in, as a tree down the
--- right of the screen, beside what the main column says. Each file has
--- a mark for every part, a review's groups or a thread's tours, lit in
--- that part's colour when the part has a chunk in it, so what goes with
--- what shows without moving the cursor. Worked out from the chunks; the
--- agent writes nothing per file.

local labels = require 'thread.draw.labels'
local text = require 'thread.base.text'
local touch = require 'thread.model.touch'

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

--- A file's row: `label`, then a mark for each part with a chunk in it;
--- lit or faded when something is lit.
---@param side thread.SheetSide
---@param label string
---@param path string
---@param lit table<string, true>|nil
---@return thread.SideRow
local function file_row(side, label, path, lit)
  local marks = #side.parts > 0 and #side.parts + 1 or 0
  local on = not lit or lit[path] == true
  local hl = not lit and 'ThreadFile' or on and 'ThreadSideLit' or 'ThreadSideFaded'
  local row = { { text.pad(text.fit(label, side.width - marks), side.width - marks), hl } } ---@type thread.Chunks
  if marks > 0 then
    row[#row + 1] = { ' ' }
  end
  for _, p in ipairs(side.parts) do
    row[#row + 1] = p.files[path] and { '▌', on and p.hl or 'ThreadSideFaded' } or { ' ' }
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
---@return thread.SideRow[]
function M.tree(side, lit, fold)
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
        out[#out + 1] = { chunks = { { text.fit(pad .. label .. '/', side.width), lit and 'ThreadSideFaded' or 'ThreadMeta' } } }
        walk(child, depth + 1)
      end
    end
    table.sort(node.files)
    for _, path in ipairs(node.files) do
      if fold == 2 and not (lit and lit[path]) then
        rest = rest + 1
      else
        out[#out + 1] = file_row(side, pad .. vim.fs.basename(path), path, lit)
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
---@return thread.Chunks[]
local function flag(side, rows, arrow, hidden, list, lit)
  if hidden == 0 then
    return {}
  end
  local say = arrow .. ' ' .. hidden .. ' more' .. (#list > 0 and (' · ' .. #list .. ' lit') or '')
  local out = { { { text.pad(text.fit(say, side.width), side.width), 'ThreadSideFlag' } } } ---@type thread.Chunks[]
  for i = 1, math.min(#list, M.LISTED) do
    local path = assert(rows[list[i]].path)
    local tail = path:match '([^/]+/[^/]+)$' or path
    out[#out + 1] = file_row(side, '  ' .. tail, path, lit).chunks
  end
  return out
end

--- What the column shows in `height` rows: its rule, then the tree. Too
--- tall, every directory with none of the lit files folds; still too
--- tall, every directory shows only its lit files and how many besides;
--- still too tall, a stretch of it from the first lit file, with a flag
--- at each edge it is cut at. A flag takes rows of its own, so it hides
--- nothing.
---@param side thread.SheetSide
---@param lit table<string, true>|nil
---@param height integer
---@return thread.Chunks[]
function M.fit(side, lit, height)
  local none = lit and next(lit) == nil
  local out = { labels.rule('files · ' .. #side.files .. (none and ' · none here' or ''), side.width) } ---@type thread.Chunks[]
  -- Folded only as far as it takes to fit.
  local rows = M.tree(side, lit)
  for fold = 1, 2 do
    if #rows + 1 <= height or not lit then
      break
    end
    rows = M.tree(side, lit, fold)
  end
  local h = height - 1
  if #rows <= h then
    for _, r in ipairs(rows) do
      out[#out + 1] = r.chunks
    end
    return out
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
  vim.list_extend(out, flag(side, rows, '▲', from - 1, above, lit))
  for i = from, math.min(#rows, from + k - 1) do
    out[#out + 1] = rows[i].chunks
  end
  vim.list_extend(out, flag(side, rows, '▼', math.max(0, #rows - (from + k - 1)), below, lit))
  return out
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
function M.beside(P, top, col, files, parts)
  P.side = { top = top, col = col, width = M.WIDTH, files = files, parts = parts }
  local tall = #M.tree(P.side) + 1
  while top + tall > #P.lines do
    P.add ''
  end
  for at = top, #P.lines - 1 do
    P.mark(at, 0, { virt_text = { { '│', 'ThreadTabRule' } }, virt_text_win_col = col - M.GAP + 1 })
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
--- a contract, a group, a thread, a tour or a step.
---@param p thread.Part
---@return thread.Owner|nil
function M.owner(p)
  if p.kind == 'contract' then
    return p.contract
  elseif p.kind == 'group' then
    return p.group and (p.group.group or touch.NONE)
  elseif p.kind == 'thread' then
    return p.thread
  elseif p.kind == 'tour' then
    return p.tour
  elseif p.kind == 'step' then
    return p.step
  end
end

--- The files a part touches, to light beside it: its owner's, or a
--- chunk's. None for a thread, tour or step on no line, which lights
--- nothing and fades the rest; nil for what is not about code, the
--- introduction or a message, which leaves the tree as drawn.
---@param T thread.Touches
---@param p thread.Part
---@return table<string, true>|nil
function M.of(T, p)
  local owner = M.owner(p)
  if owner then
    return T.files[owner] or {}
  end
  return p.chunk and { [p.chunk.file] = true } or nil
end

--- The tree into `buf`, in `ns`, in the rows of the window `view`
--- shows from its top: with `lit`, those files lit and the rest faded.
---@param buf integer
---@param ns integer
---@param side thread.SheetSide
---@param lit table<string, true>|nil
---@param view { top: integer, bottom: integer }  the window's first and last rows, 0-based
function M.paint(buf, ns, side, lit, view)
  local first = math.max(side.top, view.top)
  for i, row in ipairs(M.fit(side, lit, view.bottom - first + 1)) do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, first + i - 1, 0, { virt_text = row, virt_text_win_col = side.col })
  end
end

return M
