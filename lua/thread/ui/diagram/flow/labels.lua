--- A flow's edge labels (step 5 of thread.ui.diagram.flow): beside a straight
--- run of the edge where there is room, else a numbered footnote.

local canvas = require 'thread.ui.diagram.canvas'
local diagram = require 'thread.ui.diagram'

local N, E, S, W = canvas.N, canvas.E, canvas.S, canvas.W

----------------------------------------------------------------------
-- 5. Labels
----------------------------------------------------------------------

local function free(c, g, r, col)
  return g.inside(r, col) and not g.blocked[g.key(r, col)] and not c:used(r, col)
end

local function run_free(c, g, r, from, to)
  for col = from, to do
    if not free(c, g, r, col) then
      return false
    end
  end
  return true
end

--- Find room for `label` next to one of the path's straight runs.
---@return integer|nil row, integer|nil col
local function place_label(c, g, path, label, prefer_vertical)
  local w = canvas.width_of(label)
  local mid = (#path + 1) / 2
  local order = {}
  for i = 2, #path - 1 do
    order[#order + 1] = i
  end
  table.sort(order, function(a, b)
    return math.abs(a - mid) < math.abs(b - mid)
  end)
  -- The ends last: in a tight gap the only straight run beside which a label
  -- can sit may be the cell just above the arrowhead, and a label beside the
  -- line reads far better than one squeezed between two branches.
  order[#order + 1] = #path
  if #path > 1 then
    order[#order + 1] = 1
  end

  -- A run that has bent away from where the edge started gets its label on
  -- the outside of the bend: two branches fanning out would otherwise put both
  -- labels in the gap between them, reading as one.
  local start_col = path[1][2]
  local function try_vertical(r, col)
    local right = function()
      if run_free(c, g, r, col + 1, col + 2 + w) then
        return r, col + 2
      end
    end
    local left = function()
      if run_free(c, g, r, col - 2 - w, col - 1) then
        return r, col - 1 - w
      end
    end
    local first, second = right, left
    if col < start_col then
      first, second = left, right
    end
    local lr, lc = first()
    if lr then
      return lr, lc
    end
    return second()
  end
  local function try_horizontal(r, col)
    for _, row in ipairs { r - 1, r + 1 } do
      for off = 0, w do
        local start = col - math.floor(w / 2) + (off % 2 == 0 and off / 2 or -(off + 1) / 2)
        if run_free(c, g, row, start - 1, start + w) then
          return row, start
        end
      end
    end
  end

  for pass = 1, 2 do
    local vertical = (pass == 1) == prefer_vertical
    for _, i in ipairs(order) do
      local r, col = path[i][1], path[i][2]
      local mask = c:mask(r, col)
      if vertical and mask == N + S then
        local lr, lc = try_vertical(r, col)
        if lr then
          return lr, lc
        end
      elseif not vertical and mask == E + W then
        local lr, lc = try_horizontal(r, col)
        if lr then
          return lr, lc
        end
      end
    end
  end
end

--- Number the labels that found no room, and list them under the diagram.
local function add_footnotes(res)
  local c = res.canvas
  if #res.footnotes == 0 then
    return
  end
  local _, bottom = c:row_extent()
  local row = (bottom or 0) + 2
  local first = c:extent() or 0
  for i, e in ipairs(res.footnotes) do
    local mark = tostring(i)
    -- The number goes on the edge itself: beside a straight run if there is
    -- room, otherwise it is only in the legend, which still names both ends.
    local placed = false
    for j = 2, #(e.path or {}) - 1 do
      local r, col = e.path[j][1], e.path[j][2]
      local mask = c:mask(r, col)
      local spot
      if mask == N + S then
        spot = (not c:used(r, col + 1)) and { r, col + 1 } or ((not c:used(r, col - 1)) and { r, col - 1 })
      elseif mask == E + W then
        spot = (not c:used(r - 1, col)) and { r - 1, col } or ((not c:used(r + 1, col)) and { r + 1, col })
      end
      if spot then
        c:text(spot[1], spot[2], mark, 'ThreadDiagramHint')
        placed = true
        break
      end
    end
    local col = c:text(row, first, mark .. ' ', 'ThreadDiagramHint')
    if not placed then
      col = c:text(row, col, res.by_id[e.from].label:gsub('\n', ' ') .. ' → ' .. res.by_id[e.to].label:gsub('\n', ' ') .. ': ', 'ThreadDiagramHint')
    end
    c:text(row, col, diagram.truncate(e.label, 60), 'ThreadDiagramLabel')
    row = row + 1
  end
end

return { run_free = run_free, place = place_label, footnotes = add_footnotes }
