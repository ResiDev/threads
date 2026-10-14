--- Chunks by file: the same chunks a review, a thread or a tour shows by
--- what they are for, laid out by where they are. Each file says how many
--- of its chunks there are, what the diff did to it and how many you have
--- accepted; under it each chunk's title and what the agent says of it,
--- in the order they come in the file; with `code`, or opened, its
--- code.

local chunk = require 'thread.model.chunk'
local chunk_draw = require 'thread.draw.chunk'
local diff = require 'thread.base.diff'
local draw = require 'thread.draw'
local labels = require 'thread.draw.labels'
local prose = require 'thread.prose'
local text = require 'thread.base.text'
local thread = require 'thread.model.thread'

local M = {}

--- A chunk and what it is in: a step's, or a thread's own.
---@class thread.FileEntry
---@field thread thread.Thread
---@field tour thread.Tour|nil
---@field step thread.Step|nil
---@field chunk thread.Chunk

---@class thread.FilesOpts
---@field width integer
---@field indent integer|nil  else the sheet's
---@field open table<string, true>|nil  the files opened, by draw.key
---@field threads boolean|nil  each chunk says the thread it is in
---@field code boolean|nil  each chunk's code, unless accepted; else only opened

-- Rows of a chunk's code, until it or its file is opened.
M.CODE = 12

--- The chunks of a thread's steps, a tour's when given, else every
--- tour's, after the thread's own.
---@param t thread.Thread
---@param x thread.Tour|nil
---@return thread.FileEntry[]
function M.of_thread(t, x)
  local out = {} ---@type thread.FileEntry[]
  if t.chunk and not x then
    out[1] = { thread = t, chunk = t.chunk }
  end
  for _, tour in ipairs(x and { x } or thread.tours(t)) do
    for _, s in ipairs(tour.steps) do
      if s.chunk then
        out[#out + 1] = { thread = t, tour = tour, step = s, chunk = s.chunk }
      end
    end
  end
  return out
end

--- The chunks of a review's open threads.
---@param r thread.Review
---@return thread.FileEntry[]
function M.of_review(r)
  local out = {} ---@type thread.FileEntry[]
  for _, t in ipairs(r.threads) do
    if not thread.closed(t) then
      vim.list_extend(out, M.of_thread(t))
    end
  end
  return out
end

--- Its line now, to order a file's chunks by; one gone goes last.
---@param e thread.FileEntry
---@param spec thread.DiffSpec|nil
---@return integer
local function line_of(e, spec)
  local at = chunk.locate(e.chunk, spec)
  return at and (at.old or at.line) or math.huge
end

--- A file's row: its path; on the right its chunks, what the diff did to
--- it and how many you have accepted.
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
    yes = yes + (chunk.accepted(r, e.thread, e.chunk) and 1 or 0)
  end
  local right = { { text.plural(#list, 'chunk'), 'ThreadMeta' } } ---@type thread.Chunks
  local f = spec and diff.file(spec, file)
  if f then
    vim.list_extend(right, { { '  +' .. f.add, 'ThreadAdded' }, { ' −' .. f.del, 'ThreadRemoved' } })
  end
  right[#right + 1] = { string.format('  ✓ %d/%d', yes, #list), yes == #list and 'ThreadAccepted' or 'ThreadMeta' }
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

--- One chunk under its file: accepted or not, its line, its title, the
--- thread it is in; what the agent says of it; its code, with `code`
--- unless accepted, or opened.
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
  local accepted = chunk.accepted(r, e.thread, e.chunk)
  local at = chunk.locate(e.chunk, spec)
  local where = at and (':' .. (at.old or at.line) .. (at.old and ' removed' or '')) or ':gone'
  local s = e.step
  local title = s and s.title or e.thread.title or ('#' .. e.thread.id)
  local left = {
    { accepted and '✓ ' or '· ', accepted and 'ThreadAccepted' or 'ThreadMeta' },
    { text.pad(where, 6) .. ' ', at and 'LineNr' or 'ThreadBroken' },
    { title, accepted and 'ThreadMeta' or 'ThreadTitle' },
  }
  local tags = labels.tags(s or e.thread)
  if #tags > 0 then
    table.insert(tags, 1, { '  ' })
    vim.list_extend(left, tags)
  end
  local right = {} ---@type thread.Chunks
  if o.threads then
    right[1] = { '#' .. e.thread.id .. (e.tour and (' · ' .. e.tour.title) or ''), 'ThreadCrumb' }
  end
  local first = draw.row(P, left, right, width, indent)
  ---@type thread.Part
  local part = {
    kind = s and 'step' or 'chunk',
    first = first,
    last = first,
    thread = e.thread,
    tour = e.tour,
    step = s,
    chunk = e.chunk,
    file = e.chunk.file,
    item = true,
  }
  local out = { part } ---@type thread.Part[]
  open = open or (o.open or {})[draw.key(part)] == true
  local hang = indent + 2 + 7
  local said = s and s.text or prose.gist(e.thread.messages[1] and e.thread.messages[1].text)
  if said and said ~= '' then
    draw.prose(prose.draw(P, said, width - (hang - indent), { indent = hang, spec = spec }), out)
  end
  if open or (o.code and not accepted) then
    P.add ''
    local rows = not open and M.CODE or nil
    vim.list_extend(out, chunk_draw.draw(P, e.chunk, spec, { width = width - (hang - indent), indent = hang, notes = s and s.notes, rows = rows }))
  end
  part.last = #P.lines - 1
  if accepted then
    draw.bar(P, first, part.last, indent, 'ThreadAcceptedBar')
  end
  draw.within(out, 1, { thread = e.thread, tour = e.tour, step = s })
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
