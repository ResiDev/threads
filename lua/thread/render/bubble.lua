--- A thread in the code, drawn as virtual lines above its first line: a
--- bubble holding its last messages, or one line; a tour's stop as a card.

local blocks = require 'thread.blocks'
local config = require 'thread.config'
local look = require 'thread.look'
local store = require 'thread.store'
local text = require 'thread.text'

local M = {}

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

local LABEL = 3 -- `󰚩 ` before a message's text

---@class thread.BubbleOpts
---@field level integer|nil   messages in full; 0 is one line
---@field active boolean|nil  the cursor is on its lines: keys shown
---@field here integer|nil    threads on the cursor's line
---@field seen integer|nil    messages seen
---@field stale boolean|nil   its line is gone

--- A tour's stop you have replied in, not waiting on the agent: both a
--- tour and a conversation, so drawn between their colours.
---@param thread thread.Thread
---@return boolean
function M.both(thread)
  return thread.stop ~= nil and not thread.virtual and store.status(thread) ~= 'waiting' and store.status(thread) ~= 'closed'
end

--- The keys a bubble lists while the cursor is on it.
local function hints(thread, o)
  local list = {}
  -- Everything else (reply, close, the history) is done in the float ⏎
  -- opens: one key to learn here.
  list[#list + 1] = { '⏎', 'open' }
  if o.walking then
    local w = config.options.walk
    if w.next then
      list[#list + 1] = { look.show_key(w.next) .. '/' .. (look.show_key(w.prev) or ''), 'next/prev' }
    end
    local batch = store.active()
    local rv = batch and thread.stop and require('thread.review').owner_of(batch, thread)
    if rv and w.up then
      list[#list + 1] = { look.show_key(w.up), 'the review' }
    end
    if w.quit then
      list[#list + 1] = { look.show_key(w.quit), 'end' }
    end
  elseif thread.stop or o.leads then
    local key = look.key 'walk'
    if key then
      list[#list + 1] = { key, thread.stop and 'walk from here' or 'walk it' }
    end
  end
  local z = config.options.zone or {}
  if (o.here or 1) > 1 and not o.walking and z.next then
    -- Cards stacked on this line: this one on top, the key to the next.
    local key = look.show_key(z.next):gsub('<S%-Tab>', 'S-tab')
    list[#list + 1] = { key, o.here == 2 and 'the other card here' or string.format('next of %d cards here', o.here) }
  end
  if not o.stale and z.fold then
    list[#list + 1] = { look.show_key(z.fold):gsub('<Tab>', 'tab'), (o.level or 1) == 0 and 'whole' or 'fold' }
  end
  return list
end

--- One line: glyph, id, title, dots, and the last message trailing off, or
--- the keys when the cursor is on it.
local function line_bubble(thread, indent, width, o)
  local status = store.status(thread)
  local closed = status == 'closed'
  local messages = thread.messages
  local seen = o.seen or #messages
  local g, ghl = look.glyph(status, seen < #messages and messages[#messages].from ~= 'you', o.stale)
  local dim = closed and 'ThreadSignDone' or nil
  local row = { { string.rep(' ', indent), 'Normal' }, { g .. ' ', ghl }, { (o.crumb and o.crumb.pos or thread.id) .. ' ', dim or (o.crumb and 'ThreadCrumbHere' or 'ThreadMeta') } }
  local title = store.title(thread)
  local tail
  if o.active then
    tail = look.hints(hints(thread, o))
  elseif o.stale then
    tail = { { 'its line is gone', 'DiagnosticWarn' } }
  else
    local last = messages[#messages]
    local who, who_hl = '', 'ThreadMeta'
    if last then
      who, who_hl = look.label(last)
    end
    tail = { { who .. ' ', dim or who_hl } }
    if #messages > 1 or thread.title then
      tail[#tail + 1] = { text.first_line(last and last.text), dim or 'ThreadMeta' }
    end
  end
  local dots = look.dots(messages, seen)
  if closed or thread.virtual then
    dots = { { '', 'ThreadMeta' } }
  end
  local used = indent + 2 + text.width((o.crumb and o.crumb.pos or thread.id) .. ' ') + text.width(dots) + 2
  -- The keys are never cut, so the title gives way to them; else the
  -- title comes first and the last message trails off after it.
  local room = o.active and (width - used - text.width(tail) - 2) or (width - used - 16)
  local title_w = math.min(text.width(title), math.max(12, room), 40)
  row[#row + 1] = { text.fit(title, title_w) .. ' ', dim or 'ThreadTitle' }
  vim.list_extend(row, dots)
  row[#row + 1] = { '  ', 'Normal' }
  -- What is left of the width for the tail; the keys are never cut.
  local left = width + indent - text.width(row)
  if o.active then
    vim.list_extend(row, tail)
  else
    for _, c in ipairs(tail) do
      local s = text.fit(c[1], left)
      left = left - text.width(s)
      row[#row + 1] = { s, c[2] }
    end
  end
  return { row }
end

--- The bubble for a thread, as virtual lines.
---@param thread thread.Thread
---@param indent integer  the code line's indent, in columns
---@param room integer    the window's text width
---@param o thread.BubbleOpts|nil
---@return table[][]
function M.draw(thread, indent, room, o)
  o = o or {}
  local width = math.max(24, math.min(config.options.ui.width, room - indent - 6))
  local level = o.level or math.max(1, #thread.messages - (o.seen or 0))
  if level == 0 or o.stale then
    return line_bubble(thread, indent, math.min(room - indent - 1, width + 8), o)
  end
  local status = store.status(thread)
  local border = o.active and SIGN[status] or BORDER[status] or 'ThreadBorderInfo'
  if M.both(thread) then
    border = o.active and 'ThreadSignBoth' or 'ThreadBorderBoth'
  end
  local messages = thread.messages
  local seen = o.seen or #messages
  -- A tour's stop: its first message is what the stop says, written by no
  -- one in particular, so it has no label and runs the full width.
  local stop = thread.stop ~= nil
  local text_w = width - LABEL

  local rows = {}
  local function row(label, label_hl, chunks)
    local r = { { label .. string.rep(' ', LABEL - text.width(label)), label_hl } }
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
      put { { text.fit('changed ' .. table.concat(places, ', '), text_w), 'ThreadFold' } }
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

  local from = math.max(1, #messages - level + 1)
  local first = 1
  if stop then
    first = 2
    if from > 1 then
      plain(text.segments { text = text.fit(text.first_line(messages[1].text), width) })
    else
      for _, l in ipairs(text.wrap(messages[1].text or '', width)) do
        plain(text.segments(l))
      end
      extras(messages[1], plain)
    end
    if #messages > 1 then
      -- Below the stop's words, a rule, then the conversation in it.
      rows[#rows + 1] = {}
      plain { { string.rep('─', width), border } }
    end
  end
  local start = math.max(first, from)
  if start > first and not stop then
    if messages[1].from == 'you' then
      plain(blocks.chat(text.fit(text.first_line(messages[1].text), math.floor(width * 0.8) - LABEL), width, LABEL)[1])
    else
      local label, label_hl = look.label(messages[1])
      row(label, label_hl, { { text.fit(text.first_line(messages[1].text), text_w), 'ThreadText' } })
    end
  end
  local skipped = start - first - (stop and 0 or 1)
  if skipped > 0 then
    row('', 'ThreadText', { { string.format('⋯ %d earlier', skipped), 'ThreadFold' } })
  end
  for i = start, #messages do
    local m = messages[i]
    if #rows > 0 then
      rows[#rows + 1] = {}
    end
    local agent = m.from ~= 'you'
    if agent then
      local lines = text.wrap(m.text or '', blocks.side(width, LABEL))
      if #lines == 0 then
        lines = { { text = '' } }
      end
      for j, l in ipairs(lines) do
        if j == 1 then
          local label, label_hl = look.label(m, i > seen)
          row(label, label_hl, text.segments(l))
        else
          row('', 'ThreadText', text.segments(l))
        end
      end
    else
      for _, r in ipairs(blocks.chat(m.text, width, LABEL)) do
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
    local title = thread.title or store.title(thread)
    local room_top = room - indent - 12 - text.width(label)
    if text.width(title) <= room_top - 2 then
      label[#label + 1] = { '  ', border }
      label[#label + 1] = { title, 'ThreadTitle' }
    else
      local lines = text.wrap('**' .. title .. '**', width)
      for k = #lines, 1, -1 do
        table.insert(rows, 1, text.segments(lines[k]))
      end
      table.insert(rows, #lines + 1, {})
    end
  else
    local g, ghl = look.glyph(status, seen < #messages and messages[#messages].from ~= 'you')
    label[#label + 1] = { g .. ' ', ghl }
    label[#label + 1] = { tostring(thread.id), border }
    if thread.title then
      label[#label + 1] = { ' · ', border }
      label[#label + 1] = { text.fit(thread.title, width - 24), 'ThreadTitle' }
    end
    label[#label + 1] = { note, 'ThreadMeta' }
  end
  local verdict = look.verdict_of(thread)
  if verdict then
    label[#label + 1] = { ' ', border }
    label[#label + 1] = { ' ' .. verdict.text .. ' ', verdict.hl }
  end
  -- The tour's name, unless the winbar is already saying it.
  if o.crumb and o.crumb.head and not o.walking then
    label[#label + 1] = { ' · ' .. text.fit(o.crumb.head, 24), 'ThreadCrumb' }
  end
  local dots = thread.virtual and { { '', 'ThreadMeta' } } or look.dots(messages, seen)
  local keys = o.active and look.hints(hints(thread, o)) or nil

  -- Padding: a blank line inside the top and bottom edges, two columns at
  -- the sides.
  local PADX = 2
  table.insert(rows, 1, {})
  rows[#rows + 1] = {}
  local widest = 0
  for _, r in ipairs(rows) do
    r.width = text.width(r)
    widest = math.max(widest, r.width)
  end
  local inner = math.max(widest + PADX * 2, text.width(label) + text.width(dots) + 8, keys and (text.width(keys) + 6) or 0)
  inner = math.min(inner, math.max(widest + PADX * 2, room - indent - 3))

  local lead = { string.rep(' ', indent), 'Normal' }
  local out = {}
  local top = { lead, { '╭─ ', border } }
  vim.list_extend(top, label)
  top[#top + 1] = { ' ' .. string.rep('─', math.max(1, inner - 5 - text.width(label) - text.width(dots))), border }
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
    bottom[#bottom + 1] = { string.rep('─', math.max(1, inner - 4 - text.width(keys))) .. ' ', border }
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

return M
