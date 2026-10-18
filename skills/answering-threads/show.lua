-- What waits for you in thread.nvim's reviews, or whether a review you
-- wrote reads. Run from anywhere inside the repository:
--
--   nvim -l show.lua                    what waits for you, in every open review
--   nvim -l show.lua <review>           in that one only, with its next ids and chunks
--   nvim -l show.lua --check [review]   is it right: the format, then the code it names
--
-- It asks thread.nvim's own model (store/, model/, base/) and reads prose
-- as the editor does (prose/), so what it says waits is what the editor
-- says waits. It writes nothing: when a message was first heard is the
-- editor's to note.

local args = { id = nil, check = false }
for _, a in ipairs(arg) do
  if a == '--check' then
    args.check = true
  else
    args.id = a
  end
end

---@param msg string
local function die(msg)
  io.stderr:write(msg .. '\n')
  os.exit(1)
end

-- thread.nvim itself: beside this file (it is in <plugin>/skills/, maybe
-- through a symlink), or at $THREAD_NVIM, or where lazy.nvim keeps it.
-- The model's conversation module is what this script needs, so a plugin
-- too old to have it is passed over.
local here = vim.uv.fs_realpath(debug.getinfo(1, 'S').source:sub(2)) or ''
local plugin
for _, dir in ipairs { vim.fn.fnamemodify(here, ':h:h:h'), vim.env.THREAD_NVIM or '', vim.fn.stdpath 'data' .. '/lazy/thread.nvim' } do
  if not plugin and dir ~= '' and vim.uv.fs_stat(dir .. '/lua/thread/model/conversation.lua') then
    plugin = dir
  end
end
if not plugin then
  die 'thread.nvim not found: link this skill from the plugin (ln -s <plugin>/skills/answering-threads ~/.claude/skills/), or set THREAD_NVIM to its directory'
end
vim.opt.runtimepath:prepend(plugin)

local chunk = require 'thread.model.chunk'
local conversation = require 'thread.model.conversation'
local diff = require 'thread.base.diff'
local file = require 'thread.store.file'
local prose_check = require 'thread.prose.check'
local review = require 'thread.model.review'

--- A review as its file has it, checked, and what is wrong with it.
---@param id string
---@return thread.Review|nil, thread.Problems
local function load(id)
  local raw, err = file.read(id)
  if not raw then
    return nil, { errors = { err or ('no review ' .. id) }, warnings = {} }
  end
  return review.parse(raw, id)
end

