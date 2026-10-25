--- A review's notes as an inbox: a section for each way a note can
--- stand, in the order to look at them, and in each a note, its title
--- wrapped whole. The note under the cursor opens under it: what it
--- says, how its conversation stands, its last reply, and how to answer.

local chunk = require 'thread.model.chunk'
local chunk_draw = require 'thread.draw.chunk'
local conversation = require 'thread.model.conversation'
local draw = require 'thread.draw'
local labels = require 'thread.draw.labels'
local message = require 'thread.model.message'
local model_prose = require 'thread.model.prose'
local note = require 'thread.model.note'
local prose = require 'thread.prose'
local review = require 'thread.model.review'
local text = require 'thread.base.text'

local M = {}

---@alias thread.InboxSection 'yours'|'new'|'waiting'|'reference'|'settled'

---@class thread.InboxOpts
---@field width integer
---@field indent integer|nil  else the sheet's
---@field here string|nil  the note opened, by draw.key: the one under the cursor

-- A row's columns, from its indent: the unread dot, the kind's icon and
-- its word, the title. Who spoke last is left to the section, which says
-- whose move it is.
local DOT, ICON, KIND, TITLE = 0, 2, 5, 17

-- A note opened: rows of what it says alone, and of it and its last
-- reply each once there is one.
M.ALONE, M.MOST = 10, 5

--- A section: its name, the colours of its glyph and its name, and why a
--- note is in it, said from the notes there.
---@class thread.InboxKind
---@field id thread.InboxSection
---@field name string
---@field glyph string  its glyph's colour
---@field head string  its name's
---@field why fun(r: thread.Review, notes: thread.Note[]): string|nil

--- When the last of the messages of `notes` from `from` came, as a
--- person says it.
---@param r thread.Review
---@param notes thread.Note[]
---@param from 'you'|'agent'
---@return string|nil
local function last_from(r, notes, from)
  local latest ---@type string|nil
  for _, n in ipairs(notes) do
    local c = conversation.of_note(n)
    for i, m in ipairs(c.messages) do
      local at = m.from == from and message.when(r, c, i)
      if at and (not latest or at > latest) then
        latest = at
      end
    end
  end
  return text.ago(latest)
end

-- The sections, in the order to look at them. Yours is the one block.
---@type thread.InboxKind[]
M.SECTIONS = {
  {
    id = 'yours',
    name = 'your move',
    glyph = 'ThreadSectionYou',
    head = 'ThreadSectionYou',
    why = function(r, notes)
      local ago = last_from(r, notes, 'agent')
      return 'the agent answered' .. (ago and (', ' .. ago) or '')
    end,
  },
  {
    id = 'new',
    name = 'New',
    glyph = 'ThreadSectionGlyph',
    head = 'ThreadSectionHead',
    why = function()
      return 'raised by the agent; nobody has answered'
    end,
  },
  {
    id = 'waiting',
    name = 'Waiting on the agent',
    glyph = 'ThreadSectionAgent',
    head = 'ThreadSectionHead',
    why = function(r, notes)
      local ago = last_from(r, notes, 'you')
      return 'you replied' .. (ago and (' ' .. ago) or '')
    end,
  },
  {
    id = 'reference',
    name = 'For reference',
    glyph = 'ThreadSectionGlyph',
    head = 'ThreadSectionHead',
    why = function()
      return 'remarks that ask nothing'
    end,
  },
  {
    id = 'settled',
    name = 'Settled',
    glyph = 'ThreadKindDone',
    head = 'ThreadSectionDone',
    why = function() end,
  },
}

-- Whose move a note's conversation is, to the section it puts the note in;
-- nobody's, only the agent has spoken: new.
---@type table<string, thread.InboxSection>
local BY_MOVE = { you = 'yours', agent = 'waiting' }

--- The section a note is in: a comment asks nothing, so is for
--- reference; one settled is settled; else whose move it is.
---@param n thread.Note
---@return thread.InboxSection
function M.section(n)
  if n.kind == 'comment' then
    return 'reference'
  elseif note.closed(n) then
    return 'settled'
  end
  return BY_MOVE[conversation.move(conversation.of_note(n)) or ''] or 'new'
end

-- New notes, the most severe first.
local RANK = { high = 1, medium = 2, low = 3 }

