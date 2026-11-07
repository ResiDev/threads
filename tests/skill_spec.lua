-- The skill's show.lua, run as the agent runs it: what waits for it, the
-- ids it writes next, and whether a topic it wrote reads.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local SHOW = H.root .. '/skills/threads/show.lua'

---@param root string
---@param args string[]
---@return vim.SystemCompleted
local function show(root, args)
  return vim.system(vim.list_extend({ 'nvim', '-l', SHOW }, args), { cwd = root, text = true }):wait()
end

---@param root string
---@param id string
---@param value table
local function put(root, id, value)
  vim.fn.mkdir(root .. '/.threads', 'p')
  vim.fn.writefile({ vim.json.encode(value) }, root .. '/.threads/' .. id .. '.json')
end

--- A repository with a change to a.lua not committed yet: line 3
--- changed, the rest as committed.
---@return string root
local function changed()
  local root = H.repo { ['a.lua'] = { 'local M = {}', 'local x = 1', 'local y = 2', 'local z = 3', 'return M' } }
  vim.fn.writefile({ 'local M = {}', 'local x = 1', 'local y = 20', 'local z = 3', 'return M' }, root .. '/a.lua')
  return root
end

--- A message, its prose `text`; yours with the time you wrote it.
---@param from 'you'|'agent'
---@param text string|nil
---@return table
local function says(from, text)
  return { from = from, at = from == 'you' and '2026-10-13T10:00:00' or nil, prose = { text = text or (from .. ' said') } }
end

---@param id string
---@param line integer
---@param from string
---@param rev string|nil
---@return table
local function chunk(id, line, from, rev)
  return { id = id, file = 'a.lua', line = line, from = from, rev = rev or 'head' }
end

--- A topic of the uncommitted change in `changed()`, with something
--- waiting in a contract, a step and a thread, and what does not wait.
---@return table
local function waiting()
  return {
    title = 'Open',
    diff = { of = 'uncommitted' },
    introduction = { text = 'y went up: #step:1.' },
    contracts = {
      {
        id = 1,
        name = 'y',
        kind = 'local',
        source = { change = 'changed', before = 'y-was', after = 'y' },
        why = 'Ten times what it was.',
        prose = { text = 'It is 20.' },
        messages = { says('you', 'who reads y?') },
      },
    },
    tours = {
      {
        id = 1,
        title = 'What y is',
        colour = 'teal',
        introduction = { text = 'Two steps.' },
        steps = {
          { id = 2, title = 'x stays', text = { text = 'Untouched.' }, messages = {} },
          { id = 1, title = 'y is 20', text = { text = 'Ten times.' }, chunk = 'y', messages = { says('you', 'why ten?') } },
        },
      },
    },
    threads = {
      {
        id = 4,
        kind = 'question',
        status = 'open',
        title = 'Why a table?',
        chunk = 'm',
        messages = { says('agent', 'Should M be a table?'), says('you', 'what else?'), says('agent', 'A function.'), says('you', 'why not?') },
      },
      { id = 5, kind = 'comment', title = 'Answered', messages = { says 'you', says 'agent' } },
      { id = 6, kind = 'issue', issue = 'bug', severity = 'low', status = 'fixed', title = 'Settled', messages = { says 'agent', says 'you' } },
    },
    chunks = { chunk('m', 1, 'local M = {}', 'now'), chunk('y', 3, 'local y = 20'), chunk('y-was', 3, 'local y = 2', 'base') },
  }
end