---@param id string
local function known(id)
  if not file.mtime(id) then
    local ids = file.ids()
    die(string.format('no review %s in %s%s', id, file.dir(), #ids > 0 and ('; there are: ' .. table.concat(ids, ', ')) or ''))
  end
end

--- `3 steps`, `1 step`.
---@param n integer
---@param noun string
---@return string
local function count(n, noun)
  return n .. ' ' .. noun .. (n == 1 and '' or 's')
end

---@param h thread.DiffHunk
---@return string
local function span(h)
  return string.format('%s:%d%s', h.file, h.lo, h.hi > h.lo and ('-' .. h.hi) or '')
end

if args.check then
  if args.id then
    known(args.id)
  end
  local ids = args.id and { args.id } or file.ids()
  local failed = false
  for _, id in ipairs(ids) do
    if #ids > 1 then
      io.stdout:write(string.format('== %s\n', id))
    end
    local r, p = load(id)
    if r then
      for _, u in ipairs {
        review.unfound(r),
        prose_check.review(r, function(other)
          if not file.mtime(other) then
            return nil
          end
          local o, op = load(other)
          return o, not o and op.errors[1] or nil
        end),
      } do
        vim.list_extend(p.errors, u.errors)
        vim.list_extend(p.warnings, u.warnings)
      end
    end
    for _, w in ipairs(p.warnings) do
      io.stdout:write('warn: ' .. w .. '\n')
    end
    for _, e in ipairs(p.errors) do
      io.stdout:write('error: ' .. e .. '\n')
    end
    local left = r and review.left_out(r) or {}
    if #left > 0 then
      io.stdout:write(string.format('note: %s of the diff on no step, note or contract, so not in the review:\n', count(#left, 'hunk')))
      for _, h in ipairs(left) do
        io.stdout:write(string.format('note:   %s (+%d -%d)\n', span(h), h.add, h.del))
      end
    end
    if #p.errors > 0 or not r then
      failed = true
      io.stdout:write(string.format('%s: %s\n', id, count(#p.errors, 'error')))
    else
      local steps = 0
      for _, x in ipairs(r.tours) do
        steps = steps + #x.steps
      end
      io.stdout:write(
        string.format(
          'ok: %s, %s, %s, %s, %s, %s\n',
          id,
          count(#r.contracts, 'contract'),
          count(#r.tours, 'tour'),
          count(steps, 'step'),
          count(#r.notes, 'note'),
          count(#r.chunks, 'chunk')
        )
      )
    end
  end
  if #ids == 0 then
    io.stdout:write('no reviews in ' .. file.dir() .. '\n')
  end
  os.exit(failed and 1 or 0)
end

local out = {}
---@param s string|nil
local function say(s)
  out[#out + 1] = s or ''
end

---@param text string
---@param indent string
---@return string
local function indented(text, indent)
  return (vim.trim(text):gsub('\n', '\n' .. indent))
end

--- Prose as the agent wrote it: its text, then the names of its diagrams.
---@param label string  what it is, before its text
---@param x thread.Prose
local function say_prose(label, x)
  say(string.format('    %s: %s', label, indented(x.text, '      ')))
  local names = vim.tbl_keys(x.diagrams or {})
  if #names > 0 then
    table.sort(names)
    say('      (diagrams: ' .. table.concat(names, ', ') .. ')')
  end
end

-- Rows of code shown for one chunk, at most: a long one is cut around
-- where it starts.
local MOST = 40

--- A hunk as a diff, the lines of the chunk on it marked `>`.
---@param spec thread.DiffSpec
---@param h thread.DiffHunk
---@param at thread.Located
local function say_hunk(spec, h, at)
  say(string.format('    the hunk %s (+%d -%d):', span(h), h.add, h.del))
  local base = at.side == 'base'
  local rows = diff.rows(spec, h)
  local on, first = {}, nil ---@type boolean[], integer|nil
  for i, row in ipairs(rows) do
    on[i] = base == (row.sign == '-') and row.num >= at.line and row.num <= at.last
    first = first or (on[i] and i or nil)
  end
  local from = math.max(1, math.min((first or 1) - 10, #rows - MOST + 1))
  local to = math.min(#rows, from + MOST - 1)
  if from > 1 then
    say(string.format('        … %d lines above', from - 1))
  end
  for i = from, to do
    local row = rows[i]
    say(string.format('  %s%5d %s %s', on[i] and '>' or ' ', row.num, row.sign, row.line))
  end
  if to < #rows then
    say(string.format('        … %d lines below', #rows - to))
  end
end

--- A chunk by its id: where it is, and its code, each hunk it is on or
--- its lines with two either side.
---@param r thread.Review
---@param id string
local function say_chunk(r, id)
  local c = review.chunk(r, id)
  if not c then
    return
  end
  local spec = chunk.spec(r.diff)
  local at = chunk.locate(c, spec)
  if not at then
    say(string.format('    ! chunk %s not found: %s has no line reading %q at %s (--check %s says more)', c.id, c.file, c.from, c.rev, r.id))
    return
  end
  say(string.format('    chunk %s, %s at %s%s', c.id, chunk.span(c, at), c.rev, at.confidence < 1 and ', found by likeness' or ''))
  if at.hunk and spec then
    for _, h in ipairs(at.hunks or { at.hunk }) do
      say_hunk(spec, h, at)
    end
    return
  end
  local lines = chunk.lines(c, spec) or {}
  local last = math.min(at.last, at.line + MOST - 1)
  for n = math.max(1, at.line - 2), math.min(#lines, last + 2) do
    say(string.format('  %s%5d  %s', (n >= at.line and n <= at.last) and '>' or ' ', n, lines[n]))
  end
  if last < at.last then
    say(string.format('        … %d lines more in the chunk', at.last - last))
  end
end

--- Where a conversation's messages are in the review's file, as a path
--- counting from 1: `tours[2].steps[3].messages`.
---@param r thread.Review
---@param c thread.Conversation
---@return string
local function path(r, c)
  for i, k in ipairs(r.contracts) do
    if k == c.contract then
      return string.format('contracts[%d].messages', i)
    end
  end
  for k, x in ipairs(r.tours) do
    for n, s in ipairs(x.steps) do
      if s == c.step then
        return string.format('tours[%d].steps[%d].messages', k, n)
      end
    end
  end
  for i, n in ipairs(r.notes) do
    if n == c.note then
      return string.format('notes[%d].messages', i)
    end
  end
  return '?'
end

--- A contract's side, said short: a chunk's id, or written out.
---@param side thread.Side|nil
---@return string|nil
local function side_of(side)
  if type(side) == 'string' then
    return 'chunk ' .. side
  elseif side then
    return 'written out, ' .. side.lang
  end
end

--- One conversation that waits: what it is on, its code, and what was
--- said since the agent last spoke.
---@param r thread.Review
---@param c thread.Conversation
local function say_conversation(r, c)
  say ''
  local on ---@type string|nil  the chunk to show
  if c.contract then
    local k = c.contract
    local sides = {}
    for _, s in ipairs { 'before', 'after' } do
      local said = side_of(k.source[s])
      if said then
        sides[#sides + 1] = s .. ': ' .. said
      end
    end
    say(string.format('%s  contract "%s" (%s, %s)  %s', conversation.link(c), k.name, k.kind, k.source.change, table.concat(sides, ' · ')))
    if k.why then
      say('    why: ' .. indented(k.why, '      '))
    end
    on = type(k.source.after) == 'string' and k.source.after or type(k.source.before) == 'string' and k.source.before or nil
  elseif c.step then
    local s = c.step
    say(string.format('%s  step "%s", in tour "%s"%s', conversation.link(c), s.title, c.tour and c.tour.title or '?', s.chunk and '' or ', a page'))
    if s.text then
      say_prose('the step says', s.text)
    end
    on = s.chunk
  else
    local n = assert(c.note)
    local kind = n.kind == 'issue' and string.format('issue, a %s %s', n.severity, n.issue) or n.kind
    say(string.format('%s  %s "%s"%s%s', conversation.link(c), kind, n.title, n.status and (', ' .. n.status) or '', n.chunk and '' or ', on no line'))
    on = n.chunk
  end
  say(string.format('    reply in: %s (counting from 1)', path(r, c)))
  if on then
    say_chunk(r, on)
  end
  local last = 0
  for i, m in ipairs(c.messages) do
    if m.from == 'agent' then
      last = i
    end
  end
  -- A note's first message says what it is, so it is shown however old.
  local first = c.note ~= nil and last >= 1
  if first then
    say_prose('first, ' .. c.messages[1].from, c.messages[1].prose)
  end
  local skipped = last - (first and 1 or 0)
  if skipped > 0 then
    say(string.format("    … %s%s, the last the agent's", count(skipped, 'message'), first and ' more' or ''))
  end
  for i = last + 1, #c.messages do
    local m = c.messages[i]
    say_prose(m.from, m.prose)
  end
end

--- A review's chunks by file, each id once: what is in use, so a new
--- chunk takes an id of its own.
---@param r thread.Review
local function say_chunks(r)
  if #r.chunks == 0 then
    say '  chunks: none yet'
    return
  end
  local files, by = {}, {} ---@type string[], table<string, string[]>
  for _, c in ipairs(r.chunks) do
    if not by[c.file] then
      by[c.file] = {}
      files[#files + 1] = c.file
    end
    table.insert(by[c.file], c.id)
  end
  table.sort(files)
  say(string.format('  %s, by file:', count(#r.chunks, 'chunk')))
  for _, f in ipairs(files) do
    say(string.format('    %s  %s', f, table.concat(by[f], ' ')))
  end
end

if args.id then
  known(args.id)
end
local ids = args.id and { args.id } or file.ids()
table.sort(ids, function(a, b)
  local ta, tb = file.mtime(a) or 0, file.mtime(b) or 0
  if ta ~= tb then
    return ta > tb
  end
  return a < b
end)
local open, waiting = 0, 0
for _, id in ipairs(ids) do
  local r, p = load(id)
  if not r then
    say(string.format('cannot read %s (%s; --check %s says them)', id, count(#p.errors, 'error'), id))
  elseif r.status == 'closed' then
    if args.id then
      say(string.format('review %s is closed: nothing in it waits', id))
    end
  else
    open = open + 1
    local list = conversation.waiting(r)
    waiting = waiting + #list
    if #list > 0 or args.id then
      say ''
      say(string.format('review %s  "%s"  %d waiting', id, r.title, #list))
      local spec = chunk.spec(r.diff)
      say(string.format('  file %s/%s.json · about %s', file.dir(), id, spec and (spec.label .. ' ' .. vim.json.encode(r.diff)) or 'the code as it stands'))
      say(
        string.format(
          '  next ids: tour %d, step %d, note %d, contract %d',
          review.next_id(r, 'tour'),
          review.next_id(r, 'step'),
          review.next_id(r, 'note'),
          review.next_id(r, 'contract')
        )
      )
      say_chunks(r)
      for _, c in ipairs(list) do
        say_conversation(r, c)
      end
    end
  end
end
say ''
local within = args.id and ('review ' .. args.id) or count(open, 'open review')
if waiting == 0 then
  say('nothing waits for you in ' .. within)
else
  say(string.format('%d waiting for you, in %s', waiting, within))
end
io.stdout:write(table.concat(out, '\n') .. '\n')
