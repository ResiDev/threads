--- What touches what in a review, worked out once a draw from its chunks:
--- each tour, step, note and contract, the chunks and files it has; and
--- between tours, steps and notes on one side and contracts on the other,
--- which touch which. Two things touch when they point at the same chunk,
--- or failing that at chunks whose lines overlap. Nothing here is written
--- by the agent; every screen that links one thing to another asks this.

local chunk = require 'thread.model.chunk'
local contract = require 'thread.model.contract'
local review = require 'thread.model.review'

local M = {}

--- Something that has chunks: a tour, a step, a note or a contract.
---@alias thread.Owner thread.Tour|thread.Step|thread.Note|thread.Contract

---@class thread.Touches
---@field chunks table<thread.Owner, thread.Chunk[]>
---@field files table<thread.Owner, table<string, true>>
---@field contracts table<thread.Owner, thread.Contract[]>  a tour's, a step's or a note's, in the review's order
---@field touched table<thread.Contract, table<thread.Owner, true>>  the tours, steps and notes that touch each contract

--- A review's index.
---@param r thread.Review
---@return thread.Touches
function M.index(r)
  local T = { chunks = {}, files = {}, contracts = {}, touched = {} } ---@type thread.Touches
  local spec = chunk.spec(r.diff)
  ---@param owner thread.Owner
  ---@param ids (string|nil)[]
  local function add(owner, ids)
    local list, files, seen = {}, {}, {} ---@type thread.Chunk[], table<string, true>, table<string, true>
    for _, id in ipairs(ids) do
      local c = review.chunk(r, id)
      if c and not seen[c.id] then
        seen[c.id] = true
        list[#list + 1] = c
        files[c.file] = true
      end
    end
    T.chunks[owner], T.files[owner] = list, files
  end
  for _, c in ipairs(r.contracts) do
    add(c, contract.chunks(c))
    T.touched[c] = {}
  end
  ---@param mine thread.Chunk[]
  ---@param theirs thread.Chunk[]
  ---@return boolean
  local function meet(mine, theirs)
    for _, a in ipairs(mine) do
      for _, b in ipairs(theirs) do
        if a.id == b.id then
          return true
        end
      end
    end
    for _, a in ipairs(mine) do
      for _, b in ipairs(theirs) do
        if chunk.overlap(a, b, spec) then
          return true
        end
      end
    end
    return false
  end
  ---@param owner thread.Owner
  local function link(owner)
    local list = {} ---@type thread.Contract[]
    for _, c in ipairs(r.contracts) do
      if meet(T.chunks[owner], T.chunks[c]) then
        list[#list + 1] = c
        T.touched[c][owner] = true
      end
    end
    T.contracts[owner] = list
  end
  for _, x in ipairs(r.tours) do
    local ids = {} ---@type string[]
    for _, s in ipairs(x.steps) do
      add(s, { s.chunk })
      link(s)
      ids[#ids + 1] = s.chunk
    end
    add(x, ids)
    link(x)
  end
  for _, n in ipairs(r.notes) do
    add(n, { n.chunk })
    link(n)
  end
  return T
end

--- Whatever is on the other side of `owner`: a contract's tours, steps
--- and notes; a tour's, a step's or a note's contracts. Nil when it is on
--- neither side.
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

--- The notes on a chunk a step is on: what the step shows as you walk it.
---@param r thread.Review
---@param s thread.Step
---@return thread.Note[]
function M.notes_on(r, s)
  local c = review.chunk(r, s.chunk)
  if not c then
    return {}
  end
  local spec = chunk.spec(r.diff)
  return vim.tbl_filter(function(n)
    local other = review.chunk(r, n.chunk)
    return other ~= nil and (other.id == c.id or chunk.overlap(c, other, spec))
  end, r.notes)
end

return M
