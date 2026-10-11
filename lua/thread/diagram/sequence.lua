--- `sequence`: participants across the top, a lifeline down from each, and one
--- arrow per message in time order.
---
---   ┌─────────┐   ┌────────┐   ┌────────┐
---   │ session │   │ render │   │ inline │
---   └────┬────┘   └───┬────┘   └───┬────┘
---        │   show     │            │
---        ├───────────▶│            │
---        │            │   build    │
---        │            ├───────────▶│
---        │            │   lines    │
---        │            │◀╌╌╌╌╌╌╌╌╌╌╌┤
---
--- Columns are spaced by what has to fit between them: the boxes, and every
--- message label spanning that gap. When the total will not fit, labels are
--- shortened -- messages first, then participants -- before giving up.

local canvas = require 'thread.diagram.canvas'
local diagram = require 'thread.diagram'

local M = {}

local N, E, S, W = canvas.N, canvas.E, canvas.S, canvas.W

--- Column centres for a given pair of label caps.
local function place(d, index, part_cap, msg_cap)
  local n = #d.participants
  local labels, bw = {}, {}
  for i, p in ipairs(d.participants) do
    labels[i] = diagram.truncate(p.label, part_cap)
    bw[i] = canvas.width_of(labels[i]) + 4
  end

  -- Minimum distance between neighbouring centres: the boxes, two apart.
  local gap = {}
  for i = 1, n - 1 do
    gap[i] = (bw[i] - math.floor(bw[i] / 2)) + math.floor(bw[i + 1] / 2) + 2
  end

  local mlabels = {}
  local right_room = 0 -- columns needed past the last centre, for self-messages
  local spans = {}
  for k, m in ipairs(d.messages) do
    mlabels[k] = m.label and diagram.truncate(m.label, msg_cap) or ''
    local a, b = index[m.from], index[m.to]
    local w = canvas.width_of(mlabels[k])
    if a == b then
      -- `├─╮ label` takes the label plus four columns right of the lifeline;
      -- a following lifeline needs one more, so the label does not touch it.
      if a < n then
        gap[a] = math.max(gap[a], w + 5)
      else
        right_room = math.max(right_room, w + 4)
      end
    else
      spans[#spans + 1] = { lo = math.min(a, b), hi = math.max(a, b), need = w + 4 }
    end
  end

  -- Narrow spans first, so a wide span only adds what its parts still lack;
  -- the shortfall is spread across the gaps it covers.
  table.sort(spans, function(x, y)
    return (x.hi - x.lo) < (y.hi - y.lo)
  end)
  for _, s in ipairs(spans) do
    local have = 0
    for i = s.lo, s.hi - 1 do
      have = have + gap[i]
    end
    local short = s.need - have
    if short > 0 then
      local count = s.hi - s.lo
      for i = s.lo, s.hi - 1 do
        local share = math.floor(short / count) + ((i - s.lo) < (short % count) and 1 or 0)
        gap[i] = gap[i] + share
      end
    end
  end

  local cx = { math.floor(bw[1] / 2) }
  for i = 2, n do
    cx[i] = cx[i - 1] + gap[i - 1]
  end
  local right = math.max(cx[n] + (bw[n] - math.floor(bw[n] / 2)), cx[n] + right_room)
  return { cx = cx, bw = bw, labels = labels, mlabels = mlabels, width = right }
end

---@param d table validated `sequence` diagram
---@param opts { max_width: integer, status: table|nil }
---@return tour.Canvas|nil, thread.DiagramHit[]|nil, string|nil
function M.layout(d, opts)
  local index = {}
  for i, p in ipairs(d.participants) do
    index[p.id] = i
  end

  -- The widest labels first; then shorter and shorter message labels, then
  -- participant labels, until the whole thing fits.
  local longest = 0
  for _, m in ipairs(d.messages) do
    longest = math.max(longest, m.label and canvas.width_of(m.label) or 0)
  end
  local longest_part = 0
  for _, p in ipairs(d.participants) do
    longest_part = math.max(longest_part, canvas.width_of(p.label))
  end

  local g, degraded
  local msg_cap, part_cap = math.max(longest, 1), math.max(longest_part, 1)
  while true do
    g = place(d, index, part_cap, msg_cap)
    if g.width <= opts.max_width then
      break
    end
    if msg_cap > 6 then
      msg_cap = msg_cap - 1
    elseif part_cap > 6 then
      part_cap = part_cap - 1
    else
      return nil -- the caller falls back to a list
    end
    degraded = 'labels shortened to fit'
  end

  local c = canvas.new()
  local hits = {}
  local cx = g.cx

  -- Participant boxes, with the lifeline leaving through the bottom border.
  for i, p in ipairs(d.participants) do
    local left = cx[i] - math.floor(g.bw[i] / 2)
    local label_hl, box_hl = diagram.node_hl(p, opts.status)
    c:box(0, left, 3, g.bw[i], box_hl)
    c:text(1, left + 2, g.labels[i], label_hl)
    c:put(2, cx[i], '┬', box_hl)
    hits[#hits + 1] = { node = p, row = 0, col = left, width = g.bw[i], height = 3 }
  end

  -- Messages: a label row, then an arrow row.
  local y = 3
  for k, m in ipairs(d.messages) do
    local a, b = index[m.from], index[m.to]
    local label = g.mlabels[k]
    local hl = 'ThreadDiagramEdge'
    if a == b then
      -- ├─╮ label
      -- │◀╯
      local x = cx[a]
      c:link(y, x, E, hl, m.reply)
      c:link(y, x + 1, E + W, hl, m.reply)
      c:link(y, x + 2, W + S, hl, m.reply)
      c:link(y + 1, x + 2, N + W, hl, m.reply)
      c:put(y + 1, x + 1, '◀', hl)
      if label ~= '' then
        c:text(y, x + 4, label, 'ThreadDiagramLabel')
      end
    else
      local lo, hi = math.min(cx[a], cx[b]), math.max(cx[a], cx[b])
      local rightward = cx[b] > cx[a]
      local arrow_row = y + 1
      c:link(arrow_row, cx[a], rightward and E or W, hl, m.reply)
      for x = lo + 1, hi - 1 do
        local head = rightward and x == hi - 1 or (not rightward and x == lo + 1)
        if head then
          c:put(arrow_row, x, rightward and '▶' or '◀', hl)
        else
          c:link(arrow_row, x, E + W, hl, m.reply)
        end
      end
      if label ~= '' then
        -- Centred in the gap next to the sender when it fits there, so a
        -- message crossing several lifelines does not paint over them;
        -- otherwise centred over the whole span.
        local w = canvas.width_of(label)
        local near = rightward and cx[a + 1] or cx[a - 1]
        local glo, ghi = lo, hi
        if math.abs(near - cx[a]) >= w + 4 then
          glo, ghi = math.min(cx[a], near), math.max(cx[a], near)
        end
        local start = glo + math.ceil((ghi - glo - w) / 2)
        c:text(y, start, label, 'ThreadDiagramLabel')
      end
    end
    y = y + 2
  end

  -- Lifelines last: wherever an arrow already crosses or leaves one, the
  -- connections merge into a tee or a crossing.
  for i = 1, #d.participants do
    for row = 3, y do
      if not c:glyph(row, cx[i]) then
        c:link(row, cx[i], N + (row < y and S or 0), 'ThreadDiagramLifeline')
      end
    end
  end

  return c, hits, degraded
end

return M
