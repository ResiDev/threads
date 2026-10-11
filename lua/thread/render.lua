--- Threads in the code: a bubble above each thread's first line holding its
--- messages, and a bar in the sign column over every line it covers. The code
--- itself is never changed.
---
--- A bubble is as big as you make it: one line, or its last messages in full
--- (the default shows everything you have not read). The thread the cursor
--- is on lights up: its lines washed, its border bright, its keys listed
--- under it, and its notes on their lines.
---
--- A step of a tour is drawn the same way, as a card (thread.tour.display).
--- Until you reply in it it stays quiet, a sign only, unless it is the stop
--- you are walking or the cursor is on it: ten steps must not bury the code
--- in bubbles.

local anchor = require 'thread.anchor'
local config = require 'thread.config'
local store = require 'thread.store'
local tour = require 'thread.tour'

local M = {}

M.ns = vim.api.nvim_create_namespace 'thread'

-- 'full': each bubble at its own size; 'line': every bubble one line.
local mode = 'full'
-- Hidden: signs only, whatever the mode.
local hidden = false
-- batch id .. ':' .. comment id -> messages shown in full; 0 is one line.
local levels = {}
-- bufnr -> { id, here } for the thread the cursor is on.
local active = {}
-- Dim everything but the thread you are on.
local dimming = false
-- thread id -> true: its changes drawn into the code.
local drawn = {}

---@type table<integer, { comment: thread.Comment, line: integer, to: integer, stale: boolean|nil }[]>
M.placed = {}

local BORDER = {
  waiting = 'ThreadBorderWaiting',
  answered = 'ThreadBorderAnswered',
  info = 'ThreadBorderInfo',
  closed = 'ThreadSignDone',
}
local SIGN = {
  waiting = 'ThreadSignWaiting',
  answered = 'ThreadSignAnswered',
  info = 'ThreadSignInfo',
  closed = 'ThreadSignDone',
}
M.SIGN = SIGN

local width_of = vim.fn.strdisplaywidth
local LABEL = 3 -- `󰚩 ` before a message's text

