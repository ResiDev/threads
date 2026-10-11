-- Print the threads waiting for an answer, with the code they are on and
-- the tour stop they are a reply in, or check a batch after answering it.
--
--   nvim -l show.lua [batch-id]           the waiting threads
--   nvim -l show.lua [batch-id] --all     every thread, done ones too
--   nvim -l show.lua [batch-id] --check   is the file valid, do the anchors resolve
--
-- Run from anywhere inside the repository. Needs Neovim and thread.nvim,
-- whose own idea of a thread it uses.

local args = { batch = nil, all = false, check = false }
for _, a in ipairs(arg) do
  if a == '--all' then
    args.all = true
  elseif a == '--check' then
    args.check = true
  else
    args.batch = a
  end
end

local function die(msg, code)
  io.stderr:write(msg .. '\n')
  os.exit(code or 1)
end

-- thread.nvim itself: its own idea of a thread's status and title, where
-- a quote is now, what a tour's stops are, and its diagram and review
-- checkers. Found beside this file (it is in <plugin>/skills/, maybe
-- through a symlink), or at $THREAD_NVIM, or where lazy.nvim keeps it.
local here = vim.uv.fs_realpath(debug.getinfo(1, 'S').source:sub(2)) or ''
local plugin
for _, dir in ipairs { vim.fn.fnamemodify(here, ':h:h:h'), vim.env.THREAD_NVIM or '', vim.fn.stdpath 'data' .. '/lazy/thread.nvim' } do
  if not plugin and dir ~= '' and vim.uv.fs_stat(dir .. '/lua/thread/init.lua') then
    plugin = dir
  end
end
if not plugin then
  die 'thread.nvim not found: link this skill from the plugin (ln -s <plugin>/skills/answering-threads ~/.claude/skills/), or set THREAD_NVIM to its directory'
end
vim.opt.runtimepath:prepend(plugin)
local anchor = require 'thread.anchor'
local diagram = require 'thread.diagram'
local review = require 'thread.review'
local store = require 'thread.store'
local tour = require 'thread.tour'

local root = store.root()
local dir = root .. '/.threads'

local function read(path)
  local fd = io.open(path, 'r')
  if not fd then
    return nil
  end
  local s = fd:read '*a'
  fd:close()
  return s
end

