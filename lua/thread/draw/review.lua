--- A review: as a line, in Home's list; or its overview, what it is about,
--- its introduction, and its threads, a line each, the closed ones apart.
--- One that cannot be read is a line saying why.

local chunk = require 'thread.model.chunk'
local diff = require 'thread.base.diff'
local draw = require 'thread.draw'
local files = require 'thread.draw.files'
local labels = require 'thread.draw.labels'
local prose = require 'thread.prose'
local review = require 'thread.model.review'
local text = require 'thread.base.text'
local thread = require 'thread.model.thread'
local thread_draw = require 'thread.draw.thread'

local M = {}

---@class thread.ReviewOpts
---@field width integer
---@field indent integer|nil  else the sheet's
---@field open table<string, true>|nil  an overview: what is opened, by draw.key
---@field files boolean|nil  an overview: its chunks by file, not its threads

--- What a review is about, said: its diff, or the code as it stands.
---@param r thread.Review
---@return string
local function about(r)
  local spec = chunk.spec(r.diff)
  return spec and spec.label or 'the code as it stands'
end

--- How many of its conversations want you, and how many wait on the
--- agent (thread.waiting); none in a closed review.
---@param r thread.Review
---@return integer you, integer agent
local function counts(r)
  local you = 0
  for _, t in ipairs(r.threads) do
    for _, c in ipairs(thread.conversations(t)) do
      you = you + (thread.for_you(r, c) and 1 or 0)
    end
  end
  return you, #thread.waiting(r)
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

-- Rows of a review's introduction, until it is opened.
M.INTRO = 6

--- A review's overview: its title; what it is about, and its diff's size;
--- its introduction, its first rows until opened; its open threads, two
--- rows each, then its closed ones; how many hunks of its diff no thread
--- is on. With `files`, its open threads' chunks by file instead.
---@param P thread.Sheet
---@param r thread.Review
---@param o thread.ReviewOpts
---@return thread.Part[]  the review, then what in it goes somewhere
function M.overview(P, r, o)
  local indent = o.indent or P.indent
  local spec = chunk.spec(r.diff)
  local first = P.chunks(text.fit_chunks({ { r.title, 'ThreadTitle' }, { r.status == 'closed' and '  closed' or '', 'ThreadMeta' } }, o.width), indent)
  local out = { { kind = 'review', first = first, last = first, review = r, item = true } } ---@type thread.Part[]
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
    local whole = (o.open or {})[draw.key(out[1])]
    draw.prose(prose.draw(P, r.introduction, math.min(o.width, 100), { indent = indent, spec = spec, most = not whole and M.INTRO or nil }), out)
  end
  if o.files then
    P.add ''
    P.chunks(labels.rule('files', o.width), indent)
    P.add ''
    vim.list_extend(out, files.draw(P, r, files.of_review(r), { width = o.width, indent = indent, open = o.open, threads = true }))
  else
    local open, closed = {}, {} ---@type thread.Thread[], thread.Thread[]
    local ids = 0
    for _, t in ipairs(r.threads) do
      table.insert(thread.closed(t) and closed or open, t)
      ids = math.max(ids, #tostring(t.id))
    end
    for _, list in ipairs { { 'threads', open }, { 'closed', closed } } do
      if #list[2] > 0 then
        P.add ''
        P.chunks(labels.rule(list[1] .. ' · ' .. #list[2], o.width), indent)
        for _, t in ipairs(list[2]) do
          P.add ''
          out[#out + 1] = thread_draw.row(P, r, t, { width = o.width, indent = indent, ids = ids })
        end
      end
    end
  end
  local left = spec and #review.left_out(r) or 0
  if left > 0 then
    P.add ''
    P.chunks({ { text.fit(text.plural(left, 'hunk') .. ' of the diff ' .. (left == 1 and 'is' or 'are') .. ' in no thread', o.width), 'ThreadMeta' } }, indent)
  end
  out[1].last = #P.lines - 1
  draw.within(out, 1, { review = r })
  return out
end

return M
