--- `flow`: boxes and arrows, laid out in layers.
---
---   ┌────────┐     ┌─────────┐
---   │ parse  ├────▶│ resolve │
---   └────────┘     └────┬────┘
---                       │ loc
---                  ┌────▼────┐
---                  │ render  │
---                  └─────────┘
---
--- A small Sugiyama-style layout, then a router:
---
---   1. ranks     cycles are broken by reversing back edges, then each node
---                sits one rank past its deepest predecessor
---   2. order     barycentre sweeps reorder each rank to uncross the edges,
---                keeping whichever ordering crossed least
---   3. place     every node is pulled towards its neighbours' centres, so a
---                chain of single edges draws as a straight line
---   4. route     each edge is a cheapest path on the character grid -- bends
---                and crossings cost extra, boxes cannot be crossed at all,
---                and edges sharing an endpoint may share a trunk
---   5. labels    an edge's label goes in free space beside one of its straight
---                runs; failing that, it becomes a numbered footnote
---
--- Routing on the grid rather than drawing straight segments between layers
--- is what makes back edges, self-loops and long edges come out right without
--- each needing a case of its own.

local canvas = require 'thread.ui.diagram.canvas'
local diagram = require 'thread.ui.diagram'
local labels = require 'thread.ui.diagram.flow.labels'
local ranks = require 'thread.ui.diagram.flow.ranks'
local router = require 'thread.ui.diagram.flow.router'

local M = {}

local N, E, S, W = canvas.N, canvas.E, canvas.S, canvas.W
local opposite = canvas.opposite

----------------------------------------------------------------------
-- 3. Place
----------------------------------------------------------------------