local id = args.batch or vim.trim(read(dir .. '/active') or '')
if id == '' then
  local names = {}
  for name in vim.fs.dir(dir) do
    names[#names + 1] = name:match '^(.+)%.json$'
  end
  die('no current batch in ' .. dir .. (#names > 0 and ('; batches: ' .. table.concat(names, ', ')) or ''))
end
local path = dir .. '/' .. id .. '.json'
local raw = read(path) or die('no batch file ' .. path)
-- Read as written, nothing filled in, so what is missing can be said.
local ok, data = pcall(vim.json.decode, raw, { luanil = { object = true, array = true } })
if not ok or type(data) ~= 'table' then
  die(path .. ' is not valid JSON: ' .. tostring(data))
end
local threads = data.threads or {}
for _, c in ipairs(threads) do
  c.messages = c.messages or {}
end
-- The batch as the plugin holds it, for its tours and reviews.
local batch = { id = id, path = path, data = { title = data.title, rounds = data.rounds or {}, threads = threads } }

--- The line a quote is on now, as the plugin finds it; else why not.
local function find(a)
  local lines = anchor.lines_of(a)
  if not lines then
    return nil, 'no file ' .. tostring(a.file) .. (a.rev and (' at ' .. a.rev) or '')
  end
  local loc = anchor.locate(a, lines)
  if not loc then
    return nil, string.format('%s: no line reads %q', a.file, a.text or '')
  end
  return loc.line
end

local VERDICTS = { bug = true, flaw = true, risk = true, ['trade-off'] = true, decision = true, ['how it works'] = true, fine = true }

if args.check then
  local problems, warnings = {}, {}
  local ids = {}
  for _, c in ipairs(threads) do
    local function bad(msg)
      problems[#problems + 1] = string.format('thread %s: %s', tostring(c.id), msg)
    end
    local function warn(msg)
      warnings[#warnings + 1] = string.format('thread %s: %s', tostring(c.id), msg)
    end
    if type(c.id) ~= 'number' then
      bad 'no numeric id'
    elseif ids[c.id] then
      bad 'its id is used twice'
    end
    ids[c.id or false] = true
    if type(c.messages) ~= 'table' or #c.messages == 0 then
      bad 'no messages'
    end
    local done = store.status(c) == 'closed'
    if store.anchored(c) then
      local _, err = find(c)
      if err and not done then
        bad(err .. " (if your change rewrote this line, update the thread's text and line)")
      end
    elseif c.text or c.line then
      warn 'has `text` or `line` but no `file`: it is about no line and shows as a page'
    end
    if not store.talked(c) and not (c.title and c.title ~= '') then
      warn 'a thread you started has no `title`'
    end
    if c.on ~= nil then
      local owner, stop = tour.owner(batch, c)
      if not owner then
        bad(string.format('is a reply in thread %s, which does not exist', tostring(type(c.on) == 'table' and c.on.thread)))
      elseif not stop then
        bad(string.format('is a reply in stop %s of thread %d, which does not exist', tostring(c.on.step), owner.id))
      end
    end
    for i, m in ipairs(c.messages or {}) do
      local where = string.format('message %d', i)
      if m.from ~= 'you' and m.from ~= 'agent' then
        bad(where .. ': from must be "you" or "agent"')
      end
      if (type(m.text) ~= 'string' or m.text == '') and not (m.walk and #m.walk > 0) then
        bad(where .. ': no text')
      end
      if m.children ~= nil then
        bad(where .. ': `children` is gone; a tour is the message\'s `walk`')
      end
      for j, ch in ipairs(m.changes or {}) do
        local _, cerr = find(ch)
        if cerr and i == #c.messages then
          bad(string.format('%s, change %d: %s', where, j, cerr))
        end
      end
      -- Notes, a verdict and a diagram: on a message or a stop alike.
      local function extras(x, xwhere, file, rev)
        for j, n in ipairs(x.notes or {}) do
          local a = vim.tbl_extend('keep', n, { file = file, rev = rev })
          if not a.file then
            bad(string.format('%s, note %d: no file, and there is none to go by', xwhere, j))
          else
            local _, nerr = find(a)
            if nerr then
              bad(string.format('%s, note %d: %s', xwhere, j, nerr))
            elseif type(n.mark) == 'string' and n.mark ~= '' then
              local at = find(a)
              local line = (anchor.lines_of(a) or {})[at] or ''
              if not line:find(n.mark, 1, true) then
                warn(string.format('%s, note %d: the mark %q is not on its line', xwhere, j, n.mark))
              end
            end
          end
        end
        if x.verdict ~= nil and not VERDICTS[x.verdict] then
          bad(string.format('%s: verdict %q is not one of bug, flaw, risk, trade-off, decision, how it works, fine', xwhere, tostring(x.verdict)))
        end
        if x.diagram ~= nil then
          local d, derr = diagram.validate(x.diagram)
          if not d then
            bad(string.format('%s, diagram: %s', xwhere, derr))
          else
            for _, node in ipairs(diagram.nodes(d)) do
              if node.file then
                local _, nerr = find { file = node.file, text = node.text, line = node.line }
                if nerr and node.text then
                  bad(string.format('%s, diagram node %q: %s', xwhere, node.label, nerr))
                end
              end
            end
          end
        end
      end
      extras(m, where, c.file, c.rev)
      -- The tour it leads to: every stop.
      if m.walk ~= nil and type(m.walk) ~= 'table' then
        bad(where .. ': walk must be a list of stops')
      end
      -- A review: its diff, and every group's hunks, affected code and tests.
      if m.review ~= nil then
        local r = m.review
        local spec, serr = require('thread.review.diff').spec(type(r) == 'table' and r.diff or nil)
        if type(r) ~= 'table' or type(r.groups) ~= 'table' then
          bad(where .. ': a review needs `diff` and a list of `groups`')
        elseif not spec then
          bad(where .. ': review diff: ' .. tostring(serr))
        else
          local function is(list, x)
            return vim.tbl_contains(list, x)
          end
          for k, g in ipairs(r.groups) do
            local gwhere = string.format('%s, group %d', where, k)
            if not (type(g.title) == 'string' and g.title ~= '') then
              bad(gwhere .. ': no `title`')
            end
            if not is(review.KINDS, g.kind) then
              bad(string.format('%s: kind %q is not one of %s', gwhere, tostring(g.kind), table.concat(review.KINDS, ', ')))
            end
            if not is(review.RISKS, g.risk) then
              bad(string.format('%s: risk %q is not one of low, medium, high', gwhere, tostring(g.risk)))
            elseif g.risk ~= 'low' and not (type(g.risk_why) == 'string' and g.risk_why ~= '') then
              warn(gwhere .. ': a ' .. g.risk .. ' risk with no `risk_why`')
            end
            if not (type(g.body) == 'string' and g.body ~= '') then
              warn(gwhere .. ': no `body`, the explanation of its hunks')
            end
            if type(g.hunks) ~= 'table' or #g.hunks == 0 then
              bad(gwhere .. ': no `hunks`')
            end
            for j, ref in ipairs(type(g.hunks) == 'table' and g.hunks or {}) do
              if not review.find(spec, ref) then
                local _, ferr = find(vim.tbl_extend('force', ref, { rev = ref.side == 'old' and spec.old or nil }))
                bad(string.format('%s, hunk %d: %s', gwhere, j, ferr or string.format('%s:%s is in no hunk of the diff (quote a changed line, or a removed one with "side": "old")', tostring(ref.file), tostring(ref.line))))
              end
            end
            for _, list in ipairs { 'affected', 'tests' } do
              for j, a in ipairs(type(g[list]) == 'table' and g[list] or {}) do
                local _, aerr = find(a)
                if aerr then
                  bad(string.format('%s, %s %d: %s', gwhere, list, j, aerr))
                end
              end
            end
            extras(g, gwhere)
          end
          local w = review.work(r)
          if #w.loose > 0 then
            local names = {}
            for i2, h in ipairs(w.loose) do
              if i2 <= 8 then
                names[#names + 1] = h.file .. ':' .. h.lo .. (h.hi > h.lo and ('-' .. h.hi) or '')
              end
            end
            warn(string.format('%s: %d hunk%s no group explains: %s%s', where, #w.loose, #w.loose == 1 and '' or 's', table.concat(names, ', '), #w.loose > 8 and ', …' or ''))
          end
        end
      end
      for k, e in ipairs(type(m.walk) == 'table' and m.walk or {}) do
        local swhere = string.format('%s, stop %d', where, k)
        local kind = tour.kind(e)
        if kind == 'stage' then
          if e.file then
            bad(swhere .. ': a stage is a page and has no file; put its line in the next stop')
          end
          if not (type(e.point) == 'string' and e.point ~= '') then
            warn(swhere .. ': a stage has no `point`')
          end
        elseif kind == 'step' then
          local _, serr = find(e)
          if serr then
            bad(swhere .. ': ' .. serr)
          end
          if not (type(e.title) == 'string' and e.title ~= '') then
            warn(swhere .. ': a step has no `title`, its claim')
          end
        end
        if kind ~= 'stage' and not (type(e.body) == 'string' and e.body ~= '') then
          warn(swhere .. ': no `body`')
        end
        extras(e, swhere, e.file, e.rev)
      end
    end
  end
  for _, w in ipairs(warnings) do
    io.stdout:write('warn: ' .. w .. '\n')
  end
  if #problems > 0 then
    io.stdout:write(table.concat(problems, '\n') .. '\n')
    os.exit(1)
  end
  io.stdout:write(string.format('ok: %s, %d threads\n', id, #threads))
  os.exit(0)
end

local out = {}
local function say(s)
  out[#out + 1] = s or ''
end
local rounds = data.rounds or {}
say(string.format('batch %s: "%s", replies %s, %d round%s sent', id, data.title or '', data.reply or 'inline', #rounds, #rounds == 1 and '' or 's'))
say(string.format('file: %s', path))
say(string.format('next free thread id: %d', store.next_id(batch)))
if data.diff then
  local spec = require('thread.review.diff').spec(data.diff)
  say(string.format('the diff to review: %s (%s)', spec and spec.label or '?', vim.json.encode(data.diff)))
end
local counts, shown = {}, 0
for _, c in ipairs(threads) do
  local s = store.status(c)
  counts[s] = (counts[s] or 0) + 1
  if args.all or s == 'waiting' then
    shown = shown + 1
    say ''
    local place
    if store.anchored(c) then
      local at, err = find(c)
      local span = c.lines and c.lines > 1 and string.format('-%d', (at or c.line) + c.lines - 1) or ''
      place = string.format('%s:%s%s%s', c.file, at or c.line or '?', span, c.rev and (' @ ' .. c.rev) or '')
      say(string.format('#%d  %s  [%s]%s', c.id, place, s, c.title and ('  "' .. c.title .. '"') or '  (no title yet: give it one)'))
      if err then
        say('    ! ' .. err)
      end
      local lines = anchor.lines_of(c)
      if at and lines then
        local last = at + (c.lines or 1) - 1
        for n = math.max(1, at - 2), math.min(#lines, last + 2) do
          say(string.format('  %s%4d  %s', (n >= at and n <= last) and '>' or ' ', n, lines[n]))
        end
      end
    else
      say(string.format('#%d  (about no line)  [%s]%s', c.id, s, c.title and ('  "' .. c.title .. '"') or '  (no title yet: give it one)'))
    end
    local owner, stop, n = tour.owner(batch, c)
    if owner and stop then
      say(string.format('    in: stop %d (%s) of #%d "%s": "%s"  (a reply in a tour: answer about this stop)', n, tour.kind(stop), owner.id, store.title(owner), tour.title(stop)))
      local body = ((stop.point and ('**' .. stop.point .. '**\n\n') or '') .. (stop.body or '')):gsub('\n', '\n      ')
      say('    the stop says: ' .. body)
    end
    for _, m in ipairs(c.messages or {}) do
      local text = (m.text or ''):gsub('\n', '\n      ')
      say(string.format('    %s: %s', m.from == 'you' and 'you' or 'agent', text))
      if m.walk and #m.walk > 0 then
        say(string.format('      (leads to a tour of %d stops)', #m.walk))
      end
    end
  end
end
local parts = {}
for _, s in ipairs { 'waiting', 'answered', 'info', 'closed' } do
  if counts[s] then
    parts[#parts + 1] = counts[s] .. ' ' .. s
  end
end
say ''
say(#parts > 0 and table.concat(parts, ', ') or 'no threads')
if shown == 0 and not args.all then
  say 'nothing is waiting for you; --all shows everything'
end
io.stdout:write(table.concat(out, '\n') .. '\n')
