--- The threads as a tree. The only edge is a message's `children`: the
--- threads it leads to, in order. A thread has one parent at most, so there
--- is always one way back to the top.
---
--- A walk is the tree read top to bottom under its head: the nearest
--- ancestor that is anchored, or the root. Stages (threads about no line)
--- are walked through; a step's own children (a reply that led somewhere)
--- are not, until you go into them.

local store = require 'thread.store'

local M = {}

--- child id -> { id = parent thread id, index = message index }, worked out
--- once per load of the batch.
---@param batch thread.Batch
local function parents(batch)
  if not batch.parents then
    local out = {}
    for _, c in ipairs(batch.data.threads) do
      for i, m in ipairs(c.messages) do
        for _, child in ipairs(m.children or {}) do
          -- One parent each: the first message to claim a thread keeps it.
          if out[child] == nil and child ~= c.id then
            out[child] = { id = c.id, index = i }
          end
        end
      end
    end
    batch.parents = out
  end
  return batch.parents
end

---@param batch thread.Batch
---@param id integer
---@return thread.Comment|nil
local function find(batch, id)
  return (store.find(batch, id))
end

--- The thread that leads to this one, and the index of the message that does.
---@param batch thread.Batch
---@param id integer
---@return thread.Comment|nil, integer|nil
function M.parent(batch, id)
  local p = parents(batch)[id]
  if p then
    return find(batch, p.id), p.index
  end
end

--- The threads a thread leads to, every message's in order.
---@param batch thread.Batch
---@param c thread.Comment
---@return thread.Comment[]
function M.children(batch, c)
  local out = {}
  local own = parents(batch)
  for _, m in ipairs(c.messages) do
    for _, id in ipairs(m.children or {}) do
      local child = own[id] and own[id].id == c.id and find(batch, id)
      if child then
        out[#out + 1] = child
      end
    end
  end
  return out
end

--- Whether a thread leads anywhere.
function M.leads(batch, c)
  return #M.children(batch, c) > 0
end

--- From the top down to this thread.
---@param batch thread.Batch
---@param id integer
---@return thread.Comment[]
function M.path(batch, id)
  local out, seen = {}, {}
  local c = find(batch, id)
  while c and not seen[c.id] do
    seen[c.id] = true
    table.insert(out, 1, c)
    c = M.parent(batch, c.id)
  end
  return out
end

--- The top of a thread's tree.
function M.root(batch, id)
  return M.path(batch, id)[1]
end

--- The thread a walk through this one is under: its parent, climbing
--- through stages (threads about no line) to an anchored thread or the root.
---@param batch thread.Batch
---@param id integer
---@return thread.Comment|nil
function M.head(batch, id)
  local h = M.parent(batch, id)
  local seen = {}
  while h and not seen[h.id] and not store.anchored(h) do
    seen[h.id] = true
    local up = M.parent(batch, h.id)
    if not up then
      break
    end
    h = up
  end
  return h
end

---@class thread.WalkItem
---@field c thread.Comment
---@field depth integer  1 for the head's own children

--- Everything a walk under `head` goes through, in order: its children, and
--- the children of those that are about no line (stages), depth first.
---@param batch thread.Batch
---@param head thread.Comment
---@return thread.WalkItem[]
function M.walk(batch, head)
  local out, seen = {}, { [head.id] = true }
  local function visit(c, depth)
    for _, child in ipairs(M.children(batch, c)) do
      if not seen[child.id] then
        seen[child.id] = true
        out[#out + 1] = { c = child, depth = depth }
        if not store.anchored(child) then
          visit(child, depth + 1)
        end
      end
    end
  end
  visit(head, 1)
  return out
end

--- Where a thread sits in its walk: the head, the list, and its index.
---@param batch thread.Batch
---@param id integer
---@return thread.Comment|nil head, thread.WalkItem[]|nil list, integer|nil index
function M.position(batch, id)
  local head = M.head(batch, id)
  if not head then
    return nil
  end
  local list = M.walk(batch, head)
  for i, item in ipairs(list) do
    if item.c.id == id then
      return head, list, i
    end
  end
  return head, list, nil
end

--- The step number in a walk, counting only threads on lines: `2/4`.
---@param list thread.WalkItem[]
---@param index integer
---@return integer n, integer total
function M.step_of(list, index)
  local n, total = 0, 0
  for i, item in ipairs(list) do
    if store.anchored(item.c) then
      total = total + 1
      if i <= index then
        n = n + 1
      end
    end
  end
  return n, total
end

--- How big a walk is: stages (threads about no line) and steps.
---@param list thread.WalkItem[]
---@return integer stages, integer steps
function M.size(list)
  local stages, steps = 0, 0
  for _, item in ipairs(list) do
    if store.anchored(item.c) then
      steps = steps + 1
    else
      stages = stages + 1
    end
  end
  return stages, steps
end

--- `2 stages · 6 steps`, or `3 steps`.
function M.describe(list)
  local stages, steps = M.size(list)
  local parts = {}
  if stages > 0 then
    parts[#parts + 1] = stages .. (stages == 1 and ' stage' or ' stages')
  end
  parts[#parts + 1] = steps .. (steps == 1 and ' step' or ' steps')
  return table.concat(parts, ' · ')
end

--- Every tour in the batch, by its head: the topmost threads that lead
--- somewhere. A head's own steps that lead further are tours of their own.
---@param batch thread.Batch
---@return thread.Comment[]
function M.tours(batch)
  local out = {}
  for _, c in ipairs(batch.data.threads) do
    if M.leads(batch, c) then
      local p = M.parent(batch, c.id)
      -- A stage leads somewhere, but belongs to its parent's tour.
      if not p or store.anchored(c) then
        out[#out + 1] = c
      end
    end
  end
  return out
end

--- The walk a thread's own messages start: the thread itself as the head.
---@param batch thread.Batch
---@param c thread.Comment
---@return thread.WalkItem[]
function M.led(batch, c)
  return M.walk(batch, c)
end

--- A thread's siblings: the threads the same message leads to. Threads with
--- no parent count as siblings of each other.
---@param batch thread.Batch
---@param id integer
---@return thread.Comment[]
function M.siblings(batch, id)
  local p, index = M.parent(batch, id)
  if not p then
    local out = {}
    for _, c in ipairs(batch.data.threads) do
      if not M.parent(batch, c.id) then
        out[#out + 1] = c
      end
    end
    return out
  end
  local out = {}
  for _, child in ipairs(p.messages[index].children or {}) do
    local c = find(batch, child)
    if c then
      out[#out + 1] = c
    end
  end
  return out
end

--- Whether a thread belongs to a tour: it has a parent.
function M.in_tour(batch, id)
  return M.parent(batch, id) ~= nil
end

return M
