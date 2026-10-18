--- Chunks by file: the same chunks a review or a tour shows by what
--- they are for, laid out by where they are. Each file says how many of
--- its chunks there are, what the diff did to it and how many are done:
--- a step's walked, a note's accepted; under it each chunk's step or note and what it says, in the
--- order they come in the file; with `code`, or opened, its code.

local chunk = require 'thread.model.chunk'
local chunk_draw = require 'thread.draw.chunk'
local diff = require 'thread.base.diff'
local draw = require 'thread.draw'
local labels = require 'thread.draw.labels'
local prose = require 'thread.prose'
local review = require 'thread.model.review'
local step = require 'thread.model.step'
local text = require 'thread.base.text'

local M = {}

--- A chunk and what it is in: a step's, or a note's.
---@class thread.FileEntry
---@field tour thread.Tour|nil
---@field step thread.Step|nil
---@field note thread.Note|nil
---@field chunk thread.Chunk

---@class thread.FilesOpts
---@field width integer
---@field indent integer|nil  else the sheet's
---@field open table<string, true>|nil  the files opened, by draw.key
---@field tours boolean|nil  each chunk says the tour it is in
---@field code boolean|nil  each chunk's code, unless done; else only opened

-- Rows of a chunk's code, until it or its file is opened.
M.CODE = 12

