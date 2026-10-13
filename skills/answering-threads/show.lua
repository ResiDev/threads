-- What waits for you in thread.nvim's reviews, or whether a review you
-- wrote reads. Run from anywhere inside the repository:
--
--   nvim -l show.lua                    what waits for you, in every open review
--   nvim -l show.lua <review>           in that one only
--   nvim -l show.lua --check [review]   is it right: the format, then the code it names
--
-- It asks thread.nvim's own model (store/, model/, base/), so what it says
-- waits is what the editor says waits. It writes nothing: when a message
-- was first heard is the editor's to note.

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
local here = vim.uv.fs_realpath(debug.getinfo(1, 'S').source:sub(2)) or ''
local plugin
for _, dir in ipairs { vim.fn.fnamemodify(here, ':h:h:h'), vim.env.THREAD_NVIM or '', vim.fn.stdpath 'data' .. '/lazy/thread.nvim' } do
  if not plugin and dir ~= '' and vim.uv.fs_stat(dir .. '/lua/thread/model/review.lua') then
    plugin = dir
  end
end
if not plugin then
  die 'thread.nvim, with format 2, not found: link this skill from the plugin (ln -s <plugin>/skills/answering-threads ~/.claude/skills/), or set THREAD_NVIM to its directory'
end
vim.opt.runtimepath:prepend(plugin)