R.test('show.lua: what waits for the agent, where to reply, its code and what was said since it spoke', function()
  local root = changed()
  put(root, 'open', waiting())
  local shut = waiting()
  shut.status = 'closed'
  put(root, 'shut', shut)
  put(root, 'old', { format = 3, title = 'Before', tours = {}, chunks = {} })
  local out = show(root, {}).stdout
  R.ok(out:find('topic open  "Open"  3 waiting', 1, true), 'the open topic, and how many wait:\n' .. out)
  R.ok(out:find('next ids: tour 2, step 3, thread 7, contract 2', 1, true), 'the next id of each kind')
  R.ok(out:find('3 chunks, by file:\n    a.lua  m y y-was\n', 1, true), 'the chunk ids in use')

  R.ok(out:find('#contract:1  contract "y" (local, changed)  before: chunk y-was · after: chunk y', 1, true), 'the contract, its sides')
  R.ok(out:find('    why: Ten times what it was.', 1, true), 'what it is for')
  R.ok(out:find('reply in: contracts[1].messages (counting from 1)', 1, true), "where to write in a contract's")

  R.ok(out:find('#step:1  step "y is 20", in tour "What y is"', 1, true), 'the step, by its id')
  R.ok(out:find('the step says: Ten times.', 1, true), 'what it says')
  R.ok(out:find('reply in: tours[1].steps[2].messages (counting from 1)', 1, true), "in a step's, by its place, not its id")
  R.ok(out:find('chunk y, a.lua:3 at head\n    the hunk a.lua:3 (+1 -1):', 1, true), 'its chunk, and the hunk it is on')
  R.ok(out:find('     3 - local y = 2', 1, true), 'with what the hunk replaced')
  R.ok(out:find('>    3 + local y = 20', 1, true), 'its line marked')
  R.ok(out:find('you: why ten?', 1, true), 'what you asked')

  R.ok(out:find('#thread:4  question "Why a table?", open', 1, true), 'the thread, its kind and status')
  R.ok(out:find('reply in: threads[1].messages (counting from 1)', 1, true), "in a thread's")
  R.ok(out:find('chunk m, a.lua:1 at now\n  >    1  local M = {}\n       2  local x = 1', 1, true), 'a chunk on no hunk, with the lines after it')
  R.ok(
    out:find("first, agent: Should M be a table?\n    … 2 messages more, the last the agent's\n    you: why not?", 1, true),
    'what it is, then only what is new'
  )
  R.ok(not out:find('what else?', 1, true), 'not what the agent has answered')

  R.ok(not out:find('#thread:5', 1, true), 'not a conversation the agent spoke last in')
  R.ok(not out:find('#thread:6', 1, true), 'not a settled thread')
  R.ok(not out:find('#step:2', 1, true), 'not a step nobody spoke in')
  R.ok(not out:find('topic shut', 1, true), 'not a closed topic')
  R.ok(out:find('cannot read old (1 error; --check old says them)', 1, true), 'one it cannot read, named')
  R.ok(out:find('3 waiting for you, in 1 open topic', 1, true), 'the count')
  R.ok(show(root, { 'shut' }).stdout:find('topic shut is closed', 1, true), 'naming a closed one says so')
  R.eq(vim.fn.filereadable(root .. '/.threads/open.seen'), 0, 'nothing written')
end)

R.test('show.lua <topic>: its next ids and chunks, though nothing waits', function()
  local root = changed()
  put(root, 'quiet', {
    title = 'Quiet',
    tours = {
      { id = 1, title = 'T', colour = 'sky', introduction = { text = 'One step.' }, steps = { { id = 3, title = 's', chunk = 'm', messages = {} } } },
    },
    chunks = { chunk('m', 1, 'local M = {}', 'now') },
  })
  local res = show(root, { 'quiet' })
  R.eq(res.code, 0, 'runs')
  R.ok(res.stdout:find('topic quiet  "Quiet"  0 waiting\n', 1, true), 'the topic:\n' .. res.stdout)
  R.ok(res.stdout:find('about the code as it stands', 1, true), 'no diff')
  R.ok(res.stdout:find('next ids: tour 2, step 4, thread 1, contract 1', 1, true), 'the next ids')
  R.ok(res.stdout:find('1 chunk, by file:\n    a.lua  m', 1, true), 'its chunks')
  R.ok(res.stdout:find('nothing waits for you in topic quiet', 1, true), 'nothing waits')
  R.eq(show(root, { 'nope' }).code, 1, 'no such topic')
end)

R.test("show.lua: a chunk far down a long hunk is shown, with the hunk's rows around it", function()
  local before, after = {}, {}
  for n = 1, 100 do
    before[n], after[n] = 'old ' .. n, 'new ' .. n
  end
  local root = H.repo { ['b.lua'] = before }
  vim.fn.writefile(after, root .. '/b.lua')
  put(root, 'long', {
    title = 'Long',
    diff = { of = 'uncommitted' },
    threads = { { id = 1, kind = 'comment', title = 'this one?', chunk = 'fifty', messages = { says('you', 'this one?') } } },
    chunks = { { id = 'fifty', file = 'b.lua', line = 50, from = 'new 50', rev = 'head' } },
  })
  local out = show(root, {}).stdout
  R.ok(out:find('>   50 + new 50', 1, true), 'its line, marked:\n' .. out)
  R.ok(out:find('lines above', 1, true) and out:find('lines below', 1, true), 'the rest, counted')
end)

