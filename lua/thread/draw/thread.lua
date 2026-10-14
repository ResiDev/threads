--- A thread: as a line, in its review's list; as a card, its last few
--- messages, for a bubble in the code; whole, in the screen, with its
--- chunk's code, its introduction set apart, its conversation, the tours
--- under the messages that brought them, and its checks.

local check = require 'thread.draw.check'
local chunk = require 'thread.model.chunk'
local chunk_draw = require 'thread.draw.chunk'
local diff = require 'thread.base.diff'
local draw = require 'thread.draw'
local files = require 'thread.draw.files'
local labels = require 'thread.draw.labels'
local message = require 'thread.draw.message'
local prose = require 'thread.prose'
local text = require 'thread.base.text'
local thread = require 'thread.model.thread'
local tour = require 'thread.draw.tour'

local M = {}

---@class thread.ThreadOpts
---@field width integer
---@field indent integer|nil  else the sheet's
---@field messages integer|nil  a card: its last few messages
---@field most integer|nil  a card: rows of each message's text at most
---@field cut table<integer, true>|nil  a card, filled in: the places of the messages it cut short
---@field columns thread.RowColumns|nil  a row: the columns its list lines up in; else its own
---@field open table<string, true>|nil  whole: what is opened, by draw.key
---@field files boolean|nil  whole: each tour's chunks by file
---@field fold boolean|nil  whole: each message its first row; a row: one row
---@field code boolean|nil  whole: each chunk's code, not only where opened
---@field groups table<string, boolean>|nil  whole: its tours folded to cards, by draw.key

--- Its title: the agent's; on a thread of yours with none yet, the first
--- line of what you said.
---@param t thread.Thread
---@return string
local function title(t)
  return t.title or prose.first_line(t.messages[1] and t.messages[1].text)
end

