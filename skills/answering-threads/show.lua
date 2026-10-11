-- Print the threads waiting for an answer, with the code they are on and
-- the tour stop they are a reply in, or check a batch after answering it.
--
--   nvim -l show.lua [batch-id]           the waiting threads
--   nvim -l show.lua [batch-id] --all     every thread, done ones too
--   nvim -l show.lua [batch-id] --check   is the file valid, do the anchors resolve
--
-- Run from anywhere inside the repository. Needs only Neovim.

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

-- thread.nvim itself, for its diagram checker: this file is in
-- <plugin>/skills/answering-threads/, maybe through a symlink.
local here = vim.uv.fs_realpath(debug.getinfo(1, 'S').source:sub(2)) or ''
local plugin = vim.fn.fnamemodify(here, ':h:h:h')
vim.opt.runtimepath:prepend(plugin)
local has_diagram, diagram = pcall(require, 'thread.diagram')

local root = vim.trim(vim.fn.system { 'git', 'rev-parse', '--show-toplevel' })
if vim.v.shell_error ~= 0 then
  root = vim.fn.getcwd()
end
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
local ok, batch = pcall(vim.json.decode, raw, { luanil = { object = true, array = true } })
if not ok or type(batch) ~= 'table' then
  die(path .. ' is not valid JSON: ' .. tostring(batch))
end
local threads = batch.threads or {}

local function anchored(c)
  return type(c.file) == 'string' and c.file ~= ''
end

local function talked(c)
  for _, m in ipairs(c.messages or {}) do
    if m.from == 'you' then
      return true
    end
  end
  return false
end

local function status(c)
  if c.status == 'closed' or c.status == 'resolved' or c.status == 'dismissed' then
    return 'closed'
  end
  local last = (c.messages or {})[#(c.messages or {})]
  if last and last.from ~= 'you' then
    return talked(c) and 'answered' or 'info'
  end
  return 'waiting'
end

local by_id = {}
for _, c in ipairs(threads) do
  if type(c.id) == 'number' then
    by_id[c.id] = c
  end
end

--- The tour a thread leads to: its latest message with a walk.
local function walk_of(c)
  for i = #(c.messages or {}), 1, -1 do
    local w = c.messages[i].walk
    if type(w) == 'table' and #w > 0 then
      return w
    end
  end
end

local function stop_kind(e)
  if type(e.stage) == 'string' and e.stage ~= '' then
    return 'stage'
  end
  return anchored(e) and 'step' or 'page'
end

local function stop_title(e)
  if stop_kind(e) == 'stage' then
    return e.stage
  end
  return e.title or ((e.body or ''):match '^%s*([^\n]*)' or '')
end

local function title(c)
  if c.title and c.title ~= '' then
    return c.title
  end
  local first = (c.messages or {})[1]
  return ((first and first.text or ''):match '^%s*([^\n]*)' or '')
end

local files = {}
local function lines_of(a)
  local key = (a.rev or '') .. ':' .. a.file
  if files[key] == nil then
    local text
    if a.rev then
      text = vim.fn.system { 'git', '-C', root, 'show', a.rev .. ':' .. a.file }
      text = vim.v.shell_error == 0 and text or nil
    else
      text = read(root .. '/' .. a.file)
    end
    files[key] = text and vim.split((text:gsub('\n$', '')), '\n', { plain = true }) or false
  end
  return files[key] or nil
end

local function norm(s)
  return (s:gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', ''))
end

--- The line a quote is on: verbatim or ignoring whitespace, nearest the hint.
local function find(a)
  local lines = lines_of(a)
  if not lines then
    return nil, 'no file ' .. a.file .. (a.rev and (' at ' .. a.rev) or '')
  end
  if not a.text or a.text == '' then
    return a.line
  end
  local best, gap
  for i, l in ipairs(lines) do
    if l == a.text or norm(l) == norm(a.text) then
      local g = math.abs(i - (a.line or i))
      if not gap or g < gap then
        best, gap = i, g
      end
    end
  end
  if not best then
    return nil, string.format('%s: no line reads %q', a.file, a.text)
  end
  return best
end

--- The stop of a tour a thread is a reply in: the owner, the stop, its index.
local function stop_of(c)
  if type(c.on) ~= 'table' then
    return nil
  end
  local owner = by_id[c.on.thread]
  local list = owner and walk_of(owner)
  return owner, list and list[c.on.step], c.on.step
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
    local done = status(c) == 'closed'
    if anchored(c) then
      local _, err = find(c)
      if err and not done then
        bad(err .. " (if your change rewrote this line, update the thread's text and line)")
      end
    elseif c.text or c.line then
      warn 'has `text` or `line` but no `file`: it is about no line and shows as a page'
    end
    if not talked(c) and not (c.title and c.title ~= '') then
      warn 'a thread you started has no `title`'
    end
    if c.on ~= nil then
      local owner, stop = stop_of(c)
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
              local line = (lines_of(a) or {})[at] or ''
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
          if has_diagram then
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
          elseif type(x.diagram) ~= 'table' or not x.diagram.kind then
            bad(xwhere .. ': a diagram needs a kind')
          end
        end
      end
      extras(m, where, c.file, c.rev)
      -- The tour it leads to: every stop.
      if m.walk ~= nil and type(m.walk) ~= 'table' then
        bad(where .. ': walk must be a list of stops')
      end
      for k, e in ipairs(type(m.walk) == 'table' and m.walk or {}) do
        local swhere = string.format('%s, stop %d', where, k)
        local kind = stop_kind(e)
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
local rounds = batch.rounds or {}
local next_id = 0
for tid in pairs(by_id) do
  next_id = math.max(next_id, tid)
end
say(string.format('batch %s: "%s", replies %s, %d round%s sent', id, batch.title or '', batch.reply or 'inline', #rounds, #rounds == 1 and '' or 's'))
say(string.format('file: %s', path))
say(string.format('next free thread id: %d', next_id + 1))
if batch.diff then
  say(string.format('reviewing the diff %s..%s', batch.diff.base or '?', batch.diff.head or 'working tree'))
end
local counts, shown = {}, 0
for _, c in ipairs(threads) do
  local s = status(c)
  counts[s] = (counts[s] or 0) + 1
  if args.all or s == 'waiting' then
    shown = shown + 1
    say ''
    local place
    if anchored(c) then
      local at, err = find(c)
      local span = c.lines and c.lines > 1 and string.format('-%d', (at or c.line) + c.lines - 1) or ''
      place = string.format('%s:%s%s%s', c.file, at or c.line or '?', span, c.rev and (' @ ' .. c.rev) or '')
      say(string.format('#%d  %s  [%s]%s', c.id, place, s, c.title and ('  "' .. c.title .. '"') or '  (no title yet: give it one)'))
      if err then
        say('    ! ' .. err)
      end
      local lines = lines_of(c)
      if at and lines then
        local last = at + (c.lines or 1) - 1
        for n = math.max(1, at - 2), math.min(#lines, last + 2) do
          say(string.format('  %s%4d  %s', (n >= at and n <= last) and '>' or ' ', n, lines[n]))
        end
      end
    else
      say(string.format('#%d  (about no line)  [%s]%s', c.id, s, c.title and ('  "' .. c.title .. '"') or '  (no title yet: give it one)'))
    end
    local owner, stop, n = stop_of(c)
    if owner and stop then
      say(string.format('    in: stop %d (%s) of #%d "%s": "%s"  (a reply in a tour: answer about this stop)', n, stop_kind(stop), owner.id, title(owner), stop_title(stop)))
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