R.test('show.lua: a chunk read at the base marks the removed lines it quotes', function()
  local root = H.repo { ['a.lua'] = { 'local M = {}', 'local gone = 1', 'local kept = 2', 'return M' } }
  local base = vim.trim(H.git(root, { 'rev-parse', 'HEAD' }))
  vim.fn.writefile({ 'local M = {}', 'local kept = 2', 'return M' }, root .. '/a.lua')
  H.git(root, { 'commit', '-qam', 'gone' })
  put(root, 'removed', {
    title = 'Removed',
    diff = { base = base, head = 'HEAD' },
    threads = { { id = 1, kind = 'question', status = 'open', title = 'why?', chunk = 'gone', messages = { says('you', 'why?') } } },
    chunks = { chunk('gone', 2, 'local gone = 1', 'base') },
  })
  local out = show(root, {}).stdout
  R.ok(out:find('chunk gone, a.lua:2 at base', 1, true), 'read at the base:\n' .. out)
  R.ok(out:find('>    2 - local gone = 1', 1, true), 'the removed line, marked')
end)

R.test('show.lua --check: passes a good topic, and counts what is in it', function()
  local root = changed()
  local good = waiting()
  put(root, 'good', good)
  local res = show(root, { '--check', 'good' })
  R.eq({ res.code, res.stdout }, { 0, 'ok: good, 1 contract, 1 tour, 2 steps, 3 threads, 3 chunks\n' }, 'clean')
end)

R.test('show.lua --check: says what is wrong in the format, and fails', function()
  local root = changed()
  local bad = waiting()
  bad.format = 3
  bad.tours[1].steps[1].kind = 'feat'
  bad.threads[2].status = 'open'
  bad.threads[1].messages[1] = { from = 'agent', text = 'old' }
  bad.tours[1].steps[2].chunk = 'nowhere'
  put(root, 'bad', bad)
  local res = show(root, { '--check', 'bad' })
  R.eq(res.code, 1, 'fails')
  for _, line in ipairs {
    'error: the topic: `format` is not a field; a topic has no format number',
    'error: tour 1, step 1: `kind` is not a field',
    'error: thread 5: a comment asks for nothing, so it has no `status`',
    'error: thread 4, message 1: `text` is not a field',
    'error: thread 4, message 1: no `prose`',
    'error: tour 1, step 2: its `chunk` is "nowhere", which is not one of the topic\'s chunks',
    'bad: 6 errors',
  } do
    R.ok(res.stdout:find(line, 1, true), line .. ':\n' .. res.stdout)
  end
  R.eq(show(root, { '--check', 'nope' }).code, 1, 'no such topic')
end)

R.test('show.lua --check: reads the chunks against the code, and lists the hunks left out', function()
  local root = changed()
  vim.fn.writefile({ 'return 1' }, root .. '/b.lua')
  local r = waiting()
  r.tours[1].steps[1].chunk = 'z'
  r.threads[2].chunk = 'gone'
  vim.list_extend(r.chunks, { chunk('z', 4, 'local z = 30'), chunk('gone', 9, 'print("nothing like it")'), chunk('spare', 2, 'local x = 1') })
  put(root, 'code', r)
  local res = show(root, { '--check', 'code' })
  R.eq(res.code, 1, 'a chunk not in the code fails it')
  for _, line in ipairs {
    'warn: chunk spare: nothing points at it',
    'warn: chunk z: found by likeness at a.lua:4: line 4 reads "local z = 3"',
    'error: chunk gone: a.lua has no line reading "print(\\"nothing like it\\")" at head',
    'note: 1 hunk of the diff on no step, thread or contract, so not in the topic:\nnote:   b.lua:1 (+1 -0)\n',
    'code: 1 error',
  } do
    R.ok(res.stdout:find(line, 1, true), line .. ':\n' .. res.stdout)
  end
end)

