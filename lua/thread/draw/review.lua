--- A review: as a line, in Home's list; its head, what it is about and
--- its introduction; its notes as an index grouped by kind; its files
--- beside. One that cannot be read is a line saying why.

local chunk = require 'thread.model.chunk'
local conversation = require 'thread.model.conversation'
local diff = require 'thread.base.diff'
local draw = require 'thread.draw'
local labels = require 'thread.draw.labels'
local note = require 'thread.model.note'
local note_draw = require 'thread.draw.note'
local prose = require 'thread.prose'
local review = require 'thread.model.review'
local side = require 'thread.draw.side'
local text = require 'thread.base.text'
local tour = require 'thread.model.tour'

local M = {}

---@class thread.ReviewOpts
---@field width integer
---@field indent integer|nil  else the sheet's
---@field open table<string, true>|nil  its notes: the kinds opened to their settled notes, by M.kind_key

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

--- The notes heading: how many, and how many of each kind are open,
--- `notes · 9 · open: 3 issues · 1 question`.
---@param r thread.Review
---@param groups { kind: thread.NoteKind, notes: thread.Note[], open: integer }[]
---@return string
local function notes_heading(r, groups)
  local open = {} ---@type string[]
  for _, g in ipairs(groups) do
    if g.open > 0 then
      open[#open + 1] = note.noun(g.kind, g.open)
    end
  end
  return 'notes · ' .. #r.notes .. (#open > 0 and (' · open: ' .. table.concat(open, ' · ')) or '')
end

--- What a kind of note's heading is known by, for the screen to open it.
---@param kind thread.NoteKind
---@return string
function M.kind_key(kind)
  return draw.key { kind = 'kind', first = 0, last = 0, name = kind }
end

--- A review's notes as an index: a rule counting what is open, then
--- each kind, the open first, its heading an item saying how many and
--- how many are open, a row a note. Settled notes are a row saying how
--- many until their kind is opened.
---@param P thread.Sheet
---@param r thread.Review
---@param o thread.ReviewOpts
---@return thread.Part[]
function M.notes(P, r, o)
  local indent = o.indent or P.indent
  local out = {} ---@type thread.Part[]
  local groups = review.notes(r)
  if #groups == 0 then
    return out
  end
  -- The kinds with something open first, in their order.
  table.sort(groups, function(a, b)
    if (a.open > 0) ~= (b.open > 0) then
      return a.open > 0
    end
    return vim.fn.index(note.KINDS, a.kind) < vim.fn.index(note.KINDS, b.kind)
  end)
  P.add ''
  local rule = P.chunks(labels.rule(notes_heading(r, groups), o.width), indent)
  out[#out + 1] = { kind = 'heading', first = rule, last = rule, name = 'notes' }
  local ids = 0
  for _, n in ipairs(r.notes) do
    ids = math.max(ids, #tostring(n.id))
  end
  for _, g in ipairs(groups) do
    P.add ''
    local said = note.noun(g.kind, #g.notes)
    local sample = labels.tag(g.notes[1])
    local hl = g.kind == 'issue' and 'ThreadTagBad' or sample[#sample][2]
    local right = g.open > 0 and { { g.open .. ' open', 'ThreadMeta' } } or {}
    local head = draw.row(P, { { said, hl } }, right, o.width, indent)
    local part = { kind = 'kind', first = head, last = head, name = g.kind, item = true } ---@type thread.Part
    out[#out + 1] = part
    local whole = (o.open or {})[M.kind_key(g.kind)] == true
    local settled = 0
    for _, n in ipairs(g.notes) do
      if note.closed(n) and not whole then
        settled = settled + 1
      else
        out[#out + 1] = note_draw.row(P, r, n, { width = o.width - 2, indent = indent + 2, ids = ids })
      end
    end
    if settled > 0 then
      -- An item of its kind's, so the cursor lands on it and Tab on it
      -- does what it says.
      local row = P.chunks({ { text.fit('… ' .. settled .. ' settled   ⇥ shows them', o.width - 4), 'ThreadMeta' } }, indent + 4)
      out[#out + 1] = { kind = 'kind', first = row, last = row, name = g.kind, item = true }
    end
    part.last = #P.lines - 1
  end
  return out
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
function M.side(P, r, top, col, T, width)
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
    side.beside(P, top, col, side.paths(all), parts, width)
  end
end

return M
