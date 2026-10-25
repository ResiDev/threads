--- A review: as a line, in Home's list; its head, what it is about,
--- its introduction and the review at a glance; the link under the
--- cursor there, said; its files beside. One that cannot be read is a
--- line saying why.

local chunk = require 'thread.model.chunk'
local chunk_draw = require 'thread.draw.chunk'
local contract = require 'thread.model.contract'
local contracts = require 'thread.draw.contracts'
local conversation = require 'thread.model.conversation'
local diff = require 'thread.base.diff'
local draw = require 'thread.draw'
local labels = require 'thread.draw.labels'
local note = require 'thread.model.note'
local prose = require 'thread.prose'
local review = require 'thread.model.review'
local side = require 'thread.draw.side'
local step = require 'thread.model.step'
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

--- What a review is about as its Overview's line under its title says
--- it, quiet: its diff, its revisions in the code's colour; its size;
--- how many hunks of it no step, note or contract is on. A piece each.
---@param r thread.Review
---@return thread.Chunks[]
local function deck(r)
  local first = {} ---@type thread.Chunks
  for word, gap in about(r):gmatch '(%S+)(%s*)' do
    first[#first + 1] = { word, word:match '^%x%x%x%x%x%x%x+$' and 'ThreadCode' or 'ThreadDeck' }
    first[#first + 1] = { gap, 'ThreadDeck' }
  end
  local out = { first } ---@type thread.Chunks[]
  local spec = chunk.spec(r.diff)
  if not spec then
    return out
  end
  local list, err = diff.files(spec)
  if err then
    out[#out + 1] = { { 'git cannot read it: ' .. err, 'ThreadBroken' } }
    return out
  end
  local add, del = 0, 0
  for _, f in ipairs(list) do
    add, del = add + f.add, del + f.del
  end
  out[#out + 1] = { { text.plural(#list, 'file') .. ', +' .. add .. ' −' .. del, 'ThreadDeck' } }
  local left = #review.left_out(r)
  if left > 0 then
    out[#out + 1] = { { text.plural(left, 'hunk') .. ' in no step, note or contract', 'ThreadDeck' } }
  end
  return out
end

--- Pieces a row, ` · ` between, as many to a row as fit in `width`.
---@param P thread.Sheet
---@param pieces thread.Chunks[]
---@param width integer
---@param indent integer
local function pieces_in(P, pieces, width, indent)
  local row = {} ---@type thread.Chunks
  for _, piece in ipairs(pieces) do
    if #row > 0 and text.width(row) + 3 + text.width(piece) > width then
      P.chunks(text.fit_chunks(row, width), indent)
      row = {}
    end
    if #row > 0 then
      row[#row + 1] = { ' · ', 'ThreadDeck' }
    end
    vim.list_extend(row, piece)
  end
  P.chunks(text.fit_chunks(row, width), indent)
end

--- A review's head, what its Overview shows: its title, what it is about
--- under it, two blank rows, its introduction; then the review at a
--- glance.
---@param P thread.Sheet
---@param r thread.Review
---@param o thread.ReviewOpts
---@return thread.Part[]  the review, then what in it goes somewhere
function M.head(P, r, o)
  local indent = o.indent or P.indent
  -- A row lower than the lists start: a page, not a list.
  P.add ''
  local title = { { r.title, 'ThreadPageTitle' }, { r.status == 'closed' and '  closed' or '', 'ThreadMeta' } }
  local first = P.chunks(text.fit_chunks(title, o.width), indent)
  local out = { { kind = 'review', first = first, last = first, review = r } } ---@type thread.Part[]
  pieces_in(P, deck(r), o.width, indent)
  if r.introduction then
    P.add ''
    P.add ''
    draw.prose(prose.draw(P, r.introduction, math.min(o.width, PROSE), { indent = indent, review = r }), out)
  end
  P.add ''
  P.add ''
  M.glance(P, r, o)
  out[1].last = #P.lines - 1
  draw.within(out, 1, { review = r })
  return out
end

-- The glance's columns, from its left: the marks, the words, what needs
-- you; nearer, when it is narrow, for what needs you to fit.
local MARKS, WORDS, NEEDS = 12, 48, 70

--- Marks, `gap` between, in rows that end two columns short of `width`:
--- every one is drawn, as many rows as they take.
---@param marks thread.Chunks[]
---@param gap string
---@param width integer
---@return thread.Chunks[]
local function wrapped(marks, gap, width)
  local rows, row = {}, {} ---@type thread.Chunks[], thread.Chunks
  for _, m in ipairs(marks) do
    local with = vim.list_extend(vim.list_slice(row), #row > 0 and { { gap } } or {})
    vim.list_extend(with, m)
    if #row > 0 and text.width(with) > width - 2 then
      rows[#rows + 1] = row
      row = vim.list_slice(m)
    else
      row = with
    end
  end
  rows[#rows + 1] = row
  return rows
end

--- What a glance's row says needs you: a symbol and how many; nothing
--- when none does.
---@param n integer
---@param symbol { [1]: string, [2]: string }
---@param said string
---@return thread.Chunks
local function needs(n, symbol, said)
  if n == 0 then
    return {}
  end
  return { { symbol[1] .. ' ', symbol[2] }, { said, 'ThreadYourMove' } }
end

--- The review at a glance, a table under a quiet head: a row each for
--- its contracts, its tours and its notes, each with a mark for every
--- one as its tab draws it, the same in words, and what of it needs you.
---@param P thread.Sheet
---@param r thread.Review
---@param o thread.ReviewOpts
function M.glance(P, r, o)
  local indent = o.indent or P.indent
  local rows = {} ---@type { [1]: string, [2]: thread.Chunks[], [3]: string, [4]: thread.Chunks, [5]: string }[]
  if #r.contracts > 0 then
    local walked = contracts.walked_chunks(r)
    local marks, by, missed = {}, {}, 0 ---@type thread.Chunks[], table<string, integer>, integer
    for _, c in ipairs(r.contracts) do
      local group = contracts.group(r, c, walked)
      local sign = contract.sign(c)
      missed = missed + (group == 'needs' and 1 or 0)
      marks[#marks + 1] = { { sign, group == 'needs' and 'ThreadImpactMissed' or group == 'walked' and 'ThreadSevDone' or contracts.SIGN[sign] } }
      by[c.source.change] = (by[c.source.change] or 0) + 1
    end
    local words = {} ---@type string[]
    for _, change in ipairs { 'changed', 'added', 'removed' } do
      if by[change] then
        words[#words + 1] = by[change] .. ' ' .. change
      end
    end
    local said = (missed == 1 and '1 missed a caller' or missed .. ' missed callers')
    rows[#rows + 1] = { 'contracts', marks, table.concat(words, ', '), needs(missed, { '✗', 'ThreadImpactMissed' }, said), ' ' }
  end
  local list = tour.list(r)
  if #list > 0 then
    local marks = {} ---@type thread.Chunks[]
    local steps, walked, replies, at = 0, 0, 0, {} ---@type integer, integer, integer, string[]
    for place, x in ipairs(list) do
      local name, line = labels.colour(x.colour, place)
      local dots = {} ---@type thread.Chunks
      local here = 0
      for _, s in ipairs(x.steps) do
        local yes = step.walked(r, s)
        dots[#dots + 1] = yes and { '●', name } or { '○', line }
        steps, walked = steps + 1, walked + (yes and 1 or 0)
        here = here + (conversation.move(conversation.of_step(s, x)) == 'you' and 1 or 0)
      end
      marks[#marks + 1] = dots
      if here > 0 then
        replies, at[#at + 1] = replies + here, tostring(place)
      end
    end
    local said = text.plural(replies, 'reply', 'replies') .. ' in tour' .. (#at > 1 and 's ' or ' ') .. table.concat(at, ' ')
    rows[#rows + 1] = {
      'tours',
      marks,
      walked .. ' of ' .. steps .. ' steps walked',
      needs(replies, { labels.glyph 'yours', 'ThreadYourMove' }, said),
      ' ',
    }
  end
  if #r.notes > 0 then
    local marks, open, settled, yours = {}, 0, 0, 0 ---@type thread.Chunks[], integer, integer, integer
    for _, n in ipairs(r.notes) do
      local g, hl = labels.icon(n)
      marks[#marks + 1] = { { g, hl } }
      if note.closed(n) then
        settled = settled + 1
      else
        open = open + 1
      end
      yours = yours + (n.kind ~= 'comment' and not note.closed(n) and conversation.move(conversation.of_note(n)) == 'you' and 1 or 0)
    end
    local said = yours == 1 and '1 answer for you' or (yours .. ' answers for you')
    rows[#rows + 1] = { 'notes', marks, open .. ' open, ' .. settled .. ' settled', needs(yours, { '?', 'ThreadIconAsk' }, said), '  ' }
  end
  if #rows == 0 then
    return
  end
  local said, worded = 9, 8 ---@type integer, integer
  for _, row in ipairs(rows) do
    worded, said = math.max(worded, #row[3]), math.max(said, text.width(row[4]))
  end
  local needs_at = math.max(MARKS + 8, math.min(NEEDS, o.width - said))
  local words_at = math.max(MARKS + 4, math.min(WORDS, needs_at - worded - 2))
  ---@param row thread.Chunks
  ---@param col integer
  ---@param chunks thread.Chunks
  local function at(row, col, chunks)
    local w = text.width(row)
    if w < col and #chunks > 0 then
      row[#row + 1] = { string.rep(' ', col - w) }
    end
    vim.list_extend(row, chunks)
  end
  P.chunks({ { 'at a glance', 'ThreadGroupHead' } }, indent)
  P.add ''
  local head = {} ---@type thread.Chunks
  at(head, MARKS, { { words_at - MARKS > 20 and 'a mark for each one' or 'marks', 'ThreadDeck' } })
  at(head, words_at, { { 'in words', 'ThreadDeck' } })
  at(head, needs_at, { { 'needs you', 'ThreadDeck' } })
  P.chunks(text.fit_chunks(head, o.width), indent)
  for i, row in ipairs(rows) do
    if i > 1 then
      P.add ''
    end
    local marks = wrapped(row[2], row[5], words_at - MARKS)
    local line = { { row[1], 'ThreadMetaHi' } } ---@type thread.Chunks
    at(line, MARKS, marks[1])
    at(line, words_at, { { row[3], 'ThreadMeta' } })
    at(line, needs_at, row[4])
    P.chunks(text.fit_chunks(line, o.width), indent)
    for k = 2, #marks do
      P.chunks(marks[k], indent + MARKS)
    end
  end
end

--- The link under the cursor, said on the row over the keys: what it
--- goes to, what that is and where; a contract's callers and the tours
--- that walk it; what ⏎ does. As much as fits in `width`, what it says
--- last left out first. Nil when the cursor is on none.
---@param r thread.Review
---@param p thread.Part|nil
---@param T thread.Touches
---@param width integer|nil
---@return thread.Chunks|nil
function M.named(r, p, T, width)
  local l = p and p.kind == 'link' and p.link
  if not l or (l.review and l.review ~= r.id) then
    return nil
  end
  local spec = chunk.spec(r.diff)
  local what, pieces = {}, {} ---@type thread.Chunks, thread.Chunks[]
  ---@param c thread.Chunk|nil
  ---@param none string
  local function place(c, none)
    pieces[#pieces + 1] = c and chunk_draw.place(c, spec) or { { none, 'ThreadMeta' } }
  end
  if l.kind == 'contract' then
    local c = review.contract(r, l.id)
    if not c then
      return nil
    end
    local sign = contract.sign(c)
    what = { { c.name, 'ThreadContract' }, { '  ' }, { sign .. ' ', contracts.SIGN[sign] }, { c.kind, 'ThreadKind' } }
    place(contracts.home(r, c), 'written out')
    local callers = contracts.callers(c, false, true)
    if #callers > 0 then
      pieces[#pieces + 1] = callers
    end
    local by = T.touched[c] or {}
    local walks = {} ---@type thread.Chunks
    for i, x in ipairs(tour.list(r)) do
      if by[x] then
        vim.list_extend(walks, { { #walks > 0 and ' ' or 'tours ', 'ThreadMeta' }, { tostring(i), (labels.colour(x.colour, i)) } })
      end
    end
    pieces[#pieces + 1] = #walks > 0 and walks or { { 'in no tour', 'ThreadMeta' } }
  elseif l.kind == 'note' then
    local n = review.note(r, l.id)
    if not n then
      return nil
    end
    local g, hl = labels.icon(n)
    what = { { g .. ' ', hl }, { n.title, 'ThreadSubject' } }
    place(n.chunk and review.chunk(r, n.chunk), 'on no line')
  elseif l.kind == 'step' then
    local s, x = review.step(r, l.id)
    if not (s and x) then
      return nil
    end
    what = { { 'step ' .. s.id .. ' ', 'ThreadMetaHi' }, { s.title, 'ThreadText' } }
    for i, t in ipairs(tour.list(r)) do
      if t == x then
        pieces[#pieces + 1] = { { 'tour ', 'ThreadMeta' }, { tostring(i), (labels.colour(x.colour, i)) } }
      end
    end
    place(s.chunk and review.chunk(r, s.chunk), 'on no line')
  else
    return nil
  end
  local enter = { { '⏎', 'ThreadKey' }, { ' its page', 'ThreadKeyLabel' } } ---@type thread.Chunks
  while true do
    local out = vim.list_extend({ { '↳ ', 'ThreadMeta' } }, what)
    for _, piece in ipairs(pieces) do
      out[#out + 1] = { '   ' }
      vim.list_extend(out, piece)
    end
    out[#out + 1] = { '   ' }
    vim.list_extend(out, enter)
    if not width or text.width(out) <= width or #pieces == 0 then
      return width and text.fit_chunks(out, width) or out
    end
    pieces[#pieces] = nil
  end
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
---@param bottom integer|nil  their last row; else the sheet's
function M.side(P, r, top, col, T, width, pane, bottom)
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
    side.beside(P, top, col, side.paths(all), parts, width, pane, bottom)
  end
end

return M