--- Box contents for a node: its label lines, each shortened to `cap`.
local function box_of(node, cap)
  local lines = {}
  local widest = 0
  for _, l in ipairs(vim.split(node.label, '\n', { plain = true })) do
    l = diagram.truncate(vim.trim(l), cap)
    lines[#lines + 1] = l
    widest = math.max(widest, canvas.width_of(l))
  end
  return { lines = lines, w = widest + 4, h = #lines + 2 }
end

--- Positions along the minor axis (across a rank) for every node.
local function place_minor(layers, max_rank, ext, neighbours, rank, sep)
  local pos = {}
  -- Start packed.
  for r = 0, max_rank do
    local x = 0
    for _, id in ipairs(layers[r]) do
      pos[id] = x
      x = x + ext[id] + sep
    end
  end
  local function centre(id)
    return pos[id] + math.floor(ext[id] / 2)
  end

  local function pass(r, side)
    local ids = layers[r]
    local desired = {}
    for _, id in ipairs(ids) do
      local sum, count = 0, 0
      for _, nb in ipairs(neighbours[id]) do
        if (side < 0 and rank[nb] < r) or (side > 0 and rank[nb] > r) then
          sum, count = sum + centre(nb), count + 1
        end
      end
      desired[id] = count > 0 and math.floor(sum / count + 0.5) - math.floor(ext[id] / 2) or pos[id]
    end
    -- Greedy left to right, then slide the whole rank by the mean shortfall so
    -- the push-right of the greedy pass does not bias everything one way.
    local prev_end
    for _, id in ipairs(ids) do
      local p = desired[id]
      if prev_end and p < prev_end + sep then
        p = prev_end + sep
      end
      pos[id] = p
      prev_end = p + ext[id]
    end
    local drift, count = 0, 0
    for _, id in ipairs(ids) do
      drift, count = drift + (desired[id] - pos[id]), count + 1
    end
    -- Only slide left: sliding right never helps a rank packed against its own
    -- constraint, and a negative mean means the greedy pass pushed it too far.
    if count > 0 and drift < 0 then
      local shift = math.ceil(drift / count)
      for _, id in ipairs(ids) do
        pos[id] = pos[id] + shift
      end
    end
  end

  for _ = 1, 3 do
    for r = 1, max_rank do
      pass(r, -1)
    end
    for r = max_rank - 1, 0, -1 do
      pass(r, 1)
    end
  end
  local lo = math.huge
  for _, p in pairs(pos) do
    lo = math.min(lo, p)
  end
  for id, p in pairs(pos) do
    pos[id] = p - lo
  end
  return pos
end

----------------------------------------------------------------------
-- Putting it together
----------------------------------------------------------------------

--- One complete attempt at a given direction, label cap and spacing.
---@param d table  validated `flow` diagram
---@param dir 'down'|'right'
---@param cap integer  the widest a label may be before it wraps
---@param spacing integer  extra gap between ranks
---@param status table|nil
---@param max_width integer
---@return table|nil result, string|nil why
local function attempt(d, dir, cap, spacing, status, max_width)
  local out = {}
  for _, n in ipairs(d.nodes) do
    out[n.id] = {}
  end
  local edges = vim.deepcopy(d.edges)
  for _, e in ipairs(edges) do
    table.insert(out[e.from], e)
  end
  local by_id = {}
  for _, n in ipairs(d.nodes) do
    by_id[n.id] = n
  end

  local rank = ranks.assign({ nodes = d.nodes, edges = edges }, out)

  -- An edge crossing several ranks gets a dummy node in each rank it passes
  -- through: a one-column channel that ordering and placement treat like any
  -- node, and that the router is made to run straight down. Without them a
  -- long edge has no place of its own -- it hugs the nearest box, bundles
  -- with its neighbours, and tangles into its target.
  local lnodes, ledges = {}, {}
  for _, n in ipairs(d.nodes) do
    lnodes[#lnodes + 1] = n
  end
  local is_dummy = {}
  for i, e in ipairs(edges) do
    if not e.self then
      local a, b = rank[e.from], rank[e.to]
      local dir_ = b > a and 1 or -1
      local prev = e.from
      e.index, e.chain = i, {}
      for r = a + dir_, b - dir_, dir_ do
        local id = string.format('\1%d:%d', i, r)
        rank[id], is_dummy[id] = r, true
        lnodes[#lnodes + 1] = { id = id }
        e.chain[#e.chain + 1] = id
        ledges[#ledges + 1] = { from = prev, to = id }
        prev = id
      end
      ledges[#ledges + 1] = { from = prev, to = e.to }
    end
  end

  local layers, max_rank = ranks.order({ nodes = lnodes, edges = ledges }, rank)

  local box = {}
  for _, n in ipairs(d.nodes) do
    box[n.id] = box_of(n, cap)
  end
  local down = dir == 'down'
  -- Extents along the minor axis (across a rank) and the major (along ranks).
  local minor, major = {}, {}
  for id, b in pairs(box) do
    minor[id] = down and b.w or b.h
    major[id] = down and b.h or b.w
  end
  for id in pairs(is_dummy) do
    minor[id], major[id] = 1, 0
  end

  local neighbours = {}
  for _, n in ipairs(lnodes) do
    neighbours[n.id] = {}
  end
  for _, e in ipairs(ledges) do
    table.insert(neighbours[e.from], e.to)
    table.insert(neighbours[e.to], e.from)
  end

  local sep = down and (3 + spacing * 2) or (1 + spacing)
  local pos = place_minor(layers, max_rank, minor, neighbours, rank, sep)

  -- The gap after each rank: room to route in, and in a left-to-right flow,
  -- room for the labels of the edges crossing it.
  local longest_label = 0
  for _, e in ipairs(edges) do
    if e.label then
      longest_label = math.max(longest_label, canvas.width_of(diagram.truncate(e.label, cap)))
    end
  end
  local gaps = {}
  for r = 0, max_rank do
    if down then
      gaps[r] = 2 + spacing
    else
      local widest = 0
      for _, e in ipairs(edges) do
        if e.label and rank[e.from] == r and rank[e.to] == r + 1 then
          widest = math.max(widest, canvas.width_of(diagram.truncate(e.label, cap)))
        end
      end
      gaps[r] = math.max(6, widest + 4) + spacing * 2
    end
  end

  local rank_start, rank_size = {}, {}
  local cursor = 0
  for r = 0, max_rank do
    local size = 0
    for _, id in ipairs(layers[r]) do
      size = math.max(size, major[id])
    end
    size = math.max(size, 1)
    rank_start[r], rank_size[r] = cursor, size
    cursor = cursor + size + gaps[r]
  end
  local major_total = cursor - gaps[max_rank]
  local minor_total = 0
  for id, p in pairs(pos) do
    minor_total = math.max(minor_total, p + minor[id])
  end

  -- The boxes alone already need this many columns; routing cannot make it
  -- narrower, so do not pay for routing an attempt that is lost already.
  if (down and minor_total or major_total) > max_width then
    return nil, 'too wide'
  end

  -- Margins all round, for back edges and self-loops to swing out into; a
  -- label's width extra on the right, where the router tends to put them.
  local margin = 3 + spacing
  local top, left = margin, margin + (down and 0 or 0)
  local grid_h = (down and major_total or minor_total) + margin * 2 + 2
  local grid_w = (down and minor_total or major_total) + margin * 2 + longest_label + 3

  -- Box rectangles on the grid, centred within their rank.
  local rect = {}
  for _, n in ipairs(d.nodes) do
    local id = n.id
    local r = rank[id]
    local along = rank_start[r] + math.floor((rank_size[r] - major[id]) / 2)
    if down then
      rect[id] = { row = top + along, col = left + pos[id], h = box[id].h, w = box[id].w }
    else
      rect[id] = { row = top + pos[id], col = left + along, h = box[id].h, w = box[id].w }
    end
  end

  local c = canvas.new()
  local g = router.grid(grid_w, grid_h)
  local hits = {}
  for _, n in ipairs(d.nodes) do
    local b, rc = box[n.id], rect[n.id]
    local label_hl, box_hl = diagram.node_hl(n, status)
    c:box(rc.row, rc.col, rc.h, rc.w, box_hl)
    for i, line in ipairs(b.lines) do
      local inner = rc.w - 2
      local lw = canvas.width_of(line)
      c:text(rc.row + i, rc.col + 1 + math.floor((inner - lw) / 2), line, label_hl)
    end
    hits[#hits + 1] = { node = n, row = rc.row, col = rc.col, width = rc.w, height = rc.h }
    for y = rc.row, rc.row + rc.h - 1 do
      for x = rc.col, rc.col + rc.w - 1 do
        g.blocked[g.key(y, x)] = true
      end
    end
    for y = rc.row - 1, rc.row + rc.h do
      g.near[g.key(y, rc.col - 1)] = true
      g.near[g.key(y, rc.col + rc.w)] = true
    end
    for x = rc.col - 1, rc.col + rc.w do
      g.near[g.key(rc.row - 1, x)] = true
      g.near[g.key(rc.row + rc.h, x)] = true
    end
  end

  -- Ports: where on its box each edge leaves and arrives. Down a flow edges
  -- leave through the bottom and arrive through the top; across one, the right
  -- and the left. Several edges on one side are spread along it, ordered by
  -- where their other end is, so they fan out rather than cross at the box.
  local out_side, in_side = down and S or E, down and N or W
  local function centre(id)
    local rc = rect[id]
    return down and (rc.col + math.floor(rc.w / 2)) or (rc.row + math.floor(rc.h / 2))
  end
  local leaving, arriving = {}, {}
  for _, n in ipairs(d.nodes) do
    leaving[n.id], arriving[n.id] = {}, {}
  end
  -- A self-loop is not routed: a line leaving a box only to swing round and
  -- re-enter it is a lot of ink for "repeats", and it fights every other edge
  -- for the margin. It becomes a `↻ label` beside the box instead.
  local routed = {}
  for _, e in ipairs(edges) do
    if not e.self then
      routed[#routed + 1] = e
      table.insert(leaving[e.from], e)
      table.insert(arriving[e.to], e)
    end
  end
  local function assign(list, id, other, field)
    table.sort(list, function(a, b)
      local ca, cb = centre(a[other]), centre(b[other])
      if ca ~= cb then
        return ca < cb
      end
      return (a.back and 1 or 0) < (b.back and 1 or 0)
    end)
    local rc = rect[id]
    local span = (down and rc.w or rc.h) - 2
    local k = #list
    for i, e in ipairs(list) do
      local off
      if k == 1 then
        off = math.floor((down and rc.w or rc.h) / 2)
      else
        off = 1 + math.floor((i - 0.5) * span / k)
      end
      e[field] = off
    end
  end
  for _, n in ipairs(d.nodes) do
    assign(leaving[n.id], n.id, 'to', 'out_off')
    assign(arriving[n.id], n.id, 'from', 'in_off')
  end

  local function port(id, side, off)
    local rc = rect[id]
    if side == S then
      return { rc.row + rc.h - 1, rc.col + off }, { rc.row + rc.h, rc.col + off }
    elseif side == N then
      return { rc.row, rc.col + off }, { rc.row - 1, rc.col + off }
    elseif side == E then
      return { rc.row + off, rc.col + rc.w - 1 }, { rc.row + off, rc.col + rc.w }
    end
    return { rc.row + off, rc.col }, { rc.row + off, rc.col - 1 }
  end

  -- Two tags per edge. The first is its source *port*: edges leaving through
  -- the very same cell must share a trunk, and only they may -- edges with
  -- ports of their own merging on the way would draw a junction that is not
  -- there. The second, its target port, lets coinciding arrivals in.
  -- A third tag, the edge's own, owns its dummy channels.
  local function reserve(cell, tag)
    local key = g.key(cell[1], cell[2])
    g.reserved[key] = g.reserved[key] or {}
    g.reserved[key][tag] = true
  end
  for _, e in ipairs(routed) do
    e.tags = { 's:' .. e.from .. ':' .. e.out_off, 't:' .. e.to .. ':' .. e.in_off, 'e:' .. e.index }
    e.src_port, e.start = port(e.from, out_side, e.out_off)
    e.dst_port, e.goal = port(e.to, in_side, e.in_off)
    reserve(e.start, e.tags[1])
    reserve(e.goal, e.tags[2])

    -- Each dummy's channel: the run of cells across its rank, in the order
    -- the edge travels them -- along the flow, or against it for a back edge.
    e.travel = (rank[e.to] > rank[e.from]) and out_side or opposite[out_side]
    e.channels = {}
    for _, id in ipairs(e.chain) do
      local r = rank[id]
      local cells = {}
      for k = 0, rank_size[r] - 1 do
        local along = top + rank_start[r] + k
        if down then
          cells[#cells + 1] = { along, left + pos[id] }
        else
          cells[#cells + 1] = { left + pos[id], left + rank_start[r] + k }
        end
      end
      if not down then
        for _, cell in ipairs(cells) do
          cell[1], cell[2] = top + pos[id], cell[2]
        end
      end
      if e.travel == N or e.travel == W then
        local rev = {}
        for k = #cells, 1, -1 do
          rev[#rev + 1] = cells[k]
        end
        cells = rev
      end
      for _, cell in ipairs(cells) do
        reserve(cell, e.tags[3])
      end
      e.channels[#e.channels + 1] = cells
    end
  end

  --- The edge's whole path: a leg to each channel, straight through it, and a
  --- last leg to the target port.
  local function route_edge(e)
    local path = {}
    local function append(cells, skip_first)
      for i, cell in ipairs(cells) do
        if not (skip_first and i == 1) then
          path[#path + 1] = cell
        end
      end
    end
    local from, from_dir = e.start, out_side
    for _, cells in ipairs(e.channels) do
      local leg = router.route(g, c, from, cells[1], from_dir, e.travel, e.tags)
      if not leg then
        return nil
      end
      append(leg, #path > 0)
      append(cells, true)
      from, from_dir = cells[#cells], e.travel
    end
    local leg = router.route(g, c, from, e.goal, from_dir, opposite[in_side], e.tags)
    if not leg then
      return nil
    end
    append(leg, #path > 0)
    return path
  end

  -- Short forward edges first: they are the backbone, and should get the
  -- straight lines. Back edges and self-loops, which go the long way round,
  -- route last into whatever room is left.
  local order = {}
  for i, e in ipairs(routed) do
    order[i] = e
  end
  local function span_of(e)
    return (e.back or e.self) and 1000 or math.abs(rank[e.to] - rank[e.from])
  end
  table.sort(order, function(a, b)
    local sa, sb = span_of(a), span_of(b)
    if sa ~= sb then
      return sa < sb
    end
    return (a.label and 0 or 1) < (b.label and 0 or 1)
  end)

  for _, e in ipairs(order) do
    local path = route_edge(e)
    if not path then
      return nil, 'no route'
    end
    e.path = path
    local hl = 'ThreadDiagramEdge'
    c:link(path[1][1], path[1][2], opposite[out_side], hl, e.dashed)
    for i = 1, #path - 1 do
      local a, b = path[i], path[i + 1]
      local bit_ = (b[1] < a[1] and N) or (b[1] > a[1] and S) or (b[2] > a[2] and E) or W
      c:link(a[1], a[2], bit_, hl, e.dashed)
      c:link(b[1], b[2], opposite[bit_], hl, e.dashed)
    end
    c:link(path[#path][1], path[#path][2], opposite[in_side], hl, e.dashed)
    for _, cell in ipairs(path) do
      local key = g.key(cell[1], cell[2])
      g.owners[key] = g.owners[key] or {}
      g.owners[key][e.tags[1]] = true
    end
  end

  -- Ports last, over the box borders: a tee where an edge leaves, an
  -- arrowhead where it arrives.
  for _, e in ipairs(routed) do
    local _, box_hl = diagram.node_hl(by_id[e.from], status)
    c:put(e.src_port[1], e.src_port[2], down and '┬' or '├', box_hl)
  end
  -- Down a flow the arrowhead notches the top border (`┌──▼──┐`), which reads
  -- well. Across one, a `▶` in place of the left border makes the box look
  -- open, so it sits just outside instead (`──▶│`) -- when every edge into
  -- that port arrives straight; arriving round a corner, the corner has to
  -- stay. Either way one arrowhead per port, however many edges share it.
  local at_port = {}
  for _, e in ipairs(routed) do
    local key = g.key(e.dst_port[1], e.dst_port[2])
    at_port[key] = at_port[key] or { port = e.dst_port, goal = e.goal, straight = true }
    local last, before = e.path[#e.path], e.path[#e.path - 1]
    if before and before[1] ~= last[1] then
      at_port[key].straight = false
    end
  end
  for _, p in pairs(at_port) do
    if not down and p.straight then
      c:put(p.goal[1], p.goal[2], '▶', 'ThreadDiagramEdge')
    else
      c:put(p.port[1], p.port[2], down and '▼' or '▶', 'ThreadDiagramEdge')
    end
  end

  -- Labels, in the routing order: the backbone's labels get the best spots.
  local footnotes = {}
  for _, e in ipairs(order) do
    if e.label then
      local label = diagram.truncate(e.label, cap)
      local lr, lc = labels.place(c, g, e.path, label, down)
      if lr and lc then
        c:text(lr, lc, label, 'ThreadDiagramLabel')
      else
        footnotes[#footnotes + 1] = e
      end
    end
  end

  for _, e in ipairs(edges) do
    if e.self then
      local rc = rect[e.from]
      local text = '↻' .. (e.label and (' ' .. diagram.truncate(e.label, cap)) or '')
      local w = canvas.width_of(text)
      local placed = false
      for dy = 0, rc.h - 1 do
        local row = rc.row + (math.floor(rc.h / 2) + dy) % rc.h
        if labels.run_free(c, g, row, rc.col + rc.w, rc.col + rc.w + w + 1) then
          c:text(row, rc.col + rc.w + 1, text, 'ThreadDiagramLabel')
          placed = true
          break
        elseif labels.run_free(c, g, row, rc.col - w - 2, rc.col - 1) then
          c:text(row, rc.col - w - 1, text, 'ThreadDiagramLabel')
          placed = true
          break
        end
      end
      if not placed then
        footnotes[#footnotes + 1] = e
      end
    end
  end

  return {
    canvas = c,
    hits = hits,
    footnotes = footnotes,
    cap = cap,
    by_id = by_id,
  }
end

---@param d table validated `flow` diagram
---@param opts { max_width: integer, status: table|nil }
---@return tour.Canvas|nil, thread.DiagramHit[]|nil, string|nil
function M.layout(d, opts)
  local longest = 0
  for _, n in ipairs(d.nodes) do
    for _, l in ipairs(vim.split(n.label, '\n', { plain = true })) do
      longest = math.max(longest, canvas.width_of(vim.trim(l)))
    end
  end
  for _, e in ipairs(d.edges) do
    if e.label then
      longest = math.max(longest, canvas.width_of(e.label))
    end
  end

  local caps = { longest }
  for _, cap in ipairs { 24, 16, 12, 8 } do
    if cap < longest then
      caps[#caps + 1] = cap
    end
  end
  local dirs = { d.direction }
  if d.direction == 'right' then
    dirs[2] = 'down'
  end

  local fallback
  for di, dir in ipairs(dirs) do
    for ci, cap in ipairs(caps) do
      local too_wide = false
      for spacing = 0, 2 do
        local res, why = attempt(d, dir, cap, spacing, opts.status, opts.max_width)
        if why == 'too wide' then
          too_wide = true
        elseif res then
          local first, last = res.canvas:extent()
          local width = first and (last - first + 1) or 0
          if width > opts.max_width then
            too_wide = true
          elseif #res.footnotes == 0 or spacing == 2 then
            labels.footnotes(res)
            local notes = {}
            if di > 1 then
              notes[#notes + 1] = 'drawn top-down to fit'
            end
            if ci > 1 then
              notes[#notes + 1] = 'labels shortened to fit'
            end
            return res.canvas, res.hits, #notes > 0 and table.concat(notes, '; ') or nil
          elseif not fallback then
            fallback = { res, di, ci }
          end
        end
        if too_wide then
          break -- more spacing only makes it wider
        end
      end
    end
  end
  if fallback then
    local res = fallback[1]
    labels.footnotes(res)
    return res.canvas, res.hits, nil
  end
  return nil
end

return M
