--- Diagrams inside a step's card: laid out as box-drawing text, and handed
--- back as `virt_lines`-style rows plus where each node landed, so a cursor
--- (in the prose window) or a picker can follow one. What the agent wrote
--- is checked first, by thread.model.diagram; this takes it checked.
---
--- Three kinds, each its own layout:
---   `calls`     an indented call tree rooted at an entry point
---   `sequence`  participants as lifelines, messages as arrows over time
---   `flow`      boxes and arrows, layered top-down or left-to-right
---
--- Every node may be anchored exactly the way a step is -- `file` plus `text`
--- or `line` -- or point at another step with `step`. The
--- anchors resolve through the same code as steps, so a node whose code has
--- gone is reported broken, never guessed at.
---
--- Pure: checked diagrams in, chunk rows out.

local canvas = require 'thread.ui.diagram.canvas'

local M = {}

--- Every node of a diagram, in reading order.
---@param d table validated diagram
---@return table[]
function M.nodes(d)
  if d.kind == 'flow' then
    return d.nodes
  elseif d.kind == 'sequence' then
    return d.participants
  end
  local out = {}
  local function walk(n)
    out[#out + 1] = n
    for _, c in ipairs(n.children or {}) do
      walk(c)
    end
  end
  walk(d.root)
  return out
end

--- Whether a node goes anywhere when followed.
---@param node table  a checked diagram's node
---@return boolean
function M.is_linked(node)
  return node.chunk ~= nil
end

----------------------------------------------------------------------
-- Rendering
----------------------------------------------------------------------

--- Shorten `s` to at most `w` display columns, marking the cut.
---@param s string
---@param w integer
---@return string
function M.truncate(s, w)
  if canvas.width_of(s) <= w then
    return s
  end
  if w <= 1 then
    return '…'
  end
  local chars = vim.fn.split(s, '\\zs')
  local out, used = {}, 0
  for _, ch in ipairs(chars) do
    local cw = canvas.width_of(ch)
    if used + cw > w - 1 then
      break
    end
    out[#out + 1] = ch
    used = used + cw
  end
  return table.concat(out) .. '…'
end

--- The highlight group of a node's label and border, by how it resolved.
---@param node table
---@param status table<table, 'ok'|'broken'|'here'>|nil
---@return string label_hl, string border_hl
function M.node_hl(node, status)
  local s = status and status[node]
  if s == 'broken' then
    return 'ThreadBroken', 'ThreadBroken'
  elseif s == 'here' then
    return 'ThreadDiagramHere', 'ThreadDiagramHere'
  end
  if M.is_linked(node) then
    return 'ThreadDiagramNode', 'ThreadDiagramBox'
  end
  return 'ThreadDiagramText', 'ThreadDiagramBox'
end

---@class thread.DiagramHit
---@field node table   the node, as validated
---@field row integer  0-indexed row in `rows`
---@field col integer  0-indexed display column
---@field width integer
---@field height integer

---@class thread.DiagramRender
---@field rows [string, string][][]  one chunk list per row, all `width` wide
---@field width integer
---@field hits thread.DiagramHit[]
---@field degraded string|nil  why the diagram was drawn simpler than asked

--- The last resort when nothing fits: one row per connection, no geometry. Not
--- pretty, but every label is still there and every node still followable.
local function list_fallback(d, max_width, status)
  local c = canvas.new()
  local hits = {}
  local row = 0
  local by_id = {}
  for _, n in ipairs(M.nodes(d)) do
    if n.id then
      by_id[n.id] = n
    end
  end

  local function node_text(r, col, node, w)
    local label = M.truncate((node.label:gsub('\n', ' ')), w)
    local hl = M.node_hl(node, status)
    hits[#hits + 1] = { node = node, row = r, col = col, width = canvas.width_of(label), height = 1 }
    return c:text(r, col, label, hl)
  end

  local pairs_ = {}
  if d.kind == 'flow' then
    for _, e in ipairs(d.edges) do
      pairs_[#pairs_ + 1] = { by_id[e.from], by_id[e.to], e.label }
    end
  elseif d.kind == 'sequence' then
    for _, m in ipairs(d.messages) do
      pairs_[#pairs_ + 1] = { by_id[m.from], by_id[m.to], m.label }
    end
  end

  -- Each row is budgeted so it cannot overflow: the connection's label gets
  -- a quarter, the two ends split what is left, and a short arrow replaces
  -- the labelled one when there is no room for it at all.
  for _, p in ipairs(pairs_) do
    local arrow = ' → '
    if p[3] then
      local labelled = ' ── ' .. M.truncate(p[3], math.max(3, math.floor(max_width / 4))) .. ' ─▶ '
      if max_width - canvas.width_of(labelled) >= 8 then
        arrow = labelled
      end
    elseif max_width >= 16 then
      arrow = ' ──▶ '
    end
    local room = max_width - canvas.width_of(arrow)
    local left_w = math.max(1, math.min(canvas.width_of(p[1].label), math.floor(room / 2)))
    local col = node_text(row, 0, p[1], left_w)
    col = c:text(row, col, arrow, 'ThreadDiagramLabel')
    node_text(row, col, p[2], math.max(1, max_width - col))
    row = row + 1
  end
  -- Nodes that no connection mentions would vanish from the list otherwise.
  local seen = {}
  for _, p in ipairs(pairs_) do
    seen[p[1]], seen[p[2]] = true, true
  end
  for _, n in ipairs(M.nodes(d)) do
    if not seen[n] then
      node_text(row, 0, n, max_width)
      row = row + 1
    end
  end
  return c, hits
end

--- Crop a laid-out canvas to what was drawn and package it.
local function finish(c, hits, degraded)
  local first, last = c:extent()
  local top, bottom = c:row_extent()
  if not first then
    return { rows = {}, width = 0, hits = {}, degraded = degraded }
  end
  local rows = c:rows(first, last + 1)
  rows = vim.list_slice(rows, top + 1, bottom + 1)
  local shifted = {}
  for _, h in ipairs(hits) do
    shifted[#shifted + 1] = { node = h.node, row = h.row - top, col = h.col - first, width = h.width, height = h.height }
  end
  return { rows = rows, width = last - first + 1, hits = shifted, degraded = degraded }
end

--- Lay a diagram out in at most `max_width` columns.
---@param d table validated diagram
---@param opts { max_width: integer, status: table|nil }
---@return thread.DiagramRender
function M.render(d, opts)
  local max_width = math.max(16, opts.max_width or 80)
  local layout = require('thread.ui.diagram.' .. d.kind)
  local c, hits, degraded = layout.layout(d, { max_width = max_width, status = opts.status })
  if c then
    local first, last = c:extent()
    if not first or last - first + 1 <= max_width then
      return finish(c, hits, degraded)
    end
  end
  local fc, fhits = list_fallback(d, max_width, opts.status)
  return finish(fc, fhits, string.format('too wide for %d columns; shown as a list', max_width))
end

--- The node, if any, drawn at a display position of the rendered diagram.
---@param r thread.DiagramRender
---@param row integer 0-indexed
---@param col integer 0-indexed display column
---@return table|nil node
function M.hit(r, row, col)
  for _, h in ipairs(r.hits) do
    if row >= h.row and row < h.row + h.height and col >= h.col and col < h.col + h.width then
      return h.node
    end
  end
end

return M
