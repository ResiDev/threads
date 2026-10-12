--- A flow's edges (step 4 of thread.ui.diagram.flow): each a cheapest path on
--- the character grid, round the boxes.

local canvas = require 'thread.ui.diagram.canvas'

local N, E, S, W = canvas.N, canvas.E, canvas.S, canvas.W
local DIRS = { N, E, S, W }
local delta, opposite = canvas.delta, canvas.opposite

----------------------------------------------------------------------
-- 4. Route
----------------------------------------------------------------------

--- A minimal binary heap of { cost, state }.
local function heap()
  local h = { n = 0 }
  function h.push(cost, st)
    h.n = h.n + 1
    local i = h.n
    h[i] = { cost, st }
    while i > 1 do
      local p = math.floor(i / 2)
      if h[p][1] <= h[i][1] then
        break
      end
      h[p], h[i] = h[i], h[p]
      i = p
    end
  end
  function h.pop()
    if h.n == 0 then
      return nil
    end
    local top = h[1]
    h[1] = h[h.n]
    h[h.n] = nil
    h.n = h.n - 1
    local i = 1
    while true do
      local l, r = i * 2, i * 2 + 1
      local m = i
      if l <= h.n and h[l][1] < h[m][1] then
        m = l
      end
      if r <= h.n and h[r][1] < h[m][1] then
        m = r
      end
      if m == i then
        break
      end
      h[m], h[i] = h[i], h[m]
      i = m
    end
    return top[1], top[2]
  end
  return h
end

local COST = { step = 2, share = 1, bend = 7, near = 3, cross = 12 }
local DIR_INDEX = { [N] = 1, [E] = 2, [S] = 3, [W] = 4 }

--- The grid the router walks: which cells are boxes, which are next to one,
--- which lines already pass through, and who owns them.
local function grid(width, height)
  local g = { w = width, h = height, blocked = {}, near = {}, owners = {}, reserved = {} }
  function g.key(r, c)
    return r * width + c
  end
  function g.inside(r, c)
    return r >= 0 and c >= 0 and r < height and c < width
  end
  return g
end

--- Whether a set of owner tags shares anything with this edge's tags.
local function shares(owners, tags)
  if not owners then
    return false
  end
  for _, tag in ipairs(tags) do
    if owners[tag] then
      return true
    end
  end
  return false
end

--- Cheapest path from `start` (leaving in `out_dir`) to `goal` (entering the
--- port in `in_dir`). Returns the cells in order, or nil.
local function route(g, c, start, goal, out_dir, in_dir, tags)
  local width = g.w
  local best = {}
  local prev = {}
  local h = heap()
  local function state(r, col, dir)
    return ((r * width + col) * 4) + DIR_INDEX[dir] - 1
  end
  -- A*: the Manhattan distance, at the cheapest step cost, never overestimates.
  local function h_cost(r, col)
    return (math.abs(r - goal[1]) + math.abs(col - goal[2])) * COST.share
  end
  local s0 = state(start[1], start[2], out_dir)
  best[s0] = 0
  h.push(h_cost(start[1], start[2]), s0)

  local goal_state
  while true do
    local prio, st = h.pop()
    if not prio then
      break
    end
    local dir = DIRS[(st % 4) + 1]
    local cell = math.floor(st / 4)
    local r, col = math.floor(cell / width), cell % width
    local cost = best[st]
    if prio <= cost + h_cost(r, col) then
      if r == goal[1] and col == goal[2] then
        goal_state = st
        break
      end
      local key = g.key(r, col)
      -- In a cell some other edge passes through, only straight on: turning
      -- there would fuse two unrelated lines into one junction.
      local crossing = c:mask(r, col) ~= 0 and not shares(g.owners[key], tags)
      for _, d2 in ipairs(DIRS) do
        if d2 ~= opposite[dir] and (not crossing or d2 == dir) then
          local nr, nc = r + delta[d2][1], col + delta[d2][2]
          local nkey = g.key(nr, nc)
          if g.inside(nr, nc) and not g.blocked[nkey] then
            local reserved = g.reserved[nkey]
            local ok = not reserved or shares(reserved, tags)
            local step = COST.step
            local mask = c:mask(nr, nc)
            local into_shared_goal = nr == goal[1] and nc == goal[2] and reserved and shares(reserved, tags)
            if ok and mask ~= 0 then
              if shares(g.owners[nkey], tags) or into_shared_goal then
                step = COST.share
              else
                -- A foreign line may be crossed only at a right angle, through
                -- a plain straight run of it.
                local straight = (mask == N + S or mask == N or mask == S) and (d2 == E or d2 == W)
                  or (mask == E + W or mask == E or mask == W) and (d2 == N or d2 == S)
                ok = straight and not c:glyph(nr, nc)
                step = COST.cross
              end
            elseif ok and c:glyph(nr, nc) then
              ok = false -- a label or an arrowhead
            end
            if ok then
              local add = step + (d2 ~= dir and COST.bend or 0) + (g.near[nkey] and COST.near or 0)
              if nr == goal[1] and nc == goal[2] and d2 ~= in_dir then
                add = add + COST.bend
              end
              local ns = state(nr, nc, d2)
              local nc_cost = cost + add
              if nc_cost < (best[ns] or math.huge) then
                best[ns] = nc_cost
                prev[ns] = st
                h.push(nc_cost + h_cost(nr, nc), ns)
              end
            end
          end
        end
      end
    end
  end

  if not goal_state then
    return nil
  end
  local cells = {}
  local st = goal_state
  while st do
    local cell = math.floor(st / 4)
    table.insert(cells, 1, { math.floor(cell / width), cell % width })
    st = prev[st]
  end
  return cells
end

return { grid = grid, route = route }
