--- Home: every thread in the current batch on one full screen, grouped by
--- file, one line each — like an inbox in conversation view. Tabs pick what
--- shows: the conversations, whose move, the tours, the review of a diff. The focused
--- thread opens in place: its code, with what changed since you sent it, and
--- as much of its history as you ask for (h/l). You reply and close
--- from here; Enter goes to the code only when you want to.
---
--- Everything shown is worked out from the batch file, the code and the
--- round's snapshot: whose turn it is, how long the thread is, how the code
--- around it changed. The agent only writes messages and a title.

local actions = require 'thread.actions'
local anchor = require 'thread.anchor'
local diagram = require 'thread.diagram'
local git = require 'thread.git'
local look = require 'thread.look'
local refs = require 'thread.refs'
local render = require 'thread.render'
local store = require 'thread.store'
local tour = require 'thread.tour'
local strip
local divider

local M = {}

local ns = vim.api.nvim_create_namespace 'thread.home'
local label_ns = vim.api.nvim_create_namespace 'thread.home.reply'

-- Where a thread's messages sit: under its row in Home, and closer in when
-- focused from the code, where the window is narrower.
local INDENT, LABEL, TEXT_COL
local function layout(single)
  INDENT = single and 2 or 6 -- the expanded thread, under its row
  LABEL = single and 3 or 4 -- `󰚩 ` and its padding
  TEXT_COL = INDENT + LABEL
end
layout(false)

-- The tabs: the conversations, the tours, the review, what is closed. Whose
-- move each conversation is shows in its glyph, and grouping by turn (g)
-- splits them. `all` has no tab: it is what focusing one thread shows.
local FILTERS = {
  { key = '1', name = 'threads', test = function(t)
    return t.status ~= 'closed' and t.status ~= 'info'
  end },
  { key = '2', name = 'tours', view = 'tours', test = function()
    return false
  end },
  { key = '3', name = 'review', view = 'review', test = function()
    return false
  end },
  { key = '4', name = 'closed', test = function(t)
    return t.status == 'closed'
  end },
  { key = false, name = 'all', hidden = true, test = function()
    return true
  end },
}
local TABS = #FILTERS - 1

---@class thread.HomeState
---@field win integer
---@field buf integer
---@field focus integer|nil       the focused thread's id
---@field levels table<integer, integer>  thread id -> messages shown
---@field filter integer          index into FILTERS
---@field reply { id: integer }|nil  a reply being typed
---@field order integer[]         thread ids as displayed
---@field row_of table<integer, integer>
---@field owner table<integer, integer>  line -> thread id
---@field rendering boolean
---@field group integer           index into GROUPS
---@field query string|nil        the search: only threads that mention it
---@field marked table<integer, boolean>  threads picked with space
---@field code table<integer, integer>    thread id -> how much code: 0, 1, 2
---@field single integer|nil   focused from the code: only this thread, in a float
---@field others integer[]|nil  the other threads on that line, for tab
---@field src_win integer|nil   the code window it was focused from
---@field quick boolean|nil     opened to reply: back to the code once sent
---@type thread.HomeState|nil
local S

local width_of = vim.fn.strdisplaywidth
local footer
local resolve_selection
local single_title, single_footer, place
local draw_change

--- `s` cut to `w` display columns, with an ellipsis when cut.
local function fit(s, w)
  if w <= 0 then
    return ''
  end
  if width_of(s) <= w then
    return s
  end
  local n = vim.fn.strchars(s)
  local lo, hi = 0, n
  while lo < hi do
    local mid = math.ceil((lo + hi) / 2)
    if width_of(vim.fn.strcharpart(s, 0, mid)) <= w - 1 then
      lo = mid
    else
      hi = mid - 1
    end
  end
  return vim.fn.strcharpart(s, 0, lo) .. '…'
end

local function pad(s, w)
  return s .. string.rep(' ', math.max(0, w - width_of(s)))
end

local function first_line(text)
  return vim.split(vim.trim(text or ''), '\n', { plain = true })[1] or ''
end

local ago = require('thread.text').ago

-- How the threads are grouped: by where they are, whose turn it is, or the
-- round they were last sent in, newest first, which reads like a log.
local TURNS = { answered = 1, waiting = 2, closed = 3 }
local TURN_NAMES = { 'your turn', "the agent's turn", 'closed' }
local GROUPS = {
  { name = 'file', of = function(t)
    if not t.anchored then
      return '', 'general · on no line'
    end
    local key = t.c.file .. (t.c.rev and (' @ ' .. t.c.rev:sub(1, 7)) or '')
    return key, key
  end },
  { name = 'turn', of = function(t)
    local n = TURNS[t.status] or 1
    return n, TURN_NAMES[n]
  end },
  { name = 'round', of = function(t, batch)
    local round = 0
    for _, m in ipairs(t.c.messages) do
      round = math.max(round, m.round or 0)
    end
    local r = batch.data.rounds[round]
    local when = r and r.sent and ago(r.sent)
    return -round, 'round ' .. round .. (when and (' · sent ' .. when) or '')
  end },
}

----------------------------------------------------------------------
-- What there is to show, worked out from the file, the code and git
----------------------------------------------------------------------

---@class thread.HomeThread
---@field c thread.Comment
---@field status string
---@field unseen boolean
---@field lines string[]|nil  the file as it is now
---@field line integer|nil    where the anchor is now; nil when gone
---@field to integer|nil
---@field delta { add: integer, del: integer, hunks: thread.Hunk[], old: string[] }|nil