--- The chunks of a tour's steps.
---@param r thread.Review
---@param x thread.Tour
---@return thread.FileEntry[]
function M.of_tour(r, x)
  local out = {} ---@type thread.FileEntry[]
  for _, s in ipairs(x.steps) do
    local c = review.chunk(r, s.chunk)
    if c then
      out[#out + 1] = { tour = x, step = s, chunk = c }
    end
  end
  return out
end

--- The chunks of a review's steps, then of its notes.
---@param r thread.Review
---@return thread.FileEntry[]
function M.of_review(r)
  local out = {} ---@type thread.FileEntry[]
  for _, x in ipairs(r.tours) do
    vim.list_extend(out, M.of_tour(r, x))
  end
  for _, n in ipairs(r.notes) do
    local c = review.chunk(r, n.chunk)
    if c then
      out[#out + 1] = { note = n, chunk = c }
    end
  end
  return out
end

--- Whether one is done: its step walked, or its note's chunk accepted.
---@param r thread.Review
---@param e thread.FileEntry
---@return boolean
local function done(r, e)
  if e.step then
    return step.walked(r, e.step)
  end
  return chunk.accepted(r, e.chunk)
end

--- Its line now, to order a file's chunks by; one gone goes last.
---@param e thread.FileEntry
---@param spec thread.DiffSpec|nil
---@return integer
local function line_of(e, spec)
  local at = chunk.now(e.chunk, spec)
  return at and at.line or math.huge
end

--- A file's row: its path; on the right its chunks, what the diff did to
--- it and how many are done.
---@param P thread.Sheet
---@param r thread.Review
---@param file string
---@param list thread.FileEntry[]
---@param o thread.FilesOpts
---@return thread.Part
local function head(P, r, file, list, o)
  local spec = chunk.spec(r.diff)
  local yes = 0
  for _, e in ipairs(list) do
    yes = yes + (done(r, e) and 1 or 0)
  end
  local right = { { text.plural(#list, 'chunk'), 'ThreadMeta' } } ---@type thread.Chunks
  local f = spec and diff.file(spec, file)
  if f then
    vim.list_extend(right, { { '  +' .. f.add, 'ThreadAdded' }, { ' −' .. f.del, 'ThreadRemoved' } })
  end
  right[#right + 1] = { string.format('  %d/%d done', yes, #list), yes == #list and 'ThreadAccepted' or 'ThreadMeta' }
  local row = draw.row(P, { { file, 'Directory' } }, right, o.width, o.indent)
  return {
    kind = 'file',
    first = row,
    last = row,
    file = file,
    review = r,
    item = true,
    chunks = vim.tbl_map(function(e)
      return e.chunk
    end, list),
  }
end

--- One chunk under its file: done or not, its line, its step's or its
--- note's title, the tour it is in; what the step says, or the note
--- first; its code, with `code` unless done, or opened.
---@param P thread.Sheet
---@param r thread.Review
---@param e thread.FileEntry
---@param open boolean  its file is opened
---@param o thread.FilesOpts
---@return thread.Part[]
local function entry(P, r, e, open, o)
  local spec = chunk.spec(r.diff)
  local indent = (o.indent or P.indent) + 2
  local width = o.width - 2
  local accepted = done(r, e)
  local at = chunk.now(e.chunk, spec)
  local where = at and (':' .. at.line .. (at.removed and ' removed' or '')) or 'gone'
  local s, n = e.step, e.note
  -- A step walked is a track's cell; a note accepted, a tick.
  local g, hl = labels.walked(accepted)
  if not s then
    g, hl = accepted and '✓' or '·', accepted and 'ThreadAccepted' or 'ThreadMeta'
  end
  local left = {
    { g .. ' ', hl },
    { text.pad(where, 6) .. ' ', at and 'LineNr' or 'ThreadBroken' },
  } ---@type thread.Chunks
  if n then
    vim.list_extend(left, labels.tag(n))
    left[#left + 1] = { '  ' }
  end
  left[#left + 1] = { s and s.title or n and n.title or '', accepted and 'ThreadMeta' or 'ThreadTitle' }
  local right = {} ---@type thread.Chunks
  if o.tours and e.tour then
    right[1] = { e.tour.title, (labels.colour(e.tour.colour)) }
  elseif n then
    right[1] = { 'note ' .. n.id, 'ThreadMeta' }
  end
  local first = draw.row(P, left, right, width, indent)
  ---@type thread.Part
  local part = {
    kind = s and 'step' or n and 'note' or 'chunk',
    first = first,
    last = first,
    tour = e.tour,
    step = s,
    note = n,
    chunk = e.chunk,
    file = e.chunk.file,
    item = true,
  }
  local out = { part } ---@type thread.Part[]
  open = open or (o.open or {})[draw.key(part)] == true
  local hang = indent + 2 + 7
  local said = s and s.text or n and n.messages[1] and n.messages[1].prose
  if said and said.text ~= '' then
    draw.prose(prose.draw(P, said, width - (hang - indent), { indent = hang, review = r, most = not open and 2 or nil }), out)
  end
  if open or (o.code and not accepted) then
    P.add ''
    local rows = not open and M.CODE or nil
    vim.list_extend(out, chunk_draw.draw(P, e.chunk, spec, { width = width - (hang - indent), indent = hang, rows = rows }))
  end
  part.last = #P.lines - 1
  if accepted then
    draw.bar(P, first, part.last, indent, 'ThreadAcceptedBar')
  end
  draw.within(out, 1, { tour = e.tour, step = s, note = n })
  return out
end

--- Chunks by file, the files in order of their paths, a blank row
--- between each chunk. Nothing when there are none.
---@param P thread.Sheet
---@param r thread.Review
---@param entries thread.FileEntry[]
---@param o thread.FilesOpts
---@return thread.Part[]
function M.draw(P, r, entries, o)
  local spec = chunk.spec(r.diff)
  local by, files = {}, {} ---@type table<string, thread.FileEntry[]>, string[]
  for _, e in ipairs(entries) do
    local f = e.chunk.file
    if not by[f] then
      by[f] = {}
      files[#files + 1] = f
    end
    table.insert(by[f], e)
  end
  table.sort(files)
  local out = {} ---@type thread.Part[]
  for i, f in ipairs(files) do
    if i > 1 then
      P.add ''
    end
    local list = by[f]
    local lines = {} ---@type table<thread.FileEntry, integer>
    for _, e in ipairs(list) do
      lines[e] = line_of(e, spec)
    end
    table.sort(list, function(a, b)
      return lines[a] < lines[b]
    end)
    local h = head(P, r, f, list, o)
    out[#out + 1] = h
    local open = (o.open or {})[draw.key(h)] == true
    for _, e in ipairs(list) do
      P.add ''
      vim.list_extend(out, entry(P, r, e, open, o))
    end
    h.last = #P.lines - 1
  end
  if #files == 0 then
    P.chunks({ { 'No chunks here.', 'ThreadMeta' } }, o.indent)
  end
  return out
end

return M