--- The notes of each section, in the review's order but for New: the
--- most severe first, then those you have not read.
---@param r thread.Review
---@return table<thread.InboxSection, thread.Note[]>
function M.sorted(r)
  local out = {} ---@type table<thread.InboxSection, thread.Note[]>
  local at = {} ---@type table<thread.Note, integer>
  for i, n in ipairs(r.notes) do
    local s = M.section(n)
    out[s] = out[s] or {}
    table.insert(out[s], n)
    at[n] = i
  end
  table.sort(out.new or {}, function(a, b)
    local ra, rb = RANK[a.severity or ''] or 4, RANK[b.severity or ''] or 4
    if ra ~= rb then
      return ra < rb
    end
    local ua = conversation.unread(r, conversation.of_note(a)) > 0
    local ub = conversation.unread(r, conversation.of_note(b)) > 0
    if ua ~= ub then
      return ua
    end
    return at[a] < at[b]
  end)
  return out
end

--- A title's text, what is in backticks in the code's colour, in rows
--- `width` wide.
---@param s string
---@param hl string
---@param code string
---@param width integer
---@return thread.Chunks[]
function M.titled(s, hl, code, width)
  local out = {} ---@type thread.Chunks[]
  for _, row in ipairs(prose.rows(model_prose.of(s), width)) do
    local line = {} ---@type thread.Chunks
    for _, c in ipairs(row.chunks) do
      line[#line + 1] = { c[1], c[2] == 'ThreadCode' and code or hl }
    end
    out[#out + 1] = line
  end
  return out
end

--- `chunks` from `col`, the row so far padded to it.
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

--- What the right of a note's row says, and of its page's head:
--- `✓ accepted` once you have accepted its code, how it ended, a shape
--- for each of its last few messages by who wrote it once there is a
--- reply, and when the last came.
---@param r thread.Review
---@param n thread.Note
---@return thread.Chunks
function M.right(r, n)
  local c = conversation.of_note(n)
  local unread = conversation.unread(r, c) > 0
  local out = {} ---@type thread.Chunks
  local ch = review.chunk(r, n.chunk)
  if ch and chunk.accepted(r, ch) then
    out[#out + 1] = { '✓ accepted   ', 'ThreadAccepted' }
  end
  local outcome = labels.outcome(n)
  if outcome then
    out[#out + 1] = { outcome .. '   ', 'ThreadKindDone' }
  end
  if #c.messages > 1 then
    vim.list_extend(out, labels.dots(c.messages, conversation.read(r, c), 2))
    out[#out + 1] = { '   ' }
  end
  local when = (text.ago(message.when(r, c, #c.messages)) or ''):gsub(' ago$', '')
  out[#out + 1] = { when, unread and not outcome and 'ThreadWhenUnread' or 'ThreadWhen' }
  return out
end

--- A note's row: whether it is unread, its icon and its kind, quieter;
--- its title, the one thing bright, wrapped under itself, never cut;
--- on the right, how it stands, as M.right says.
---@param P thread.Sheet
---@param r thread.Review
---@param n thread.Note
---@param section thread.InboxSection
---@param width integer
---@param indent integer
---@return thread.Part
local function row(P, r, n, section, width, indent)
  local c = conversation.of_note(n)
  local unread = conversation.unread(r, c) > 0
  local done = section == 'settled'
  local g, hl, kind = labels.icon(n)
  local lead = {} ---@type thread.Chunks
  at(lead, DOT, { { unread and labels.glyph 'unread' or ' ', 'ThreadUnread' } })
  at(lead, ICON, { { g, hl } })
  at(lead, KIND, { { kind, hl .. 'Word' } })
  local right = M.right(r, n)
  local rw = text.width(right)
  local room = math.max(12, width - TITLE - rw - 3)
  local base = done and 'ThreadDone' or 'ThreadSubject'
  local first, last ---@type integer, integer
  for i, t in ipairs(M.titled(n.title, base, base, room)) do
    local line = i == 1 and lead or {} ---@type thread.Chunks
    at(line, TITLE, t)
    if i == 1 then
      at(line, width - rw, right)
    end
    last = P.chunks(line, indent)
    first = first or last
  end
  return { kind = 'note', first = first, last = last, note = n, item = true, alone = true }
end

--- A conversation's messages from the `from`th, as Notes draws a
--- thread: each its writer and when, `new` on one you have not read, its
--- text, a bar down its side in its writer's colour, and a blank row
--- after it. From column `x`, its text `room` wide, cut at `most` rows.
---@param P thread.Sheet
---@param r thread.Review
---@param c thread.Conversation
---@param o { x: integer, room: integer, from: integer|nil, most: integer|nil, changes: boolean|nil }
---@return thread.Part[]  each message, then what in it goes somewhere
function M.thread(P, r, c, o)
  local out = {} ---@type thread.Part[]
  local x, room = o.x, o.room
  local read = conversation.read(r, c)
  for i = o.from or 1, #c.messages do
    local m = c.messages[i]
    local new = m.from == 'agent' and i > read
    local bar = m.from == 'you' and 'ThreadQuoteYou' or 'ThreadQuoteAgent'
    local head = { { m.from, m.from == 'you' and 'ThreadWhoYou' or 'ThreadWhoAgent' } } ---@type thread.Chunks
    local ago = text.ago(message.when(r, c, i))
    if ago then
      head[#head + 1] = { '  ' .. ago, 'ThreadMeta' }
    end
    if new then
      head[#head + 1] = { '   new', 'ThreadUnread' }
    end
    local first = P.chunks(text.fit_chunks(head, room), x + 2)
    if new then
      P.mark(first, 0, { virt_text = { { labels.glyph 'unread', 'ThreadUnread' } }, virt_text_win_col = x - 2 })
    end
    local part = { kind = 'message', first = first, last = first, conversation = c, message = i, cols = { col = x + 2, width = room } } ---@type thread.Part
    local parts = { part }
    draw.prose(prose.draw(P, m.prose, room, { indent = x + 2, most = o.most, review = r, hl = 'ThreadMsgText' }), parts)
    -- On a page, the code it changed, a row a chunk, each going there.
    for j, id in ipairs(o.changes and m.changes or {}) do
      local ch = review.chunk(r, id)
      if ch then
        if j == 1 then
          P.add ''
        end
        local said = { { j == 1 and 'changed  ' or '         ', 'ThreadMeta' } } ---@type thread.Chunks
        vim.list_extend(said, chunk_draw.where(ch, chunk.locate(ch, chunk.spec(r.diff))))
        local line = P.chunks(text.fit_chunks(said, room), x + 2)
        parts[#parts + 1] = { kind = 'change', first = line, last = line, chunk = ch }
      end
    end
    part.last = #P.lines - 1
    draw.gutter(P, first, part.last, '▎', bar, x)
    draw.within(parts, 1, { conversation = c, message = i, note = c.note, contract = c.contract })
    vim.list_extend(out, parts)
    P.add ''
  end
  return out
end

--- A conversation on a page, from its `from`th message, as Notes draws
--- one, each message an item; then where you answer, a row saying how,
--- `s settle` beside it for a note still open, and what it waits on.
---@param P thread.Sheet
---@param r thread.Review
---@param c thread.Conversation
---@param o { x: integer, room: integer, from: integer|nil, ask: string|nil, quiet: boolean|nil }  `ask`, what the row says before anyone has; `quiet`, no row
---@param out thread.Part[]  added to
function M.talk(P, r, c, o, out)
  local from = o.from or 1
  local said = o.ask
  if #c.messages >= from then
    for _, p in ipairs(M.thread(P, r, c, { x = o.x, room = o.room, from = from, changes = true })) do
      if p.kind == 'message' then
        -- Lit from its bar, which the light takes the place of.
        p.item, p.span = true, { from = o.x, to = o.x + o.room + 2 }
      end
      out[#out + 1] = p
    end
    said = 'reply…'
  end
  -- What you write goes under its last message, over this row.
  local under = #P.lines - (#c.messages >= from and 2 or 1)
  out[#out + 1] = { kind = 'reply', first = under, last = under, cols = { col = o.x + 2, width = o.room }, conversation = c }
  if o.quiet then
    return
  end
  local answer = { { 'r', 'ThreadKey' }, { '  ' .. said, 'ThreadPlaceholder' } } ---@type thread.Chunks
  if c.note and note.open(c.note) then
    at(answer, 30, { { 's', 'ThreadKey' }, { '  settle', 'ThreadKeyLabel' } })
  end
  if conversation.move(c) == 'agent' then
    vim.list_extend(answer, { { '   ' }, { 'waiting on the agent', 'ThreadMeta' } })
  end
  P.chunks(text.fit_chunks(answer, o.room + 2), o.x)
end

--- A note opened under its row: what it says, plain, cut short; then
--- its last reply, with a bar in its writer's colour, marked new when
--- you have not read it.
---@param P thread.Sheet
---@param r thread.Review
---@param n thread.Note
---@param width integer
---@param indent integer
---@return thread.Part[]
local function opened(P, r, n, width, indent)
  local c = conversation.of_note(n)
  local x = indent + TITLE
  local room = width - TITLE - 2
  local out = {} ---@type thread.Part[]
  local first = c.messages[1]
  local most = #c.messages > 1 and M.MOST or M.ALONE
  if first then
    P.add ''
    local at_row = #P.lines
    local part = { kind = 'message', first = at_row, last = at_row, conversation = c, message = 1, cols = { col = x, width = room } } ---@type thread.Part
    local parts = { part }
    draw.prose(prose.draw(P, first.prose, room, { indent = x, most = most, review = r, hl = 'ThreadMsgText' }), parts)
    part.last = #P.lines - 1
    draw.within(parts, 1, { conversation = c, message = 1, note = n })
    vim.list_extend(out, parts)
  end
  if #c.messages > 1 then
    P.add ''
    vim.list_extend(out, M.thread(P, r, c, { x = x, room = room, from = #c.messages, most = M.MOST }))
  end
  return out
end

--- A section's head: its glyph and name, how many are in it, and why;
--- yours a block, as what asks most.
---@param P thread.Sheet
---@param r thread.Review
---@param s thread.InboxKind
---@param notes thread.Note[]
---@param indent integer
---@param width integer
---@return thread.Part  a heading, which } and { go between
local function head(P, r, s, notes, indent, width)
  local glyph = labels.glyph(s.id)
  local why = s.why(r, notes)
  local tail = { { '  ' .. #notes, 'ThreadMetaHi' } } ---@type thread.Chunks
  if why then
    tail[#tail + 1] = { '   ' .. why, 'ThreadMeta' }
  end
  local first ---@type integer
  if s.id == 'yours' then
    local said = { { ' ' .. glyph .. '  ' .. s.name .. ' ', s.head } } ---@type thread.Chunks
    -- A column left of the rest, so its glyph lines up with theirs.
    local out = indent > 0 and 1 or 0
    first = P.chunks(text.fit_chunks(vim.list_extend(said, tail), width + out), indent - out)
  else
    local said = { { glyph, s.glyph } } ---@type thread.Chunks
    at(said, 3, { { s.name, s.head } })
    first = P.chunks(text.fit_chunks(vim.list_extend(said, tail), width), indent)
  end
  return { kind = 'heading', first = first, last = first, name = s.id }
end

--- The inbox: each section with notes in it, its head, a blank row, its
--- notes a blank row apart, two before the next section's head. The
--- note `o.here` names opens under its row.
---@param P thread.Sheet
---@param r thread.Review
---@param o thread.InboxOpts
---@return thread.Part[]
function M.draw(P, r, o)
  local indent = o.indent or P.indent
  local out = {} ---@type thread.Part[]
  local sorted = M.sorted(r)
  for _, s in ipairs(M.SECTIONS) do
    local notes = sorted[s.id]
    if notes then
      if #out > 0 then
        P.add ''
      end
      out[#out + 1] = head(P, r, s, notes, indent, o.width)
      P.add ''
      for _, n in ipairs(notes) do
        local here = o.here == draw.key { kind = 'note', first = 0, last = 0, note = n }
        out[#out + 1] = row(P, r, n, s.id, o.width, indent)
        if here then
          vim.list_extend(out, opened(P, r, n, o.width, indent))
        end
        -- A reply ends in a blank row of its own.
        if P.lines[#P.lines] ~= '' then
          P.add ''
        end
      end
    end
  end
  draw.within(out, 1, { review = r })
  return out
end

return M