--- How the code around a thread changed since the last round it was sent in.
local function delta(batch, t)
  if not t.line or t.c.rev or not t.anchored then
    return nil
  end
  local round = 0
  for _, m in ipairs(t.c.messages) do
    if m.round and m.round > round then
      round = m.round
    end
  end
  local r = batch.data.rounds[round]
  if not (r and r.snapshot) then
    return nil
  end
  -- No snapshot to compare with (pruned, or another clone): no change shown,
  -- rather than every line as new.
  local old = git.show(r.snapshot, t.c.file)
  if not old then
    return nil
  end
  local lo, hi = t.line - 3, t.to + 3
  local kept, add, del = {}, 0, 0
  for _, h in ipairs(git.hunks(old, t.lines)) do
    local s = h.new_start
    local e = h.new_count == 0 and s + 1 or s + h.new_count - 1
    if e >= lo and s <= hi then
      kept[#kept + 1] = h
      add, del = add + h.new_count, del + h.old_count
    end
  end
  if add + del == 0 then
    return nil
  end
  return { add = add, del = del, hunks = kept, old = old }
end

--- Whether the thread mentions `q`, in its title or any message; smartcase.
local function matches(c, q)
  if not q or q == '' then
    return true
  end
  local fold = not q:find '%u'
  local needle = fold and q:lower() or q
  local function has(text)
    text = text or ''
    return (fold and text:lower() or text):find(needle, 1, true) ~= nil
  end
  if has(c.title) or has(c.file) then
    return true
  end
  for _, m in ipairs(c.messages) do
    if has(m.text) then
      return true
    end
  end
  return false
end

---@param batch thread.Batch
---@return thread.HomeThread[]
local function collect(batch, only)
  local files = {}
  local out = {}
  for _, c in ipairs(batch.data.threads) do
    if (only and c.id ~= only) or not matches(c, S.query) then
      goto continue
    end
    local lines, loc
    if store.anchored(c) then
      local key = (c.rev or '') .. ':' .. c.file
      if files[key] == nil then
        files[key] = anchor.lines_of(c) or false
      end
      lines = files[key] or nil
      loc = lines and anchor.locate(c, lines)
    end
    local t = {
      c = c,
      anchored = store.anchored(c),
      status = store.status(c),
      unseen = store.unseen(batch, c),
      lines = lines,
      line = loc and loc.line,
    }
    if t.line then
      t.to = math.min(#lines, t.line + (c.lines or 1) - 1)
    end
    t.delta = delta(batch, t)
    t.seen = store.seen_count(batch, c)
    out[#out + 1] = t
    ::continue::
  end
  return out
end

local function glyph(t)
  return look.glyph(t.status, t.unseen, t.anchored and not t.line)
end

--- The last few messages, a dot each in the colour of who wrote it.
local function dots(t)
  return look.dots(t.c.messages, (S.seen_at and S.seen_at[t.c.id]) or t.seen or 0)
end

local function title_of(c)
  return store.title(c)
end

----------------------------------------------------------------------
-- Treesitter colours for a few lines of code, out of their file
----------------------------------------------------------------------

---@return table<integer, { [1]: integer, [2]: integer, [3]: string }[]>  line index -> spans
local function syntax(lines, file)
  local ft = vim.filetype.match { filename = file }
  local lang = ft and vim.treesitter.language.get_lang(ft)
  if not lang or #lines == 0 then
    return {}
  end
  local text = table.concat(lines, '\n')
  local ok, parser = pcall(vim.treesitter.get_string_parser, text, lang)
  local query = ok and vim.treesitter.query.get(lang, 'highlights')
  if not query then
    return {}
  end
  local ok_parse, trees = pcall(parser.parse, parser)
  if not ok_parse or not trees[1] then
    return {}
  end
  local spans = {}
  for id, node in query:iter_captures(trees[1]:root(), text, 0, -1) do
    local name = query.captures[id]
    if name ~= 'spell' and name ~= 'nospell' and name:sub(1, 1) ~= '_' then
      local sr, sc, er, ec = node:range()
      for r = sr, er do
        local line = lines[r + 1]
        if line then
          spans[r + 1] = spans[r + 1] or {}
          table.insert(spans[r + 1], { r == sr and sc or 0, r == er and ec or #line, '@' .. name .. '.' .. lang })
        end
      end
    end
  end
  return spans
end
M.syntax = syntax

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------

--- The page being built: lines, highlights, and which thread owns each line.
local function page()
  local P = { lines = {}, hls = {}, owner = {} }
  function P.add(text, owner)
    P.lines[#P.lines + 1] = text
    P.owner[#P.lines] = owner
    return #P.lines - 1
  end
  function P.hl(row, s, e, group, opts)
    P.hls[#P.hls + 1] = { row, s, e, group, opts }
  end
  P.marks = {}
  function P.mark(row, col, opts)
    P.marks[#P.marks + 1] = { row, col, opts }
  end
  return P
end

--- `keys` as `key label   key label`, the keys standing out, on `row`.
--- Keys and what they do on one line; with `right`, ending at that column.
local function key_hints(P, row, col, keys, right)
  if right then
    local w = 0
    for i, k in ipairs(keys) do
      w = w + (i > 1 and 3 or 0) + width_of(k[1]) + 1 + width_of(k[2])
    end
    col = math.max(col, right - w)
  end
  local text = string.rep(' ', col)
  for i, k in ipairs(keys) do
    if i > 1 then
      text = text .. '   '
    end
    P.hl(row, #text, #text + #k[1], 'ThreadKey')
    text = text .. k[1] .. ' '
    P.hl(row, #text, #text + #k[2], 'ThreadKeyLabel')
    text = text .. k[2]
  end
  P.lines[row + 1] = text
end

--- The function, method or class the thread's lines are in, by treesitter;
--- else a dozen lines either side.
local scopes = {} -- file text -> { [line..':'..to] = { lo, hi } }
local function scope(t)
  local key = t.line .. ':' .. t.to
  local text = table.concat(t.lines, '\n')
  scopes[text] = scopes[text] or {}
  local hit = scopes[text][key]
  if hit then
    return hit[1], hit[2]
  end
  local lo, hi = math.max(1, t.line - 12), math.min(#t.lines, t.to + 12)
  local ft = vim.filetype.match { filename = t.c.file }
  local lang = ft and vim.treesitter.language.get_lang(ft)
  local ok, parser = pcall(vim.treesitter.get_string_parser, text, lang or '')
  local ok_parse, trees = false, nil
  if lang and ok then
    ok_parse, trees = pcall(parser.parse, parser)
  end
  if ok_parse and trees and trees[1] then
    local slo, shi = require('thread.code').enclosing(trees[1]:root(), t.line, t.to)
    if slo then
      lo, hi = slo, shi
    end
  end
  scopes[text][key] = { lo, hi }
  return lo, hi
end

-- How much code a thread shows: just its lines, a line either side, or the
-- whole function it is in.
local CODE = { { name = 'its lines', around = 0, cap = 8 }, { name = 'around it', around = 1, cap = 8 }, { name = 'the whole function', cap = 60 } }

--- The notes of a thread's latest message that has any.
---@param c thread.Comment
---@return thread.Note[]
local function notes_of(c)
  for i = #c.messages, 1, -1 do
    if c.messages[i].notes and #c.messages[i].notes > 0 then
      return c.messages[i].notes
    end
  end
  return {}
end

--- The code under an open thread, with what changed since it was sent and
--- its notes on their lines.
local function draw_code(P, t)
  local lines = t.lines
  local size = CODE[(S.code[t.c.id] or 1) + 1]
  local lo, hi
  if size.around then
    lo, hi = math.max(1, t.line - size.around), math.min(#lines, t.to + size.around)
  else
    lo, hi = scope(t)
  end
  local cap = size.cap
  -- Its notes: every noted line shown, numbered, the note after it.
  local noted = {}
  for k, n in ipairs(notes_of(t.c)) do
    local note = vim.tbl_extend('keep', n, { file = t.c.file })
    if note.file == t.c.file then
      local loc = anchor.locate(note, lines)
      if loc then
        noted[loc.line] = { num = look.num(k), text = type(note.note) == 'string' and note.note or '', mark = note.mark }
        if math.abs(loc.line - t.line) < 40 then
          lo, hi = math.min(lo, loc.line), math.max(hi, loc.line)
          cap = math.max(cap, 30)
        end
      end
    end
  end
  local added, removed_before = {}, {}
  for _, h in ipairs(t.delta and t.delta.hunks or {}) do
    local old = vim.list_slice(t.delta.old, h.old_start, h.old_start + h.old_count - 1)
    if h.new_count == 0 then
      removed_before[h.new_start + 1] = old
      lo, hi = math.min(lo, math.max(1, h.new_start)), math.max(hi, math.min(#lines, h.new_start + 1))
    else
      removed_before[h.new_start] = old
      for n = h.new_start, h.new_start + h.new_count - 1 do
        added[n] = true
      end
      lo, hi = math.min(lo, h.new_start), math.max(hi, h.new_start + h.new_count - 1)
    end
  end
  -- Enough code to place the thread, not a page of it: + or ⏎ for the rest.
  local cut
  if hi - lo + 1 > cap then
    hi, cut = lo + cap - 1, hi - lo + 1 - cap
  end

  local first = #P.lines
  local new_lines = vim.list_slice(lines, lo, hi)
  local new_syntax = syntax(new_lines, t.c.file)
  local code_col = INDENT + 4 + 3
  local function code_row(num, sign, text, spans, wash)
    local prefix = string.rep(' ', INDENT) .. (num and string.format('%4d', num) or '    ') .. ' ' .. sign .. ' '
    local row = P.add(prefix .. text:gsub('\t', '    '), t.c.id)
    P.hl(row, INDENT, INDENT + 4, 'LineNr')
    if wash then
      P.hl(row, INDENT + 5, -1, wash, { hl_eol = true, priority = 10 })
      P.hl(row, INDENT + 5, INDENT + 6, wash == 'ThreadDiffAdd' and 'ThreadAdded' or 'ThreadRemoved', { priority = 30 })
    end
    if not text:find '\t' then
      for _, s in ipairs(spans or {}) do
        P.hl(row, code_col + s[1], code_col + s[2], s[3], { priority = 20 })
      end
    end
    local note = num and noted[num]
    if note then
      P.hl(row, INDENT + 5, -1, 'ThreadNoteLine', { hl_eol = true, priority = 8 })
      P.mark(row, 0, { virt_text = { { '  ' .. note.num, 'ThreadNoteNum' }, { note.text ~= '' and (' ' .. note.text) or '', 'ThreadNote' } }, virt_text_pos = 'eol' })
      local at = type(note.mark) == 'string' and note.mark ~= '' and not text:find '\t' and text:find(note.mark, 1, true)
      if at then
        P.hl(row, code_col + at - 1, code_col + at - 1 + #note.mark, 'ThreadNoteMark', { priority = 40 })
      end
    end
  end
  for i = 1, #new_lines do
    local lnum = lo + i - 1
    local old = removed_before[lnum]
    if old then
      local old_syntax = syntax(old, t.c.file)
      for j, l in ipairs(old) do
        code_row(nil, '-', l, old_syntax[j], 'ThreadDiffDelete')
      end
    end
    code_row(lnum, added[lnum] and '+' or ' ', new_lines[i], new_syntax[i], added[lnum] and 'ThreadDiffAdd' or nil)
  end
  if cut then
    P.hl(P.add(string.rep(' ', INDENT + 7) .. '⋯ ' .. cut .. ' more line' .. (cut == 1 and '' or 's') .. ((S.code[t.c.id] or 1) < #CODE - 1 and ' · + shows more' or ''), t.c.id), 0, -1, 'ThreadMeta')
  end
  return first, #P.lines - 1
end

--- The code a reference points to, under the paragraph that names it: a few
--- lines around the place, the place itself lifted.
--- The name you are on inside a thread, if any.
local function selected_ref()
  if not (S and S.inside and S.inside.ref) then
    return nil
  end
  for _, r in ipairs(S.refs or {}) do
    if r.key == S.inside.ref then
      return r
    end
  end
end

--- The name whose code you are on or at: the selected name, or the code
--- part you are on.
local function current_ref()
  local ref = selected_ref()
  if ref then
    return ref
  end
  local it = S and S.inside and S.items and S.items[S.inside.item]
  if it and it.kind == 'excerpt' then
    for _, r in ipairs(S.refs or {}) do
      if r.key == it.key then
        return r
      end
    end
  end
end

--- Be on part `n` of the thread you are inside, remembered by its name.
local function select(n)
  local it = S.items and S.items[n]
  S.inside.item, S.inside.sel = n, it and it.id
end

--- After a redraw, find the part you were on again by its name. When it is
--- gone: closed code goes back to its name; a part merged away goes to the
--- one before it in the same message; failing that, the same position.
resolve_selection = function()
  local items, sel = S.items or {}, S.inside.sel
  local function find(id)
    for n, it in ipairs(items) do
      if it.id == id then
        return n
      end
    end
  end
  local n = sel and find(sel)
  if not n and sel then
    local key = sel:match '^x:(.*)$'
    if key then
      for _, r in ipairs(S.refs or {}) do
        if r.key == key then
          n, S.inside.ref = r.item, key
        end
      end
    end
    local msg, part = sel:match '^m:(%d+):(%d+)$'
    for p = tonumber(part or 0) - 1, 1, -1 do
      n = n or find('m:' .. msg .. ':' .. p)
    end
  end
  n = n or math.max(1, math.min(#items, S.inside.item or #items))
  S.inside.item = n
  S.inside.sel = items[n] and items[n].id
end

-- How many lines a name's code shows; + and - step through these.
local REF_SIZES = { 4, 8, 16, 32 }

local function draw_excerpt(P, t, places, n, size)
  local place = places[n]
  local lines = place and anchor.lines_of { file = place.file }
  if not lines then
    return nil
  end
  local lo = math.max(1, place.line - math.floor(size / 4))
  local hi = math.min(#lines, lo + size - 1)
  local where = place.file .. ':' .. place.line
  local first = #P.lines
  local more = #places > 1 and string.format('   %d of %d · n next', n, #places) or ''
  local head = P.add(string.rep(' ', TEXT_COL) .. where .. more, t.c.id)
  P.hl(head, TEXT_COL, TEXT_COL + #where, 'Directory')
  P.hl(head, TEXT_COL + #where, -1, 'ThreadMeta')
  local slice = vim.list_slice(lines, lo, hi)
  local spans = syntax(slice, place.file)
  for i, l in ipairs(slice) do
    local num = lo + i - 1
    local prefix = string.rep(' ', TEXT_COL) .. string.format('%4d  ', num)
    local row = P.add(prefix .. (l:gsub('\t', '    ')), t.c.id)
    P.hl(row, TEXT_COL, TEXT_COL + 4, 'LineNr')
    if num == place.line then
      P.hl(row, #prefix, -1, 'ThreadRange', { hl_eol = true, priority = 10 })
    end
    if not l:find '\t' then
      for _, sp in ipairs(spans[i] or {}) do
        P.hl(row, #prefix + sp[1], #prefix + sp[2], sp[3], { priority = 20 })
      end
    end
  end
  local last = #P.lines - 1
  P.add('', t.c.id)
  return first, last
end

--- What an agent's message changed at one place: the hunks there between
--- the round it answers and the file now.
---@return { old: string[], new: string[], hunks: thread.WordHunk[], words: boolean }|nil
local function change_view(t, index, ch)
  local batch = store.active()
  local base = batch and git.base_for(batch, t.c, index)
  local new = base and anchor.lines_of { file = ch.file }
  local old = new and git.show(base, ch.file)
  if not old then
    return nil
  end
  local loc = anchor.locate(ch, new)
  local line = loc and loc.line or ch.line or 1
  local lo, hi = line - 1, line + (ch.lines or 1)
  local all, words = git.word_hunks(old, new)
  local kept = {}
  for _, h in ipairs(all) do
    local s = h.new_start
    local e = h.new_count == 0 and s + 1 or s + h.new_count - 1
    if e >= lo and s <= hi then
      kept[#kept + 1] = h
    end
  end
  return { old = old, new = new, hunks = kept, words = words, line = line }
end

local CHANGE_CAP = 16 -- rows of a change shown; the whole diff is on ⏎

--- A change under its message: where, then its hunks, coloured the way
--- CodeDiff colours them when it is installed and the way Vim's diff mode
--- does when not.
---@return integer first, integer last, table|nil view
function draw_change(P, t, index, ch)
  local view = change_view(t, index, ch)
  local where = ch.file .. ':' .. (view and view.line or ch.line or '?')
  local first = P.add(string.rep(' ', TEXT_COL) .. 'changed ' .. where, t.c.id)
  P.hl(first, TEXT_COL, TEXT_COL + #'changed ', 'ThreadMeta')
  P.hl(first, TEXT_COL + #'changed ', -1, 'Directory')
  if not view then
    return first, first, nil
  end
  if #view.hunks == 0 then
    P.lines[first + 1] = P.lines[first + 1] .. ' · no change there now'
    P.hl(first, #P.lines[first + 1] - #' · no change there now', -1, 'ThreadMeta')
    return first, first, view
  end
  local line_add = view.words and 'CodeDiffLineInsert' or 'ThreadDiffAdd'
  local line_del = view.words and 'CodeDiffLineDelete' or 'ThreadDiffDelete'
  local word_add = view.words and 'CodeDiffCharInsert' or nil
  local word_del = view.words and 'CodeDiffCharDelete' or nil
  local col = TEXT_COL + 7
  local shown, cut = 0, 0
  local function row(num, sign, text, spans, wash, word_hl, words)
    if shown >= CHANGE_CAP then
      cut = cut + 1
      return
    end
    shown = shown + 1
    local r = P.add(string.rep(' ', TEXT_COL) .. (num and string.format('%4d', num) or '    ') .. ' ' .. sign .. ' ' .. text:gsub('\t', '    '), t.c.id)
    P.hl(r, TEXT_COL, TEXT_COL + 4, 'LineNr')
    if wash then
      P.hl(r, TEXT_COL + 5, -1, wash, { hl_eol = true, priority = 10 })
      P.hl(r, TEXT_COL + 5, TEXT_COL + 6, sign == '+' and 'ThreadAdded' or 'ThreadRemoved', { priority = 30 })
    end
    if not text:find '\t' then
      for _, sp in ipairs(spans or {}) do
        P.hl(r, col + sp[1], col + sp[2], sp[3], { priority = 20 })
      end
      for _, w in ipairs(words or {}) do
        P.hl(r, col + w[1], col + w[2], word_hl, { priority = 25 })
      end
    end
  end
  for i, h in ipairs(view.hunks) do
    if i > 1 then
      row(nil, ' ', '⋯', nil)
    end
    local old = vim.list_slice(view.old, h.old_start, h.old_start + h.old_count - 1)
    local new = vim.list_slice(view.new, h.new_start, h.new_start + h.new_count - 1)
    local old_syntax, new_syntax = syntax(old, ch.file), syntax(new, ch.file)
    for j, l in ipairs(old) do
      row(nil, '-', l, old_syntax[j], line_del, word_del, h.words.old[h.old_start + j - 1])
    end
    for j, l in ipairs(new) do
      row(h.new_start + j - 1, '+', l, new_syntax[j], line_add, word_add, h.words.new[h.new_start + j - 1])
    end
  end
  if cut > 0 then
    P.hl(P.add(string.rep(' ', TEXT_COL + 7) .. '⋯ ' .. cut .. ' more line' .. (cut == 1 and '' or 's') .. ' · ⏎ the whole diff', t.c.id), 0, -1, 'ThreadMeta')
  end
  return first, #P.lines - 1, view
end

--- Code a message quotes the way a tour's excerpt does: a ```code fence
--- holding an anchor. The lines it points at, numbered, its own line lit.
local function draw_quoted(P, t, a)
  local lines = anchor.lines_of { file = a.file }
  local loc = lines and anchor.locate({ file = a.file, text = a.text, line = a.line }, lines)
  if not loc then
    P.hl(P.add(string.rep(' ', TEXT_COL) .. '▤ ' .. a.file .. ' · its line is gone', t.c.id), TEXT_COL, -1, 'ThreadBroken')
    return
  end
  local count = math.max(1, math.min(15, tonumber(a.lines) or 6))
  local lo, hi = loc.line, math.min(#lines, loc.line + count - 1)
  local where = a.file .. ':' .. lo
  local head = P.add(string.rep(' ', TEXT_COL) .. where, t.c.id)
  P.hl(head, TEXT_COL, -1, 'Directory')
  local slice = vim.list_slice(lines, lo, hi)
  local spans = syntax(slice, a.file)
  for i, l in ipairs(slice) do
    local prefix = string.rep(' ', TEXT_COL) .. string.format('%4d  ', lo + i - 1)
    local row = P.add(prefix .. (l:gsub('\t', '    ')), t.c.id)
    P.hl(row, TEXT_COL, TEXT_COL + 4, 'LineNr')
    if i == 1 then
      P.hl(row, #prefix, -1, 'ThreadRange', { hl_eol = true, priority = 10 })
    end
    if not l:find '\t' then
      for _, sp in ipairs(spans[i] or {}) do
        P.hl(row, #prefix + sp[1], #prefix + sp[2], sp[3], { priority = 20 })
      end
    end
  end
end

--- A message's diagram, laid out to the width there is.
---@return integer first, integer last, table|nil drawn
local function draw_diagram(P, t, raw, width)
  local d, err = diagram.validate(raw)
  if not d then
    local row = P.add(string.rep(' ', TEXT_COL) .. 'diagram: ' .. (err or '?'), t.c.id)
    P.hl(row, TEXT_COL, -1, 'ThreadBroken')
    return row, row, nil
  end
  local drawn = diagram.render(d, { max_width = math.max(30, width) })
  local first = #P.lines
  for _, chunks in ipairs(drawn.rows) do
    local text, col = string.rep(' ', TEXT_COL), TEXT_COL
    local hls = {}
    for _, ch in ipairs(chunks) do
      hls[#hls + 1] = { col, col + #ch[1], ch[2] }
      text = text .. ch[1]
      col = col + #ch[1]
    end
    local row = P.add((text:gsub('%s+$', '')), t.c.id)
    for _, h in ipairs(hls) do
      if h[3] and h[3] ~= 'Normal' then
        P.hl(row, h[1], h[2], h[3])
      end
    end
  end
  local last = #P.lines - 1
  if drawn.degraded then
    last = P.add(string.rep(' ', TEXT_COL) .. '(' .. drawn.degraded .. ')', t.c.id)
    P.hl(last, 0, -1, 'ThreadMeta')
  end
  return first, last, drawn
end

--- The tour a message leads to: every stop, a part to step to, the steps
--- of a stage indented under it.
---@return table[] parts
local function draw_stops(P, t, m, width)
  local batch = store.active()
  if not batch then
    return {}
  end
  local items = tour.outline(m.walk)
  local head = P.add(string.rep(' ', TEXT_COL) .. '▶ leads to ' .. tour.describe(m.walk), t.c.id)
  P.hl(head, TEXT_COL, -1, 'ThreadLeads')
  local w = require('thread.walk').state()
  local parts = {}
  local files = {}
  -- Under a row, the first few stops and a line saying how many more;
  -- inside the thread (o), every one.
  local cap = (S.inside and S.inside.id == t.c.id) and math.huge or 8
  for k, it in ipairs(items) do
    if k > cap then
      local more = #items - cap
      P.hl(P.add(string.rep(' ', TEXT_COL + 2) .. string.format('⋯ %d more stop%s · o shows them all', more, more == 1 and '' or 's'), t.c.id), 0, -1, 'ThreadMeta')
      break
    end
    local e = it.e
    local talk = tour.thread_at(batch, t.c.id, it.n)
    local been = store.visited(batch, t.c.id, it.n)
    local g, ghl = '', nil
    if talk then
      g, ghl = look.glyph(store.status(talk), store.unseen(batch, talk), false)
    elseif been and it.kind ~= 'stage' then
      g, ghl = '✓', 'ThreadSignDone'
    else
      g, ghl = it.kind == 'stage' and '▸' or '·', 'ThreadSignInfo'
    end
    local num = it.kind == 'stage' and (it.stage .. ' ') or it.kind == 'step' and (it.step .. ' ') or ''
    local indent = string.rep(' ', TEXT_COL + 2 + ((it.kind ~= 'stage' and it.stage > 0) and 4 or 0))
    local name = num .. tour.title(e)
    local where = ''
    if it.kind == 'step' then
      if files[e.file] == nil then
        files[e.file] = anchor.lines_of(e) or false
      end
      local loc = files[e.file] and anchor.locate(e, files[e.file])
      where = vim.fs.basename(e.file) .. ':' .. (loc and loc.line or '–')
    end
    local verdict = e.verdict and look.verdict_of { messages = { e } }
    local room = width - #indent - 2 - width_of(where) - 4 - (verdict and (width_of(verdict.text) + 3) or 0)
    local text = indent .. g .. ' ' .. fit(name, math.max(10, room))
    local tcol = #indent + #g + 1
    local tlen = #(fit(name, math.max(10, room)))
    local vcol
    if verdict then
      text = text .. '  '
      vcol = #text
      text = text .. ' ' .. verdict.text .. ' '
    end
    text = text .. string.rep(' ', math.max(2, width - width_of(text) - width_of(where))) .. where
    local row = P.add(text, t.c.id)
    P.hl(row, #indent, #indent + #g, ghl)
    local here = w and w.owner == t.c.id and w.n == it.n
    P.hl(row, tcol, tcol + tlen, here and 'ThreadCrumbHere' or (it.kind == 'stage' and 'ThreadTitle' or nil))
    if vcol then
      P.hl(row, vcol, vcol + #verdict.text + 2, verdict.hl)
    end
    P.hl(row, #text - #where, #text, 'LineNr')
    parts[#parts + 1] = { kind = 'stop', n = it.n, id = 'k:' .. it.n, first = row, last = row }
  end
  return parts
end

--- Files a thread names, which its references most likely mean.
local function mentioned(t)
  local out = {}
  if t.anchored then
    out[t.c.file] = true
  end
  for _, m in ipairs(t.c.messages) do
    for _, ch in ipairs(m.changes or {}) do
      out[ch.file] = true
    end
  end
  return out
end

--- One message: its speaker in the label column, its text wrapped beside it.
--- An agent's `names` that point at code are underlined, and the ones opened
--- show their code under their paragraph, which splits the message there:
--- its parts, text and code in turn, are what j/k step through inside.
---@return table[] parts, table[] refs
local function draw_message(P, t, m, index, new, width)
  local agent = m.from ~= 'you'
  local label, label_hl = look.label(m, new)
  local mark = ''
  local batch = store.active()
  local time = batch and ago(store.when(batch, t.c, index))
  if not agent then
    -- Yours on the right, as in a chat, when it was on its left.
    local first = #P.lines
    for _, r in ipairs(render.chat(m.text, width + LABEL, LABEL, time)) do
      local text, col, spans = string.rep(' ', INDENT), INDENT, {}
      for _, ch in ipairs(r) do
        spans[#spans + 1] = { col, col + #ch[1], ch[2] == 'ThreadCode' and 'ThreadInlineCode' or ch[2] }
        text = text .. ch[1]
        col = col + #ch[1]
      end
      local row = P.add(text, t.c.id)
      for _, sp in ipairs(spans) do
        if sp[3] ~= 'ThreadText' then
          P.hl(row, sp[1], sp[2], sp[3])
        end
      end
    end
    return { { kind = 'message', index = index, id = 'm:' .. index .. ':1', first = first, last = #P.lines - 1 } }, {}
  end
  -- The agent's text stops short on the right, as yours does on the left.
  local rows = require('thread.text').wrap(m.text or '', render.side(width + LABEL, LABEL))
  if #rows == 0 then
    rows = { { text = '' } }
  end
  -- Under its row in Home, a long message trails off; o reads it all.
  local MAX = 8
  if not S.single and not (S.inside and S.inside.id == t.c.id) and #rows > MAX then
    rows = vim.list_slice(rows, 1, MAX)
    while #rows > 1 and rows[#rows].text == '' do
      rows[#rows] = nil
    end
    rows[#rows + 1] = { text = '⋯ o reads it all' }
  end
  local ctx = agent and { file = t.c.file, line = t.line, mentioned = mentioned(t), near = refs.near(m.text) }
  local found, pending, k = {}, {}, 0
  -- Each part has a name that holds across redraws, so where you are
  -- survives code being opened or closed above it.
  local parts, part_first, part_n = {}, #P.lines, 1
  local function close_part(last)
    if part_first and last >= part_first then
      parts[#parts + 1] = { kind = 'message', index = index, id = 'm:' .. index .. ':' .. part_n, first = part_first, last = last }
      part_n = part_n + 1
    end
    part_first = nil
  end
  local skip_blank = false
  for i, l in ipairs(rows) do
    -- After code, its own blank line already parts it from the next paragraph.
    if skip_blank and l.text == '' then
      skip_blank = false
      goto next_row
    end
    skip_blank = false
    if l.excerpt then
      part_first = part_first or #P.lines
      draw_quoted(P, t, l.excerpt)
      goto next_row
    end
    local head = i == 1 and pad(label .. mark, LABEL) or string.rep(' ', LABEL)
    -- Columns are counted in bytes: the label's shape is one cell but
    -- several bytes.
    local text, col, spans = {}, INDENT + #head, {}
    for _, chunk in ipairs(require('thread.text').segments(l)) do
      text[#text + 1] = chunk[1]
      if chunk[2] == 'ThreadCode' and not l.code then
        spans[#spans + 1] = { col, col + #chunk[1], chunk[1] }
      end
      col = col + #chunk[1]
    end
    local row = P.add(string.rep(' ', INDENT) .. head .. table.concat(text), t.c.id)
    part_first = part_first or row
    if i == 1 then
      P.hl(row, INDENT, INDENT + #label, label_hl)
      -- When, on the right, past where the text stops.
      if time then
        local line = P.lines[row + 1]
        local at = TEXT_COL + width - width_of(time)
        if at > width_of(line) + 2 then
          P.lines[row + 1] = line .. string.rep(' ', at - width_of(line)) .. time
          P.hl(row, #P.lines[row + 1] - #time, -1, 'ThreadMeta')
        end
      end
    end
    for _, sp in ipairs(spans) do
      local places = {}
      if ctx then
        local at = (m.text or ''):find('`' .. sp[3] .. '`', 1, true)
        local after = at and m.text:sub(at + #sp[3] + 2, at + #sp[3] + 60)
        places = refs.resolve(sp[3], ctx, after)
      end
      if #places > 0 then
        k = k + 1
        local key = t.c.id .. ':' .. index .. ':' .. k
        P.hl(row, sp[1], sp[2], 'ThreadRef')
        found[#found + 1] = { kind = 'ref', key = key, places = places, first = row, last = row, s = sp[1], e = sp[2], part = 'm:' .. index .. ':' .. part_n }
        if S.open_refs[key] then
          pending[#pending + 1] = { places, S.open_refs[key], REF_SIZES[S.ref_size[key] or 2], key }
        end
      else
        P.hl(row, sp[1], sp[2], 'ThreadInlineCode')
      end
    end
    -- The end of a paragraph: the code its opened names point to, each a
    -- part of its own, and the text so far a part before them.
    if #pending > 0 and (not rows[i + 1] or rows[i + 1].text == '') then
      close_part(#P.lines - 1)
      P.add('', t.c.id)
      for _, o in ipairs(pending) do
        local a, b = draw_excerpt(P, t, o[1], o[2], o[3])
        if a then
          parts[#parts + 1] = { kind = 'excerpt', index = index, key = o[4], id = 'x:' .. o[4], first = a, last = b }
        end
      end
      pending = {}
      skip_blank = true
    end
    ::next_row::
  end
  -- Code drawn last leaves a blank line behind it; the part ends before.
  local last = #P.lines - 1
  while part_first and last >= part_first and P.lines[last + 1] == '' do
    last = last - 1
  end
  close_part(last)
  -- Its diagram, a part of its own: ⏎ on a box goes to its code.
  local under_row = not S.single and not (S.inside and S.inside.id == t.c.id)
  if m.diagram and type(m.diagram) == 'table' and under_row then
    -- Under its row, a diagram is one line; o shows it.
    local n = #(m.diagram.nodes or m.diagram.participants or {})
    P.add('', t.c.id)
    P.hl(P.add(string.rep(' ', TEXT_COL) .. string.format('▸ %s diagram%s · o shows it', m.diagram.kind or '', n > 0 and (', ' .. n .. ' boxes') or ''), t.c.id), 0, -1, 'ThreadMeta')
  elseif m.diagram and type(m.diagram) == 'table' then
    P.add('', t.c.id)
    local a, b, drawn = draw_diagram(P, t, m.diagram, width)
    parts[#parts + 1] = { kind = 'diagram', index = index, drawn = drawn, id = 'd:' .. index, first = a, last = b }
  end
  -- What it changed, each place a part of its own.
  for k, ch in ipairs(m.changes or {}) do
    local a, b, view = draw_change(P, t, index, ch)
    parts[#parts + 1] = { kind = 'change', index = index, change = ch, view = view, id = 'c:' .. index .. ':' .. k, first = a, last = b }
  end
  -- The tour it leads to, each stop a part of its own.
  if type(m.walk) == 'table' and #m.walk > 0 then
    P.add('', t.c.id)
    vim.list_extend(parts, draw_stops(P, t, m, TEXT_COL + width))
  end
  return parts, found
end

--- A rule across Home above and below the thread that is open, so you can
--- see where it ends.
function divider(P, width, id)
  P.hl(P.add('  ' .. string.rep('─', math.max(4, width - 4)), id), 2, -1, 'ThreadTabRule')
end

--- The focused thread, opened: its code, then the last `level` messages.
local function draw_open(P, batch, t, level, width)
  -- The parts of the thread you can step through once inside it.
  S.items, S.refs = {}, {}
  P.add('', t.c.id)
  -- Its verdict, as a badge, when the agent gave one.
  local verdict = look.verdict_of(t.c)
  if verdict then
    local row = P.add(string.rep(' ', INDENT) .. ' ' .. verdict.text .. ' ', t.c.id)
    P.hl(row, INDENT, -1, verdict.hl)
    P.add('', t.c.id)
  end
  if t.line then
    local a, b = draw_code(P, t)
    S.items[#S.items + 1] = { kind = 'code', id = 'code', first = a, last = b }
    P.add('', t.c.id)
  elseif t.anchored and t.status ~= 'closed' then
    P.hl(P.add(string.rep(' ', INDENT) .. 'The line this was on is gone: the quote no longer matches the file.', t.c.id), 0, -1, 'DiagnosticWarn')
    P.add('', t.c.id)
  end
  -- A reply in a tour's stop: the stop it is in, and what the stop says.
  local batch_on = t.c.on and store.active()
  local owner, stop = nil, nil
  if batch_on then
    owner, stop = tour.owner(batch_on, t.c)
  end
  if owner and stop then
    local list = tour.of(owner)
    local where = string.format('in %s of %s · %s', tour.position(list, t.c.on.step), store.title(owner), tour.title(stop))
    P.hl(P.add(string.rep(' ', INDENT) .. '▶ ' .. where, t.c.id), INDENT, -1, 'ThreadLeads')
    -- What the stop says, in full only when focused or inside the thread.
    local lines = require('thread.text').wrap(tour.body(stop), math.max(30, math.min(96, width - TEXT_COL - 2)))
    if not (S.single or (S.inside and S.inside.id == t.c.id)) and #lines > 2 then
      lines = { lines[1], { text = '⋯' } }
    end
    for _, l in ipairs(lines) do
      local text, col, spans = string.rep(' ', TEXT_COL), TEXT_COL, {}
      for _, ch in ipairs(require('thread.text').segments(l)) do
        spans[#spans + 1] = { col, col + #ch[1], ch[2] == 'ThreadText' and 'ThreadMeta' or ch[2] }
        text = text .. ch[1]
        col = col + #ch[1]
      end
      local row = P.add(text, t.c.id)
      for _, sp in ipairs(spans) do
        P.hl(row, sp[1], sp[2], sp[3])
      end
    end
    P.add('', t.c.id)
  end
  local thread = t.c.messages
  local shown = math.min(level, #thread)
  if shown < #thread then
    local n = #thread - shown
    P.hl(P.add(string.rep(' ', INDENT) .. string.format('⋯ %d earlier message%s · l shows more', n, n == 1 and '' or 's'), t.c.id), 0, -1, 'ThreadMeta')
  end
  -- New is what was unseen when you arrived, so it stays marked while you
  -- read it, though showing it marked it seen.
  local seen = S.seen_at[t.c.id] or 0
  local text_width = math.max(30, math.min(96, width - TEXT_COL - 2))
  for i = #thread - shown + 1, #thread do
    if i > #thread - shown + 1 then
      P.add('', t.c.id)
    end
    local parts, found = draw_message(P, t, thread[i], i, i > seen and thread[i].from ~= 'you', text_width)
    local at_part = {}
    for _, part in ipairs(parts) do
      S.items[#S.items + 1] = part
      at_part[part.id] = #S.items
    end
    -- Inside a thread, the names in it, in reading order, for w and b.
    if S.inside and S.inside.id == t.c.id then
      for _, r in ipairs(found) do
        r.item = at_part[r.part] or #S.items
        S.refs[#S.refs + 1] = r
      end
    end
  end
  if S.inside and S.inside.id == t.c.id then
    resolve_selection()
  end
  -- Inside, a bar beside the part you are on.
  local at = S.inside and S.inside.id == t.c.id and S.items[S.inside.item]
  if at then
    for r = at.first, at.last do
      P.mark(r, math.max(0, INDENT - 2), { virt_text = { { '▎', 'ThreadFocus' } }, virt_text_pos = 'overlay' })
    end
  end
  local ref = selected_ref()
  if ref then
    P.hl(ref.first, ref.s, ref.e, 'ThreadRefFocus', { priority = 40 })
  end
  if S.reply and S.reply.id == t.c.id then
    S.reply.first = #P.lines -- 0-based row of the first reply line
    P.add('', t.c.id)
    local to = S.reply.ids and (' · goes to all ' .. #S.reply.ids .. ' marked') or ''
    local hint = P.add(string.rep(' ', TEXT_COL) .. '<C-s> save · <C-c> cancel' .. to, t.c.id)
    P.hl(hint, 0, -1, 'ThreadMeta')
    S.reply.hint = hint
  else
    P.add('', t.c.id)
    local close = { 'c', t.status == 'closed' and 'reopen' or 'close' }
    local n = vim.tbl_count(S.marked)
    local cur = current_ref()
    local on = S.inside and S.items and S.items[S.inside.item]
    local m = on and on.kind == 'message' and t.c.messages[on.index]
    local change = on and on.kind == 'change' and on
    local child = on and on.kind == 'stop' and on
    -- The message a tour hangs on: ⏎ walks it from the start.
    local _, intro = tour.of(t.c)
    local on_intro = intro and on and on.index == intro
    local start = { '⏎', 'walk from the start' }
    local leads = tour.leads(t.c) or t.c.on ~= nil
    local can_undo = change and change.view and #change.view.hunks > 0
    local keys = child and { { 'j/k', 'step' }, { '⏎', 'walk from here' }, { S.single and 'q' or 'o', 'back' } }
      or on and on.kind == 'diagram' and { { 'j/k', 'step' }, { '⏎', on_intro and 'on a box: its code, else walk' or 'on a box: its code' }, { S.single and 'q' or 'o', 'back' } }
      or change and vim.tbl_filter(function(k)
        return k ~= false
      end, { { 'j/k', 'step' }, { '⏎', 'the whole diff' },
        can_undo and { 'u', S.undo_armed == change.id and 'again to undo it' or 'undo it' } or false,
        { S.single and 'q' or 'o', 'back' } })
      or S.single and not cur and vim.tbl_filter(function(k)
        return k ~= false
      end, { { 'j/k', 'step' }, (S.prev or S.next) and { 'h/l', 'threads' } or false, intro and not t.anchored and start or false, leads and { 'J', 'resume' } or false,
        #S.refs > 0 and { 'w/b', 'names' } or false, t.line and { '+/-', 'code' } or false, { 'r', 'reply' }, close,
        t.anchored and { '⏎', 'go there' } or false,
        #(S.others or {}) > 1 and { 'tab', 'next here' } or false, { 'q', 'back' } })
      or n > 0 and { { 'space', S.marked[t.c.id] and 'unmark' or 'mark' }, { 'c', 'close or reopen ' .. n }, { 'r', 'reply to all ' .. n }, { 'Esc', 'unmark all' } }
      or cur and vim.tbl_filter(function(k)
        return k ~= false
      end, { { 'j/k', 'step' }, { 'w/b', 'names' }, { '⏎', S.open_refs[cur.key] and 'hide the code' or 'show the code' },
        #cur.places > 1 and S.open_refs[cur.key] and { 'n', 'next match' } or false,
        S.open_refs[cur.key] and { '+/-', 'lines' } or false, { S.single and 'Esc' or 'o', 'back' } })
      or S.inside and vim.tbl_filter(function(k)
        return k ~= false
      end, { { 'j/k', 'step' }, #S.refs > 0 and { 'w/b', 'names' } or false, { 'o', 'back' }, { 'r', 'reply' }, close, on_intro and start or { '⏎', 'go there' } })
      or vim.tbl_filter(function(k)
        return k ~= false
      end, { { 'o', 'open' }, { 'h/l', 'history' }, FILTERS[S.filter].view == 'tours' and intro and start or false, leads and { 'J', 'resume' } or false, { 'r', 'reply' }, close,
        not (FILTERS[S.filter].view == 'tours' and intro) and { '⏎', t.anchored and 'go there' or 'read it' } or false })
    if S.single then
      -- Focused, the keys sit in the float's border, always in sight.
      S.single_keys = keys
      P.lines[#P.lines] = nil
      P.owner[#P.lines + 1] = nil
    else
      key_hints(P, P.add('', t.c.id), INDENT, keys, width - 2)
    end
  end
  if not S.single then
    divider(P, width, t.c.id)
  end
end

--- The thread's line: where, glyph, title, its last few messages, the
--- change, who spoke last and what they said.
local function draw_row(P, t, focused, cols)
  local chunks = {}
  local function put(text, hl)
    chunks[#chunks + 1] = { text, hl }
  end
  local g, ghl = glyph(t)
  local last = t.c.messages[#t.c.messages]
  local where = t.line and tostring(t.line) or (t.anchored and '–' or '·')
  if cols.files and t.anchored then
    where = vim.fs.basename(t.c.file) .. ':' .. where
  end
  local marked = S.marked[t.c.id]
  put(focused and '▌ ' or '  ', 'ThreadFocus')
  put(string.rep(' ', math.max(0, cols.where - width_of(where))) .. where .. '  ', focused and 'ThreadFocus' or 'LineNr')
  put(g, ghl)
  -- ▶ when its answer leads somewhere: a walk.
  local batch = store.active()
  local leads = tour.leads(t.c)
  put(leads and ' ▶' or '  ', 'ThreadLeads')
  put(' ' .. pad(fit(title_of(t.c), cols.title), cols.title) .. '  ', (t.unseen or focused) and 'ThreadTitle' or nil)
  local w = 0
  for _, d in ipairs(dots(t)) do
    put(d[1], d[2])
    w = w + width_of(d[1])
  end
  put(string.rep(' ', look.DOTS_WIDTH + 1 - w))
  local add = (t.delta and t.delta.add > 0) and ('+' .. t.delta.add) or ''
  local del = (t.delta and t.delta.del > 0) and ('−' .. t.delta.del) or ''
  put(add, 'ThreadAdded')
  put(add ~= '' and del ~= '' and ' ' or '')
  put(del, 'ThreadRemoved')
  put(string.rep(' ', math.max(1, 9 - width_of(add .. del) - (add ~= '' and del ~= '' and 1 or 0))))
  if last then
    local label, label_hl = look.label(last)
    put(pad(label, 2), label_hl)
  else
    put(pad('', 2))
  end
  -- A step of a tour says which tour.
  local head = batch and t.c.on and tour.owner(batch, t.c)
  if head then
    put('in ' .. fit(title_of(head), 24) .. ' · ', 'ThreadCrumb')
  end
  local used = 0
  for _, c in ipairs(chunks) do
    used = used + width_of(c[1])
  end
  put(fit((first_line(last and last.text):gsub('`', '')), cols.total - used), t.status == 'closed' and 'ThreadMeta' or nil)

  local text, col = {}, 0
  for _, c in ipairs(chunks) do
    text[#text + 1] = c[1]
  end
  local row = P.add(table.concat(text), t.c.id)
  for _, c in ipairs(chunks) do
    if c[2] and c[1] ~= '' then
      P.hl(row, col, col + #c[1], c[2])
    end
    col = col + #c[1]
  end
  -- Marked with space: the whole row lifted, under its colours.
  if marked then
    P.hl(row, 0, -1, 'ThreadMarked', { hl_eol = true, priority = 5 })
    P.mark(row, 0, { virt_text = { { focused and '▌' or '▐', 'ThreadMarkedBar' } }, virt_text_pos = 'overlay' })
  end
  return row
end

--- Focused from the code: the one thread, all of it, nothing around it.
--- Focused from the code, the threads h and l go to: every open one, and
--- the one you are on, in file and line order.
local function neighbours(batch, id)
  id = id or S.single
  local list, files = {}, {}
  for _, c in ipairs(batch.data.threads) do
    local mine = c.id == id or store.status(c) ~= 'closed'
    if mine then
      local loc
      if store.anchored(c) then
        local key = (c.rev or '') .. ':' .. c.file
        if files[key] == nil then
          files[key] = anchor.lines_of(c) or false
        end
        loc = files[key] and anchor.locate(c, files[key])
      end
      list[#list + 1] = { c = c, line = loc and loc.line, anchored = store.anchored(c) }
    end
  end
  table.sort(list, function(a, b)
    local fa, fb = a.c.file or '\255', b.c.file or '\255'
    if fa ~= fb then
      return fa < fb
    end
    if (a.line or math.huge) ~= (b.line or math.huge) then
      return (a.line or math.huge) < (b.line or math.huge)
    end
    return a.c.id < b.c.id
  end)
  return list
end

--- Which threads h and l go to from the focused one, for its title.
--- The thread before (`dir` -1) or after `id`, in the order h and l go
--- through them, round the ends.
---@param id integer
---@param dir 1|-1
---@return thread.Comment|nil
function M.neighbour(id, dir)
  local batch = store.active()
  local list = batch and neighbours(batch, id) or {}
  for i, n in ipairs(list) do
    if n.c.id == id then
      return list[(i - 1 + dir) % #list + 1].c
    end
  end
  return list[1] and list[1].c
end

local function find_neighbours(batch)
  S.prev, S.next = nil, nil
  local list = neighbours(batch)
  for i, n in ipairs(list) do
    if n.c.id == S.single then
      -- Round the ends: h on the first goes to the last.
      if #list > 1 then
        S.prev, S.next = list[(i - 2) % #list + 1], list[i % #list + 1]
      end
    end
  end
  for _, n in ipairs { S.prev, S.next } do
    n.status, n.unseen = store.status(n.c), store.unseen(batch, n.c)
  end
end

local function draw_single(P, batch, width)
  local t = collect(batch, S.single)[1]
  if not t then
    P.add ''
    return
  end
  find_neighbours(batch)
  S.order, S.focus = { t.c.id }, t.c.id
  S.seen_at = S.seen_at or {}
  if S.seen_at[t.c.id] == nil then
    S.seen_at[t.c.id] = store.seen_count(batch, t.c)
  end
  S.row_of[t.c.id] = 1
  draw_open(P, batch, t, #t.c.messages, width)
  S.focused_thread, S.focused_level = t, #t.c.messages
end

--- The float's title: the focused thread's glyph, id, name and dots on
--- the left; on the right, the threads h and l go to.
function single_title()
  local t = S.focused_thread
  if not t then
    return ' '
  end
  local width = vim.api.nvim_win_get_width(S.win)
  local g, ghl = glyph(t)
  local left = { { ' ' } }
  -- The way back up: every thread above this one, by name.
  local batch = store.active()
  local owner = batch and t.c.on and tour.owner(batch, t.c)
  local path = { owner, t.c }
  if owner then
    left[#left + 1] = { fit(title_of(owner), 18), 'ThreadCrumb' }
    left[#left + 1] = { ' › ', 'ThreadCrumb' }
  else
    path = { t.c }
  end
  vim.list_extend(left, { { g, ghl }, { ' ' .. t.c.id .. ' ', 'ThreadMeta' } })
  left[#left + 1] = { fit(title_of(t.c), math.max(10, math.floor(width * (#path > 1 and 0.3 or 0.4)))), 'ThreadTitle' }
  left[#left + 1] = { ' ' }
  vim.list_extend(left, dots(t))
  left[#left + 1] = { ' ' }
  local function w(chunks)
    local n = 0
    for _, c in ipairs(chunks) do
      n = n + width_of(c[1])
    end
    return n
  end
  -- Each neighbour gets half of what is left, its name cut to fit.
  local room = math.floor((width - w(left) - 12) / 2)
  local right = {}
  local function side(n, before)
    if not n then
      return
    end
    local ng, nhl = glyph(n)
    local name = fit(title_of(n.c), math.max(6, room - 6))
    if before then
      vim.list_extend(right, { { ' h', 'ThreadKey' }, { ' ← ', 'ThreadKeyLabel' }, { ng, nhl }, { ' ' .. name .. ' ', 'ThreadKeyLabel' } })
    else
      vim.list_extend(right, { { ' ' .. name .. ' ', 'ThreadKeyLabel' }, { ng, nhl }, { ' → ', 'ThreadKeyLabel' }, { 'l ', 'ThreadKey' } })
    end
  end
  if room >= 10 then
    side(S.prev, true)
    if S.prev and S.next then
      right[#right + 1] = { '─', 'FloatBorder' }
    end
    side(S.next, false)
  end
  local fill = width - w(left) - w(right) - 1
  if #right > 0 and fill > 0 then
    left[#left + 1] = { string.rep('─', fill), 'FloatBorder' }
    vim.list_extend(left, right)
  end
  return left
end

function single_footer()
  local chunks = { { ' ' } }
  local keys = S.reply and { { '<C-s>', 'save' }, { '<C-c>', 'cancel' } } or vim.list_extend(vim.deepcopy(S.single_keys or {}), { { '?', 'help' } })
  for i, k in ipairs(keys) do
    if i > 1 then
      chunks[#chunks + 1] = { '  ' }
    end
    chunks[#chunks + 1] = { k[1], 'ThreadKey' }
    chunks[#chunks + 1] = { ' ' .. k[2], 'ThreadKeyLabel' }
  end
  chunks[#chunks + 1] = { ' ' }
  return chunks
end

--- In the middle of the editor, as tall as the thread up to nearly all of
--- it: the code it covers is drawn at its top.
function place()
  local width = math.min(vim.o.columns - 8, 110)
  local max = vim.o.lines - vim.o.cmdheight - 6
  vim.api.nvim_win_set_config(S.win, { width = width })
  local height = math.max(3, math.min(max, vim.api.nvim_win_text_height(S.win, {}).all))
  vim.api.nvim_win_set_config(S.win, {
    relative = 'editor',
    row = math.floor((vim.o.lines - vim.o.cmdheight - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
  })
end

--- The level a focused thread opens at: the last two messages, or further
--- back if more than that are new.
local function open_level(batch, t)
  S.seen_at = S.seen_at or {}
  if S.seen_at[t.c.id] == nil then
    S.seen_at[t.c.id] = store.seen_count(batch, t.c)
  end
  -- Under its row, a thread shows its last message; l shows more, o all.
  -- Focused from the code, the last two or all that is new.
  local level = S.levels[t.c.id] or (S.single and math.max(2, #t.c.messages - S.seen_at[t.c.id]) or 1)
  if S.inside and S.inside.id == t.c.id then
    level = #t.c.messages
  end
  return level
end

--- Keep focus on a row still listed, else the nearest one.
local function keep_focus()
  if not vim.tbl_contains(S.order, S.focus) then
    S.focus = S.order[math.min(S.focus_index or 1, #S.order)]
  end
end

--- The tours tab: every tour by its head, answers to your questions first,
--- then standalone ones. The focused one opens: its overview and outline.
function M.draw_tours(P, batch, threads, width)
  local by_id = {}
  for _, t in ipairs(threads) do
    by_id[t.c.id] = t
  end
  local groups = { { name = 'answers that walk you through it', list = {} }, { name = 'standalone tours', list = {} } }
  for _, h in ipairs(tour.tours(batch)) do
    local t = not tour.is_review(h) and by_id[h.id]
    if t then
      table.insert(groups[store.talked(h) and 1 or 2].list, t)
    end
  end
  S.order = {}
  for _, g in ipairs(groups) do
    for _, t in ipairs(g.list) do
      S.order[#S.order + 1] = t.c.id
    end
  end
  keep_focus()
  if #S.order == 0 then
    P.add ''
    P.hl(P.add '  No tours yet. An answer that walks you through the code is one.', 0, -1, 'ThreadMeta')
    return
  end
  for _, g in ipairs(groups) do
    if #g.list > 0 then
      P.add ''
      local hr = P.add('  ' .. g.name .. '  ' .. #g.list)
      P.hl(hr, 2, 2 + #g.name, 'ThreadTitle')
      P.hl(hr, 2 + #g.name, -1, 'ThreadMeta')
      for _, t in ipairs(g.list) do
        local focused = t.c.id == S.focus
        if focused then
          divider(P, width, t.c.id)
        end
        local list = tour.of(t.c)
        local seen_n = 0
        for n in ipairs(list) do
          if store.visited(batch, t.c.id, n) then
            seen_n = seen_n + 1
          end
        end
        local talks = tour.talks(batch, t.c.id)
        local g_, ghl = glyph(t)
        local where = t.anchored and (vim.fs.basename(t.c.file) .. ':' .. (t.line or '–')) or 'general'
        local lead = (focused and '▌ ' or '  ')
        local name = fit(title_of(t.c), math.min(40, math.floor(width * 0.35)))
        local text = lead .. g_ .. ' ▶ ' .. pad(name, math.min(40, math.floor(width * 0.35))) .. '  '
        local size = tour.describe(list)
        local seen_txt = string.format('%d/%d seen', seen_n, #list)
        local talk_txt = talks > 0 and string.format(' · %d with a conversation', talks) or ''
        local row = P.add(text .. pad(size, 22) .. pad(seen_txt, 12) .. pad(where, 24) .. talk_txt, t.c.id)
        P.hl(row, 0, #lead, 'ThreadFocus')
        P.hl(row, #lead, #lead + #g_, ghl)
        P.hl(row, #lead + #g_, #lead + #g_ + #' ▶', 'ThreadLeads')
        P.hl(row, #lead + #g_ + #' ▶ ', #text, (focused or t.unseen) and 'ThreadTitle' or nil)
        P.hl(row, #text, -1, 'ThreadMeta')
        S.row_of[t.c.id] = row + 1
        if focused then
          local level = open_level(batch, t)
          draw_open(P, batch, t, math.max(level, 1), width)
          S.focused_thread, S.focused_level = t, level
        end
      end
    end
  end
end

----------------------------------------------------------------------
-- Review: the reviews in the batch, each a line, and the groups of the
-- focused one under it
----------------------------------------------------------------------

local review = require 'thread.review'

--- Every thread that is a review.
local function reviews(batch)
  local out = {}
  for _, c in ipairs(batch.data.threads) do
    if review.of(c) and c.status ~= 'closed' then
      out[#out + 1] = c
    end
  end
  return out
end
M.reviews = reviews

--- What a review-tab row stands for: a review (`v:<id>`) or one of its
--- groups (`g:<id>:<stop>`).
---@return thread.Comment|nil owner, integer|nil n  the group's stop
local function review_row(batch, id)
  if type(id) ~= 'string' then
    return nil
  end
  local o, n = id:match '^[vg]:(%d+):?(%d*)$'
  local owner = o and store.find(batch, tonumber(o))
  return owner, tonumber(n)
end

--- With no review yet: the diff the batch asks for, file by file.
local function draw_unreviewed(P, batch, width)
  local spec = review.spec(batch.data.diff)
  P.add ''
  if not spec then
    P.hl(P.add '  No review yet. d picks a diff to review (unstaged, staged, uncommitted, or from a commit); then ask the agent to review it.', 0, -1, 'ThreadMeta')
    return
  end
  local files = review.files(spec)
  local hr = P.add(string.format('  %s  %d files · no review yet: ask the agent to review it', spec.label, #files))
  P.hl(hr, 2, 2 + #spec.label, 'ThreadTitle')
  P.hl(hr, 2 + #spec.label, -1, 'ThreadMeta')
  P.add ''
  for _, f in ipairs(files) do
    local add, del = '+' .. f.add, '−' .. f.del
    local text = '    ' .. pad(fit(f.file, math.floor(width * 0.5)), math.floor(width * 0.5)) .. '  '
    local col = #text
    local row = P.add(text .. add .. ' ' .. del .. '   ' .. #f.hunks .. (#f.hunks == 1 and ' hunk' or ' hunks'))
    P.hl(row, 4, col, 'Directory')
    P.hl(row, col, col + #add, 'ThreadAdded')
    P.hl(row, col + #add + 1, col + #add + 1 + #del, 'ThreadRemoved')
    P.hl(row, col + #add + 1 + #del, -1, 'ThreadMeta')
  end
end

--- The review tab: each review, how far you are through accepting it, and
--- under it its groups: what each is for, how risky, how big. The focused
--- group shows its hunks.
function M.draw_review(P, batch, width)
  S.order = {}
  local list = reviews(batch)
  if #list == 0 then
    return draw_unreviewed(P, batch, width)
  end
  local rows = {}
  for _, o in ipairs(list) do
    local walk = tour.of(o)
    rows[#rows + 1] = { id = 'v:' .. o.id, owner = o }
    for n, e in ipairs(walk) do
      if tour.kind(e) == 'stage' then
        rows[#rows + 1] = { id = 'g:' .. o.id .. ':' .. n, owner = o, n = n, e = e }
      end
    end
  end
  for _, r in ipairs(rows) do
    S.order[#S.order + 1] = r.id
  end
  keep_focus()
  for _, r in ipairs(rows) do
    local o = r.owner
    local rv = review.of(o)
    local w = review.work(rv)
    local focused = S.focus == r.id
    local lead = focused and '▌ ' or '  '
    if not r.n then
      -- The review itself.
      P.add ''

      local add, del = 0, 0
      for _, f in ipairs(w.files) do
        add, del = add + f.add, del + f.del
      end
      local name = title_of(o)
      local label = w.spec and w.spec.label or ('no diff: ' .. (w.err or '?'))
      local text = lead .. name .. '  '
      local col = #text
      text = text .. label .. string.format(' · %d files ', #w.files)
      local stat = #text
      text = text .. '+' .. add .. ' −' .. del
      local _, _, changed = review.progress(batch, o.id, w)
      local tail = '   ' .. review.said(batch, o.id, w)
      local row = P.add(text .. tail, r.id)
      P.hl(row, 0, #lead, 'ThreadFocus')
      P.hl(row, #lead, col, 'ThreadTitle')
      P.hl(row, col, stat, 'ThreadCrumbHere')
      P.hl(row, stat, stat + #('+' .. add), 'ThreadAdded')
      P.hl(row, stat + #('+' .. add) + 1, #text, 'ThreadRemoved')
      P.hl(row, #text, -1, changed > 0 and 'ThreadUnexplained' or 'ThreadMeta')
      S.row_of[r.id] = row + 1
      if focused then
        key_hints(P, P.add('', r.id), INDENT, { { '⏎', 'open it' }, { 'J', 'walk its hunks from where you left off' }, { 'd', 'the diff' } }, width - 2)
      end
    else
      local group = review.group_of(rv, r.e)
      local g = group.g
      local loose = group.k == 0
      local mark, mhl
      if loose then
        local n_ok = 0
        for _, h in ipairs(w.loose) do
          n_ok = n_ok + (review.hunk_accepted(batch, o.id, h) and 1 or 0)
        end
        mark, mhl = n_ok == #w.loose and '✓' or '⚠', n_ok == #w.loose and 'ThreadSignDone' or 'ThreadUnexplained'
      else
        local st = review.state(batch, o.id, group)
        mark = st == 'accepted' and '✓' or st == 'changed' and '◌' or st == 'partial' and '◑' or '○'
        mhl = st == 'accepted' and 'ThreadSignDone' or st == 'changed' and 'ThreadUnexplained' or st == 'partial' and 'ThreadLeads' or 'ThreadMeta'
      end
      local risk = look.risk(g.risk, true) or { ' ', 'ThreadMeta' }
      local kind = look.kind_badge(g.kind) or { '', 'ThreadMeta' }
      local text = lead .. '  ' .. mark .. ' ' .. risk[1] .. ' '
      local spans = { { #lead + 2, #lead + 2 + #mark, mhl }, { #lead + 3 + #mark, #lead + 3 + #mark + #risk[1], risk[2] } }
      local kcol = #text
      -- Kinds padded to one width, so the titles line up.
      text = text .. kind[1] .. string.rep(' ', 11 - width_of(kind[1]))
      spans[#spans + 1] = { kcol, kcol + #kind[1], kind[2] }
      local size = string.format('%d hunk%s', #group.hunks, #group.hunks == 1 and '' or 's')
      if #group.affected > 0 then
        size = size .. ' · ' .. #group.affected .. ' affected'
      end
      if #group.tests > 0 then
        size = size .. ' · ' .. #group.tests .. (#group.tests == 1 and ' test' or ' tests')
      end
      local talk = tour.thread_at(batch, o.id, r.n)
      local tcol = #text
      local name_w = math.max(10, width - width_of(text) - width_of(size) - 6)
      local title = fit(loose and 'not explained' or (g.title or ''), name_w)
      text = text .. pad(title, name_w) .. '  '
      local quiet = g.kind == 'chore' or g.kind == 'style' or g.kind == 'docs'
      spans[#spans + 1] = { tcol, tcol + #title, loose and 'ThreadUnexplained' or ((focused and 'ThreadTitle') or (mark == '✓' or quiet) and 'ThreadMeta' or 'ThreadText') }
      local scol = #text
      text = text .. size
      spans[#spans + 1] = { scol, #text, 'ThreadMeta' }
      if talk then
        local g_, ghl = look.glyph(store.status(talk), store.unseen(batch, talk), false)
        spans[#spans + 1] = { #text + 2, #text + 2 + #g_, ghl }
        text = text .. '  ' .. g_
      end
      local row = P.add(text, r.id)
      P.hl(row, 0, #lead, 'ThreadFocus')
      for _, sp in ipairs(spans) do
        P.hl(row, sp[1], sp[2], sp[3])
      end
      S.row_of[r.id] = row + 1
      if focused then
        -- Its hunks, a line each, and where it is risky.
        if type(g.risk_why) == 'string' and g.risk_why ~= '' then
          local why = P.add(string.rep(' ', INDENT + 2) .. fit(g.risk .. ' risk: ' .. g.risk_why, width - INDENT - 4), r.id)
          P.hl(why, INDENT + 2, -1, risk[2])
        end
        for j, x in ipairs(group.hunks) do
          if j > 8 then
            P.hl(P.add(string.rep(' ', INDENT + 2) .. string.format('⋯ %d more · ⏎ shows them all', #group.hunks - 8), r.id), 0, -1, 'ThreadMeta')
            break
          end
          local h = x.h
          local line
          if h then
            local span = h.lo == h.hi and tostring(h.lo) or (h.lo .. '–' .. h.hi)
            local ok = loose and review.hunk_accepted(batch, o.id, h)
            local where = (loose and (ok and '✓ ' or '○ ') or '') .. h.file .. ':' .. span
            local add, del = '+' .. h.add, '−' .. h.del
            local note = x.ref and x.ref.note or ''
            local body = string.rep(' ', INDENT + 2) .. pad(where, 36) .. '  '
            local c2 = #body
            line = P.add(body .. add .. ' ' .. del .. '   ' .. fit(note, math.max(10, width - c2 - 20)), r.id)
            P.hl(line, INDENT + 2, c2, 'Directory')
            P.hl(line, c2, c2 + #add, 'ThreadAdded')
            P.hl(line, c2 + #add + 1, c2 + #add + 1 + #del, 'ThreadRemoved')
            P.hl(line, c2 + #add + 1 + #del, -1, 'ThreadNote')
          else
            line = P.add(string.rep(' ', INDENT + 2) .. '⚠ ' .. (x.ref and x.ref.file or '?') .. ': no longer in the diff', r.id)
            P.hl(line, 0, -1, 'ThreadBroken')
          end
        end
        key_hints(P, P.add('', r.id), INDENT, {
          { '⏎', 'open it' },
          { 'a', review.state(batch, o.id, group) == 'accepted' and 'unaccept it' or 'accept it' },
          { 'r', 'ask about it' },
        }, width - 2)
      end
    end
  end
end

local function draw()
  if not (S and vim.api.nvim_win_is_valid(S.win)) then
    return
  end
  S.rendering = true
  local batch = store.active()
  local width = vim.api.nvim_win_get_width(S.win)
  local P = page()
  S.order, S.row_of, S.focused_thread = {}, {}, nil

  if not batch then
    P.add ''
    P.add('  No batch yet. Start a thread on a line with ' .. (look.key 'add' or ':Thread add') .. ', or press B for the batches.')
  elseif S.single then
    draw_single(P, batch, width)
  else
    local threads = collect(batch)
    local counts = {}
    for i in ipairs(FILTERS) do
      counts[i] = 0
    end
    local new = 0
    for _, t in ipairs(threads) do
      for i, f in ipairs(FILTERS) do
        if f.test(t) then
          counts[i] = counts[i] + 1
        end
      end
      new = new + ((t.unseen and t.status ~= 'closed' and t.status ~= 'info') and 1 or 0)
    end
    for i, f in ipairs(FILTERS) do
      if f.view == 'tours' then
        counts[i] = #vim.tbl_filter(function(c)
          return not tour.is_review(c)
        end, tour.tours(batch))
      elseif f.view == 'review' then
        counts[i] = #reviews(batch)
      end
    end

    -- The filters as tabs: a label each, the current one lifted out of the
    -- rule under them.
    local tabs, col = '  ', 2
    local spans = {}
    for i, f in ipairs(FILTERS) do
      if f.hidden then
        break
      end
      local s = string.format(' %s %s %d ', f.key, f.name, counts[i])
      if f.name == 'threads' and new > 0 then
        s = string.format(' %s %s %d · %d new ', f.key, f.name, counts[i], new)
      end
      spans[#spans + 1] = { col, col + #s, width_of(tabs), width_of(s), i == S.filter }
      tabs = tabs .. s .. ' '
      col = col + #s + 1
    end
    -- On the right, the search and the grouping, each with its key.
    local right = {
      { '/', S.query and S.query ~= '' and ('“' .. S.query .. '”') or 'search' },
      { 'g', 'by' },
    }
    local right_w = 1
    for i, k in ipairs(right) do
      right_w = right_w + width_of(k[1] .. ' ' .. k[2]) + (i > 1 and 3 or 0)
    end
    -- The groupings follow g, the current one raised like a tab.
    local choices = {}
    for i, g in ipairs(GROUPS) do
      choices[#choices + 1] = { ' ' .. g.name .. ' ', i == S.group }
      right_w = right_w + width_of(choices[#choices][1])
    end
    local gap = math.max(2, width - width_of(tabs) - right_w - 2)
    local trow = P.add(tabs)
    key_hints(P, trow, 0, right)
    local hints = P.lines[trow + 1]
    P.lines[trow + 1] = tabs .. string.rep(' ', gap) .. hints
    local shift = #tabs + gap
    for i = #P.hls, 1, -1 do
      local h = P.hls[i]
      if h[1] ~= trow then
        break
      end
      h[2], h[3] = h[2] + shift, h[3] + shift
    end
    if S.query and S.query ~= '' then
      P.hls[#P.hls - 2][4] = 'ThreadTitle'
    end
    local line = P.lines[trow + 1] .. ' '
    for _, c in ipairs(choices) do
      P.hl(trow, #line, #line + #c[1], c[2] and 'ThreadTabActive' or 'ThreadTab')
      line = line .. c[1]
    end
    P.lines[trow + 1] = line
    local rule, rule_spans = '', {}
    local at = 0
    for _, sp in ipairs(spans) do
      P.hl(trow, sp[1], sp[1] + 2, sp[5] and 'ThreadTabKeyActive' or 'ThreadTabKey')
      P.hl(trow, sp[1] + 2, sp[2], sp[5] and 'ThreadTabActive' or 'ThreadTab')
      if sp[5] then
        rule = string.rep('─', sp[3] - at) .. string.rep('━', sp[4])
        rule_spans[1] = { #string.rep('─', sp[3] - at), #rule }
        at = sp[3] + sp[4]
      end
    end
    rule = rule .. string.rep('─', math.max(0, width - at))
    local rrow = P.add(rule)
    P.hl(rrow, 0, -1, 'ThreadTabRule')
    if rule_spans[1] then
      P.hl(rrow, rule_spans[1][1], rule_spans[1][2], 'ThreadTabUnder')
    end

    local view = FILTERS[S.filter].view
    if view == 'tours' then
      M.draw_tours(P, batch, threads, width)
    elseif view == 'review' then
      M.draw_review(P, batch, width)
    else
    -- Grouped by file, turn or round; in file and line order within a group.
    local filter = FILTERS[S.filter]
    local grouping = GROUPS[S.group]
    local groups, order, label = {}, {}, {}
    for _, t in ipairs(threads) do
      if filter.test(t) then
        local key, name = grouping.of(t, batch)
        if not groups[key] then
          groups[key] = {}
          order[#order + 1] = key
          label[key] = name
        end
        table.insert(groups[key], t)
      end
    end
    table.sort(order)
    local by_file = grouping.name == 'file'
    local title_w, where_w = 12, 4
    for _, t in ipairs(threads) do
      title_w = math.max(title_w, width_of(title_of(t.c)))
      if not by_file then
        where_w = math.max(where_w, width_of(t.anchored and (vim.fs.basename(t.c.file) .. ':' .. (t.line or '–')) or '·'))
      end
    end
    local cols = { title = math.min(title_w, 36, math.floor(width * 0.3)), total = width - 2, files = not by_file, where = math.min(where_w, 24) }

    for _, key in ipairs(order) do
      table.sort(groups[key], function(a, b)
        local fa, fb = a.c.file or '\255', b.c.file or '\255'
        if fa ~= fb then
          return fa < fb
        end
        if (a.line or math.huge) ~= (b.line or math.huge) then
          return (a.line or math.huge) < (b.line or math.huge)
        end
        return a.c.id < b.c.id
      end)
      for _, t in ipairs(groups[key]) do
        S.order[#S.order + 1] = t.c.id
      end
    end
    -- On opening, focus the first thread that needs you, in the order shown:
    -- something new, then your turn, then anything open.
    if S.pick_first then
      S.pick_first = false
      local by_id, rank = {}, math.huge
      for _, t in ipairs(threads) do
        by_id[t.c.id] = t
      end
      for _, id in ipairs(S.order) do
        local t = by_id[id]
        local open = t.status ~= 'closed'
        local r = (open and t.unseen) and 1 or (t.status == 'answered' and 2) or (open and 3) or 4
        if r < rank then
          S.focus, rank = id, r
        end
      end
    end
    -- Keep focus on a thread that is still listed, else the nearest one.
    if not vim.tbl_contains(S.order, S.focus) then
      local at = S.focus_index or 1
      S.focus = S.order[math.min(at, #S.order)]
    end

    if #order == 0 then
      P.add ''
      local why = (S.query and S.query ~= '') and ('Nothing mentions “' .. S.query .. '”. Esc clears the search.')
        or #threads == 0 and ('Start a thread on a line with ' .. (look.key 'add' or ':Thread add') .. ', or ask with ' .. (look.key 'ask' or ':Thread ask') .. '.') or '2 shows the tours, 4 the closed ones.'
      P.hl(P.add('  Nothing here. ' .. why), 0, -1, 'ThreadMeta')
    end
    for _, key in ipairs(order) do
      P.add ''
      local name = label[key]
      local hr = P.add('  ' .. name .. '  ' .. #groups[key])
      P.hl(hr, 2, 2 + #name, by_file and 'Directory' or 'ThreadTitle')
      P.hl(hr, 2 + #name, -1, 'ThreadMeta')
      for _, t in ipairs(groups[key]) do
        local focused = t.c.id == S.focus
        if focused then
          divider(P, width, t.c.id)
        end
        S.row_of[t.c.id] = draw_row(P, t, focused, cols) + 1
        if focused then
          local level = open_level(batch, t)
          if level > 0 or (S.reply and S.reply.id == t.c.id) then
            draw_open(P, batch, t, math.max(level, 1), width)
          end
          S.focused_thread, S.focused_level = t, level
        end
      end
    end
    end
  end

  if S.single then
    vim.api.nvim_win_set_config(S.win, { title = single_title(), title_pos = 'left', footer = single_footer(), footer_pos = 'right' })
  else
    vim.api.nvim_win_set_config(S.win, { footer = footer(), footer_pos = 'right' })
  end

  local buf = S.buf
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, P.lines)
  vim.bo[buf].modifiable = S.reply ~= nil
  vim.bo[buf].modified = false
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(P.hls) do
    local len = #(P.lines[h[1] + 1] or '')
    local s = math.min(h[2], len)
    local e = (h[3] < 0 or h[3] > len) and len or h[3]
    local opts = vim.tbl_extend('force', { end_col = e, hl_group = h[4], priority = 15 }, h[5] or {})
    if opts.hl_eol then
      opts.end_row, opts.end_col = h[1] + 1, 0
    end
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, h[1], s, opts)
  end
  for _, m in ipairs(P.marks) do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, m[1], m[2], m[3])
  end
  S.owner = P.owner
  if S.single then
    place()
    strip()
  end

  -- The cursor on the focused row, and its whole opened thread in view.
  local row = S.focus and S.row_of[S.focus]
  if S.inside and S.inside.id ~= S.focus then
    S.inside = nil
  end
  local item = S.inside and S.items and S.items[S.inside.item]
  if row then
    local last = row
    while P.owner[last + 1] == S.focus do
      last = last + 1
    end
    if item then
      row, last = item.first + 1, item.last + 1
    end
    -- On a name: it, and its code when open, in view, the cursor on it.
    local ref = selected_ref()
    if ref then
      row = ref.first + 1
      last = row + (S.open_refs[ref.key] and (REF_SIZES[S.ref_size[ref.key] or 2] + 4) or 0)
    end
    local height = vim.api.nvim_win_get_height(S.win)
    local view = vim.api.nvim_win_call(S.win, vim.fn.winsaveview)
    local top = view.topline
    if row < top then
      top = math.max(1, row - 1)
    elseif last >= top + height then
      top = math.max(1, math.min(row - 2, last - height + 1))
    end
    local lnum = row
    if S.reply and S.reply.first then
      lnum = S.reply.first + 1
    end
    vim.api.nvim_win_call(S.win, function()
      vim.fn.winrestview { topline = top, lnum = lnum, col = ref and not S.reply and ref.s or 0 }
    end)
    for i, id in ipairs(S.order) do
      if id == S.focus then
        S.focus_index = i
      end
    end
    -- Seen once every message you had not seen is on screen.
    local t = S.focused_thread
    if t and batch then
      local shown = math.min(#t.c.messages, S.focused_level or 0)
      if shown > 0 and #t.c.messages - shown <= store.seen_count(batch, t.c) then
        store.mark_seen(batch, t.c)
      end
    end
  end
  S.rendering = false
end

----------------------------------------------------------------------
-- Replying in place
----------------------------------------------------------------------

--- Rows of the reply being typed, 0-based, from its first line to the hint.
local function reply_rows()
  local hint = vim.api.nvim_buf_get_extmark_by_id(S.buf, label_ns, S.reply.hint_mark, {})[1]
  return S.reply.first, hint - 1
end

local function relabel()
  if not (S and S.reply and S.reply.hint_mark) then
    return
  end
  local first, last = reply_rows()
  S.reply.hint = last + 1
  vim.api.nvim_buf_clear_namespace(S.buf, label_ns, 0, -1)
  S.reply.hint_mark = vim.api.nvim_buf_set_extmark(S.buf, label_ns, last + 1, 0, {})
  for r = first, last do
    local text = r == first and (string.rep(' ', INDENT) .. pad(look.label { from = 'you' }, LABEL)) or string.rep(' ', TEXT_COL)
    vim.api.nvim_buf_set_extmark(S.buf, label_ns, r, 0, {
      virt_text = { { text, r == first and 'ThreadYou' or 'Normal' } },
      virt_text_pos = 'inline',
      right_gravity = false,
    })
  end
end

--- The speaker label in front of each reply line, drawn as virtual text so
--- the text you type stays plain.
local function label_reply()
  S.reply.hint_mark = vim.api.nvim_buf_set_extmark(S.buf, label_ns, S.reply.hint, 0, {})
  relabel()
end

local function start_reply()
  if not S.focus then
    return
  end
  -- With threads marked, one reply goes to each of them.
  local ids = vim.tbl_keys(S.marked)
  S.reply = { id = S.focus, ids = #ids > 0 and ids or nil }
  if (S.levels[S.focus] or 1) < 1 then
    S.levels[S.focus] = 1
  end
  draw()
  label_reply()
  vim.api.nvim_win_set_cursor(S.win, { S.reply.first + 1, 0 })
  vim.cmd 'startinsert'
end

local function end_reply(save)
  if not (S and S.reply) then
    return
  end
  local text = ''
  if S.reply.hint_mark then
    local first, last = reply_rows()
    text = vim.trim(table.concat(vim.api.nvim_buf_get_lines(S.buf, first, last + 1, false), '\n'))
  end
  local id, ids = S.reply.id, S.reply.ids
  S.reply = nil
  vim.api.nvim_buf_clear_namespace(S.buf, label_ns, 0, -1)
  vim.cmd 'stopinsert'
  local batch = store.active()
  local c = batch and store.find(batch, id)
  if save and ids and text ~= '' then
    store.reply_all(batch, ids, text)
    S.marked = {}
  elseif save and c and text ~= '' then
    S.levels[id] = math.max(S.levels[id] or 1, 2)
    store.reply(batch, c, text) -- notifies, which redraws
  end
  if S.quick then
    -- Opened only to reply: back to the code.
    M.close()
    return
  end
  draw()
  if S.inside and S.items then
    select(#S.items)
    draw()
  end
end

----------------------------------------------------------------------
-- Keys
----------------------------------------------------------------------

local function focused()
  local batch = store.active()
  return batch, batch and S.focus and store.find(batch, S.focus)
end

local function move(n)
  if #S.order == 0 then
    return
  end
  local i = (S.focus_index or 1) + n
  i = math.max(1, math.min(#S.order, i))
  if S.order[i] ~= S.focus then
    S.seen_at = {}
  end
  S.focus = S.order[i]
  draw()
end

local function level(n)
  if not S.focus then
    return
  end
  local _, c = focused()
  local max = c and #c.messages or 1
  local cur = S.levels[S.focus] or S.focused_level or 2
  S.levels[S.focus] = math.max(0, math.min(max, cur + n))
  draw()
end

--- Go into the focused thread: its whole history, stepped through part by
--- part. You land on the first message you had not seen, else the last.
local function enter()
  if not S.focus or S.inside then
    return
  end
  local batch, c = focused()
  if not c then
    return
  end
  local seen = (S.seen_at and S.seen_at[c.id]) or store.seen_count(batch, c)
  S.inside = { id = c.id, index = #c.messages }
  for i, m in ipairs(c.messages) do
    if i > seen and m.from ~= 'you' then
      S.inside.index = i
      break
    end
  end
  draw()
  -- Items are only known once drawn: find the one for that message.
  for n, it in ipairs(S.items or {}) do
    if it.kind == 'message' and it.index == S.inside.index then
      select(n)
      break
    end
  end
  draw()
end

local function leave()
  if S.single then
    M.close()
  elseif S.inside then
    S.inside = nil
    draw()
  end
end

--- Inside a thread: the next (or previous) part of it.
local function step(n)
  local count = #(S.items or {})
  if count == 0 then
    return
  end
  select(math.max(1, math.min(count, (S.inside.item or count) + n)))
  S.inside.ref, S.undo_armed = nil, nil
  draw()
end

--- Inside a thread: the next (or previous) name that points at code, across
--- its messages; the message it is in becomes the one you are on.
local function ref_step(n)
  local list = S.inside and S.refs or {}
  if #list == 0 then
    return
  end
  local at
  for i, r in ipairs(list) do
    if r.key == S.inside.ref then
      at = i + n
    end
  end
  if not at then
    -- From a message: its first name going on, the one before it going back.
    local item = S.inside.item or 1
    for i = n > 0 and 1 or #list, n > 0 and #list or 1, n do
      if (n > 0 and list[i].item >= item) or (n < 0 and list[i].item < item) then
        at = i
        break
      end
    end
  end
  local r = at and list[at]
  if r then
    S.inside.ref = r.key
    select(r.item)
    draw()
  end
end

--- Show more or less of the focused thread's code.
local function code(n)
  -- On a name whose code is open, or on that code, it grows or shrinks.
  local ref = current_ref()
  if ref and S.open_refs[ref.key] then
    S.ref_size[ref.key] = math.max(1, math.min(#REF_SIZES, (S.ref_size[ref.key] or 2) + n))
    draw()
    return
  end
  if S.focus then
    S.code[S.focus] = math.max(0, math.min(2, (S.code[S.focus] or 1) + n))
    draw()
  end
end

--- Narrow the threads to those that mention what you type, as you type it.
local function search()
  local before = S.query
  local group = vim.api.nvim_create_augroup('thread.home.search', { clear = true })
  vim.api.nvim_create_autocmd('CmdlineChanged', {
    group = group,
    callback = function()
      S.query = vim.fn.getcmdline()
      draw()
      vim.cmd.redraw()
    end,
  })
  local ok, q = pcall(vim.fn.input, { prompt = '/', default = before or '', cancelreturn = '\0' })
  vim.api.nvim_del_augroup_by_id(group)
  if not S then
    return
  end
  if not ok or q == '\0' then
    S.query = before
  else
    S.query = q ~= '' and q or nil
  end
  draw()
end

--- What the glyphs mean and what every key does, in a float over Home.
local function help()
  local lines, hls = {}, {}
  local function add(text, spans)
    lines[#lines + 1] = text
    for _, sp in ipairs(spans or {}) do
      hls[#hls + 1] = { #lines - 1, sp[1], sp[2], sp[3] }
    end
  end
  local function head(text)
    add('', {})
    add('  ' .. text, { { 2, 2 + #text, 'ThreadTitle' } })
  end
  head 'Whose move'
  local function g_(status, unseen)
    return look.glyph(status, unseen)
  end
  for _, g in ipairs {
    { g_('answered', true), 'ThreadSignAnswered', 'your move: the agent answered, something new in it' },
    { g_('answered'), 'ThreadSignAnswered', 'your move: read, yours to reply or close' },
    { g_('waiting'), 'ThreadSignWaiting', 'the agent\'s move: it has your message' },
    { g_('info', true), 'ThreadSignInfoNew', 'a tour or explanation the agent started, new' },
    { g_('info'), 'ThreadSignInfo', 'a tour or explanation, read; nobody\'s move' },
    { '▶', 'ThreadLeads', 'its answer leads to a tour you can walk' },
    { '▸', 'ThreadSignInfo', 'in the code\'s margin: a tour\'s stop; ▎ is a thread' },
    { g_('closed'), 'ThreadSignDone', 'closed' },
    { '!', 'DiagnosticWarn', 'its line is gone from the file' },
  } do
    add('    ' .. g[1] .. '  ' .. g[3], { { 4, 4 + #g[1], g[2] }, { 4 + #g[1], -1, 'ThreadKeyLabel' } })
  end
  add('    deep blue is your move, pink the agent\'s, light blue a tour', {
    { 4, 13, 'ThreadSignAnswered' }, { 13, 28, 'ThreadKeyLabel' }, { 28, 32, 'ThreadSignWaiting' }, { 32, 46, 'ThreadKeyLabel' },
    { 46, 56, 'ThreadSignInfoNew' }, { 56, -1, 'ThreadKeyLabel' },
  })
  head 'Who said what'
  do
    local you, you_hl = look.who { from = 'you' }
    local agent, agent_hl = look.who { from = 'agent' }
    local new, new_hl = look.who({ from = 'agent' }, true)
    local function legend(g, hl, what)
      add('    ' .. g .. '  ' .. what, { { 4, 4 + #g, hl }, { 4 + #g, -1, 'ThreadKeyLabel' } })
    end
    legend(you, you_hl, 'you')
    legend(agent, agent_hl, 'the agent')
    legend(new, new_hl, "the agent, not read yet (lit)")
    add('    the last five messages show as these shapes, oldest first', { { 4, -1, 'ThreadKeyLabel' } })
  end
  add('    +2 −1  how the code there changed since you sent it', {
    { 4, 6, 'ThreadAdded' }, { 7, 7 + #'−1', 'ThreadRemoved' }, { 7 + #'−1', -1, 'ThreadKeyLabel' },
  })
  local function keys(title, list)
    head(title)
    for _, k in ipairs(list) do
      local key = '    ' .. k[1]
      add(key .. string.rep(' ', 16 - width_of(key)) .. k[2], { { 4, #key, 'ThreadKey' }, { #key, -1, 'ThreadKeyLabel' } })
    end
  end
  keys('Moving', {
    { 'j / k', 'next / previous thread' },
    { 'tab / S-tab', 'next / previous tab' },
    { '1 2', 'threads · tours' },
    { '3 4', 'the review of a diff · closed' },
    { 'h / l', 'less / more of the history' },
    { 'H / L', 'none / all of it' },
    { 'o', 'open the thread: j/k step through it, o or Esc back' },
    { 'w / b', 'inside: next / previous underlined name; ⏎ shows its code' },
    { '', 'n its next match, + / - more or fewer lines of it' },
    { '+ / -', 'more or less of its code, up to the whole function' },
    { 'J', 'walk the tour its answer leads to, or the one it is in, from where you left off' },
    { 'h / l', 'in the float: the threads either side' },
    { '/', 'show only threads that mention something; Esc clears' },
    { 'g', 'group by file, by whose turn, or by round' },
  })
  keys('Acting', {
    { 'r', 'reply here: <C-s> saves, <C-c> cancels' },
    { 'c', 'close, or reopen a closed one' },
    { 'space', 'mark threads: then c and r act on all of them' },
    { '⏎', 'go to the code; on a change its diff; on a stop walk from it;' },
    { '', 'on a diagram box its code; in review a group\'s page' },
    { 'a / d', 'review: accept a group / pick the diff to review' },
    { 'u', 'on a change: undo it (press twice), the old lines put back' },
    { 'B', 'the batches' },
    { 'q / Esc', S.single and 'back to the code' or 'close Home' },
  })
  add('', {})
  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, width_of(l) + 2)
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_set_extmark(buf, ns, h[1], h[2], { end_col = h[3] < 0 and #lines[h[1] + 1] or h[3], hl_group = h[4] })
  end
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    row = math.floor((vim.o.lines - #lines) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = #lines,
    border = 'rounded',
    style = 'minimal',
    title = ' Help ',
    title_pos = 'center',
    zindex = 60,
  })
  -- Home stays open behind it, and gets the focus back.
  S.helping = true
  local function done()
    if S then
      S.helping = false
    end
    pcall(vim.api.nvim_win_close, win, true)
    if S and vim.api.nvim_win_is_valid(S.win) then
      vim.api.nvim_set_current_win(S.win)
    end
  end
  for _, lhs in ipairs { 'q', '?', '<Esc>', '<CR>' } do
    vim.keymap.set('n', lhs, done, { buffer = buf, nowait = true })
  end
  vim.api.nvim_create_autocmd('WinLeave', { buffer = buf, once = true, callback = function()
    vim.schedule(done)
  end })
end

--- Put back what a change replaced: the old lines of each of its hunks,
--- written to the file. Its buffer's own undo brings the change back.
local function undo_change(it)
  local v, file = it.view, it.change.file
  local buf = vim.fn.bufadd(store.root() .. '/' .. file)
  vim.fn.bufload(buf)
  if not vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), v.new) then
    vim.notify('thread: ' .. file .. ' changed since this was drawn; look again and undo again', vim.log.levels.WARN)
    return draw()
  end
  local hunks = vim.deepcopy(v.hunks)
  table.sort(hunks, function(a, b)
    return a.new_start > b.new_start
  end)
  for _, h in ipairs(hunks) do
    local old = vim.list_slice(v.old, h.old_start, h.old_start + h.old_count - 1)
    if h.new_count == 0 then
      vim.api.nvim_buf_set_lines(buf, h.new_start, h.new_start, false, old)
    else
      vim.api.nvim_buf_set_lines(buf, h.new_start - 1, h.new_start - 1 + h.new_count, false, old)
    end
  end
  vim.api.nvim_buf_call(buf, function()
    vim.cmd 'silent write'
  end)
  vim.notify(string.format('thread: undid the change in %s; u in that file brings it back', file))
  draw()
end

local KEYS = {
  j = function(count)
    if S.inside then
      step(count)
    else
      move(count)
    end
  end,
  k = function(count)
    if S.inside then
      step(-count)
    else
      move(-count)
    end
  end,
  ['<Down>'] = function()
    if S.inside then
      step(1)
    else
      move(1)
    end
  end,
  ['<Up>'] = function()
    if S.inside then
      step(-1)
    else
      move(-1)
    end
  end,
  -- o opens the thread: all of it, stepped through with j/k; o again or
  -- Esc comes back out.
  o = function()
    if S.inside then
      leave()
    else
      enter()
    end
  end,
  l = function()
    if S.single then
      return M.go(S.next and S.next.c.id)
    end
    level(1)
  end,
  h = function()
    if S.single then
      return M.go(S.prev and S.prev.c.id)
    end
    level(-1)
  end,
  L = function()
    if S.single then
      return M.go(S.next and S.next.c.id)
    end
    level(math.huge)
  end,
  H = function()
    if S.single then
      return M.go(S.prev and S.prev.c.id)
    end
    level(-math.huge)
  end,
  -- Walk the tour its answer leads to, or the one it is a reply in.
  J = function()
    if FILTERS[S.filter].view == 'review' then
      local owner = review_row(store.active(), S.focus)
      if owner then
        M.close()
        require('thread.walk').start(owner.id)
      end
      return
    end
    local _, c = focused()
    if not (c and (tour.leads(c) or c.on)) then
      return
    end
    M.close()
    require('thread.walk').start(c.id)
  end,
  a = function()
    if FILTERS[S.filter].view ~= 'review' then
      return
    end
    local batch = store.active()
    local owner, n = review_row(batch, S.focus)
    if not (owner and n) then
      return
    end
    local rv = review.of(owner)
    local group = review.group_of(rv, tour.of(owner)[n])
    review.toggle(batch, owner.id, group)
    draw()
  end,
  d = function()
    if FILTERS[S.filter].view ~= 'review' then
      return
    end
    local batch = store.active()
    if not batch then
      return
    end
    local cur = type(batch.data.diff) == 'table' and batch.data.diff or {}
    local function set(d)
      batch.data.diff = d
      store.save(batch)
      store.notify()
      vim.notify('thread: the diff to review is ' .. review.spec(d).label .. '; ask the agent to review it')
    end
    local choices = {
      { 'uncommitted: everything since the last commit', { of = 'uncommitted' } },
      { 'staged: what the next commit would hold', { of = 'staged' } },
      { 'unstaged: what is not staged yet', { of = 'unstaged' } },
      { 'since a commit, to the working tree', 'base' },
      { 'between two commits', 'range' },
    }
    vim.ui.select(choices, {
      prompt = 'Review which diff?',
      format_item = function(x)
        return x[1]
      end,
    }, function(x)
      if not x then
        return
      end
      if type(x[2]) == 'table' then
        return set(x[2])
      end
      vim.ui.input({ prompt = 'From (a commit, branch or tag): ', default = cur.base or 'main' }, function(base)
        if not base or vim.trim(base) == '' then
          return
        end
        if x[2] == 'base' then
          return set { base = vim.trim(base) }
        end
        vim.ui.input({ prompt = 'To: ', default = cur.head or 'HEAD' }, function(head)
          if head and vim.trim(head) ~= '' then
            set { base = vim.trim(base), head = vim.trim(head) }
          end
        end)
      end)
    end)
  end,
  r = function()
    if FILTERS[S.filter].view == 'review' then
      -- On a group: ask about it, in a thread on it.
      local owner, n = review_row(store.active(), S.focus)
      if owner and n then
        M.close()
        actions.reply_stop(owner.id, n)
      end
      return
    end
    start_reply()
  end,
  c = function()
    if FILTERS[S.filter].view == 'review' then
      return
    end
    local batch, c = focused()
    if next(S.marked) and batch then
      -- Close them all, or reopen them all if every one is closed.
      local ids, all_closed = vim.tbl_keys(S.marked), true
      for _, id in ipairs(ids) do
        local m = store.find(batch, id)
        all_closed = all_closed and m ~= nil and store.status(m) == 'closed'
      end
      S.marked = {}
      store.set_status_all(batch, ids, all_closed and 'open' or 'closed')
    elseif c then
      actions.toggle_closed(batch, c)
    end
  end,
  ['<Space>'] = function()
    if S.focus then
      S.marked[S.focus] = not S.marked[S.focus] or nil
      move(1)
      draw()
    end
  end,
  n = function()
    local ref = current_ref()
    local open = ref and S.open_refs[ref.key]
    if open then
      S.open_refs[ref.key] = open % #ref.places + 1
      draw()
    end
  end,
  w = function()
    ref_step(1)
  end,
  b = function()
    ref_step(-1)
  end,
  g = function()
    S.group = S.group % #GROUPS + 1
    draw()
  end,
  ['/'] = search,
  ['+'] = function()
    code(1)
  end,
  ['='] = function()
    code(1)
  end,
  ['-'] = function()
    code(-1)
  end,
  ['<CR>'] = function()
    local id, at = require('thread.text').link_at(vim.api.nvim_get_current_line(), vim.api.nvim_win_get_cursor(S.win)[2])
    if id and store.find(store.active(), id) then
      M.close()
      return render.follow_link(id, at)
    end
    if FILTERS[S.filter].view == 'review' then
      -- A review: its screen, on the group if on one.
      local owner, n = review_row(store.active(), S.focus)
      if owner then
        M.close()
        require('thread.review_page').open { owner = owner.id, n = n }
      end
      return
    end
    local batch, c = focused()
    if not c then
      return
    end
    local item = S.inside and S.items and S.items[S.inside.item]
    -- On a stop of the tour an answer leads to: walk from it.
    if item and item.kind == 'stop' then
      M.close()
      require('thread.walk').start(c.id, item.n)
      return
    end
    -- A tour's own row, its overview or the message that leads to it:
    -- walk it from its first stop.
    local _, at = tour.of(c)
    if at and (FILTERS[S.filter].view == 'tours' and not S.inside or (item and item.kind == 'message' and item.index == at) or (S.single and not S.inside and not store.anchored(c))) then
      M.close()
      require('thread.walk').start(c.id, 1)
      return
    end
    -- On a diagram: the box under the cursor, its code.
    if item and item.kind == 'diagram' then
      local cur = vim.api.nvim_win_get_cursor(S.win)
      local vcol = vim.fn.virtcol { cur[1], cur[2] + 1 } - 1
      local node = item.drawn and diagram.hit(item.drawn, cur[1] - 1 - item.first, vcol - TEXT_COL)
      if node and node.file then
        M.close()
        actions.jump { id = 0, file = node.file, text = node.text, line = node.line }
      elseif at and item.index == at then
        -- The tour's diagram, off its boxes with code: the tour.
        M.close()
        require('thread.walk').start(c.id, 1)
      else
        vim.notify('thread: put the cursor on a box with code behind it', vim.log.levels.INFO)
      end
      return
    end
    -- A thread about no line: from the list, its page; on the page, nothing.
    if not store.anchored(c) and not (item and item.kind == 'change') and not current_ref() then
      if not S.single then
        local id = c.id
        M.close()
        M.focus { comment = store.find(store.active(), id) }
      end
      return
    end
    -- On a name, its code opens or closes under its paragraph; on that code,
    -- it closes, and you are back on the name.
    local ref = current_ref()
    if ref then
      if S.open_refs[ref.key] then
        S.open_refs[ref.key] = nil
        S.inside.ref = ref.key
        S.inside.sel = ref.part
      else
        S.open_refs[ref.key] = 1
      end
      draw()
      return
    end
    -- On a change, its whole diff; else the thread's line.
    M.close()
    if item and item.kind == 'change' then
      actions.changes(batch, c, { change = item.change, index = item.index })
    else
      actions.jump(c)
    end
  end,
  u = function()
    local it = S.inside and S.items and S.items[S.inside.item]
    if not (it and it.kind == 'change' and it.view and #it.view.hunks > 0) then
      return
    end
    -- Twice: the first press only says what the second will do.
    if S.undo_armed ~= it.id then
      S.undo_armed = it.id
      return draw()
    end
    S.undo_armed = nil
    undo_change(it)
  end,
  B = function()
    M.close()
    require('thread.menu').open()
  end,
  q = function()
    M.close()
  end,
  ['<Esc>'] = function()
    if S.inside then
      leave()
    elseif next(S.marked) then
      S.marked = {}
      draw()
    elseif S.query then
      S.query = nil
      draw()
    else
      M.close()
    end
  end,
  ['?'] = function()
    help()
  end,
}
-- Numbers switch tabs here, so the ones without a tab must not start a
-- count, and Home is not text to edit outside a reply: these do nothing.
for _, lhs in ipairs { '5', '6', '7', '8', '9', '0', 'A', 'i', 'I', 'O', 'S', 'C', 'D', 'R', 'x', 'X', 'p', 'P', 'V', '<C-r>', '.' } do
  KEYS[lhs] = function() end
end
--- Focused from the code: the next of the threads on that line.
local function other(n)
  local list = S.others or {}
  if #list < 2 then
    return
  end
  local at = 1
  for i, id in ipairs(list) do
    if id == S.single then
      at = i
    end
  end
  S.single = list[(at - 1 + n) % #list + 1]
  S.inside, S.seen_at = nil, {}
  draw()
  enter()
end
KEYS['<Tab>'] = function()
  if S.single then
    return other(1)
  end
  S.filter = S.filter % TABS + 1
  draw()
end
KEYS['<S-Tab>'] = function()
  if S.single then
    return other(-1)
  end
  S.filter = (S.filter - 2) % TABS + 1
  draw()
end
-- Focused from the code there is one thread and nothing to filter, group
-- or mark.
local NOT_SINGLE = { g = true, ['/'] = true, ['<Space>'] = true }
for i, f in ipairs(FILTERS) do
  if f.key then
    NOT_SINGLE[f.key] = true
    KEYS[f.key] = function()
      S.filter = i
      draw()
    end
  end
end

local function map_keys(buf)
  for lhs, fn in pairs(KEYS) do
    -- While a reply is being typed, normal mode is for editing it: every key
    -- does what it always does.
    vim.keymap.set('n', lhs, function()
      if S and S.reply then
        return lhs
      end
      if S and S.single and NOT_SINGLE[lhs] then
        return ''
      end
      local count = vim.v.count1
      vim.schedule(function()
        -- Gone in the meantime (a key that closed it came first).
        if S and vim.api.nvim_win_is_valid(S.win) then
          fn(count)
        end
      end)
      return ''
    end, { buffer = buf, nowait = true, expr = true, replace_keycodes = true })
  end
  vim.keymap.set({ 'n', 'i' }, '<C-s>', function()
    if S and S.reply then
      end_reply(true)
    end
  end, { buffer = buf })
  vim.keymap.set({ 'n', 'i' }, '<C-c>', function()
    if S and S.reply then
      end_reply(false)
    end
  end, { buffer = buf })
end

----------------------------------------------------------------------
-- Opening and closing
----------------------------------------------------------------------

function M.is_open()
  return S ~= nil and vim.api.nvim_win_is_valid(S.win)
end

--- Focused from the code: another thread, in place of this one.
---@param id integer|nil
function M.go(id)
  if not (S and S.single and id) then
    return
  end
  S.single, S.others = id, { id }
  S.inside, S.seen_at = nil, {}
  draw()
  enter()
  -- Stepping between threads: the map of them shows under the float.
  S.strip_on = true
  strip()
end

--- Under the focused float, once you step with h and l: the threads they
--- go through, a few either side, `▸` on this one.
function strip()
  if not (S and S.single and S.strip_on and vim.api.nvim_win_is_valid(S.win)) then
    return
  end
  local batch = store.active()
  if not batch then
    return
  end
  local list = neighbours(batch)
  local at = 1
  for i, n in ipairs(list) do
    if n.c.id == S.single then
      at = i
    end
  end
  local lo = math.max(1, math.min(at - 3, #list - 6))
  local hi = math.min(#list, lo + 6)
  local cfg = vim.api.nvim_win_get_config(S.win)
  local width = cfg.width
  local lines, hls = {}, {}
  for i = lo, hi do
    local n = list[i]
    local here = i == at
    local g, ghl = look.glyph(store.status(n.c), store.unseen(batch, n.c), false)
    local where = n.anchored and (vim.fs.basename(n.c.file) .. ':' .. (n.line or '–')) or 'general'
    local left = string.format(' %s %s %3d  ', here and '▸' or ' ', g, n.c.id)
    local name = fit(title_of(n.c), width - width_of(left) - width_of(where) - 4)
    local text = left .. name
    text = text .. string.rep(' ', math.max(2, width - width_of(text) - width_of(where) - 1)) .. where
    lines[#lines + 1] = text
    local row = #lines - 1
    hls[#hls + 1] = { row, 1, 1 + #'▸', 'ThreadFocus' }
    local gcol = #(string.format(' %s ', here and '▸' or ' '))
    hls[#hls + 1] = { row, gcol, gcol + #g, ghl }
    hls[#hls + 1] = { row, #left, #left + #name, here and 'ThreadTitle' or 'ThreadMeta' }
    hls[#hls + 1] = { row, #text - #where, #text, 'LineNr' }
  end
  if not (S.strip and vim.api.nvim_win_is_valid(S.strip.win)) then
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = 'wipe'
    local win = vim.api.nvim_open_win(buf, false, {
      relative = 'editor', row = 0, col = 0, width = width, height = 1,
      border = 'rounded', style = 'minimal', focusable = false, zindex = 60,
    })
    vim.wo[win].winhighlight = 'NormalFloat:Normal,FloatBorder:ThreadTabRule'
    S.strip = { win = win, buf = buf }
  end
  local buf = S.strip.buf
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, h[1], h[2], { end_col = math.min(h[3], #lines[h[1] + 1]), hl_group = h[4] })
  end
  -- Under the float when there is room; else over its foot.
  local below = cfg.row + cfg.height + 2
  local max = vim.o.lines - vim.o.cmdheight - 1
  local row = below + #lines + 2 <= max and below or (max - #lines - 2)
  vim.api.nvim_win_set_config(S.strip.win, {
    relative = 'editor', row = row, col = cfg.col, width = width, height = #lines,
    title = { { ' h ← threads → l ', 'ThreadKeyLabel' } }, title_pos = 'center',
  })
end

function M.close()
  local src = S and S.single and S.src_win
  if S and S.strip and vim.api.nvim_win_is_valid(S.strip.win) then
    vim.api.nvim_win_close(S.strip.win, true)
  end
  if S and vim.api.nvim_win_is_valid(S.win) then
    vim.api.nvim_win_close(S.win, true)
  end
  S = nil
  layout(false)
  if src and vim.api.nvim_win_is_valid(src) then
    vim.api.nvim_set_current_win(src)
    -- What was new in it has been read now.
    render.refresh()
  end
end

--- Redraw after the batch changed: our own edits or the agent's. A reply in
--- progress is never redrawn under you; it waits.
function M.refresh()
  if not M.is_open() then
    S = nil
    return
  end
  if S.reply then
    S.dirty = true
    return
  end
  draw()
end

--- The keys that work everywhere in Home; the focused thread lists its own.
footer = function()
  local chunks = { { ' ' } }
  local keys = { { 'j/k', 'thread' }, { 'tab', 'next tab' }, { '?', 'help' }, { 'q', 'quit' } }
  for i, k in ipairs(keys) do
    if i > 1 then
      chunks[#chunks + 1] = { '   ' }
    end
    chunks[#chunks + 1] = { k[1], 'ThreadKey' }
    chunks[#chunks + 1] = { ' ' .. k[2], 'ThreadKeyLabel' }
  end
  chunks[#chunks + 1] = { ' ' }
  return chunks
end

--- The buffer Home draws into, its keys, and what follows the cursor.
local function make_buf()
  -- which-key holds keys that start built-in commands, such as g, waiting
  -- for the rest, even over a buffer's own nowait mapping: keep it out.
  local wk = package.loaded['which-key.config']
  if wk and wk.disable and wk.disable.ft and not vim.tbl_contains(wk.disable.ft, 'thread-home') then
    table.insert(wk.disable.ft, 'thread-home')
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'thread-home'
  -- A reply is prose, not code: no completion menu over the threads.
  vim.b[buf].completion = false
  vim.b[buf].cmp_enabled = false
  return buf
end

local function setup_win(win)
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].breakindent = true
  vim.wo[win].breakindentopt = 'shift:' .. TEXT_COL
  vim.wo[win].cursorline = false
end

local function attach(buf, win)
  map_keys(buf)
  local group = vim.api.nvim_create_augroup('thread.home', { clear = true })
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    group = group,
    buffer = buf,
    callback = relabel,
  })
  -- Moving onto another thread's lines by other means (G, a search, the
  -- mouse) focuses it.
  vim.api.nvim_create_autocmd('CursorMoved', {
    group = group,
    buffer = buf,
    callback = function()
      if not S or S.rendering or S.reply then
        return
      end
      local lnum = vim.api.nvim_win_get_cursor(S.win)[1]
      local id = S.owner[lnum]
      if id and id ~= S.focus then
        S.focus, S.inside = id, nil
        vim.schedule(draw)
      elseif S.inside and id == S.focus then
        -- The part under the cursor: the one already on when it still is
        -- (a name's line is its message's too), else the first that holds it.
        local function holds(it)
          return it and lnum - 1 >= it.first and lnum - 1 <= it.last
        end
        if not holds(S.items and S.items[S.inside.item]) then
          for n, it in ipairs(S.items or {}) do
            if holds(it) then
              select(n)
              S.inside.ref = nil
              vim.schedule(draw)
              break
            end
          end
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd('VimResized', {
    group = group,
    callback = function()
      if M.is_open() and not S.single then
        vim.api.nvim_win_set_config(S.win, {
          relative = 'editor',
          row = 0,
          col = 0,
          width = vim.o.columns - 2,
          height = math.max(5, vim.o.lines - vim.o.cmdheight - 3),
        })
      end
      M.refresh()
    end,
  })
  vim.api.nvim_create_autocmd('WinLeave', {
    group = group,
    buffer = buf,
    callback = function()
      vim.schedule(function()
        if S and S.win == win and vim.api.nvim_get_current_win() ~= win and not S.helping then
          -- Gone elsewhere: no going back to where it was focused from.
          S.src_win = nil
          M.close()
        end
      end)
    end,
  })
end

local function new_state(win, buf)
  return { win = win, buf = buf, levels = {}, filter = 1, group = 2, marked = {}, code = {}, open_refs = {}, ref_size = {}, pick_first = true, order = {}, row_of = {}, owner = {} }
end

--- Open Home; `opts.view` picks a tab by what it shows (`review`), and
--- `opts.focus` the row to be on.
---@param opts { view: string|nil, focus: any }|nil
function M.open(opts)
  opts = opts or {}
  local function pick()
    for i, f in ipairs(FILTERS) do
      if opts.view and f.view == opts.view then
        S.filter = i
      end
    end
    if opts.focus then
      S.focus = opts.focus
    end
  end
  if M.is_open() and not S.single then
    vim.api.nvim_set_current_win(S.win)
    if opts.view or opts.focus then
      pick()
      draw()
    end
    return
  end
  M.close()
  layout(false)
  local batch = store.active()
  local buf = make_buf()
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    row = 0,
    col = 0,
    width = vim.o.columns - 2,
    height = math.max(5, vim.o.lines - vim.o.cmdheight - 3),
    border = 'rounded',
    style = 'minimal',
    title = ' Home · ' .. (batch and batch.data.title or 'no batch') .. ' ',
    title_pos = 'left',
    footer = footer(),
    footer_pos = 'right',
  })
  setup_win(win)
  S = new_state(win, buf)
  pick()
  attach(buf, win)
  draw()
end

---@class thread.FocusOpts
---@field comment thread.Comment
---@field others integer[]|nil  every thread on that line, in order, for tab
---@field reply boolean|nil     straight into a reply, and back to the code once sent

--- One thread, focused from the code: a float in the middle with its code
--- and the whole thread, and Home's keys. Esc goes back to the code.
---@param opts thread.FocusOpts
function M.focus(opts)
  M.close()
  layout(true)
  local src = vim.api.nvim_get_current_win()
  local buf = make_buf()
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    row = 1,
    col = 1,
    width = math.min(vim.o.columns - 8, 110),
    height = 3,
    border = 'rounded',
    style = 'minimal',
    title = ' ',
    footer = ' ',
  })
  setup_win(win)
  S = new_state(win, buf)
  S.pick_first = false
  S.single, S.src_win, S.quick = opts.comment.id, src, opts.reply
  S.others = opts.others or { opts.comment.id }
  S.filter = #FILTERS -- all: a closed thread is still shown
  attach(buf, win)
  draw()
  enter()
  if opts.reply then
    start_reply()
  end
end

M._state = function()
  return S
end

return M