R.test('show.lua --check: reads the links and prose the agent wrote, not yours', function()
  local root = changed()
  local r = waiting()
  r.threads[1].messages[3] =
    says('agent', 'See #step:9, #thread:5, good#thread:5, broken#thread:1, other#step:1, [[C:fields]] and #tour:1.\n\n```lua\nnever closed')
  r.threads[1].messages[4] = says('you', 'And #step:99?')
  put(root, 'prose', r)
  put(root, 'good', waiting())
  put(root, 'broken', { title = 'Broken', threads = { { id = 1, kind = 'comment', title = 'x', messages = {} } } })
  local res = show(root, { '--check', 'prose' })
  R.eq({ res.code, vim.split(vim.trim(res.stdout), '\n') }, {
    0,
    {
      'warn: thread 4, message 3: `#step:9` goes to no step; if it is no link, put it in backticks',
      'warn: thread 4, message 3: `broken#thread:1` goes to topic broken, which cannot be read: thread 1: no `messages`: the first says what it is',
      'warn: thread 4, message 3: `other#step:1` goes to no topic other',
      'warn: thread 4, message 3: `#tour:` is no link: a link names a step, a thread or a contract, `#step:7`',
      'warn: thread 4, message 3: `[[C:fields]]` is no link and shows as written: a link is `#step:7`, `#thread:12` or `#contract:3`',
      'warn: thread 4, message 3: a ``` fence is never closed, so all after it shows as code: end it with ``` on a line of its own',
      'ok: prose, 1 contract, 1 tour, 2 steps, 3 threads, 3 chunks',
    },
  }, 'good#thread:5 goes to another topic, read as the editor reads it; warnings only')
end)

R.test("show.lua --check: an open thread of the agent's opens with a short lead; whether it asks is not read", function()
  local root = changed()
  local r = waiting()
  local long = string.rep('word ', 61)
  vim.list_extend(r.threads, {
    { id = 7, kind = 'issue', issue = 'bug', severity = 'low', status = 'open', title = 'No lead', messages = { says('agent', '## Why\n\nIt breaks.') } },
    { id = 8, kind = 'question', status = 'open', title = 'Long', messages = { says('agent', long .. '?') } },
    { id = 9, kind = 'suggestion', status = 'open', title = 'Asks nothing', messages = { says('agent', 'Rename it.\n\n## Why\n\nClearer.') } },
    { id = 10, kind = 'comment', title = 'Says', messages = { says('agent', 'It is fine.') } },
    { id = 11, kind = 'question', status = 'open', title = 'Good', messages = { says('agent', 'Is it meant?\n\n## Why\n\nIt looks odd.') } },
  })
  put(root, 'leads', r)
  local res = show(root, { '--check', 'leads' })
  R.eq(
    vim.tbl_filter(function(l)
      return l:match '^warn'
    end, vim.split(res.stdout, '\n')),
    {
      'warn: thread 7, message 1: it opens with no lead: first say its point, when it happens and what you ask, in two or three sentences; the reading goes below',
      'warn: thread 8, message 1: its lead is 62 words: keep it to the point and the ask, 60 at most, and put the rest under a heading below',
    },
    'thread 9 asks nothing and is not warned of; a settled thread is not read'
  )
end)

R.test('show.lua --check: past twelve open threads of the agent it says so, as a thread; settled ones and yours are not counted', function()
  local root = changed()
  local r = waiting()
  local function ask(id)
    return { id = id, kind = 'question', status = 'open', title = 'Q' .. id, messages = { says('agent', 'Is it meant?') } }
  end
  for id = 7, 17 do
    table.insert(r.threads, ask(id))
  end
  table.insert(r.threads, { id = 18, kind = 'question', status = 'open', title = 'Mine', messages = { says('you', 'why?') } })
  put(root, 'twelve', r)
  local said = function(id)
    return vim.tbl_filter(function(l)
      return l:match '^note: %d+ of your threads' or l:match '^warn: threads'
    end, vim.split(show(root, { '--check', id }).stdout, '\n'))
  end
  R.eq(said 'twelve', {}, 'twelve open of the agent: thread 4 and 7 to 17; 5 and 18 are yours, 6 settled')
  table.insert(r.threads, ask(19))
  put(root, 'thirteen', r)
  R.eq(
    said 'thirteen',
    { 'note: 13 of your threads are open, which may be more than the user takes in at once: could some be a line each in the introduction?' },
    'the thirteenth is said, and is no warning'
  )
end)

