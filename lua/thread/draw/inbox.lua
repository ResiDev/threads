--- A review's notes as an inbox: a section for each way a note can
--- stand, in the order to look at them, and in each a row a note, two
--- lines as a mail list draws a message. The note under the cursor opens
--- under its row: its symbols said in words, its last two messages, and
--- how to answer.

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

-- A row's columns, from its indent: the unread dot, the kind's icon,
-- who spoke last, the title.
local DOT, ICON, FROM, TITLE = 0, 2, 5, 15

-- A note opened: its last few messages, and rows of each one's text.
M.LAST, M.MOST = 2, 3

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

--- Where a note is: its file and line, apart; nil on no line.
---@param r thread.Review
---@param n thread.Note
---@return string|nil file, string|nil line
local function where(r, n)
  local c = review.chunk(r, n.chunk)
  if not c then
    return nil
  end
  local said = chunk_draw.short(c, chunk.spec(r.diff))[1]
  local file, line = said:match '^(.-)(:.*)$'
  return file or said, line
end

--- A title's text, what is in backticks in the code's colour.
---@param s string
---@param hl string
---@param code string
---@return thread.Chunks
local function titled(s, hl, code)
  local out = {} ---@type thread.Chunks
  for _, row in ipairs(prose.rows(model_prose.of(s), 10000)) do
    for _, c in ipairs(row.chunks) do
      out[#out + 1] = { c[1], c[2] == 'ThreadCode' and code or hl }
    end
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

--- `left` cut to leave `right` room, then `right` ending at `width`.
---@param left thread.Chunks
---@param right thread.Chunks
---@param width integer
---@return thread.Chunks
local function spread(left, right, width)
  local rw = text.width(right)
  local row = text.fit_chunks(left, math.max(1, width - rw - 3))
  if rw > 0 then
    at(row, width - rw, right)
  end
  return row
end

--- The row's symbols in words, under the cursor: what it is, how it
--- stands, where it is, and `✓ accepted` once you have accepted the
--- code it is on.
---@param r thread.Review
---@param n thread.Note
---@param section thread.InboxSection
---@return thread.Chunks
local function spelled(r, n, section)
  local _, hl = labels.icon(n)
  local what = n.kind == 'issue' and { { 'a ', 'ThreadSpelled' }, { vim.trim((n.severity or '') .. ' ' .. (n.issue or 'issue')), hl } }
    or { { 'a ' .. n.kind, hl } }
  local state = ({
    yours = { 'the agent answered: your move', 'ThreadYourMove' },
    new = { 'nobody has answered yet', 'ThreadSpelled' },
    waiting = { 'you replied: the agent’s move', 'ThreadSpelled' },
    reference = { 'asks nothing', 'ThreadSpelled' },
    settled = { n.status or 'settled', 'ThreadSpelled' },
  })[section]
  local file, line = where(r, n)
  local place = file and { { file, 'ThreadFile' }, { line or '', 'ThreadFileLine' } } or { { 'on no line', 'ThreadSpelled' } }
  local c = review.chunk(r, n.chunk)
  local out, parts = what, { { state }, place }
  if c and chunk.accepted(r, c) then
    parts[3] = { { '✓ accepted', 'ThreadAccepted' } }
  end
  for _, part in ipairs(parts) do
    out[#out + 1] = { '  ·  ', 'ThreadMeta' }
    vim.list_extend(out, part)
  end
  return out
end

--- A note's row, two lines: whether it is unread, its icon, who spoke
--- last and how many messages, its title and when; then its last words
--- and where it is, or, under the cursor, its symbols in words.
---@param P thread.Sheet
---@param r thread.Review
---@param n thread.Note
---@param section thread.InboxSection
---@param here boolean
---@param width integer
---@param indent integer
---@return thread.Part
local function row(P, r, n, section, here, width, indent)
  local c = conversation.of_note(n)
  local unread = conversation.unread(r, c) > 0
  local done = section == 'settled'
  local last = c.messages[#c.messages]
  local g, hl = labels.icon(n)
  local left = {} ---@type thread.Chunks
  at(left, DOT, { { unread and labels.glyph 'unread' or ' ', 'ThreadUnread' } })
  at(left, ICON, { { g, hl } })
  if last then
    local who = done and 'ThreadKindDone' or ('ThreadSender' .. (last.from == 'you' and 'You' or 'Agent') .. (unread and '' or 'Read'))
    at(left, FROM, { { last.from, who } })
    if #c.messages > 1 then
      left[#left + 1] = { ' ' .. #c.messages, 'ThreadCount' }
    end
  end
  local when = (text.ago(message.when(r, c, #c.messages)) or ''):gsub(' ago$', '')
  local right = { { when, unread and 'ThreadWhenUnread' or 'ThreadWhen' } } ---@type thread.Chunks
  local outcome = labels.outcome(n)
  if outcome then
    right = { { outcome, 'ThreadKindDone' }, { '   ' .. when, 'ThreadWhen' } }
  end
  local base = done and 'ThreadDone' or (unread or here) and 'ThreadSubjectUnread' or 'ThreadSubject'
  at(left, TITLE, titled(n.title, base, done and 'ThreadDone' or 'ThreadCode'))
  local first = P.chunks(spread(left, right, width), indent)
  local second = {} ---@type thread.Chunks
  if here then
    at(second, TITLE, spelled(r, n, section))
    P.chunks(text.fit_chunks(second, width), indent)
  else
    local file, line = where(r, n)
    local place = file and { { file .. (line or ''), 'ThreadAttach' } } or {}
    local said = last and prose.first_line(last.prose, r) or ''
    at(second, TITLE, { { said, done and 'ThreadKindDone' or 'ThreadSnippet' } })
    P.chunks(spread(second, place, width), indent)
  end
  return { kind = 'note', first = first, last = first + 1, note = n, item = true, alone = true }
end

--- A note opened under its row: its last few messages, each with a bar
--- in its writer's colour, the one you have not read marked new; then
--- how to answer, and to settle it when it can be.
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
  local from = math.max(1, #c.messages - M.LAST + 1)
  P.add ''
  if from > 1 then
    P.chunks({ { text.fit('… ' .. (from - 1) .. ' earlier   ⏎ the whole thread', width - TITLE), 'ThreadMeta' } }, x)
    P.add ''
  end
  local read = conversation.read(r, c)
  for i = from, #c.messages do
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
    local part = { kind = 'message', first = first, last = first, conversation = c, message = i } ---@type thread.Part
    local parts = { part }
    draw.prose(prose.draw(P, m.prose, room, { indent = x + 2, most = M.MOST, review = r, hl = 'ThreadMsgText' }), parts)
    part.last = #P.lines - 1
    draw.gutter(P, first, part.last, '▎', bar, x)
    draw.within(parts, 1, { conversation = c, message = i, note = n })
    vim.list_extend(out, parts)
    P.add ''
  end
  local answer = { { 'r', 'ThreadKey' }, { '  ' .. (#c.messages > 1 and 'reply to the agent…' or 'start the conversation…'), 'ThreadPlaceholder' } }
  if note.open(n) then
    at(answer, 30, { { 's', 'ThreadKey' }, { '  settle', 'ThreadKeyLabel' } })
  end
  local last = P.chunks(text.fit_chunks(answer, width - TITLE), x)
  out[#out + 1] = { kind = 'block', name = 'answer', first = last, last = last, conversation = c, note = n }
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
        out[#out + 1] = row(P, r, n, s.id, here, o.width, indent)
        if here then
          vim.list_extend(out, opened(P, r, n, o.width, indent))
        end
        P.add ''
      end
    end
  end
  draw.within(out, 1, { review = r })
  return out
end

return M
