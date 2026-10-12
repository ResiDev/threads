--- A flow's ranks (steps 1 and 2 of thread.ui.diagram.flow): which rank each
--- node sits in, then the order across each rank that crosses least.

----------------------------------------------------------------------
-- 1. Ranks
----------------------------------------------------------------------

--- Mark back edges (those closing a cycle) and assign each node a rank.
---@param d table  validated `flow` diagram
---@param out table<string, table[]>  node id -> the edges leaving it
---@return table<string, integer> rank
local function rank_nodes(d, out)
  local state = {}
  local function dfs(id)
    state[id] = 1
    for _, e in ipairs(out[id]) do
      if e.from == e.to then
        e.self = true
      elseif state[e.to] == 1 then
        e.back = true
      elseif not state[e.to] then
        dfs(e.to)
      end
    end
    state[id] = 2
  end
  for _, n in ipairs(d.nodes) do
    if not state[n.id] then
      dfs(n.id)
    end
  end

  -- Longest path over the forward edges, in topological order.
  local indeg, preds = {}, {}
  for _, n in ipairs(d.nodes) do
    indeg[n.id], preds[n.id] = 0, {}
  end
  for _, e in ipairs(d.edges) do
    if not e.back and not e.self then
      indeg[e.to] = indeg[e.to] + 1
      table.insert(preds[e.to], e.from)
    end
  end
  local rank, queue = {}, {}
  for _, n in ipairs(d.nodes) do
    if indeg[n.id] == 0 then
      queue[#queue + 1] = n.id
    end
  end
  local topo = {}
  local head = 1
  while head <= #queue do
    local id = queue[head]
    head = head + 1
    topo[#topo + 1] = id
    local r = 0
    for _, p in ipairs(preds[id]) do
      r = math.max(r, rank[p] + 1)
    end
    rank[id] = r
    for _, e in ipairs(out[id]) do
      if not e.back and not e.self then
        indeg[e.to] = indeg[e.to] - 1
        if indeg[e.to] == 0 then
          queue[#queue + 1] = e.to
        end
      end
    end
  end

  -- A source feeding only deep nodes would otherwise sit on rank 0 with a long
  -- edge down to them; move it to just above its nearest child instead.
  for i = #topo, 1, -1 do
    local id = topo[i]
    if #preds[id] == 0 then
      local nearest
      for _, e in ipairs(out[id]) do
        if not e.back and not e.self then
          nearest = math.min(nearest or math.huge, rank[e.to])
        end
      end
      if nearest and nearest - 1 > rank[id] then
        rank[id] = nearest - 1
      end
    end
  end
  return rank
end

----------------------------------------------------------------------
-- 2. Order
----------------------------------------------------------------------

local function count_crossings(pos, edges, rank)
  local n = 0
  for i = 1, #edges do
    local a = edges[i]
    for j = i + 1, #edges do
      local b = edges[j]
      local ra1, ra2 = rank[a.from], rank[a.to]
      local rb1, rb2 = rank[b.from], rank[b.to]
      -- Only edges between the same pair of adjacent ranks can be compared
      -- this simply; that is most of them, and the rest the router handles.
      if ra1 == rb1 and ra2 == rb2 and math.abs(ra2 - ra1) == 1 then
        local x = (pos[a.from] - pos[b.from]) * (pos[a.to] - pos[b.to])
        if x < 0 then
          n = n + 1
        end
      end
    end
  end
  return n
end

local function order_layers(d, rank)
  local layers = {}
  local max_rank = 0
  for _, n in ipairs(d.nodes) do
    max_rank = math.max(max_rank, rank[n.id])
  end
  for r = 0, max_rank do
    layers[r] = {}
  end
  for _, n in ipairs(d.nodes) do
    table.insert(layers[rank[n.id]], n.id)
  end

  local neighbours = {}
  for _, n in ipairs(d.nodes) do
    neighbours[n.id] = {}
  end
  for _, e in ipairs(d.edges) do
    if not e.self then
      table.insert(neighbours[e.from], e.to)
      table.insert(neighbours[e.to], e.from)
    end
  end

  local function positions()
    local pos = {}
    for r = 0, max_rank do
      for i, id in ipairs(layers[r]) do
        pos[id] = i
      end
    end
    return pos
  end

  local function sweep(r, side)
    local pos = positions()
    local key = {}
    for i, id in ipairs(layers[r]) do
      local sum, count = 0, 0
      for _, nb in ipairs(neighbours[id]) do
        if (side < 0 and rank[nb] < r) or (side > 0 and rank[nb] > r) then
          sum, count = sum + pos[nb], count + 1
        end
      end
      key[id] = count > 0 and (sum / count) or i
      key[id] = key[id] + i * 1e-6 -- stable
    end
    table.sort(layers[r], function(a, b)
      return key[a] < key[b]
    end)
  end

  local best, best_x = vim.deepcopy(layers), count_crossings(positions(), d.edges, rank)
  for _ = 1, 4 do
    for r = 1, max_rank do
      sweep(r, -1)
    end
    for r = max_rank - 1, 0, -1 do
      sweep(r, 1)
    end
    local x = count_crossings(positions(), d.edges, rank)
    if x < best_x then
      best, best_x = vim.deepcopy(layers), x
    end
  end
  return best, max_rank
end

return { assign = rank_nodes, order = order_layers }