R.test('show.lua --upgrade: an old topic of notes in the words of now, its links, its own chunks and what was seen; once', function()
  local root = changed()
  local old = waiting()
  old.notes, old.threads = old.threads, nil
  old.introduction = { text = 'Read #note:4 first, and other#note:2.' }
  old.notes[1].chunk = 'note-4'
  old.notes[1].messages[3] = says('agent', 'Here:\n\n{{chunk:note-4}}')
  old.chunks[1].id = 'note-4'
  put(root, 'old', old)
  vim.fn.writefile(
    { vim.json.encode { heard = { ['note:4:1'] = '2026-10-13T10:00:00', ['step:1:1'] = '2026-10-13T10:00:00' }, read = {}, walked = {} } },
    root .. '/.threads/old.seen'
  )
  R.eq(show(root, { '--upgrade' }).stdout, 'upgraded: old\n', 'said')
  local now = vim.json.decode(table.concat(vim.fn.readfile(root .. '/.threads/old.json'), '\n'))
  R.eq({ now.notes, #now.threads, now.introduction.text }, { nil, 3, 'Read #thread:4 first, and other#thread:2.' }, 'its threads, and links to them')
  R.eq(
    { now.threads[1].chunk, now.chunks[1].id, now.threads[1].messages[3].prose.text },
    { 'thread-4', 'thread-4', 'Here:\n\n{{chunk:thread-4}}' },
    'the chunk the thread was started on, wherever it is named'
  )
  local seen = vim.json.decode(table.concat(vim.fn.readfile(root .. '/.threads/old.seen'), '\n'))
  local heard = vim.tbl_keys(seen.heard)
  table.sort(heard)
  R.eq(heard, { 'step:1:1', 'thread:4:1' }, 'what was heard')
  R.eq(show(root, { '--check', 'old' }).code, 0, 'it reads')
  R.eq(show(root, { '--upgrade' }).stdout, 'nothing to upgrade\n', 'once')
end)

R.test('show.lua --check: an excerpt that lights nothing the text named, and a diff fence that leaves lines out, warn', function()
  local root = changed()
  local r = waiting()
  r.threads[1].messages[3] = says('agent', '`local y` went up:\n\n{{chunk:y}}\n\nAnd here:\n\n{{chunk:m}}\n\n```diff\n-local y = 20\n...\n+local y = 2\n```')
  put(root, 'shown', r)
  local res = show(root, { '--check', 'shown' })
  R.eq(
    vim.tbl_filter(function(l)
      return l:match '^warn'
    end, vim.split(res.stdout, '\n')),
    {
      'warn: thread 4, message 3: {{chunk:m}} lights nothing: name in backticks, in the text before it, what in it to look at',
      'warn: thread 4, message 3: a diff fence leaves lines out: write the lines that change and their context, so the fix can be checked',
    },
    '{{chunk:y}} lights `local y`, so only the other two'
  )
end)

R.test('show.lua --check: a table of more than four columns, or wider than a card, warns; a short one does not', function()
  local root = changed()
  local r = waiting()
  local long = string.rep('a long cell ', 4)
  r.threads[1].messages[3] = says(
    'agent',
    '| a | b |\n| - | - |\n| 1 | 2 |\n\n| a | b | c | d | e |\n| - | - | - | - | - |\n| 1 | 2 | 3 | 4 | 5 |\n\n| what | why |\n| - | - |\n| '
      .. long
      .. ' | '
      .. long
      .. ' |'
  )
  put(root, 'tables', r)
  R.eq(
    vim.tbl_filter(function(l)
      return l:match '^warn'
    end, vim.split(show(root, { '--check', 'tables' }).stdout, '\n')),
    {
      'warn: thread 4, message 3: a table has 5 columns: keep it to 4, a few words a cell, or split it',
      'warn: thread 4, message 3: a table is 97 columns wide and a card 68, so its widest cells are cut short with …: a few words a cell',
    },
    'the five columns, and the wide one'
  )
end)

R.test('show.lua --check: places in prose that name nothing fail it, a diagram never placed warns', function()
  local root = changed()
  local r = waiting()
  r.tours[1].introduction = {
    text = 'The shape:\n\n{{diagram:missing}}\n\n{{chunk:nowhere}}',
    diagrams = { shape = { kind = 'flow', nodes = { { id = 'a', label = 'y', chunk = 'y' } } } },
  }
  put(root, 'placed', r)
  local res = show(root, { '--check', 'placed' })
  R.eq(res.code, 1, 'fails')
  for _, line in ipairs {
    'warn: tour 1, introduction: the diagram "shape" is never placed',
    'error: tour 1, introduction: line 3, `{{diagram:missing}}`: its `diagrams` have none by that name',
    'error: tour 1, introduction: line 5, `{{chunk:nowhere}}`: no chunk has that id',
  } do
    R.ok(res.stdout:find(line, 1, true), line .. ':\n' .. res.stdout)
  end
end)
