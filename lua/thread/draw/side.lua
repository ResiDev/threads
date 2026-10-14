--- The files a review's or a thread's chunks are in, as a tree down the
--- right of the screen, beside what the main column says. Each file has
--- a mark for every part, a review's groups or a thread's tours, lit in
--- that part's colour when the part has a chunk in it, so what goes with
--- what shows without moving the cursor. Worked out from the chunks; the
--- agent writes nothing per file.

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
---@return thread.Chunks[]
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
    end
  end
  walk(root, '', 0)
  return out
end

--- `rows` down the right of the sheet from row `top`, at column `col`,
--- with a line between them and the main column; rows added below what
--- is drawn when the tree is the longer.
---@param P thread.Sheet
---@param top integer  0-based
---@param rows thread.Chunks[]
---@param col integer
function M.beside(P, top, rows, col)
  for i, row in ipairs(rows) do
    local at = top + i - 1
    while at >= #P.lines do
      P.add ''
    end
    P.mark(at, 0, { virt_text = row, virt_text_win_col = col })
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

--- A part's files: those `chunks` are in.
---@param chunks thread.Chunk[]
---@param hl string
---@return thread.SidePart
function M.part(chunks, hl)
  local files = {} ---@type table<string, true>
  for _, c in ipairs(chunks) do
    files[c.file] = true
  end
  return { hl = hl, files = files }
end

return M
