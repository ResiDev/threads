--- A tour: a line, its title and how far you have walked it; its
--- outline, that line and a line for each step; its briefing, what the
--- walk opens on; or a row of a review's Tours tab, two lines, its chain
--- of steps walked and its route, that opens under the cursor to the
--- start of its briefing and its steps, with its files beside. Its
--- track, for a card's or a winbar's head, is thread.draw.labels.track.

local chunk = require 'thread.model.chunk'
local chunk_draw = require 'thread.draw.chunk'
local contracts = require 'thread.draw.contracts'
local conversation = require 'thread.model.conversation'
local draw = require 'thread.draw'
local labels = require 'thread.draw.labels'
local model_prose = require 'thread.model.prose'
local note = require 'thread.model.note'
local prose = require 'thread.prose'
local review = require 'thread.model.review'
local step = require 'thread.draw.step'
local step_model = require 'thread.model.step'
local text = require 'thread.base.text'
local touch = require 'thread.model.touch'
local tour = require 'thread.model.tour'

local M = {}

---@class thread.TourOpts
---@field width integer
---@field indent integer|nil  else the sheet's
---@field here thread.Step|nil  the step you are on
---@field place integer|nil  its place among the review's tours, for its colour when it has none

-- The prose reads well this wide at most.
local PROSE = 100