local chunk = require 'thread.model.chunk'
local diff = require 'thread.base.diff'
local file = require 'thread.store.file'
local review = require 'thread.model.review'
local source = require 'thread.base.source'
local thread = require 'thread.model.thread'

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
      local u = review.unfound(r)
      vim.list_extend(p.errors, u.errors)
      vim.list_extend(p.warnings, u.warnings)
    end
    for _, w in ipairs(p.warnings) do
      io.stdout:write('warn: ' .. w .. '\n')
    end
    for _, e in ipairs(p.errors) do
      io.stdout:write('error: ' .. e .. '\n')
    end
    local left = r and review.left_out(r) or {}
    if #left > 0 then
      io.stdout:write(string.format('note: %d hunk%s of the diff in no thread or step, so not in the review:\n', #left, #left == 1 and '' or 's'))
      for _, h in ipairs(left) do
        io.stdout:write(string.format('note:   %s (+%d -%d)\n', span(h), h.add, h.del))
      end
    end
    if #p.errors > 0 then
      failed = true
      io.stdout:write(string.format('%s: %d error%s\n', id, #p.errors, #p.errors == 1 and '' or 's'))
    else
      io.stdout:write(string.format('ok: %s, %d thread%s\n', id, #r.threads, #r.threads == 1 and '' or 's'))
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
  return (text:gsub('\n', '\n' .. indent))
end

--- A hunk as a diff, the lines of the chunk on it marked `>`.
---@param spec thread.DiffSpec
---@param h thread.DiffHunk
---@param c thread.Chunk
---@param at thread.Located
local function say_hunk(spec, h, c, at)
  say(string.format('    the hunk %s (+%d -%d):', span(h), h.add, h.del))
  local first = at.old or at.line
  local last = first + (c.lines or 1) - 1
  local marked = at.old and '-' or nil
  local new = diff.lines(spec, h.file, 'new') or {}
  local rows, prev_end = {}, nil
  for _, part in ipairs(h.parts) do
    if prev_end then
      for n = prev_end + 1, part.new_start - (part.new_count > 0 and 1 or 0) do
        rows[#rows + 1] = { ' ', n, new[n] or '' }
      end
    end
    for i, l in ipairs(part.old) do
      rows[#rows + 1] = { '-', part.old_start + i - 1, l }
    end
    for i, l in ipairs(part.new) do
      rows[#rows + 1] = { '+', part.new_start + i - 1, l }
    end
    prev_end = part.new_count > 0 and (part.new_start + part.new_count - 1) or part.new_start
  end
  -- A long hunk: the rows around the chunk's, which may be far down it.
  local on, at_row = {}, nil
  for i, row in ipairs(rows) do
    on[i] = (marked == '-') == (row[1] == '-') and row[2] >= first and row[2] <= last
    at_row = at_row or (on[i] and i or nil)
  end
  local from = math.max(1, math.min((at_row or 1) - 10, #rows - 39))
  local to = math.min(#rows, from + 39)
  if from > 1 then
    say(string.format('        … %d lines above', from - 1))
  end
  for i = from, to do
    local row = rows[i]
    say(string.format('  %s%5d %s %s', on[i] and '>' or ' ', row[2], row[1], row[3]))
  end
  if to < #rows then
    say(string.format('        … %d lines below', #rows - to))
  end
end

--- Where a chunk is, and its code: the hunk it is on, or the lines
--- around it.
---@param r thread.Review
---@param c thread.Chunk
local function say_chunk(r, c)
  local spec = chunk.spec(r.diff)
  local at = chunk.locate(c, spec)
  if not at then
    say(string.format('    ! not found: %s has no line reading %q now', c.file, c.text))
    return
  end
  if at.hunk and spec then
    say_hunk(spec, at.hunk, c, at)
    return
  end
  local lines = source.lines_of(c) or {}
  local last = at.line + (c.lines or 1) - 1
  for n = math.max(1, at.line - 2), math.min(#lines, last + 2) do
    say(string.format('  %s%5d  %s', (n >= at.line and n <= last) and '>' or ' ', n, lines[n]))
  end
end

---@param c thread.Chunk|nil
---@return string
local function place(c)
  if not c then
    return 'on no line'
  end
  local where = string.format('%s:%d%s', c.file, c.line, c.lines and c.lines > 1 and ('-' .. (c.line + c.lines - 1)) or '')
  if c.side == 'old' then
    where = where .. ', a removed line'
  elseif c.rev then
    where = where .. ' @ ' .. c.rev
  end
  return where
end

--- Where a conversation's messages are in the review's file.
---@param r thread.Review
---@param c thread.Conversation
---@return string
local function path(r, c)
  for i, t in ipairs(r.threads) do
    for j, m in ipairs(c.step and t == c.thread and t.messages or {}) do
      for k, x in ipairs(m.tours or {}) do
        for n, s in ipairs(x.steps) do
          if s == c.step then
            return string.format('threads[%d].messages[%d].tours[%d].steps[%d].messages', i, j, k, n)
          end
        end
      end
    end
    if t == c.thread and not c.step then
      return string.format('threads[%d].messages', i)
    end
  end
  return '?'
end

--- One conversation that waits: where it is, its code, and what was said.
---@param r thread.Review
---@param c thread.Conversation
local function say_conversation(r, c)
  local t = c.thread
  local name = t.title and string.format('"%s"', t.title) or '(no title yet: give it one)'
  say ''
  if c.step and c.tour then
    say(string.format('%s  step "%s", in tour "%s" of #%d %s  %s', thread.link(c), c.step.title, c.tour.title, t.id, name, place(c.step.chunk)))
    local intro = t.messages[1] and t.messages[1].text:match '^(.-)\n\n' or (t.messages[1] or {}).text
    if intro and intro ~= '' then
      say('    the thread begins: ' .. indented(intro, '      '))
    end
    if c.step.text then
      say('    the step says: ' .. indented(c.step.text, '      '))
    end
  else
    say(string.format('%s  %s  %s', thread.link(c), name, place(t.chunk)))
  end
  say('    reply in: ' .. path(r, c) .. ', counting from 1')
  local on = c.step and c.step.chunk or (not c.step and t.chunk) or nil
  if on then
    say_chunk(r, on)
  end
  local tours = #thread.tours(t)
  local k = 0
  for _, m in ipairs(c.messages) do
    say(string.format('    %s: %s', m.from, indented(m.text, '      ')))
    for _, x in ipairs(m.tours or {}) do
      k = k + 1
      local first = tours == 1 and string.format('#%d.1', t.id) or string.format('#%d.%d.1', t.id, k)
      say(string.format('      (tour "%s", %d step%s, from %s)', x.title, #x.steps, #x.steps == 1 and '' or 's', first))
    end
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
    say(string.format('cannot read %s (%d error%s; --check %s says them)', id, #p.errors, #p.errors == 1 and '' or 's', id))
  elseif r.status == 'closed' then
    if args.id then
      say(string.format('review %s is closed: nothing in it waits', id))
    end
  else
    open = open + 1
    local list = thread.waiting(r)
    waiting = waiting + #list
    if #list > 0 or args.id then
      say ''
      say(string.format('review %s  "%s"  %d waiting', id, r.title, #list))
      local spec = chunk.spec(r.diff)
      say(
        string.format(
          '  file %s/%s.json · about %s · next thread id %d',
          file.dir(),
          id,
          spec and (spec.label .. ' ' .. vim.json.encode(r.diff)) or 'the code as it stands',
          review.next_id(r)
        )
      )
      for _, c in ipairs(list) do
        say_conversation(r, c)
      end
    end
  end
end
say ''
local within = args.id and ('review ' .. args.id) or string.format('%d open review%s', open, open == 1 and '' or 's')
if waiting == 0 then
  say('nothing waits for you in ' .. within)
else
  say(string.format('%d waiting for you, in %s', waiting, within))
end
io.stdout:write(table.concat(out, '\n') .. '\n')