--- Its state as a glyph, its id, its title, its labels, how it was
--- closed, and how many of its steps want you.
---@param r thread.Review
---@param t thread.Thread
---@return thread.Chunks
local function head(r, t)
  local g, hl = labels.conversation(r, thread.conversation(t))
  local out = { { g .. ' ', hl }, { '#' .. t.id .. '  ', 'ThreadMeta' }, { title(t), thread.closed(t) and 'ThreadMeta' or 'ThreadTitle' } } ---@type thread.Chunks
  vim.list_extend(out, labels.badges(t, true))
  local closed = labels.closed(t)
  if closed then
    vim.list_extend(out, { { '  ' }, closed })
  end
  local steps = 0
  for _, c in ipairs(thread.conversations(t)) do
    steps = steps + ((c.step and thread.for_you(r, c)) and 1 or 0)
  end
  if steps > 0 then
    out[#out + 1] = { '  ' .. text.plural(steps, 'step') .. ' for you', 'ThreadSignAnswered' }
  end
  return out
end

--- How many of its chunks you have accepted in it, of how many.
---@param r thread.Review
---@param t thread.Thread
---@return integer accepted, integer chunks
local function accepted(r, t)
  local all = thread.chunks(r, t)
  local yes = 0
  for _, c in ipairs(all) do
    yes = yes + (chunk.accepted(r, t, c) and 1 or 0)
  end
  return yes, #all
end

--- What a thread's line has on the right: how much of it you have
--- accepted, and who said the last few of its messages.
---@param r thread.Review
---@param t thread.Thread
---@return thread.Chunks
local function right(r, t)
  local out = {} ---@type thread.Chunks
  local yes, all = accepted(r, t)
  if all > 0 then
    out[#out + 1] = { string.format('✓ %d/%d  ', yes, all), yes == all and 'ThreadAccepted' or 'ThreadMeta' }
  end
  return vim.list_extend(out, labels.dots(t.messages, thread.read(r, thread.conversation(t))))
end

--- A thread in one row: its head; on the right, how much of it you have
--- accepted and who said its last few messages.
---@param P thread.Sheet
---@param r thread.Review
---@param t thread.Thread
---@param o thread.ThreadOpts
---@return thread.Part
function M.line(P, r, t, o)
  local row = draw.row(P, head(r, t), right(r, t), o.width, o.indent)
  return { kind = 'thread', first = row, last = row, thread = t }
end

--- What a thread is about, in a sentence: its introduction's first, when
--- the agent titled it; nothing when that is all its title says.
---@param t thread.Thread
---@return string|nil
local function gist(t)
  if not t.title then
    return nil
  end
  local s = prose.gist(t.messages[1] and t.messages[1].text)
  return s ~= '' and s ~= t.title and s or nil
end

-- What the diff did to a file, as git says it: new green, changed amber,
-- gone red.
local STATUS = {
  added = { 'A', 'ThreadFileAdded' },
  deleted = { 'D', 'ThreadFileDeleted' },
  modified = { 'M', 'ThreadFileModified' },
  binary = { 'M', 'ThreadFileModified' },
}

--- The files a thread's chunks are in, the most chunks first, each git's
--- letter for what the diff did to it, then its directory and name, as
--- many as fit in `room`; then how many more. A file the diff left alone,
--- code a step points at, is `·`. Nil when it has no chunks.
---@param r thread.Review
---@param t thread.Thread
---@param room integer
---@return thread.Chunks|nil
local function where(r, t, room)
  local count, list = {}, {} ---@type table<string, integer>, string[]
  for _, e in ipairs(files.of_thread(t)) do
    local f = e.chunk.file
    if not count[f] then
      list[#list + 1] = f
    end
    count[f] = (count[f] or 0) + 1
  end
  if #list == 0 then
    return nil
  end
  table.sort(list, function(a, b)
    if count[a] ~= count[b] then
      return count[a] > count[b]
    end
    return a < b
  end)
  local spec = chunk.spec(r.diff)
  local out, used = {}, 0 ---@type thread.Chunks, integer
  for i, f in ipairs(list) do
    local base = vim.fs.basename(f)
    local parent = vim.fs.basename(vim.fs.dirname(f))
    local d = spec and diff.file(spec, f)
    local st = d and (d.from and { 'R', 'ThreadFileModified' } or STATUS[d.status])
    local one = { { i > 1 and '    ' or '' } } ---@type thread.Chunks
    one[#one + 1] = st and { st[1] .. ' ', st[2] } or { '· ', 'ThreadFileSame' }
    one[#one + 1] = { ((parent ~= '' and parent ~= '.') and (parent .. '/') or '') .. base, 'ThreadFile' }
    local w = 0
    for _, c in ipairs(one) do
      w = w + text.width(c[1])
    end
    local rest = #list - i + 1
    -- Room kept for saying how many more, unless this is the last.
    if used + w > room - (rest > 1 and 12 or 0) then
      out[#out + 1] = { (i > 1 and '    ' or '') .. rest .. ' more', 'ThreadMeta' }
      break
    end
    vim.list_extend(out, one)
    used = used + w
  end
  return out
end

--- How a list of threads lines up, so each thing on a row is in its own
--- column: the title, how its conversations stand, how much of it you
--- have accepted. Widths in columns; 0 when no row has it.
---@class thread.RowColumns
---@field title integer
---@field moves integer
---@field accepted integer

--- How threads stand, for a row: how their conversations do, or how a
--- closed one was closed; how many of their chunks you have accepted.
---@param r thread.Review
---@param list thread.Thread[]
---@return thread.Chunks moves, thread.Chunks accepted
local function pieces(r, list)
  local moves = labels.moves(r, list)
  local closed = #list == 1 and labels.closed(list[1])
  if closed then
    moves = { { vim.trim(closed[1]), 'ThreadMeta' } }
  end
  local yes, all = 0, 0
  for _, t in ipairs(list) do
    local y, a = accepted(r, t)
    yes, all = yes + y, all + a
  end
  local acc = all > 0 and { { string.format('✓ %d/%d', yes, all), yes == all and 'ThreadAccepted' or 'ThreadMeta' } } or {}
  return moves, acc
end

-- Columns between two of a row's columns.
local GAP = 3

--- The columns rows line up in, across `width`: each the widest of its
--- kind, the title whatever is left, so the rest line up at the row's
--- end. A row is a thread, or the threads of a group added up.
---@param r thread.Review
---@param rows thread.Thread[][]
---@param width integer
---@return thread.RowColumns
function M.columns(r, rows, width)
  local c = { title = 0, moves = 0, accepted = 0 }
  for _, list in ipairs(rows) do
    local moves, acc = pieces(r, list)
    c.moves = math.max(c.moves, text.width(moves))
    c.accepted = math.max(c.accepted, text.width(acc))
  end
  local rest = 0
  for _, k in ipairs { 'moves', 'accepted' } do
    rest = rest + (c[k] > 0 and (c[k] + GAP) or 0)
  end
  -- The title takes the room the rest leave, so they sit at the row's end.
  c.title = math.max(12, width - rest)
  return c
end

--- Each thread of a list as a row of its own, for M.columns.
---@param list thread.Thread[]
---@return thread.Thread[][]
function M.each(list)
  return vim.tbl_map(function(t)
    return { t }
  end, list)
end

--- `chunks` filled out to `w` columns; on the right of it, when `flush`.
---@param chunks thread.Chunks
---@param w integer
---@param flush boolean|nil
---@return thread.Chunks
local function cell(chunks, w, flush)
  local out = text.fit_chunks(chunks, w)
  local fill = { string.rep(' ', math.max(0, w - text.width(out))) }
  if flush then
    table.insert(out, 1, fill)
  else
    out[#out + 1] = fill
  end
  return out
end

--- A row of the grid: its title, then how `list` stands, each in its
--- column; nothing past the last cell it fills, not even its padding.
---@param P thread.Sheet
---@param r thread.Review
---@param name thread.Chunks
---@param list thread.Thread[]
---@param c thread.RowColumns
---@param width integer
---@param indent integer
---@return integer row
function M.grid(P, r, name, list, c, width, indent)
  local moves, acc = pieces(r, list)
  local cells = { { name, c.title } }
  for _, k in ipairs { { moves, c.moves }, { acc, c.accepted, true } } do
    if k[2] > 0 then
      cells[#cells + 1] = k
    end
  end
  local last = 1
  for i, k in ipairs(cells) do
    last = #k[1] > 0 and i or last
  end
  local line = {} ---@type thread.Chunks
  for i = 1, last do
    if i > 1 then
      line[#line + 1] = { string.rep(' ', GAP) }
    end
    vim.list_extend(line, i == last and not cells[i][3] and text.fit_chunks(cells[i][1], cells[i][2]) or cell(cells[i][1], cells[i][2], cells[i][3]))
  end
  return P.chunks(text.fit_chunks(line, width), indent)
end

-- Columns a thread's files or gist hang in under its title.
M.HANG = 2

--- A thread in two rows, for a list on the screen, in the columns its
--- list lines up in: its title, how its conversations stand, how much of
--- it you have accepted; under its title, unless folded, the files its
--- chunks are in, or for a thread of only messages, what it is about.
---@param P thread.Sheet
---@param r thread.Review
---@param t thread.Thread
---@param o thread.ThreadOpts
---@return thread.Part
function M.row(P, r, t, o)
  local indent = o.indent or P.indent
  local c = o.columns or M.columns(r, { { t } }, o.width)
  local first = M.grid(P, r, { { title(t), thread.closed(t) and 'ThreadMeta' or 'ThreadTitle' } }, { t }, c, o.width, indent)
  local in_files = not o.fold and where(r, t, o.width - M.HANG)
  local about = not o.fold and not in_files and gist(t)
  if in_files then
    P.chunks(in_files, indent + M.HANG)
  elseif about then
    P.chunks({ { text.fit(about, o.width - M.HANG), 'ThreadMeta' } }, indent + M.HANG)
  end
  return { kind = 'thread', first = first, last = #P.lines - 1, thread = t, item = true }
end

--- A thread as a card: its head, then its last few messages, each cut
--- short; a row says how many came before.
---@param P thread.Sheet
---@param r thread.Review
---@param t thread.Thread
---@param o thread.ThreadOpts
---@return thread.Part[]  the thread, then what in it goes somewhere
function M.card(P, r, t, o)
  local indent = o.indent or P.indent
  local first = draw.row(P, head(r, t), right(r, t), o.width, indent)
  local out = { { kind = 'thread', first = first, last = first } } ---@type thread.Part[]
  P.add ''
  local own = thread.conversation(t)
  vim.list_extend(
    out,
    message.conversation(
      P,
      r,
      own,
      { width = o.width, indent = indent, most = o.most or message.MOST, brief = true, last = o.messages or message.LAST, cut = o.cut }
    )
  )
  out[1].last = #P.lines - 1
  draw.within(out, 1, { thread = t })
  return out
end

-- Rows of a message folded, until it is opened; the replies a thread
-- shows under its introduction until its conversation is opened.
M.FOLDED, M.REPLIES = 1, 3

--- A thread whole, on the screen: its head and labels; why it matters;
--- its chunk's code; its conversation, the introduction and every reply;
--- each tour its messages brought, as a section of steps or of its chunks
--- by file; its checks. Folded, each message is its first row; the code is shown
--- only with `code`, or where opened.
---@param P thread.Sheet
---@param r thread.Review
---@param t thread.Thread
---@param o thread.ThreadOpts
---@return thread.Part[]  the thread, then what in it goes somewhere
function M.whole(P, r, t, o)
  local indent = o.indent or P.indent
  local open = o.open or {}
  local own = thread.conversation(t)
  local left = { { '#' .. t.id .. '  ', 'ThreadMeta' }, { title(t), thread.closed(t) and 'ThreadMeta' or 'ThreadTitle' } } ---@type thread.Chunks
  local tags = labels.tags(t)
  if #tags > 0 then
    table.insert(tags, 1, { '  ' })
    vim.list_extend(left, tags)
  end
  local closed = labels.closed(t)
  if closed then
    vim.list_extend(left, { { '  ' }, closed })
  end
  local yes, all = accepted(r, t)
  local tail = all > 0 and { { string.format('✓ %d/%d', yes, all), yes == all and 'ThreadAccepted' or 'ThreadMeta' } } or {}
  local first = draw.row(P, left, tail, o.width, indent)
  local out = { { kind = 'thread', first = first, last = first, item = true } } ---@type thread.Part[]
  local risk = labels.risk(t)
  if risk and t.risk_why then
    draw.prose(prose.draw(P, t.risk_why, o.width, { indent = indent, lead = { 'why: ', risk[2] } }), out)
  end
  if t.chunk and o.code then
    P.add ''
    vim.list_extend(out, chunk_draw.draw(P, t.chunk, chunk.spec(r.diff), { width = o.width, indent = indent, accepted = chunk.accepted(r, t, t.chunk) }))
  end
  -- The conversation together, the introduction then the replies to it;
  -- then the tours its messages brought, in their order.
  -- One item, the conversation: the introduction and the last few
  -- replies, every one once it is opened.
  local every = open['message:0:1'] == true
  local from = every and 2 or math.max(2, #t.messages - M.REPLIES + 1)
  for _, i in ipairs(vim.list_extend({ 1 }, vim.fn.range(from, #t.messages))) do
    P.add ''
    if i == from and from > 2 then
      P.chunks({ { '⋯ ' .. text.plural(from - 2, 'earlier reply', 'earlier replies') .. '   o shows them', 'ThreadMeta' } }, indent)
      P.add ''
    end
    local at = #out + 1
    local whole = not o.fold or every
    vim.list_extend(out, message.draw(P, r, own, i, { width = o.width, indent = indent, intro = i == 1, most = not whole and M.FOLDED or nil }))
    out[at].item = i == 1
  end
  local place = 0
  for _, m in ipairs(t.messages) do
    for _, x in ipairs(m.tours or {}) do
      P.add ''
      place = place + 1
      local folded = (o.groups or {})[draw.key { kind = 'tour', first = 0, last = 0, tour = x }] == true
      vim.list_extend(
        out,
        tour.section(
          P,
          r,
          t,
          x,
          { width = o.width, indent = indent, open = open, files = o.files, fold = o.fold, code = o.code, folded = folded, place = place }
        )
      )
    end
  end
  for k, c in ipairs(t.checks or {}) do
    if k == 1 then
      P.add ''
      P.chunks(labels.rule('checks', o.width), indent)
    end
    P.add ''
    local at = #out + 1
    vim.list_extend(out, check.draw(P, c, { width = o.width, indent = indent }))
    out[at].item = true
  end
  out[1].last = #P.lines - 1
  draw.within(out, 1, { thread = t })
  return out
end

return M