--- Text broken into display lines no wider than `width`. Paragraphs keep
--- their breaks; fenced code is kept as it is, cut at the width.
---@param text string
---@param width integer
---@return { text: string, code: boolean }[]
function M.wrap(text, width)
  local out = {}
  local fenced, excerpt = false, nil
  for line in (text .. '\n'):gmatch '(.-)\r?\n' do
    if line:match '^%s*```' then
      fenced = not fenced
      -- A ```code fence holds an anchor, as in a tour: the code it points at.
      if fenced and line:match '^%s*```code%s*$' then
        excerpt = {}
      elseif not fenced and excerpt then
        local ok, a = pcall(vim.json.decode, table.concat(excerpt, '\n'))
        if ok and type(a) == 'table' and a.file then
          out[#out + 1] = { text = '▤ ' .. a.file .. (a.line and (':' .. a.line) or ''), code = true, excerpt = a }
        end
        excerpt = nil
      end
    elseif excerpt then
      excerpt[#excerpt + 1] = line
    elseif fenced then
      local cut = line
      while width_of(cut) > width do
        cut = vim.fn.strcharpart(cut, 0, vim.fn.strchars(cut) - 1)
      end
      out[#out + 1] = { text = cut, code = true }
    elseif line:match '^%s*$' then
      out[#out + 1] = { text = '' }
    else
      -- `code with spaces` wraps as one word: its spaces held as no-break
      -- spaces until the line is cut.
      line = line:gsub('`[^`]+`', function(code)
        return (code:gsub(' ', '\u{a0}'))
      end)
      local lead = line:match '^(%s*[-*] )' or line:match '^(%s*%d+[.)] )' or ''
      -- A list item's continuation lines hang under its text.
      local hang = string.rep(' ', width_of(lead))
      local cur = ''
      for word in line:sub(#lead + 1):gmatch '%S+' do
        local candidate = cur == '' and (lead .. word) or (cur .. ' ' .. word)
        if cur ~= '' and width_of(candidate) > width then
          out[#out + 1] = { text = cur }
          candidate = hang .. word
        end
        cur = candidate
        -- A word longer than the line is cut where it must be.
        while width_of(cur) > width do
          local head = vim.fn.strcharpart(cur, 0, width)
          while width_of(head) > width do
            head = vim.fn.strcharpart(head, 0, vim.fn.strchars(head) - 1)
          end
          out[#out + 1] = { text = head }
          cur = hang .. vim.fn.strcharpart(cur, vim.fn.strchars(head))
        end
      end
      if vim.trim(cur) ~= '' then
        out[#out + 1] = { text = cur }
      end
    end
  end
  while #out > 0 and out[#out].text == '' do
    out[#out] = nil
  end
  -- A **bold** run that a line break cuts goes on into the next line.
  local open = false
  for _, o in ipairs(out) do
    o.text = o.text:gsub('\u{a0}', ' ')
    if not o.code then
      o.bold = open
      local _, n = o.text:gsub('%*%*', '')
      if n % 2 == 1 then
        open = not open
      end
      if o.text == '' then
        open = false
      end
    end
  end
  return out
end

--- One line of prose as chunks: `code` picked out, **bold** made bold.
--- `bold` carries a bold run over from the line before.
function M.segments(line)
  if line.code then
    return { { line.text, 'ThreadCode' } }
  end
  local chunks = {}
  local function plain(text, hl)
    -- A link to a thread, `#12`, or to a stop of its tour, `#12.3`.
    local pos = 1
    for a, link, b in text:gmatch '()(#%d+%.?%d*)()' do
      local before = a > 1 and text:sub(a - 1, a - 1) or ' '
      -- Not a colour, `#4acbe1`, nor inside a word.
      if not before:match '[%w#]' and not text:sub(b, b):match '[%w_]' then
        if a > pos then
          chunks[#chunks + 1] = { text:sub(pos, a - 1), hl }
        end
        link = link:gsub('%.$', '')
        chunks[#chunks + 1] = { link, 'ThreadLink' }
        pos = a + #link
      end
    end
    if pos <= #text then
      chunks[#chunks + 1] = { text:sub(pos), hl }
    end
  end
  local function prose(text)
    -- **bold**, its markers dropped; a run left open goes on to the end.
    local pos = 1
    while pos <= #text do
      local s = text:find('**', pos, true)
      if not s then
        plain(text:sub(pos), line.bold and 'ThreadPoint' or 'ThreadText')
        break
      end
      if s > pos then
        plain(text:sub(pos, s - 1), line.bold and 'ThreadPoint' or 'ThreadText')
      end
      line.bold = not line.bold
      pos = s + 2
    end
  end
  local pos = 1
  for s, code, e in line.text:gmatch '()`([^`]+)`()' do
    if s > pos then
      prose(line.text:sub(pos, s - 1))
    end
    chunks[#chunks + 1] = { code, 'ThreadCode' }
    pos = e
  end
  if pos <= #line.text then
    prose(line.text:sub(pos))
  end
  return chunks
end

--- The link to a thread under column `col` (0-based) of `text`: `#12`, or
--- `#12.3` for stop 3 of its tour.
---@return integer|nil id, integer|nil n
function M.link_at(text, col)
  for a, id, n, b in text:gmatch '()#(%d+)%.?(%d*)()' do
    if col >= a - 1 and col < b - 1 and not text:sub(b, b):match '[%w_]' then
      return tonumber(id), tonumber(n)
    end
  end
end

--- Open what a link names: the thread, or the stop of its tour.
---@return boolean  whether there was one
function M.follow_link(id, n)
  local batch = store.active()
  local c = batch and id and store.find(batch, id)
  if not c then
    if id then
      vim.notify('thread: there is no thread ' .. id)
    end
    return false
  end
  if n and tour.of(c) then
    require('thread.walk').start(c.id, n)
  else
    require('thread.home').focus { comment = c }
  end
  return true
end

--- `s` cut to `w` display columns, with an ellipsis when cut.
local function fit(s, w)
  if w <= 0 then
    return ''
  end
  if width_of(s) <= w then
    return s
  end
  local out = vim.fn.strcharpart(s, 0, w - 1)
  while width_of(out) > w - 1 do
    out = vim.fn.strcharpart(out, 0, vim.fn.strchars(out) - 1)
  end
  return out .. '…'
end

local function first_line(text)
  return ((text or ''):match '^%s*([^\n]*)' or ''):gsub('`', '')
end

--- A mapping as it reads in a hint: `<leader>hr` as `␣hr`.
function M.key(action)
  return M.show_key(config.options.mappings[action])
end

--- Any mapping as it reads in a hint.
---@param lhs string|false|nil
---@return string|nil
function M.show_key(lhs)
  if not lhs then
    return nil
  end
  local leader = vim.g.mapleader == ' ' and '␣' or (vim.g.mapleader or '\\')
  return (lhs:gsub('<leader>', leader))
end

----------------------------------------------------------------------
-- Glyphs, shared with Home
----------------------------------------------------------------------

--- Whose move it is, as a glyph: an envelope when it is yours (sealed
--- when there is something new, open once read), while it is the agent's
--- an envelope on its way, a map for a tour or explanation (nobody's), a check
--- when closed. Without `ui.icons`: ● ○ ◔ ◇ · ✓.
---@param status string
---@param unseen boolean|nil
---@param stale boolean|nil
---@return string glyph, string hl
function M.glyph(status, unseen, stale)
  local nerd = config.options.ui.icons ~= false
  if status == 'closed' then
    return nerd and '󰗡' or '✓', 'ThreadSignDone'
  elseif stale then
    return '!', 'DiagnosticWarn'
  elseif status == 'waiting' then
    return nerd and '󱡯' or '◔', 'ThreadSignWaiting'
  elseif status == 'info' then
    if unseen then
      return nerd and '󰍍' or '◇', 'ThreadSignInfoNew'
    end
    return nerd and '󰦂' or '·', 'ThreadSignInfo'
  elseif unseen then
    return nerd and '󰇮' or '●', 'ThreadSignAnswered'
  end
  return nerd and '󰗯' or '○', 'ThreadSignAnswered'
end

--- Who wrote a message, as a shape: a person for you, a robot for the
--- agent, lit when you have not read it. With `ui.icons` off, ● you and ▲
--- the agent, △ unread.
---@param m table  the message
---@param unread boolean|nil
---@return string glyph, string hl
function M.who(m, unread)
  local nerd = config.options.ui.icons ~= false
  if m.from == 'you' then
    return nerd and '󰀄' or '●', 'ThreadDotYou'
  elseif unread then
    return nerd and '󰚩' or '△', 'ThreadDotAgentNew'
  end
  return nerd and '󰚩' or '▲', 'ThreadDotAgent'
end

--- A message's label: its shape, `󰚩`.
---@return string label, string hl
function M.label(m, unread)
  local g = M.who(m, unread)
  if m.from == 'you' then
    return g, 'ThreadYou'
  end
  return g, unread and 'ThreadAgentNew' or 'ThreadAgent'
end

--- How wide a message's text runs, of the room a conversation has: four
--- fifths, so the agent's stop short on the right and yours on the left.
---@param width integer  the room, label included
---@param label integer  the label's width
function M.side(width, label)
  return math.max(16, math.floor(width * 0.8) - label)
end

--- The last few messages, a shape each for who wrote it.
M.DOTS = 5
M.DOTS_WIDTH = 2 + M.DOTS * 2
---@param thread table[]
---@param seen integer  messages seen
---@return { [1]: string, [2]: string }[]
function M.dots(thread, seen)
  local out = { { #thread > M.DOTS and '… ' or ' ', 'ThreadMeta' } }
  local from = math.max(1, #thread - M.DOTS + 1)
  for i = from, #thread do
    local g, hl = M.who(thread[i], thread[i].from ~= 'you' and i > seen)
    out[#out + 1] = { g .. (i < #thread and ' ' or ''), hl }
  end
  return out
end

-- A verdict's badge colour: a defect, a cost to weigh, an explanation, fine.
local VERDICT_HL = {
  bug = 'ThreadVerdictBad',
  flaw = 'ThreadVerdictBad',
  risk = 'ThreadVerdictWarn',
  ['trade-off'] = 'ThreadVerdictWarn',
  decision = 'ThreadVerdictInfo',
  ['how it works'] = 'ThreadVerdictInfo',
  fine = 'ThreadVerdictGood',
}

-- A review group's kind: new things green, fixes red, the routine quiet.
local KIND_HL = {
  feat = 'ThreadVerdictGood',
  fix = 'ThreadVerdictBad',
  perf = 'ThreadVerdictWarn',
  refactor = 'ThreadVerdictInfo',
  test = 'ThreadVerdictInfo',
  docs = 'ThreadKindQuiet',
  chore = 'ThreadKindQuiet',
  style = 'ThreadKindQuiet',
}

--- A review group's kind as a badge: ` feat `.
---@param kind string|nil
---@return { [1]: string, [2]: string }|nil
function M.kind_badge(kind)
  if type(kind) ~= 'string' or kind == '' then
    return nil
  end
  return { ' ' .. kind .. ' ', KIND_HL[kind] or 'ThreadKindQuiet' }
end

-- How risky a group is: a shape and a colour, so it reads without either.
local RISK = {
  high = { '●', 'ThreadRiskHigh' },
  medium = { '◐', 'ThreadRiskMedium' },
  low = { '○', 'ThreadRiskLow' },
}

--- A review group's risk: `● high risk`, or short, `●`.
---@param risk string|nil
---@param short boolean|nil
---@return { [1]: string, [2]: string }|nil
function M.risk(risk, short)
  local r = RISK[risk]
  if not r then
    return nil
  end
  return { short and r[1] or (r[1] .. ' ' .. risk .. ' risk'), r[2] }
end

--- The verdict of a thread's latest message that has one, as a badge.
---@param comment thread.Comment
---@return { text: string, hl: string }|nil
function M.verdict_of(comment)
  for i = #comment.messages, 1, -1 do
    local m = comment.messages[i]
    if type(m.verdict) == 'string' and m.verdict ~= '' then
      return {
        text = m.verdict:upper() .. ((type(m.severity) == 'string' and m.severity ~= '') and (' · ' .. m.severity) or ''),
        hl = VERDICT_HL[m.verdict] or 'ThreadVerdictInfo',
      }
    end
  end
end

----------------------------------------------------------------------
-- Sizes
----------------------------------------------------------------------

local function key_of(batch, comment)
  return (batch and batch.id or '') .. ':' .. comment.id
end

--- How many of a thread's messages its bubble shows in full; 0 is one line.
---@param batch thread.Batch|nil
---@param comment thread.Comment
---@return integer
function M.level(batch, comment)
  local set = levels[key_of(batch, comment)]
  if set then
    return math.min(set, #comment.messages)
  end
  if mode == 'line' or store.status(comment) == 'closed' then
    return 0
  end
  -- Everything you have not read, and at least the last message.
  local seen = batch and store.seen_count(batch, comment) or 0
  return math.max(1, math.min(#comment.messages, #comment.messages - seen))
end

--- Whether a thread's size was set by hand.
function M.set_level(batch, comment)
  return levels[key_of(batch, comment)] ~= nil
end

--- A thread's bubble to one line, or whole.
---@param batch thread.Batch
---@param comment thread.Comment
function M.fold(batch, comment)
  local whole = M.level(batch, comment) == 0
  -- The stop you are walking shows whole until set otherwise.
  local w = require('thread.walk').state()
  if comment.stop and w and w.owner == comment.stop.owner and w.n == comment.stop.n and not M.set_level(batch, comment) then
    whole = false
  end
  levels[key_of(batch, comment)] = whole and #comment.messages or 0
end

--- Show `n` more (or fewer) of a thread's messages.
---@param batch thread.Batch
---@param comment thread.Comment
---@param n integer
function M.resize(batch, comment, n)
  local cur = M.level(batch, comment)
  levels[key_of(batch, comment)] = math.max(0, math.min(#comment.messages, cur + n))
end

----------------------------------------------------------------------
-- The bubble
----------------------------------------------------------------------

---@class thread.BubbleOpts
---@field level integer|nil   messages in full; 0 is one line
---@field active boolean|nil  the cursor is on its lines: keys shown
---@field here integer|nil    comments on the cursor's line
---@field seen integer|nil    messages seen
---@field stale boolean|nil   its line is gone

--- A tour's stop you have replied in, not waiting on the agent: both a
--- tour and a conversation, so drawn between their colours.
---@param comment thread.Comment
---@return boolean
function M.both(comment)
  return comment.stop ~= nil and not comment.virtual and store.status(comment) ~= 'waiting' and store.status(comment) ~= 'closed'
end

--- The keys a bubble lists while the cursor is on it.
local function hints(comment, o)
  local list = {}
  -- Everything else (reply, close, the history) is done in the float ⏎
  -- opens: one key to learn here.
  list[#list + 1] = { '⏎', 'open' }
  if o.walking then
    local w = config.options.walk
    if w.next then
      list[#list + 1] = { M.show_key(w.next) .. '/' .. (M.show_key(w.prev) or ''), 'next/prev' }
    end
    local batch = store.active()
    local rv = batch and comment.stop and require('thread.review').owner_of(batch, comment)
    if rv and w.up then
      list[#list + 1] = { M.show_key(w.up), 'the review' }
    end
    if w.quit then
      list[#list + 1] = { M.show_key(w.quit), 'end' }
    end
  elseif comment.stop or o.leads then
    local key = M.key 'walk'
    if key then
      list[#list + 1] = { key, comment.stop and 'walk from here' or 'walk it' }
    end
  end
  local z = config.options.zone or {}
  if (o.here or 1) > 1 and not o.walking and z.next then
    -- Cards stacked on this line: this one on top, the key to the next.
    local key = M.show_key(z.next):gsub('<S%-Tab>', 'S-tab')
    list[#list + 1] = { key, o.here == 2 and 'the other card here' or string.format('next of %d cards here', o.here) }
  end
  if not o.stale and z.fold then
    list[#list + 1] = { M.show_key(z.fold):gsub('<Tab>', 'tab'), (o.level or 1) == 0 and 'whole' or 'fold' }
  end
  return list
end

local function hint_chunks(list)
  local out = {}
  for i, k in ipairs(list) do
    if i > 1 then
      out[#out + 1] = { '  ', 'ThreadKeyLabel' }
    end
    out[#out + 1] = { k[1], 'ThreadKey' }
    out[#out + 1] = { ' ' .. k[2], 'ThreadKeyLabel' }
  end
  return out
end

local function chunks_width(chunks)
  local w = 0
  for _, c in ipairs(chunks) do
    w = w + width_of(c[1])
  end
  return w
end

--- One line: glyph, id, title, dots, and the last message trailing off, or
--- the keys when the cursor is on it.
local function line_bubble(comment, indent, width, o)
  local status = store.status(comment)
  local closed = status == 'closed'
  local thread = comment.messages
  local seen = o.seen or #thread
  local g, ghl = M.glyph(status, seen < #thread and thread[#thread].from ~= 'you', o.stale)
  local dim = closed and 'ThreadSignDone' or nil
  local row = { { string.rep(' ', indent), 'Normal' }, { g .. ' ', ghl }, { (o.crumb and o.crumb.pos or comment.id) .. ' ', dim or (o.crumb and 'ThreadCrumbHere' or 'ThreadMeta') } }
  local title = store.title(comment)
  local tail
  if o.active then
    tail = hint_chunks(hints(comment, o))
  elseif o.stale then
    tail = { { 'its line is gone', 'DiagnosticWarn' } }
  else
    local last = thread[#thread]
    local who, who_hl = '', 'ThreadMeta'
    if last then
      who, who_hl = M.label(last)
    end
    tail = { { who .. ' ', dim or who_hl } }
    if #thread > 1 or comment.title then
      tail[#tail + 1] = { first_line(last and last.text), dim or 'ThreadMeta' }
    end
  end
  local dots = M.dots(thread, seen)
  if closed or comment.virtual then
    dots = { { '', 'ThreadMeta' } }
  end
  local used = indent + 2 + width_of((o.crumb and o.crumb.pos or comment.id) .. ' ') + chunks_width(dots) + 2
  -- The keys are never cut, so the title gives way to them; else the
  -- title comes first and the last message trails off after it.
  local room = o.active and (width - used - chunks_width(tail) - 2) or (width - used - 16)
  local title_w = math.min(width_of(title), math.max(12, room), 40)
  row[#row + 1] = { fit(title, title_w) .. ' ', dim or 'ThreadTitle' }
  vim.list_extend(row, dots)
  row[#row + 1] = { '  ', 'Normal' }
  -- What is left of the width for the tail; the keys are never cut.
  local left = width + indent - chunks_width(row)
  if o.active then
    vim.list_extend(row, tail)
  else
    for _, c in ipairs(tail) do
      local s = fit(c[1], left)
      left = left - width_of(s)
      row[#row + 1] = { s, c[2] }
    end
  end
  return { row }
end

--- How long ago an ISO time was, in words: `just now`, `12m ago`, `3h ago`.
---@param stamp string|nil
---@return string|nil
function M.ago(stamp)
  local y, mo, d, h, mi, s = (stamp or ''):match '(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)'
  if not y then
    return nil
  end
  local secs = os.time() - os.time { year = y, month = mo, day = d, hour = h, min = mi, sec = s }
  if secs < 90 then
    return 'just now'
  elseif secs < 5400 then
    return math.floor(secs / 60 + 0.5) .. 'm ago'
  elseif secs < 129600 then
    return math.floor(secs / 3600 + 0.5) .. 'h ago'
  end
  return math.floor(secs / 86400 + 0.5) .. 'd ago'
end

--- Your message, the way a chat draws it: narrower than the agent's and
--- set in on the left, so yours line up on the right, `you` before the
--- first line. As rows of chunks, each `width` columns at most.
---@param text string|nil
---@param width integer  the room the conversation has
---@param label integer  the label's column width
---@param time string|nil  when, shown to the left of it
---@return table[][]
function M.chat(text, width, label, time)
  local room = M.side(width, label)
  local lines = M.wrap(text or '', room)
  if #lines == 0 then
    lines = { { text = '' } }
  end
  local off = math.max(0, width - label - room)
  local out = {}
  for j, l in ipairs(lines) do
    local r = { { string.rep(' ', off), 'ThreadText' } }
    if j == 1 and time and off >= width_of(time) + 2 then
      r = { { string.rep(' ', off - width_of(time) - 2), 'ThreadText' }, { time .. '  ', 'ThreadMeta' } }
    end
    if j == 1 then
      local you = M.label { from = 'you' }
      r[#r + 1] = { you .. string.rep(' ', label - width_of(you)), 'ThreadYou' }
    else
      r[#r + 1] = { string.rep(' ', label), 'ThreadText' }
    end
    vim.list_extend(r, M.segments(l))
    out[#out + 1] = r
  end
  return out
end

--- The bubble for a comment, as virtual lines.
---@param comment thread.Comment
---@param indent integer  the code line's indent, in columns
---@param room integer    the window's text width
---@param o thread.BubbleOpts|nil
---@return table[][]
function M.bubble(comment, indent, room, o)
  o = o or {}
  local width = math.max(24, math.min(config.options.ui.width, room - indent - 6))
  local level = o.level or math.max(1, #comment.messages - (o.seen or 0))
  if level == 0 or o.stale then
    return line_bubble(comment, indent, math.min(room - indent - 1, width + 8), o)
  end
  local status = store.status(comment)
  local border = o.active and SIGN[status] or BORDER[status] or 'ThreadBorderInfo'
  if M.both(comment) then
    border = o.active and 'ThreadSignBoth' or 'ThreadBorderBoth'
  end
  local thread = comment.messages
  local seen = o.seen or #thread
  -- A tour's stop: its first message is what the stop says, written by no
  -- one in particular, so it has no label and runs the full width.
  local stop = comment.stop ~= nil
  local text_w = width - LABEL

  local rows = {}
  local function row(label, label_hl, chunks)
    local r = { { label .. string.rep(' ', LABEL - width_of(label)), label_hl } }
    vim.list_extend(r, chunks)
    rows[#rows + 1] = r
  end
  local function plain(chunks)
    rows[#rows + 1] = chunks
  end
  -- What a message carries besides its text, each on a quiet line.
  local function extras(m, put)
    if m.changes and #m.changes > 0 then
      local places = vim.tbl_map(function(c)
        return vim.fn.fnamemodify(c.file, ':t') .. ':' .. (c.line or '?')
      end, m.changes)
      put { { fit('changed ' .. table.concat(places, ', '), text_w), 'ThreadFold' } }
    end
    if m.diagram and type(m.diagram) == 'table' then
      local n = #(m.diagram.nodes or m.diagram.participants or {})
      put { { string.format('▸ %s diagram%s · ⏎ shows it', m.diagram.kind or '', n > 0 and (', ' .. n .. ' boxes') or ''), 'ThreadFold' } }
    end
    if m.notes and #m.notes > 0 and not o.active then
      put { { string.format('%d note%s on its lines', #m.notes, #m.notes == 1 and '' or 's'), 'ThreadFold' } }
    end
  end
  local function labelled(chunks)
    row('', 'ThreadText', chunks)
  end

  local from = math.max(1, #thread - level + 1)
  local first = 1
  if stop then
    first = 2
    if from > 1 then
      plain(M.segments { text = fit(first_line(thread[1].text), width) })
    else
      for _, l in ipairs(M.wrap(thread[1].text or '', width)) do
        plain(M.segments(l))
      end
      extras(thread[1], plain)
    end
    if #thread > 1 then
      -- Below the stop's words, a rule, then the conversation in it.
      rows[#rows + 1] = {}
      plain { { string.rep('─', width), border } }
    end
  end
  local start = math.max(first, from)
  if start > first and not stop then
    if thread[1].from == 'you' then
      plain(M.chat(fit(first_line(thread[1].text), math.floor(width * 0.8) - LABEL), width, LABEL)[1])
    else
      local label, label_hl = M.label(thread[1])
      row(label, label_hl, { { fit(first_line(thread[1].text), text_w), 'ThreadText' } })
    end
  end
  local skipped = start - first - (stop and 0 or 1)
  if skipped > 0 then
    row('', 'ThreadText', { { string.format('⋯ %d earlier', skipped), 'ThreadFold' } })
  end
  for i = start, #thread do
    local m = thread[i]
    if #rows > 0 then
      rows[#rows + 1] = {}
    end
    local agent = m.from ~= 'you'
    if agent then
      local lines = M.wrap(m.text or '', M.side(width, LABEL))
      if #lines == 0 then
        lines = { { text = '' } }
      end
      for j, l in ipairs(lines) do
        if j == 1 then
          local label, label_hl = M.label(m, i > seen)
          row(label, label_hl, M.segments(l))
        else
          row('', 'ThreadText', M.segments(l))
        end
      end
    else
      for _, r in ipairs(M.chat(m.text, width, LABEL)) do
        plain(r)
      end
    end
    extras(m, labelled)
  end
  -- Where the answer leads: a tour.
  if o.leads then
    rows[#rows + 1] = {}
    labelled { { '▶ leads to ' .. o.leads, 'ThreadLeads' } }
  end

  -- The top edge. A stop: a badge saying where it is in its tour, and its
  -- title. A thread: whose move it is, its id, its name.
  local note = status == 'waiting' and ' · waiting' or ''
  local label = {}
  if stop and o.crumb then
    -- Where it is in its tour: the count, and beside it how far through.
    label[#label + 1] = { ' ▶ ' .. o.crumb.count .. ' ', 'ThreadStopBadge' }
    label[#label + 1] = { ' ', border }
    vim.list_extend(label, o.crumb.track)
    -- Its title, never cut: the card widens for it, and when the window
    -- is too narrow even so, the title is the card's first lines instead.
    local title = comment.title or store.title(comment)
    local room_top = room - indent - 12 - chunks_width(label)
    if width_of(title) <= room_top - 2 then
      label[#label + 1] = { '  ', border }
      label[#label + 1] = { title, 'ThreadTitle' }
    else
      local lines = M.wrap('**' .. title .. '**', width)
      for k = #lines, 1, -1 do
        table.insert(rows, 1, M.segments(lines[k]))
      end
      table.insert(rows, #lines + 1, {})
    end
  else
    local g, ghl = M.glyph(status, seen < #thread and thread[#thread].from ~= 'you')
    label[#label + 1] = { g .. ' ', ghl }
    label[#label + 1] = { tostring(comment.id), border }
    if comment.title then
      label[#label + 1] = { ' · ', border }
      label[#label + 1] = { fit(comment.title, width - 24), 'ThreadTitle' }
    end
    label[#label + 1] = { note, 'ThreadMeta' }
  end
  local verdict = M.verdict_of(comment)
  if verdict then
    label[#label + 1] = { ' ', border }
    label[#label + 1] = { ' ' .. verdict.text .. ' ', verdict.hl }
  end
  -- The tour's name, unless the winbar is already saying it.
  if o.crumb and o.crumb.head and not o.walking then
    label[#label + 1] = { ' · ' .. fit(o.crumb.head, 24), 'ThreadCrumb' }
  end
  local dots = comment.virtual and { { '', 'ThreadMeta' } } or M.dots(thread, seen)
  local keys = o.active and hint_chunks(hints(comment, o)) or nil

  -- Padding: a blank line inside the top and bottom edges, two columns at
  -- the sides.
  local PADX = 2
  table.insert(rows, 1, {})
  rows[#rows + 1] = {}
  local widest = 0
  for _, r in ipairs(rows) do
    r.width = chunks_width(r)
    widest = math.max(widest, r.width)
  end
  local inner = math.max(widest + PADX * 2, chunks_width(label) + chunks_width(dots) + 8, keys and (chunks_width(keys) + 6) or 0)
  inner = math.min(inner, math.max(widest + PADX * 2, room - indent - 3))

  local lead = { string.rep(' ', indent), 'Normal' }
  local out = {}
  local top = { lead, { '╭─ ', border } }
  vim.list_extend(top, label)
  top[#top + 1] = { ' ' .. string.rep('─', math.max(1, inner - 5 - chunks_width(label) - chunks_width(dots))), border }
  vim.list_extend(top, dots)
  top[#top + 1] = { ' ─╮', border }
  out[1] = top
  for _, r in ipairs(rows) do
    local line = { lead, { '│', border }, { string.rep(' ', PADX), 'ThreadText' } }
    vim.list_extend(line, r)
    line[#line + 1] = { string.rep(' ', math.max(0, inner - PADX - (r.width or 0))), 'ThreadText' }
    line[#line + 1] = { '│', border }
    out[#out + 1] = line
  end
  -- The keys at the bottom right.
  local bottom = { lead, { '╰┬', border } }
  if keys then
    bottom[#bottom + 1] = { string.rep('─', math.max(1, inner - 4 - chunks_width(keys))) .. ' ', border }
    vim.list_extend(bottom, keys)
    bottom[#bottom + 1] = { ' ─╯', border }
  else
    bottom[#bottom + 1] = { string.rep('─', inner - 1) .. '╯', border }
  end
  out[#out + 1] = bottom
  -- Room around it: a blank line above, and below only the stem down to
  -- its line, so no code presses against the card.
  table.insert(out, 1, { { '', 'Normal' } })
  out[#out + 1] = { lead, { ' │', border } }
  return out
end

----------------------------------------------------------------------
-- Where comments are, and which one the cursor is on
----------------------------------------------------------------------

--- Where the active batch's comments sit in a buffer. An open comment whose
--- line is gone sits where its line was, marked stale.
---@param bufnr integer
---@return { comment: thread.Comment, line: integer, to: integer, confidence: number, stale: boolean|nil }[]
function M.locate(bufnr)
  local where = anchor.of_buf(bufnr)
  local batch = where and store.active()
  if not batch then
    return {}
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local out = {}
  -- Every thread, but a reply in a tour's step is drawn as that step's card
  -- with the conversation in it, and every step no one replied in too.
  local all = {}
  for _, c in ipairs(batch.data.threads) do
    if not (type(c.on) == 'table' and store.anchored(c)) then
      all[#all + 1] = c
    end
  end
  -- While walking, the other tours' stops no one replied in are hidden.
  local walk = require('thread.walk').state()
  for _, c in ipairs(tour.cards(batch)) do
    if not (walk and c.virtual and c.stop.owner ~= walk.owner) then
      all[#all + 1] = c
    end
  end
  for _, c in ipairs(all) do
    if anchor.belongs(c, where) then
      local loc = anchor.locate(c, lines)
      if loc then
        out[#out + 1] = {
          comment = c,
          line = loc.line,
          to = math.min(#lines, loc.line + (c.lines or 1) - 1),
          confidence = loc.confidence,
        }
      elseif store.status(c) ~= 'closed' and not c.virtual and #lines > 0 then
        local line = math.max(1, math.min(#lines, c.line or 1))
        out[#out + 1] = { comment = c, line = line, to = line, confidence = 0, stale = true }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.line ~= b.line then
      return a.line < b.line
    end
    return tostring(a.comment.id) < tostring(b.comment.id)
  end)
  return out
end

--- The comments covering `lnum`, innermost first: the smallest range, then
--- the one starting latest.
---@param placed table[]
---@param lnum integer
---@return table[]
function M.covering(placed, lnum)
  local out = {}
  for _, p in ipairs(placed) do
    if lnum >= p.line and lnum <= p.to then
      out[#out + 1] = p
    end
  end
  table.sort(out, function(a, b)
    local sa, sb = a.to - a.line, b.to - b.line
    if sa ~= sb then
      return sa < sb
    end
    if a.line ~= b.line then
      return a.line > b.line
    end
    -- A conversation before a card no one has replied in.
    if (a.comment.virtual or false) ~= (b.comment.virtual or false) then
      return not a.comment.virtual
    end
    return tostring(a.comment.id) < tostring(b.comment.id)
  end)
  return out
end

local function room_for(bufnr)
  local win = vim.fn.bufwinid(bufnr)
  if win == -1 then
    return 100
  end
  return vim.api.nvim_win_get_width(win) - vim.fn.getwininfo(win)[1].textoff
end

--- Mark a thread read once its bubble has shown you all of it: when the
--- cursor leaves it, so what was new stays marked while you read.
local function leave_active(bufnr)
  local a = active[bufnr]
  if not (a and a.full) then
    return
  end
  local batch = store.active()
  local c = batch and store.find(batch, a.id)
  if c then
    store.mark_seen(batch, c)
  end
end

--- Work out which comment the cursor is on in `bufnr`; true if it changed.
---@param bufnr integer
---@return boolean
function M.track(bufnr)
  local placed = M.placed[bufnr]
  local win = vim.api.nvim_get_current_win()
  local now
  if placed and not hidden and vim.api.nvim_win_get_buf(win) == bufnr then
    local here = M.covering(placed, vim.api.nvim_win_get_cursor(win)[1])
    if #here > 0 then
      local keep = active[bufnr]
      -- Stay on the one picked (by focusing it, say) while it still covers
      -- the line; else the innermost.
      local pick = here[1]
      for _, p in ipairs(here) do
        if keep and p.comment.id == keep.id and keep.pinned then
          pick = p
        end
      end
      now = { id = pick.comment.id, here = #here, pinned = keep and keep.pinned and keep.id == pick.comment.id }
    end
  end
  local before = active[bufnr]
  if (before and before.id) == (now and now.id) and (before and before.here) == (now and now.here) then
    return false
  end
  if before and (not now or now.id ~= before.id) then
    leave_active(bufnr)
  end
  active[bufnr] = now
  return true
end

--- The comment the cursor is on in the current buffer, and how many cover
--- the line.
---@return thread.Comment|nil, integer
function M.at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  if not M.placed[buf] then
    M.placed[buf] = M.locate(buf)
  end
  M.track(buf)
  local a = active[buf]
  if not a then
    -- Hidden bubbles still have comments under them.
    local here = M.covering(M.placed[buf], vim.api.nvim_win_get_cursor(0)[1])
    return here[1] and here[1].comment, #here
  end
  for _, p in ipairs(M.placed[buf]) do
    if p.comment.id == a.id then
      return p.comment, a.here
    end
  end
  return nil, 0
end

--- Make another of the comments on the cursor's line the current one.
---@param n integer
---@return thread.Comment|nil
function M.cycle(n)
  local buf = vim.api.nvim_get_current_buf()
  local placed = M.placed[buf] or {}
  local here = M.covering(placed, vim.api.nvim_win_get_cursor(0)[1])
  if #here == 0 then
    return nil
  end
  local at = 1
  for i, p in ipairs(here) do
    if active[buf] and p.comment.id == active[buf].id then
      at = i
    end
  end
  local pick = here[(at - 1 + n) % #here + 1]
  leave_active(buf)
  active[buf] = { id = pick.comment.id, here = #here, pinned = true }
  M.paint(buf)
  return pick.comment
end

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------

-- How each part of a tour's track is drawn: been, here, still to come.
M.TRACK = { done = 'ThreadLeads', here = 'ThreadTitle', left = 'ThreadMeta' }

--- A tour's track (thread.tour.track) as chunks to draw.
---@param list thread.Stop[]
---@param n integer
---@param hls table<string, string>|nil  in place of M.TRACK
function M.progress(list, n, hls)
  hls = hls or M.TRACK
  return vim.tbl_map(function(t)
    return { t[1], hls[t[2]] }
  end, tour.track(list, n))
end

--- Where a stop sits in its tour, for its card's top edge: `step 2/4`
--- and the tour's name.
local function crumb_of(batch, c)
  if not c.stop then
    return nil
  end
  local owner = store.find(batch, c.stop.owner)
  local list = owner and tour.of(owner)
  if not list then
    return nil
  end
  local pos = tour.position(list, c.stop.n)
  return { pos = pos, count = pos:gsub('^%a+ ', ''), head = store.title(owner), owner = owner.id, track = M.progress(list, c.stop.n) }
end

--- `2 stages · 4 steps`, when the thread's answer leads to a tour.
local function leads_of(c)
  local list = tour.of(c.real or c)
  return list and tour.describe(list) or nil
end

--- A stop no one has replied in, that you are not walking or on: a sign.
local function quiet(c, walk, is_cur)
  if is_cur or not c.virtual then
    return false
  end
  return not (walk and walk.owner == c.stop.owner and walk.n == c.stop.n)
end

--- The function or block around lines `lo`..`hi` of a buffer, by
--- treesitter; else the paragraph.
local function scope(bufnr, lo, hi)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if ok and parser then
    local tok, trees = pcall(parser.parse, parser)
    local root = tok and trees and trees[1] and trees[1]:root()
    local node = root and root:named_descendant_for_range(lo - 1, 0, hi - 1, 0)
    while node do
      local ty = node:type()
      if ty:find 'function' or ty:find 'method' or ty:find 'class' or ty:find 'impl' or ty:find 'struct' then
        local sr, _, er, ec = node:range()
        return sr + 1, ec == 0 and er or er + 1
      end
      node = node:parent()
    end
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  while lo > 1 and (lines[lo - 1] or ''):match '%S' do
    lo = lo - 1
  end
  while hi < #lines and (lines[hi + 1] or ''):match '%S' do
    hi = hi + 1
  end
  return lo, hi
end

local NUMS = { '①', '②', '③', '④', '⑤', '⑥', '⑦', '⑧', '⑨', '⑩', '⑪', '⑫', '⑬', '⑭', '⑮', '⑯', '⑰', '⑱', '⑲', '⑳' }
M.NUMS = NUMS

--- The notes of a thread's latest message that has any, on their lines: a
--- number, the note after the code or hung above it when it is long, the
--- line washed and its mark picked out.
local function paint_notes(bufnr, c, room)
  local notes
  for i = #c.messages, 1, -1 do
    if c.messages[i].notes and #c.messages[i].notes > 0 then
      notes = c.messages[i].notes
      break
    end
  end
  local where = anchor.of_buf(bufnr)
  if not (notes and where) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for k, n in ipairs(notes) do
    local note = vim.tbl_extend('keep', n, { file = c.file, rev = c.rev })
    if anchor.belongs(note, where) then
      local loc = anchor.locate(note, lines)
      if loc then
        local row = loc.line - 1
        local last = math.min(#lines, loc.line + (note.lines or 1) - 1) - 1
        local num = NUMS[k] or ('(' .. k .. ')')
        pcall(vim.api.nvim_buf_set_extmark, bufnr, M.ns, row, 0, {
          end_row = last + 1,
          end_col = 0,
          hl_eol = true,
          hl_group = 'ThreadNoteLine',
          priority = 12,
        })
        if type(note.mark) == 'string' and note.mark ~= '' then
          local s = (lines[loc.line] or ''):find(note.mark, 1, true)
          if s then
            pcall(vim.api.nvim_buf_set_extmark, bufnr, M.ns, row, s - 1, { end_col = s - 1 + #note.mark, hl_group = 'ThreadNoteMark', priority = 140 })
          end
        end
        local text = type(note.note) == 'string' and note.note or ''
        local free = room - width_of(lines[loc.line] or '') - 6
        if text == '' or width_of(text) <= free then
          pcall(vim.api.nvim_buf_set_extmark, bufnr, M.ns, row, 0, {
            virt_text = { { '  ' .. num, 'ThreadNoteNum' }, { text ~= '' and (' ' .. text) or '', 'ThreadNote' } },
            virt_text_pos = 'eol',
            priority = 130,
          })
        else
          local indent = width_of((lines[loc.line] or ''):match '^%s*')
          local rows = {}
          for i, l in ipairs(M.wrap(text, math.max(20, math.min(config.options.ui.width, room - indent - 6)))) do
            rows[#rows + 1] = { { string.rep(' ', indent), 'Normal' }, { i == 1 and (num .. ' ') or '  ', 'ThreadNoteNum' }, { l.text, 'ThreadNote' } }
          end
          pcall(vim.api.nvim_buf_set_extmark, bufnr, M.ns, row, 0, { virt_lines = rows, virt_lines_above = true, priority = 105 })
        end
      end
    end
  end
end

--- A thread's changes drawn into the code: what each replaced, hung above
--- the lines that replaced it, and those lines washed.
local function paint_changes(bufnr, batch, c)
  local where = anchor.of_buf(bufnr)
  if not where or where.rev then
    return
  end
  local git = require 'thread.git'
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i = #c.messages, 1, -1 do
    local m = c.messages[i]
    if m.changes and #m.changes > 0 then
      local base = git.base_for(batch, c, i)
      for _, ch in ipairs(m.changes) do
        if ch.file == where.file and base then
          local old = git.show(base, ch.file)
          if old then
            local loc = anchor.locate(ch, lines)
            local at = loc and loc.line or ch.line or 1
            local hunks, words = git.word_hunks(old, lines)
            local add = words and 'CodeDiffLineInsert' or 'DiffAdd'
            local del = words and 'CodeDiffLineDelete' or 'DiffDelete'
            for _, h in ipairs(hunks) do
              local s = h.new_start
              local e = h.new_count == 0 and s + 1 or s + h.new_count - 1
              if e >= at - 1 and s <= at + (ch.lines or 1) then
                local removed = {}
                for j = h.old_start, h.old_start + h.old_count - 1 do
                  removed[#removed + 1] = { { (old[j] or ''):gsub('\t', '    ') .. string.rep(' ', 200), del } }
                end
                if #removed > 0 then
                  local row = h.new_count == 0 and h.new_start or h.new_start - 1
                  pcall(vim.api.nvim_buf_set_extmark, bufnr, M.ns, math.min(row, #lines - 1), 0, {
                    virt_lines = removed,
                    virt_lines_above = h.new_count > 0 or row < #lines,
                    priority = 100,
                  })
                end
                if h.new_count > 0 then
                  pcall(vim.api.nvim_buf_set_extmark, bufnr, M.ns, h.new_start - 1, 0, {
                    end_row = h.new_start - 1 + h.new_count,
                    end_col = 0,
                    hl_eol = true,
                    hl_group = add,
                    priority = 11,
                  })
                end
              end
            end
          end
        end
      end
      return
    end
  end
end

--- Draw the bubbles and signs where they were last located.
---@param bufnr integer
function M.paint(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    M.placed[bufnr] = nil
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)
  -- A review's diff first, so the cards hang above its removed lines.
  require('thread.review').paint(bufnr, M.ns)
  local placed = M.placed[bufnr] or {}
  if #placed == 0 then
    return
  end
  local batch = store.active()
  local room = room_for(bufnr)
  local a = active[bufnr]
  local cur = a and a.id
  local walk = require('thread.walk').state()

  -- Which threads show a bubble: steps no one is walking or talking in
  -- stay quiet, a sign only.
  local shown = {}
  for _, p in ipairs(placed) do
    shown[p.comment.id] = not quiet(p.comment, walk, p.comment.id == cur)
  end

  -- Signs: one per line, deeper where threads overlap, in the colour of
  -- the current thread where it covers the line, else the innermost.
  local first, last = math.huge, 0
  for _, p in ipairs(placed) do
    first, last = math.min(first, p.line), math.max(last, p.to)
  end
  for lnum = first, last do
    local here = M.covering(placed, lnum)
    if #here > 0 then
      local pick = here[1]
      local open = 0
      for _, p in ipairs(here) do
        if p.comment.id == cur then
          pick = p
        end
        if store.status(p.comment) ~= 'closed' then
          open = open + 1
        end
      end
      local status = store.status(pick.comment)
      -- A thread is a bar; a tour's stop an arrow, in the light blue of
      -- tours until someone replies in it.
      local text = open == 0 and ' ·' or open > 1 and '▎▎' or ' ▎'
      if pick.comment.stop and open > 0 then
        text = open > 1 and '▎▸' or ' ▸'
      end
      pcall(vim.api.nvim_buf_set_extmark, bufnr, M.ns, lnum - 1, 0, {
        sign_text = pick.stale and ' !' or text,
        sign_hl_group = pick.stale and 'DiagnosticWarn' or (M.both(pick.comment) and 'ThreadSignBoth') or SIGN[status],
        line_hl_group = pick.comment.id == cur and not hidden and 'ThreadZone' or nil,
        priority = 20,
      })
    end
  end
  if hidden then
    return
  end

  -- The thread in focus here: the stop being walked when it is in this
  -- buffer, else the one the cursor is on. Its notes and its scope.
  local function walked(c)
    return walk and c.stop and c.stop.owner == walk.owner and c.stop.n == walk.n
  end
  local focus
  for _, p in ipairs(placed) do
    if walked(p.comment) then
      focus = p
    end
  end
  if not focus then
    for _, p in ipairs(placed) do
      if p.comment.id == cur then
        focus = p
      end
    end
  end
  if focus and not focus.stale then
    paint_notes(bufnr, focus.comment, room)
    if dimming then
      local lo, hi = scope(bufnr, focus.line, focus.to)
      local count = vim.api.nvim_buf_line_count(bufnr)
      if lo > 1 then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, M.ns, 0, 0, { end_row = lo - 1, end_col = 0, hl_group = 'ThreadDim', priority = 150 })
      end
      if hi < count then
        pcall(vim.api.nvim_buf_set_extmark, bufnr, M.ns, hi, 0, { end_row = count, end_col = 0, hl_group = 'ThreadDim', priority = 150 })
      end
    end
  end
  for _, p in ipairs(placed) do
    if drawn[(p.comment.real or p.comment).id] and batch then
      paint_changes(bufnr, batch, p.comment)
    end
  end

  -- Threads on the same line stack: the current one at its size, the
  -- others one line each, so a stack never pushes the code off screen.
  local lead_of = {}
  for _, p in ipairs(placed) do
    if shown[p.comment.id] and (not lead_of[p.line] or p.comment.id == cur or walked(p.comment)) then
      lead_of[p.line] = p.comment.id
    end
  end
  -- Virtual lines placed later sit above earlier ones on the same line, so
  -- walk backwards: the lowest-numbered thread ends up on top.
  for i = #placed, 1, -1 do
    local p = placed[i]
    local c = p.comment
    if shown[c.id] then
      local row = p.line - 1
      local text = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
      local indent = text:match '^%s*$' and 0 or width_of(text:match '^%s*')
      local level = M.level(batch, c)
      if lead_of[p.line] ~= c.id then
        level = 0
      end
      local crumb = batch and crumb_of(batch, c)
      local walking = walked(c)
      if walking and not M.set_level(batch, c) then
        -- The stop you are walking: its words and all the talk in it.
        level = #c.messages
      elseif c.virtual and not M.set_level(batch, c) then
        -- A stop you are not walking: one line under the cursor, enough
        -- to say what it is; Tab shows it whole.
        level = 0
      elseif walk and not (c.stop and c.stop.owner == walk.owner) and not M.set_level(batch, c) then
        -- Walking a tour, every other thread folds to a line.
        level = 0
      end
      local seen = batch and store.seen_count(batch, c) or #c.messages
      local is_cur = c.id == cur
      if is_cur then
        -- Read once it has all been on screen: everything after `seen`.
        a.full = level > 0 and #c.messages - level <= seen
      end
      pcall(vim.api.nvim_buf_set_extmark, bufnr, M.ns, row, 0, {
        virt_lines = M.bubble(c, indent, room, {
          level = level,
          active = is_cur or walking,
          here = a and a.here,
          seen = seen,
          stale = p.stale,
          crumb = crumb,
          walking = walking,
          leads = leads_of(c),
        }),
        virt_lines_above = true,
        priority = 110,
      })
    end
  end
end

--- Locate the comments in a buffer again, and draw them.
---@param bufnr integer
function M.draw(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    M.placed[bufnr] = nil
    return
  end
  M.placed[bufnr] = M.locate(bufnr)
  M.track(bufnr)
  M.paint(bufnr)
end

--- Redraw every buffer on screen.
function M.refresh()
  local seen = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if not seen[buf] then
      seen[buf] = true
      M.draw(buf)
    end
  end
  for buf in pairs(M.placed) do
    if not seen[buf] and vim.api.nvim_buf_is_valid(buf) then
      M.draw(buf)
    end
  end
end

local pending = false
function M.schedule()
  if pending then
    return
  end
  pending = true
  vim.defer_fn(function()
    pending = false
    M.refresh()
  end, 30)
end

--- The cursor moved: light up the comment it is on now, if that changed.
function M.cursor_moved()
  local buf = vim.api.nvim_get_current_buf()
  if M.placed[buf] and M.track(buf) then
    M.paint(buf)
  end
  M.show_top()
end

--- A card above the first line shows only as filler the window is
--- scrolled up to, and moving the cursor back to the top never scrolls
--- there. So while the top of the file is in view, near the cursor, show it.
function M.show_top()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  if not M.placed[buf] or vim.fn.line('w0', win) ~= 1 then
    return
  end
  local view = vim.fn.winsaveview()
  if view.topfill > 0 or view.lnum > vim.api.nvim_win_get_height(win) / 2 then
    return
  end
  local fill = 0
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, M.ns, { 0, 0 }, { 0, -1 }, { details = true })) do
    if m[4].virt_lines and m[4].virt_lines_above then
      fill = fill + #m[4].virt_lines
    end
  end
  if fill > 0 then
    vim.fn.winrestview { topline = 1, topfill = fill }
  end
end

--- Every bubble at its own size, or one line each.
---@return 'full'|'line'
function M.toggle()
  mode = mode == 'full' and 'line' or 'full'
  -- A new mode applies to every bubble: sizes set by hand go.
  levels = {}
  hidden = false
  M.refresh()
  return mode
end

---@return 'full'|'line'
function M.mode()
  return mode
end

--- Hide every bubble, leaving the signs, or show them again.
---@return boolean visible
function M.hide()
  hidden = not hidden
  M.refresh()
  return not hidden
end

function M.visible()
  return not hidden
end

--- Dim everything but the thread in focus, or stop.
---@return boolean on
function M.dim()
  dimming = not dimming
  M.refresh()
  return dimming
end

function M.dimming()
  return dimming
end

--- Draw a thread's changes into the code, or stop.
---@param id integer
---@return boolean on
function M.toggle_drawn(id)
  drawn[id] = not drawn[id] or nil
  M.refresh()
  return drawn[id] == true
end

--- After a save, re-quote comments that only matched loosely, so the next
--- edit starts from the line as it is now.
---@param bufnr integer
function M.follow(bufnr)
  local batch = store.active()
  if not batch then
    return
  end
  local changed = false
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for _, p in ipairs(M.locate(bufnr)) do
    -- A stop no one replied in belongs to the agent's message: left alone.
    local c = p.comment.real or p.comment
    if not p.stale and not p.comment.virtual and (c.line ~= p.line or (p.confidence < 1 and lines[p.line] ~= c.text)) then
      c.line = p.line
      if c.text ~= '' then
        c.text = lines[p.line]
      end
      changed = true
    end
  end
  if changed then
    store.save(batch)
  end
end

return M
