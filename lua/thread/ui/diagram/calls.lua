--- `calls`: an indented call tree, rooted at an entry point.
---
---   :Tour
---   └─ session.start               init.lua
---      ├─ parse.tour               parse.lua
---      └─ session.goto_step
---
--- The narrowest of the three kinds, so it is the one that fits anywhere. A
--- node's file is named at the right edge where the tree crosses into a new
--- file -- the boundary is the interesting part, a column of repeats is not.

local canvas = require 'thread.ui.diagram.canvas'
local diagram = require 'thread.ui.diagram'

local M = {}

---@param d table validated `calls` diagram
---@param opts { max_width: integer, status: table|nil }
---@return tour.Canvas, thread.DiagramHit[]
function M.layout(d, opts)
  local rows = {}

  -- Flatten into rows first, so the file column can be lined up afterwards.
  local function walk(node, prefix, branch, parent_file)
    rows[#rows + 1] = {
      node = node,
      prefix = prefix .. branch,
      hint = node.file and node.file ~= parent_file and vim.fs.basename(node.file) or nil,
    }
    local children = node.children or {}
    local cont = branch == '' and '' or (branch == '└─ ' and '   ' or '│  ')
    for i, child in ipairs(children) do
      walk(child, prefix .. cont, i == #children and '└─ ' or '├─ ', node.file or parent_file)
    end
  end
  walk(d.root, '', '', nil)

  -- The file column sits one gap past the longest row, unless that would push
  -- it off the edge -- then labels are shortened before hints are dropped.
  local widest, widest_hint = 0, 0
  for _, r in ipairs(rows) do
    widest = math.max(widest, canvas.width_of(r.prefix) + canvas.width_of(r.node.label))
    if r.hint then
      widest_hint = math.max(widest_hint, canvas.width_of(r.hint))
    end
  end
  local gap = 3
  local hint_col = widest + gap
  local show_hints = widest_hint > 0
  if show_hints and hint_col + widest_hint > opts.max_width then
    hint_col = opts.max_width - widest_hint
    -- Below this the labels are mostly ellipsis; the hints go instead.
    if hint_col < math.floor(opts.max_width / 2) then
      show_hints = false
    end
  end
  local label_room = show_hints and (hint_col - gap) or opts.max_width

  local c = canvas.new()
  local hits = {}
  for i, r in ipairs(rows) do
    local row = i - 1
    local col = c:text(row, 0, r.prefix, 'ThreadDiagramEdge')
    local label = diagram.truncate(r.node.label, math.max(4, label_room - col))
    local hl = diagram.node_hl(r.node, opts.status)
    hits[#hits + 1] = { node = r.node, row = row, col = col, width = canvas.width_of(label), height = 1 }
    c:text(row, col, label, hl)
    if show_hints and r.hint then
      c:text(row, hint_col, r.hint, 'ThreadDiagramHint')
    end
  end
  return c, hits
end

return M
