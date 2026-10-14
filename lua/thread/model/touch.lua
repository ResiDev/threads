--- What touches what in a review, worked out once from its chunks as
--- written, not as found in the code, so it reads no file: each
--- thread, tour, step, contract and group, the chunks and files it has,
--- and between threads, tours and groups on one side and contracts on
--- the other, which touch which. Nothing here is written by the agent;
--- every screen that links one thing to another asks this.

local contract = require 'thread.model.contract'
local review = require 'thread.model.review'
local thread = require 'thread.model.thread'

local M = {}

--- What stands for the threads in no group, as a group's table does for
--- the threads in it.
M.NONE = {}

--- Something that has chunks: a thread, a tour, a step, a contract, or a
--- group (its thread.Group, or M.NONE).
---@alias thread.Owner table

---@class thread.Touches
---@field chunks table<thread.Owner, thread.Chunk[]>
---@field files table<thread.Owner, table<string, true>>
---@field contracts table<thread.Owner, thread.Contract[]>  a thread's, a tour's or a group's, in the review's order
---@field touched table<thread.Contract, table<thread.Owner, true>>  the threads, tours and groups that touch each contract

--- A review's index.
---@param r thread.Review
---@return thread.Touches
function M.index(r)
  local T = { chunks = {}, files = {}, contracts = {}, touched = {} } ---@type thread.Touches
  ---@param owner thread.Owner
  ---@param list thread.Chunk[]
  local function add(owner, list)
    T.chunks[owner] = list
    local files = {} ---@type table<string, true>
    for _, c in ipairs(list) do
      files[c.file] = true
    end
    T.files[owner] = files
  end
  for _, c in ipairs(r.contracts or {}) do
    add(c, contract.chunks(c))
    T.touched[c] = {}
  end
  ---@param owner thread.Owner
  local function link(owner)
    local list = contract.touched(r, T.chunks[owner])
    T.contracts[owner] = list
    for _, c in ipairs(list) do
      T.touched[c][owner] = true
    end
  end
  -- Every thread, the tours' carrier in format 3 too, which no group
  -- lists.
  for _, t in ipairs(r.threads) do
    local own = { t.chunk } ---@type thread.Chunk[]
    for _, x in ipairs(thread.tours(t)) do
      local steps = {} ---@type thread.Chunk[]
      for _, s in ipairs(x.steps) do
        add(s, { s.chunk })
        steps[#steps + 1] = s.chunk
      end
      add(x, steps)
      link(x)
      vim.list_extend(own, steps)
    end
    add(t, own)
    link(t)
  end
  for _, g in ipairs(review.grouped(r)) do
    local mine = {} ---@type thread.Chunk[]
    for _, t in ipairs(g.threads) do
      vim.list_extend(mine, T.chunks[t])
    end
    local owner = g.group or M.NONE
    add(owner, mine)
    link(owner)
  end
  return T
end

--- Whatever is on the other side of `owner`: a contract's threads, tours
--- and groups; a thread's, a tour's or a group's contracts. Nil when it is
--- on neither side.
---@param T thread.Touches
---@param owner thread.Owner
---@return table<thread.Owner, true>|nil
function M.related(T, owner)
  if T.touched[owner] then
    return T.touched[owner]
  end
  local list = T.contracts[owner]
  if not list then
    return nil
  end
  local out = {} ---@type table<thread.Owner, true>
  for _, c in ipairs(list) do
    out[c] = true
  end
  return out
end

return M