--- A tour in one row: `▶ ` its title, how far you have walked it on the
--- right.
---@param P thread.Sheet
---@param r thread.Review
---@param x thread.Tour
---@param o thread.TourOpts
---@return thread.Part
function M.line(P, r, x, o)
  local right = {} ---@type thread.Chunks
  if #x.steps <= labels.TRACK then
    right = labels.track(r, x, o.here)
    right[#right + 1] = { '  ' }
  end
  right[#right + 1] = { tour.walked(r, x) .. '/' .. #x.steps .. ' walked', 'ThreadMeta' }
  local name = labels.colour(x.colour, o.place)
  local row = draw.row(P, { { '▶ ', 'ThreadLeads' }, { x.title, name } }, right, o.width, o.indent)
  return { kind = 'tour', first = row, last = row, tour = x }
end

--- Its steps a line each, set in by two, the one you are on marked.
---@param P thread.Sheet
---@param r thread.Review
---@param x thread.Tour
---@param o thread.TourOpts
---@param out thread.Part[]
local function step_lines(P, r, x, o, out)
  local indent = o.indent or P.indent
  local ids = 0
  for _, s in ipairs(x.steps) do
    ids = math.max(ids, #tostring(s.id))
  end
  for _, s in ipairs(x.steps) do
    out[#out + 1] = step.line(P, r, x, s, { width = o.width - 2, indent = indent + 2, here = s == o.here, ids = ids })
  end
end

--- A tour's outline: its line, then each step's line, set in under it.
---@param P thread.Sheet
---@param r thread.Review
---@param x thread.Tour
---@param o thread.TourOpts
---@return thread.Part[]  the tour, then its steps
function M.outline(P, r, x, o)
  local out = { M.line(P, r, x, o) }
  step_lines(P, r, x, o, out)
  out[1].last = #P.lines - 1
  draw.within(out, 1, { tour = x })
  return out
end

-- The tab

-- A tour's chain is a dot a step and a line between; past this many
-- columns, dots alone; past that, how many walked in words.
local CHAIN = 25

-- Steps a tour opened under its row lists, until it is read whole.
M.MOST = 6

-- Where a tour's row puts its title, and its chain's right edge from the
-- row's: room for ` walked ` after it.
local TITLE, WALKED = 3, 10

--- A tour's place among its review's listed tours, from 1.
---@param r thread.Review
---@param x thread.Tour
---@return integer
local function place_of(r, x)
  for i, t in ipairs(tour.list(r)) do
    if t == x then
      return i
    end
  end
  return 1
end

--- How far you have walked a tour, a dot a step: ● walked, ◉ the next
--- once some is, ○ to walk; ━ between two walked, ─ else. In its
--- colour, what is still to walk in its quieter one.
---@param r thread.Review
---@param x thread.Tour
---@param place integer
---@return thread.Chunks
function M.chain(r, x, place)
  local name, line = labels.colour(x.colour, place)
  local n = #x.steps
  local walked = tour.walked(r, x)
  if n > CHAIN then
    return { { walked .. '/' .. n .. ' walked', walked > 0 and name or line } }
  end
  local next_one = walked > 0 and tour.next(r, x)
  local out, before = {}, false ---@type thread.Chunks, boolean
  for i, s in ipairs(x.steps) do
    local yes = step_model.walked(r, s)
    if i > 1 and 2 * n - 1 <= CHAIN then
      out[#out + 1] = (before and yes) and { '━', name } or { '─', line }
    end
    out[#out + 1] = yes and { '●', name } or i == next_one and { '◉', name } or { '○', line }
    before = yes
  end
  return out
end

--- The files a tour's steps are in, in the order it walks them, each
--- once: its route.
---@param r thread.Review
---@param x thread.Tour
---@return thread.Chunks
function M.route(r, x)
  local out, seen = {}, {} ---@type thread.Chunks, table<string, true>
  for _, s in ipairs(x.steps) do
    local c = review.chunk(r, s.chunk)
    if c and not seen[c.file] then
      seen[c.file] = true
      if #out > 0 then
        out[#out + 1] = { ' › ', 'ThreadMeta' }
      end
      out[#out + 1] = { vim.fs.basename(c.file), 'ThreadFile' }
    end
  end
  return out
end

--- What waits on a tour, said: the agent's reply to you on a step, and
--- a note on its way, its icon and colour; nothing else.
---@param r thread.Review
---@param x thread.Tour
---@return thread.Chunks[]
function M.waits(r, x)
  local replies, first = 0, nil ---@type integer, thread.Step|nil
  local noted ---@type { [1]: thread.Note, [2]: thread.Step }|nil
  for _, s in ipairs(x.steps) do
    if conversation.move(conversation.of_step(s, x)) == 'you' then
      replies, first = replies + 1, first or s
    end
    for _, n in ipairs(noted and {} or touch.notes_on(r, s)) do
      if not noted and n.kind ~= 'comment' and note.open(n) then
        noted = { n, s }
      end
    end
  end
  local out = {} ---@type thread.Chunks[]
  if first then
    local said = replies == 1 and 'a reply for you on step ' or (replies .. ' replies for you, the first on step ')
    out[#out + 1] = { { labels.glyph 'yours' .. ' ' .. said .. first.id, 'ThreadYourMove' } }
  end
  if noted then
    local n, s = noted[1], noted[2]
    local g, hl = labels.icon(n)
    out[#out + 1] = { { g .. ' ' .. (n.kind == 'issue' and (n.issue or 'issue') or n.kind) .. ' #' .. n.id .. ' on step ' .. s.id, hl } }
  end
  return out
end

--- A title, what is in backticks in the code's colour.
---@param title string
---@param width integer
---@return thread.Chunks
local function titled(title, width)
  local row = prose.rows(model_prose.of(title), 10000)[1]
  local out = {} ---@type thread.Chunks
  for _, c in ipairs(row and row.chunks or {}) do
    out[#out + 1] = { c[1], c[2] == 'ThreadCode' and 'ThreadCode' or 'ThreadTitle' }
  end
  return text.fit_chunks(out, width)
end

--- `chunks` from column `col` of `row`, the row padded to it.
---@param row thread.Chunks
---@param col integer
---@param chunks thread.Chunks
local function at(row, col, chunks)
  local w = text.width(row)
  if w < col then
    row[#row + 1] = { string.rep(' ', col - w) }
  end
  vim.list_extend(row, chunks)
end

---@class thread.TourHeadOpts
---@field width integer
---@field indent integer
---@field place integer  among the listed, from 1

--- A tour's row, two lines: its place in its colour, its title, the chain
--- of its steps and ` walked ` once all are; under them its route and
--- what waits on it.
---@param P thread.Sheet
---@param r thread.Review
---@param x thread.Tour
---@param o thread.TourHeadOpts
---@return thread.Part  lit over its two rows alone
function M.head(P, r, x, o)
  local name = labels.colour(x.colour, o.place)
  local chain = M.chain(r, x, o.place)
  local cw = text.width(chain)
  local stop = o.width - WALKED - cw
  local row = { { tostring(o.place), name } } ---@type thread.Chunks
  at(row, TITLE, titled(x.title, stop - TITLE - 2))
  at(row, stop, chain)
  if #x.steps > 0 and tour.walked(r, x) == #x.steps then
    at(row, o.width - 8, { { ' walked ', 'ThreadBadgeWalked' } })
  end
  local first = P.chunks(row, o.indent)
  local parts = { M.route(r, x) }
  vim.list_extend(parts, M.waits(r, x))
  ---@return thread.Chunks
  local function joined()
    local out = {} ---@type thread.Chunks
    for i, part in ipairs(parts) do
      if i > 1 then
        out[#out + 1] = { '  ·  ', 'ThreadMeta' }
      end
      vim.list_extend(out, part)
    end
    return out
  end
  while #parts > 1 and text.width(joined()) > o.width - TITLE do
    parts[#parts] = nil
  end
  P.chunks(text.fit_chunks(joined(), o.width - TITLE), o.indent + TITLE)
  return { kind = 'tour', first = first, last = first + 1, tour = x, item = true, alone = true }
end

--- A tour's introduction in its first two rows, the second cut with `…`
--- when it goes on; whole with `whole`.
---@param P thread.Sheet
---@param r thread.Review
---@param x thread.Tour
---@param width integer
---@param indent integer
---@param whole boolean
---@param out thread.Part[]
local function briefed(P, r, x, width, indent, whole, out)
  if whole then
    draw.prose(prose.draw(P, x.introduction, width, { indent = indent, review = r }), out)
    return
  end
  local rows = vim.tbl_filter(function(row)
    return #row.chunks > 0
  end, prose.rows(x.introduction, width, r))
  for i = 1, math.min(2, #rows) do
    local chunks = rows[i].chunks
    if i == 2 and #rows > 2 then
      chunks = vim.list_extend(text.fit_chunks(chunks, width - 1), { { '…', 'ThreadMeta' } })
    end
    P.chunks(chunks, indent)
  end
end

---@class thread.TourStepsOpts
---@field width integer
---@field indent integer
---@field place integer
---@field most integer|nil  steps at most, then how many more

--- A tour's steps a line each: its dot, its id, what it claims, a reply
--- waiting on it, where it is.
---@param P thread.Sheet
---@param r thread.Review
---@param x thread.Tour
---@param o thread.TourStepsOpts
---@return thread.Part[]
function M.steps(P, r, x, o)
  local name, line = labels.colour(x.colour, o.place)
  local next_one = tour.walked(r, x) > 0 and tour.next(r, x)
  local ids = 0
  for _, s in ipairs(x.steps) do
    ids = math.max(ids, #tostring(s.id))
  end
  local spec = chunk.spec(r.diff)
  local out = {} ---@type thread.Part[]
  local shown = math.min(#x.steps, o.most or #x.steps)
  for i = 1, shown do
    local s = x.steps[i]
    local yes = step_model.walked(r, s)
    local dot = yes and { '●', name } or i == next_one and { '◉', name } or { '○', line }
    local claim = yes and 'ThreadDone' or i == next_one and 'ThreadTitle' or 'ThreadStepTodo'
    local right = {} ---@type thread.Chunks
    local c = conversation.of_step(s, x)
    if conversation.move(c) == 'you' then
      -- Your move; how many of the agent's you have not read, when some.
      local n = conversation.unread(r, c)
      vim.list_extend(right, { { labels.glyph 'yours' .. (n > 0 and (' ' .. n) or ''), 'ThreadYourMove' }, { '   ' } })
    end
    local ch = review.chunk(r, s.chunk)
    vim.list_extend(right, ch and chunk_draw.place(ch, spec) or { { 'on no line', 'ThreadMeta' } })
    local left = { dot, { ' ' .. text.pad(tostring(s.id), ids), 'ThreadMeta' } } ---@type thread.Chunks
    at(left, ids + 4, { { s.title, claim } })
    local row = vim.list_extend(text.fit_chunks(left, o.width - text.width(right) - 2), {})
    at(row, o.width - text.width(right), right)
    local at_row = P.chunks(row, o.indent)
    out[#out + 1] = { kind = 'step', first = at_row, last = at_row, tour = x, step = s }
  end
  if shown < #x.steps then
    P.chunks({ { '… ' .. (#x.steps - shown) .. ' more', 'ThreadMeta' } }, o.indent + ids + 4)
  end
  return out
end

---@class thread.ToursTabOpts
---@field width integer
---@field indent integer
---@field here string|nil  the tour opened under the cursor, by draw.key
---@field open table<string, true>|nil  read whole: its introduction and every step

--- A review's Tours tab: a tour's row each, a blank row apart. The one
--- `o.here` names opens under its row: two rows of its briefing, then its
--- first few steps; read whole, all of both. Two blank rows after it.
---@param P thread.Sheet
---@param r thread.Review
---@param o thread.ToursTabOpts
---@return thread.Part[]
function M.tab(P, r, o)
  local out = {} ---@type thread.Part[]
  for place, x in ipairs(tour.list(r)) do
    local head = M.head(P, r, x, { width = o.width, indent = o.indent, place = place })
    out[#out + 1] = head
    local key = draw.key(head)
    if o.here == key then
      local whole = (o.open or {})[key] == true
      local inner, width = o.indent + TITLE, o.width - TITLE
      P.add ''
      briefed(P, r, x, width, inner, whole, out)
      P.add ''
      vim.list_extend(out, M.steps(P, r, x, { width = width, indent = inner, place = place, most = not whole and M.MOST or nil }))
      P.add ''
    end
    P.add ''
  end
  return out
end

--- The files beside Tours: those of the tour under the cursor lit, the
--- numbers of its steps in each in a column, and a tick column a tour,
--- that one's bright; how many it walks under them.
---@param r thread.Review
---@return thread.SidePane
function M.pane(r)
  local list = tour.list(r)
  local files, ids = {}, {} ---@type table<string, true>[], table<string, integer[]>[]
  local most = 4
  for place, x in ipairs(list) do
    files[place], ids[place] = {}, {}
    for _, s in ipairs(x.steps) do
      local c = review.chunk(r, s.chunk)
      if c then
        files[place][c.file] = true
        ids[place][c.file] = ids[place][c.file] or {}
        table.insert(ids[place][c.file], s.id)
      end
    end
    for _, list_ in pairs(ids[place]) do
      most = math.max(most, #table.concat(list_, ' '))
    end
  end
  most = math.min(most, 8)
  ---@param p thread.Part|nil
  ---@return integer|nil
  local function open(p)
    return p and p.tour and place_of(r, p.tour) or nil
  end
  ---@param place integer
  ---@param here integer|nil
  ---@return string
  local function tick(place, here)
    local name, line = labels.colour(list[place].colour, place)
    return (here == nil or here == place) and name or line
  end
  local cols = most + 1 + #list
  return {
    parts = {},
    cols = cols,
    head = function(p, side)
      local here = open(p)
      local row = { { 'files', 'ThreadSideHead' }, { '  ' .. #side.files, 'ThreadMeta' } } ---@type thread.Chunks
      local digits = { { text.pad('step', most + 1), 'ThreadMeta' } } ---@type thread.Chunks
      for place = 1, #list do
        digits[#digits + 1] = { tostring(place % 10), tick(place, here) }
      end
      at(row, side.width - cols, digits)
      return { row, {} }
    end,
    lit = function(p)
      local here = open(p)
      return here and files[here] or nil
    end,
    cells = function(path, p)
      local here = open(p)
      local nums = here and ids[here][path] and table.concat(ids[here][path], ' ') or ''
      local out = { { text.pad(text.fit(nums, most), most + 1), here and tick(here, here) or 'ThreadMeta' } } ---@type thread.Chunks
      for place = 1, #list do
        out[#out + 1] = files[place][path] and { '┃', tick(place, here) } or { ' ' }
      end
      return out
    end,
    foot = function(p, side)
      local here = open(p) or 1
      if not list[here] then
        return {}
      end
      return {
        {
          { 'tour ', 'ThreadMeta' },
          { tostring(here), tick(here, here) },
          { ' walks ', 'ThreadMeta' },
          { tostring(vim.tbl_count(files[here])), 'ThreadMetaHi' },
          { ' of ' .. text.plural(#side.files, 'file'), 'ThreadMeta' },
        },
      }
    end,
  }
end

-- The briefing

---@class thread.BriefingOpts
---@field width integer
---@field indent integer
---@field place integer  among the listed, from 1

--- How far a tour is walked, said over its steps.
---@param r thread.Review
---@param x thread.Tour
---@return string
local function how_far(r, x)
  local n = tour.walked(r, x)
  local i = tour.next(r, x)
  if n == #x.steps then
    return 'all walked'
  elseif n == 0 then
    return 'none walked'
  end
  return n .. ' walked' .. (i and (', step ' .. x.steps[i].id .. ' next') or '')
end

--- A tour's briefing, what the walk opens on and comes back to, a page
--- of the Tours tab: the tour's row as Tours draws it; set in under it,
--- its introduction whole, a contract it places as Contracts draws one
--- opened, then its steps under a head saying how far you are.
---@param P thread.Sheet
---@param r thread.Review
---@param x thread.Tour
---@param o thread.BriefingOpts
---@return thread.Part[]  the tour, then what in it goes somewhere, then its steps
function M.briefing(P, r, x, o)
  local head = M.head(P, r, x, { width = o.width, indent = o.indent, place = o.place })
  local out = { head } ---@type thread.Part[]
  local inner, width = o.indent + TITLE, o.width - TITLE
  ---@param Q thread.Sheet
  ---@param c thread.Contract
  ---@param w integer
  ---@param from integer
  ---@return thread.Drawn[]
  local function placed(Q, c, w, from)
    local parts = contracts.block(Q, r, c, { width = w, indent = from })
    local row = parts[1]
    local drawn = { { first = row.first, last = row.first, s = from, e = from + w, link = { kind = 'contract', id = c.id } } } ---@type thread.Drawn[]
    for k = 2, #parts do
      local q = parts[k]
      drawn[#drawn + 1] = { first = q.first, last = q.last, s = q.s, e = q.e, link = q.link, name = q.name }
    end
    return drawn
  end
  if x.introduction then
    P.add ''
    draw.prose(prose.draw(P, x.introduction, math.min(width, PROSE), { indent = inner, review = r, contract = placed }), out)
  end
  P.add ''
  local said = { { 'steps', 'ThreadGroupHead' }, { '  ' .. #x.steps, 'ThreadMetaHi' }, { '   ' .. how_far(r, x), 'ThreadMeta' } }
  P.chunks(text.fit_chunks(said, width), inner)
  P.add ''
  vim.list_extend(out, M.steps(P, r, x, { width = width, indent = inner, place = o.place }))
  draw.within(out, 1, { tour = x })
  return out
end

return M
