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

---@class thread.SideDir
---@field dirs table<string, thread.SideDir>
---@field files string[]  their names

--- The tree's rows: a rule saying how many files, then each directory,
--- a chain of lone ones on one row, and its files set in under it, each
--- with a mark a part.
---@param paths string[]
---@param parts thread.SidePart[]
---@param width integer
---@return thread.Chunks[] rows, table<integer, string> paths  a file's row: its path
function M.rows(paths, parts, width)
  local root = { dirs = {}, files = {} } ---@type thread.SideDir
  for _, path in ipairs(paths) do
    local node = root
    local segs = vim.split(path, '/', { plain = true })
    for i = 1, #segs - 1 do
      node.dirs[segs[i]] = node.dirs[segs[i]] or { dirs = {}, files = {} }
      node = node.dirs[segs[i]]
    end
    node.files[#node.files + 1] = segs[#segs]
  end
  local out = { labels.rule('files · ' .. #paths, width) } ---@type thread.Chunks[]
  local at_row = {} ---@type table<integer, string>
  local marks = #parts > 0 and #parts + 1 or 0
  ---@param node thread.SideDir
  ---@param at string  its path, with a slash after
  ---@param depth integer
  local function walk(node, at, depth)
    local pad = string.rep(' ', depth * 2)
    local names = vim.tbl_keys(node.dirs)
    table.sort(names)
    for _, name in ipairs(names) do
      local child, label = node.dirs[name], name
      while #child.files == 0 and vim.tbl_count(child.dirs) == 1 do
        local only = next(child.dirs)
        label, child = label .. '/' .. only, child.dirs[only]
      end
      out[#out + 1] = { { text.fit(pad .. label .. '/', width), 'ThreadMeta' } }
      walk(child, at .. label .. '/', depth + 1)
    end
    table.sort(node.files)
    for _, name in ipairs(node.files) do
      local path = at .. name
      local row = { { text.pad(text.fit(pad .. name, width - marks), width - marks), 'ThreadFile' } } ---@type thread.Chunks
      if marks > 0 then
        row[#row + 1] = { ' ' }
      end
      for _, p in ipairs(parts) do
        row[#row + 1] = p.files[path] and { '▌', p.hl } or { ' ' }
      end
      out[#out + 1] = row
      at_row[#out] = path
    end
  end
  walk(root, '', 0)
  return out, at_row
end

--- `rows` down the right of the sheet from row `top`, at column `col`,
--- with a line between them and the main column; rows added below what
--- is drawn when the tree is the longer. The rows themselves are left to
--- M.paint, so the screen can draw them lit as the cursor moves: two
--- marks at one column do not stack.
---@param P thread.Sheet
---@param top integer  0-based
---@param rows thread.Chunks[]
---@param paths table<integer, string>  a file's row: its path
---@param col integer
function M.beside(P, top, rows, paths, col)
  P.side = { top = top, col = col, rows = rows, paths = paths }
  while top + #rows > #P.lines do
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
--- chunk's. Nil for what has no code, which leaves the tree as drawn.
---@param T thread.Touches
---@param p thread.Part
---@return table<string, true>|nil
function M.of(T, p)
  local owner = M.owner(p)
  local files = owner and T.files[owner] or (p.chunk and { [p.chunk.file] = true })
  return files and next(files) and files or nil
end

--- The tree into `buf`, in `ns`: with `lit`, those files lit and the
--- rest faded; else as drawn.
---@param buf integer
---@param ns integer
---@param drawn thread.SheetSide
---@param lit table<string, true>|nil
function M.paint(buf, ns, drawn, lit)
  for i, row in ipairs(drawn.rows) do
    local path = drawn.paths[i]
    if lit and path then
      local on = lit[path] == true
      local again = { { row[1][1], on and 'ThreadSideLit' or 'ThreadSideFaded' } } ---@type thread.Chunks
      for k = 2, #row do
        again[k] = on and row[k] or { row[k][1], row[k][2] and 'ThreadSideFaded' }
      end
      row = again
    end
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, drawn.top + i - 1, 0, { virt_text = row, virt_text_win_col = drawn.col })
  end
end

return M
