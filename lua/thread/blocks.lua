--- What screens are made of, drawn into a sheet: prose with the code it
--- quotes, numbered lines of code, a diagram, a conversation, a rule.

local anchor = require 'thread.anchor'
local code = require 'thread.code'
local look = require 'thread.look'
local text = require 'thread.text'

local M = {}

--- How wide a message's text runs, of the room a conversation has: four
--- fifths, so the agent's stop short on the right and yours on the left.
---@param width integer  the room, label included
---@param label integer  the label's width
function M.side(width, label)
  return math.max(16, math.floor(width * 0.8) - label)
end

--- Your message, the way a chat draws it: narrower than the agent's and
--- set in on the left, so yours line up on the right, `you` before the
--- first line. As rows of chunks, each `width` columns at most.
---@param body string|nil
---@param width integer  the room the conversation has
---@param label integer  the label's column width
---@param time string|nil  when, shown to the left of it
---@return table[][]
function M.chat(body, width, label, time)
  local room = M.side(width, label)
  local lines = text.wrap(body or '', room)
  if #lines == 0 then
    lines = { { text = '' } }
  end
  local off = math.max(0, width - label - room)
  local out = {}
  for j, l in ipairs(lines) do
    local r = { { string.rep(' ', off), 'ThreadText' } }
    if j == 1 and time and off >= text.width(time) + 2 then
      r = { { string.rep(' ', off - text.width(time) - 2), 'ThreadText' }, { time .. '  ', 'ThreadMeta' } }
    end
    if j == 1 then
      r[#r + 1] = { text.pad(look.label { from = 'you' }, label), 'ThreadYou' }
    else
      r[#r + 1] = { string.rep(' ', label), 'ThreadText' }
    end
    vim.list_extend(r, text.segments(l))
    out[#out + 1] = r
  end
  return out
end

---@class thread.CodeLine
---@field num integer|nil     its number; none for a line that was removed
---@field sign string|nil     `+`, `-` or ` ` in a column of its own
---@field line string
---@field spans table|nil     its colours (code.syntax)
---@field wash string|nil     the whole row's colour, from the sign on
---@field num_hl string|nil   the number's colour, else LineNr
---@field words table|nil     { start, end } byte columns, coloured `word_hl`
---@field word_hl string|nil

--- One line of code, numbered, coloured by its syntax.
---@param P thread.Sheet
---@param indent integer
---@param l thread.CodeLine
---@return integer row
function M.code_line(P, indent, l)
  local prefix = string.rep(' ', indent) .. (l.num and string.format('%4d', l.num) or '    ') .. (l.sign and (' ' .. l.sign .. ' ') or '  ')
  local row = P.add(prefix .. l.line:gsub('\t', '    '))
  P.hl(row, indent, indent + 4, l.num_hl or 'LineNr')
  if l.wash then
    P.hl(row, l.sign and indent + 5 or #prefix, -1, l.wash, { hl_eol = true, priority = 10 })
    if l.sign == '+' or l.sign == '-' then
      P.hl(row, indent + 5, indent + 6, l.sign == '+' and 'ThreadAdded' or 'ThreadRemoved', { priority = 30 })
    end
  end
  -- Columns are bytes: past a tab they no longer line up.
  if not l.line:find '\t' then
    for _, s in ipairs(l.spans or {}) do
      P.hl(row, #prefix + s[1], #prefix + s[2], s[3], { priority = 20 })
    end
    for _, w in ipairs(l.words or {}) do
      P.hl(row, #prefix + w[1], #prefix + w[2], l.word_hl, { priority = 25 })
    end
  end
  return row
end

--- Lines `lo`..`hi` of a file, numbered; line `lit` washed.
---@return integer first, integer last
function M.code(P, indent, file, lines, lo, hi, lit)
  local slice = vim.list_slice(lines, lo, hi)
  local spans = code.syntax(slice, file)
  local first = #P.lines
  for i, l in ipairs(slice) do
    M.code_line(P, indent, { num = lo + i - 1, line = l, spans = spans[i], wash = lit == lo + i - 1 and 'ThreadRange' or nil })
  end
  return first, #P.lines - 1
end

--- The code a ```code fence points at: where, then its lines from the
--- quoted one (`lines` of them, 6 unless it says), that line washed when
--- `lit`.
---@param a { file: string, text: string|nil, line: integer|nil, lines: integer|nil }
---@param o { indent: integer|nil, lit: boolean|nil }|nil
function M.excerpt(P, a, o)
  o = o or {}
  local indent = o.indent or P.indent
  local lines = anchor.lines_of { file = a.file }
  local loc = lines and anchor.locate({ file = a.file, text = a.text or '', line = a.line }, lines)
  if not loc then
    P.chunks({ { '▤ ' .. a.file .. ' · its line is gone', 'ThreadBroken' } }, indent)
    return
  end
  local lo = loc.line
  local hi = math.min(#lines, lo + math.max(1, math.min(15, tonumber(a.lines) or 6)) - 1)
  P.chunks({ { a.file .. ':' .. lo, 'Directory' } }, indent)
  M.code(P, indent, a.file, lines, lo, hi, o.lit and lo or nil)
end

--- Prose, wrapped to `width`: `code` and **bold** picked out, links lit, and
--- an excerpt drawn as the code it points at.
function M.prose(P, body, width)
  for _, l in ipairs(text.wrap(body or '', width)) do
    if l.excerpt then
      M.excerpt(P, l.excerpt)
    else
      P.chunks(text.segments(l))
    end
  end
end

--- A diagram, laid out to `width`.
---@return integer first, integer last, table|nil drawn  nil when it is not one
function M.diagram(P, raw, width, indent)
  local diagram = require 'thread.diagram'
  local d, err = diagram.validate(raw)
  if not d then
    local row = P.chunks({ { 'diagram: ' .. (err or '?'), 'ThreadBroken' } }, indent)
    return row, row, nil
  end
  local drawn = diagram.render(d, { max_width = width })
  local first = #P.lines
  for _, chunks in ipairs(drawn.rows) do
    -- Its own colour is the window's: none.
    local row = P.chunks(
      vim.tbl_map(function(c)
        return { c[1], c[2] ~= 'Normal' and c[2] or nil }
      end, chunks),
      indent
    )
    P.lines[row + 1] = P.lines[row + 1]:gsub('%s+$', '')
  end
  local last = #P.lines - 1
  if drawn.degraded then
    last = P.chunks({ { '(' .. drawn.degraded .. ')', 'ThreadMeta' } }, indent)
  end
  return first, last, drawn
end

--- What a message changed at one place, as a diff: where, then the lines
--- it removed and added, coloured the way CodeDiff colours them when it is
--- installed and the way Vim's diff mode does when not. `cap` rows at
--- most, then how many more and `more`.
---@param ch thread.Anchor  the change, as the agent listed it
---@param view table|nil    what it did there (thread.home.model.change)
---@return integer first, integer last
function M.change(P, indent, ch, view, cap, more)
  local where = ch.file .. ':' .. (view and view.line or ch.line or '?')
  local none = view and #view.hunks == 0 and ' · no change there now' or ''
  local first = P.chunks({ { 'changed ', 'ThreadMeta' }, { where, 'Directory' }, { none, 'ThreadMeta' } }, indent)
  if not view or #view.hunks == 0 then
    return first, first
  end
  local add = view.words and { 'CodeDiffLineInsert', 'CodeDiffCharInsert' } or { 'ThreadDiffAdd' }
  local del = view.words and { 'CodeDiffLineDelete', 'CodeDiffCharDelete' } or { 'ThreadDiffDelete' }
  local rows = {}
  for i, h in ipairs(view.hunks) do
    if i > 1 then
      rows[#rows + 1] = { sign = ' ', line = '⋯' }
    end
    local old = vim.list_slice(view.old, h.old_start, h.old_start + h.old_count - 1)
    local new = vim.list_slice(view.new, h.new_start, h.new_start + h.new_count - 1)
    local old_syntax, new_syntax = code.syntax(old, ch.file), code.syntax(new, ch.file)
    for j, l in ipairs(old) do
      rows[#rows + 1] = { sign = '-', line = l, spans = old_syntax[j], wash = del[1], word_hl = del[2], words = h.words.old[h.old_start + j - 1] }
    end
    for j, l in ipairs(new) do
      rows[#rows + 1] =
        { num = h.new_start + j - 1, sign = '+', line = l, spans = new_syntax[j], wash = add[1], word_hl = add[2], words = h.words.new[h.new_start + j - 1] }
    end
  end
  for i = 1, math.min(#rows, cap) do
    M.code_line(P, indent, rows[i])
  end
  if #rows > cap then
    P.chunks({ { '⋯ ' .. text.plural(#rows - cap, 'more line', 'more lines') .. (more or ''), 'ThreadMeta' } }, indent + 7)
  end
  return first, #P.lines - 1
end

---@class thread.TalkOpts
---@field indent integer|nil  where its rows start; else the sheet's
---@field line boolean|nil    a thread on a line: its glyph and id on top, a bar down its side
---@field whole boolean|nil   closed, all of it still
---@field cap integer|nil     rows of each change shown
---@field more string|nil     said after the rows of a change left out

--- A conversation you started, as a chat: the agent's messages on the
--- left with when they came on the right, yours set in from the left, and
--- under the agent's what it changed, against the code as it was when you
--- asked. On a stop, under a rule saying whose move it is; on a line, under
--- its glyph and id, with a bar down its side. Closed, one line says so,
--- unless `whole`. Shown, it is seen.
---@param P thread.Sheet
---@param batch thread.Batch
---@param c thread.Thread
---@param width integer
---@param o thread.TalkOpts|nil
---@return integer first, integer last  its rows
function M.talk(P, batch, c, width, o)
  o = o or {}
  local store = require 'thread.store'
  local indent = o.indent or P.indent
  local status = store.status(c)
  local g, ghl = look.glyph(status, store.unseen(batch, c), false)
  local first = #P.lines
  if o.line then
    P.chunks({ { g .. ' ', ghl }, { '#' .. c.id .. ' · ' .. status, 'ThreadMeta' } }, indent)
  else
    first = M.rule(P, 'your thread here · ' .. g .. ' ' .. status, width)
  end
  local function blank()
    P.add(o.line and string.rep(' ', indent) or '')
  end
  if status == 'closed' and not o.whole then
    local last = c.messages[#c.messages]
    local said = text.plural(#c.messages, 'message') .. ' · '
    P.chunks({ { said, 'ThreadMeta' }, { text.fit(text.first_line(last and last.text), width - text.width(said)), 'ThreadMeta' } }, indent)
  else
    for i, m in ipairs(c.messages) do
      if i > 1 then
        blank()
      end
      local time = text.ago(store.when(batch, c, i))
      if m.from ~= 'you' then
        for j, l in ipairs(text.wrap(m.text or '', M.side(width, 3))) do
          local row = { { j == 1 and text.pad(look.label(m), 3) or '   ', 'ThreadAgent' } }
          vim.list_extend(row, text.segments(l))
          if j == 1 and time then
            row[#row + 1] = { string.rep(' ', math.max(2, width - text.width(row) - text.width(time))) .. time, 'ThreadMeta' }
          end
          P.chunks(row, indent)
        end
        for _, ch in ipairs(type(m.changes) == 'table' and m.changes or {}) do
          local view = require('thread.home.model').change(batch, c, i, ch)
          M.change(P, indent + 3, ch, view, o.cap or 12, o.more)
        end
      else
        for _, r in ipairs(M.chat(m.text, width, 3, time)) do
          P.chunks(r, indent)
        end
      end
    end
  end
  if o.line then
    for row = first, #P.lines - 1 do
      P.mark(row, math.max(0, indent - 2), { virt_text = { { '▎', ghl } }, virt_text_pos = 'overlay' })
    end
  end
  store.mark_seen(batch, c)
  return first, #P.lines - 1
end

--- A blank line, then `── label ──────` across `width`.
---@return integer row
function M.rule(P, label, width)
  P.add ''
  return P.chunks { { '── ' .. label .. ' ', 'ThreadCrumb' }, { string.rep('─', math.max(2, width - text.width(label) - 4)), 'ThreadTabRule' } }
end

return M
