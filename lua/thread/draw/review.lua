--- A review: as a line, in Home's list; its head, what it is about and
--- its introduction; its files beside. One that cannot be read is a line
--- saying why.

local chunk = require 'thread.model.chunk'
local conversation = require 'thread.model.conversation'
local diff = require 'thread.base.diff'
local draw = require 'thread.draw'
local labels = require 'thread.draw.labels'
local prose = require 'thread.prose'
local review = require 'thread.model.review'
local side = require 'thread.draw.side'
local text = require 'thread.base.text'
local tour = require 'thread.model.tour'

local M = {}

---@class thread.ReviewOpts
---@field width integer
---@field indent integer|nil  else the sheet's

-- The prose reads well this wide at most.
local PROSE = 100

--- What a review is about, said: its diff, or the code as it stands.
---@param r thread.Review
---@return string
local function about(r)
  local spec = chunk.spec(r.diff)
  return spec and spec.label or 'the code as it stands'
end

--- How many of its conversations want you, and how many wait on the
--- agent; none in a closed review.
---@param r thread.Review
---@return integer you, integer agent
local function counts(r)
  local you = 0
  for _, c in ipairs(conversation.all(r)) do
    you = you + (conversation.for_you(r, c) and 1 or 0)
  end
  return you, #conversation.waiting(r)
end

--- A review in one row: its state, its title, what it is about; on the
--- right, what wants you, what waits on the agent, and when it last
--- changed.
---@param P thread.Sheet
---@param r thread.Review
---@param o thread.ReviewOpts
---@return thread.Part
function M.line(P, r, o)
  local you, agent = counts(r)
  local g, hl = labels.state(r.status == 'closed', you > 0 and 'you' or agent > 0 and 'agent' or nil, you > 0)
  local right = {} ---@type thread.Chunks
  if you > 0 then
    right[#right + 1] = { you .. ' for you', 'ThreadSignAnswered' }
  end
  if agent > 0 then
    right[#right + 1] = { (#right > 0 and ' · ' or '') .. agent .. ' with the agent', 'ThreadSignWaiting' }
  end
  local when = text.ago(review.latest(r))
  if when then
    right[#right + 1] = { (#right > 0 and '  ' or '') .. when, 'ThreadMeta' }
  end
  local left = { { g .. ' ', hl }, { r.title, r.status == 'closed' and 'ThreadMeta' or 'ThreadTitle' }, { '  ' .. about(r), 'ThreadMeta' } }
  local row = draw.row(P, left, right, o.width, o.indent)
  return { kind = 'review', first = row, last = row, review = r, item = true }
end

--- A review that cannot be read, in one row: its name, and why.
---@param P thread.Sheet
---@param id string
---@param why string
---@param o thread.ReviewOpts
---@return integer row
function M.broken(P, id, why, o)
  return P.chunks(text.fit_chunks({ { '! ', 'ThreadBroken' }, { id, 'ThreadTitle' }, { '  cannot be read: ' .. why, 'ThreadBroken' } }, o.width), o.indent)
end

--- A review's head, what its Overview shows: its title; what it is
--- about, and its diff's size; its introduction; how many hunks of its
--- diff no step, note or contract is on.
---@param P thread.Sheet
---@param r thread.Review
---@param o thread.ReviewOpts
---@return thread.Part[]  the review, then what in it goes somewhere
function M.head(P, r, o)
  local indent = o.indent or P.indent
  local spec = chunk.spec(r.diff)
  local first = P.chunks(text.fit_chunks({ { r.title, 'ThreadTitle' }, { r.status == 'closed' and '  closed' or '', 'ThreadMeta' } }, o.width), indent)
  local out = { { kind = 'review', first = first, last = first, review = r } } ---@type thread.Part[]
  local said = { { about(r), 'ThreadCrumbHere' } } ---@type thread.Chunks
  if spec then
    local list, err = diff.files(spec)
    if err then
      said[#said + 1] = { ' · git cannot read it: ' .. err, 'ThreadBroken' }
    else
      local add, del = 0, 0
      for _, f in ipairs(list) do
        add, del = add + f.add, del + f.del
      end
      vim.list_extend(
        said,
        { { ' · ' .. text.plural(#list, 'file') .. ' ', 'ThreadMeta' }, { '+' .. add, 'ThreadAdded' }, { ' −' .. del, 'ThreadRemoved' } }
      )
    end
  end
  P.chunks(text.fit_chunks(said, o.width), indent)
  if r.introduction then
    P.add ''
    draw.prose(prose.draw(P, r.introduction, math.min(o.width, PROSE), { indent = indent, review = r }), out)
  end
  local left = spec and #review.left_out(r) or 0
  if left > 0 then
    P.add ''
    P.chunks(
      { { text.fit(text.plural(left, 'hunk') .. ' of the diff ' .. (left == 1 and 'is' or 'are') .. ' in no step, note or contract', o.width), 'ThreadMeta' } },
      indent
    )
  end
  out[1].last = #P.lines - 1
  draw.within(out, 1, { review = r })
  return out
end

--- A review's files down the right of a tab, from row `top`, `width`
--- wide: every chunk's its steps, notes and contracts point at, each
--- marked with the tours whose steps have a chunk in it, and then the
--- notes.
---@param P thread.Sheet
---@param r thread.Review
---@param top integer
---@param col integer
---@param T thread.Touches
---@param width integer
---@param pane thread.SidePane|nil  how the tab draws them, else as the review's
function M.side(P, r, top, col, T, width, pane)
  local all = {} ---@type thread.Chunk[]
  local parts = {} ---@type thread.SidePart[]
  for place, x in ipairs(tour.list(r)) do
    vim.list_extend(all, T.chunks[x])
    parts[#parts + 1] = { hl = (labels.colour(x.colour, place)), files = T.files[x] }
  end
  local noted = {} ---@type table<string, true>
  for _, n in ipairs(r.notes) do
    vim.list_extend(all, T.chunks[n])
    noted = vim.tbl_extend('force', noted, T.files[n])
  end
  if next(noted) then
    parts[#parts + 1] = { hl = 'ThreadSideNote', files = noted }
  end
  for _, c in ipairs(r.contracts) do
    vim.list_extend(all, T.chunks[c])
  end
  if #all > 0 then
    side.beside(P, top, col, side.paths(all), parts, width, pane)
  end
end

return M
