-- Print the threads waiting for an answer, with the code they are on and
-- where they sit in their tree, or check a batch after answering it.
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
  return last and last.round and 'waiting' or 'draft'
end

local by_id, parent = {}, {}
for _, c in ipairs(threads) do
  if type(c.id) == 'number' then
    by_id[c.id] = c
  end
end
for _, c in ipairs(threads) do
  for _, m in ipairs(c.messages or {}) do
    for _, child in ipairs(m.children or {}) do
      if parent[child] == nil then
        parent[child] = c.id
      end
    end
  end
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

--- The way down to a thread: its ancestors' titles.
local function crumbs(c)
  local out, seen = {}, {}
  local p = parent[c.id]
  while p and by_id[p] and not seen[p] do
    seen[p] = true
    table.insert(out, 1, string.format('#%d "%s"', p, title(by_id[p])))
    p = parent[p]
  end
  return out
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
    for i, m in ipairs(c.messages or {}) do
      local where = string.format('message %d', i)
      if m.from ~= 'you' and m.from ~= 'agent' then
        bad(where .. ': from must be "you" or "agent"')
      end
      if (type(m.text) ~= 'string' or m.text == '') and not (m.children and #m.children > 0) then
        bad(where .. ': no text')
      end
      for j, ch in ipairs(m.changes or {}) do
        local _, cerr = find(ch)
        if cerr and i == #c.messages then
          bad(string.format('%s, change %d: %s', where, j, cerr))
        end
      end
      for j, n in ipairs(m.notes or {}) do
        local a = vim.tbl_extend('keep', n, { file = c.file, rev = c.rev })
        if not a.file then
          bad(string.format('%s, note %d: no file, and the thread has none', where, j))
        else
          local _, nerr = find(a)
          if nerr then
            bad(string.format('%s, note %d: %s', where, j, nerr))
          elseif type(n.mark) == 'string' and n.mark ~= '' then
            local at = find(a)
            local line = (lines_of(a) or {})[at] or ''
            if not line:find(n.mark, 1, true) then
              warn(string.format('%s, note %d: the mark %q is not on its line', where, j, n.mark))
            end
          end
        end
      end
      if m.verdict ~= nil and not VERDICTS[m.verdict] then
        bad(string.format('%s: verdict %q is not one of bug, flaw, risk, trade-off, decision, how it works, fine', where, tostring(m.verdict)))
      end
      if m.diagram ~= nil then
        if has_diagram then
          local d, derr = diagram.validate(m.diagram)
          if not d then
            bad(string.format('%s, diagram: %s', where, derr))
          else
            for _, node in ipairs(diagram.nodes(d)) do
              if node.file then
                local _, nerr = find { file = node.file, text = node.text, line = node.line }
                if nerr and node.text then
                  bad(string.format('%s, diagram node %q: %s', where, node.label, nerr))
                end
              end
            end
          end
        elseif type(m.diagram) ~= 'table' or not m.diagram.kind then
          bad(where .. ': a diagram needs a kind')
        end
      end
      for _, child in ipairs(m.children or {}) do
        if type(child) ~= 'number' or not by_id[child] then
          bad(string.format('%s leads to thread %s, which does not exist', where, tostring(child)))
        elseif child == c.id then
          bad(where .. ' leads to its own thread')
        elseif parent[child] ~= c.id then
          bad(string.format('%s leads to thread %d, which thread %d already leads to: a thread has one parent', where, child, parent[child]))
        end
      end
    end
  end
  -- No thread may be its own ancestor.
  for tid in pairs(by_id) do
    local seen, p = {}, parent[tid]
    while p do
      if p == tid or seen[p] then
        problems[#problems + 1] = string.format('thread %d: its parents loop back to it', tid)
        break
      end
      seen[p] = true
      p = parent[p]
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
    local up = crumbs(c)
    if #up > 0 then
      say('    in: ' .. table.concat(up, ' › ') .. '  (a step of a walk: answer about this step)')
    end
    for _, m in ipairs(c.messages or {}) do
      local text = (m.text or ''):gsub('\n', '\n      ')
      say(string.format('    %s: %s', m.from == 'you' and 'you' or 'agent', text))
      if m.children and #m.children > 0 then
        say(string.format('      (leads to %s)', table.concat(vim.tbl_map(function(child)
          return '#' .. child
        end, m.children), ', ')))
      end
    end
  end
end
local parts = {}
for _, s in ipairs { 'waiting', 'draft', 'answered', 'info', 'closed' } do
  if counts[s] then
    parts[#parts + 1] = counts[s] .. ' ' .. s
  end
end
say ''
say(#parts > 0 and table.concat(parts, ', ') or 'no threads')
if shown == 0 and not args.all then
  say 'nothing is waiting for you: drafts are not sent yet; --all shows everything'
end
io.stdout:write(table.concat(out, '\n') .. '\n')
