-- The skill's show.lua, run as the agent runs it: what waits for it, the
-- ids it writes next, and whether a review it wrote reads.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local SHOW = H.root .. '/skills/answering-threads/show.lua'

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

--- A review of the uncommitted change in `changed()`, with something
--- waiting in a contract, a step and a note, and what does not wait.
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
        title = 'What y is',
        colour = 'teal',
        introduction = { text = 'Two steps.' },
        steps = {
          { id = 2, title = 'x stays', text = { text = 'Untouched.' }, messages = {} },
          { id = 1, title = 'y is 20', text = { text = 'Ten times.' }, chunk = 'y', messages = { says('you', 'why ten?') } },
        },
      },
    },
    notes = {
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
  R.ok(out:find('review open  "Open"  3 waiting', 1, true), 'the open review, and how many wait:\n' .. out)
  R.ok(out:find('next ids: step 3, note 7, contract 2', 1, true), 'the next id of each kind')
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

  R.ok(out:find('#note:4  question "Why a table?", open', 1, true), 'the note, its kind and status')
  R.ok(out:find('reply in: notes[1].messages (counting from 1)', 1, true), "in a note's")
  R.ok(out:find('chunk m, a.lua:1 at now\n  >    1  local M = {}\n       2  local x = 1', 1, true), 'a chunk on no hunk, with the lines after it')
  R.ok(
    out:find("first, agent: Should M be a table?\n    … 2 messages more, the last the agent's\n    you: why not?", 1, true),
    'what it is, then only what is new'
  )
  R.ok(not out:find('what else?', 1, true), 'not what the agent has answered')

  R.ok(not out:find('#note:5', 1, true), 'not a conversation the agent spoke last in')
  R.ok(not out:find('#note:6', 1, true), 'not a settled note')
  R.ok(not out:find('#step:2', 1, true), 'not a step nobody spoke in')
  R.ok(not out:find('review shut', 1, true), 'not a closed review')
  R.ok(out:find('cannot read old (1 error; --check old says them)', 1, true), 'one it cannot read, named')
  R.ok(out:find('3 waiting for you, in 1 open review', 1, true), 'the count')
  R.ok(show(root, { 'shut' }).stdout:find('review shut is closed', 1, true), 'naming a closed one says so')
  R.eq(vim.fn.filereadable(root .. '/.threads/open.seen'), 0, 'nothing written')
end)

R.test('show.lua <review>: its next ids and chunks, though nothing waits', function()
  local root = changed()
  put(root, 'quiet', {
    title = 'Quiet',
    tours = {
      { title = 'T', colour = 'sky', introduction = { text = 'One step.' }, steps = { { id = 3, title = 's', chunk = 'm', messages = {} } } },
    },
    chunks = { chunk('m', 1, 'local M = {}', 'now') },
  })
  local res = show(root, { 'quiet' })
  R.eq(res.code, 0, 'runs')
  R.ok(res.stdout:find('review quiet  "Quiet"  0 waiting\n', 1, true), 'the review:\n' .. res.stdout)
  R.ok(res.stdout:find('about the code as it stands', 1, true), 'no diff')
  R.ok(res.stdout:find('next ids: step 4, note 1, contract 1', 1, true), 'the next ids')
  R.ok(res.stdout:find('1 chunk, by file:\n    a.lua  m', 1, true), 'its chunks')
  R.ok(res.stdout:find('nothing waits for you in review quiet', 1, true), 'nothing waits')
  R.eq(show(root, { 'nope' }).code, 1, 'no such review')
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
    notes = { { id = 1, kind = 'comment', title = 'this one?', chunk = 'fifty', messages = { says('you', 'this one?') } } },
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
    notes = { { id = 1, kind = 'question', status = 'open', title = 'why?', chunk = 'gone', messages = { says('you', 'why?') } } },
    chunks = { chunk('gone', 2, 'local gone = 1', 'base') },
  })
  local out = show(root, {}).stdout
  R.ok(out:find('chunk gone, a.lua:2 at base', 1, true), 'read at the base:\n' .. out)
  R.ok(out:find('>    2 - local gone = 1', 1, true), 'the removed line, marked')
end)

R.test('show.lua --check: passes a good review, and counts what is in it', function()
  local root = changed()
  local good = waiting()
  put(root, 'good', good)
  local res = show(root, { '--check', 'good' })
  R.eq({ res.code, res.stdout }, { 0, 'ok: good, 1 contract, 1 tour, 2 steps, 3 notes, 3 chunks\n' }, 'clean')
end)

R.test('show.lua --check: says what is wrong in the format, and fails', function()
  local root = changed()
  local bad = waiting()
  bad.format = 3
  bad.tours[1].steps[1].kind = 'feat'
  bad.notes[2].status = 'open'
  bad.notes[1].messages[1] = { from = 'agent', text = 'old' }
  bad.tours[1].steps[2].chunk = 'nowhere'
  put(root, 'bad', bad)
  local res = show(root, { '--check', 'bad' })
  R.eq(res.code, 1, 'fails')
  for _, line in ipairs {
    'error: the review: `format` is not a field; a review has no format number',
    'error: tour 1, step 1: `kind` is not a field',
    'error: note 5: a comment asks for nothing, so it has no `status`',
    'error: note 4, message 1: `text` is not a field',
    'error: note 4, message 1: no `prose`',
    'error: tour 1, step 2: its `chunk` is "nowhere", which is not one of the review\'s chunks',
    'bad: 6 errors',
  } do
    R.ok(res.stdout:find(line, 1, true), line .. ':\n' .. res.stdout)
  end
  R.eq(show(root, { '--check', 'nope' }).code, 1, 'no such review')
end)

R.test('show.lua --check: reads the chunks against the code, and lists the hunks left out', function()
  local root = changed()
  vim.fn.writefile({ 'return 1' }, root .. '/b.lua')
  local r = waiting()
  r.tours[1].steps[1].chunk = 'z'
  r.notes[2].chunk = 'gone'
  vim.list_extend(r.chunks, { chunk('z', 4, 'local z = 30'), chunk('gone', 9, 'print("nothing like it")'), chunk('spare', 2, 'local x = 1') })
  put(root, 'code', r)
  local res = show(root, { '--check', 'code' })
  R.eq(res.code, 1, 'a chunk not in the code fails it')
  for _, line in ipairs {
    'warn: chunk spare: nothing points at it',
    'warn: chunk z: found by likeness at a.lua:4: line 4 reads "local z = 3"',
    'error: chunk gone: a.lua has no line reading "print(\\"nothing like it\\")" at head',
    'note: 1 hunk of the diff on no step, note or contract, so not in the review:\nnote:   b.lua:1 (+1 -0)\n',
    'code: 1 error',
  } do
    R.ok(res.stdout:find(line, 1, true), line .. ':\n' .. res.stdout)
  end
end)

R.test('show.lua --check: reads the links and prose the agent wrote, not yours', function()
  local root = changed()
  local r = waiting()
  r.notes[1].messages[3] = says('agent', 'See #step:9, #note:5, good#note:5, broken#note:1, other#step:1, [[C:fields]] and #tour:1.\n\n```lua\nnever closed')
  r.notes[1].messages[4] = says('you', 'And #step:99?')
  put(root, 'prose', r)
  put(root, 'good', waiting())
  put(root, 'broken', { title = 'Broken', notes = { { id = 1, kind = 'comment', title = 'x', messages = {} } } })
  local res = show(root, { '--check', 'prose' })
  R.eq({ res.code, vim.split(vim.trim(res.stdout), '\n') }, {
    0,
    {
      'warn: note 4, message 3: `#step:9` goes to no step; if it is no link, put it in backticks',
      'warn: note 4, message 3: `broken#note:1` goes to review broken, which cannot be read: note 1: no `messages`: the first says what it is',
      'warn: note 4, message 3: `other#step:1` goes to no review other',
      'warn: note 4, message 3: `#tour:` is no link: a link names a step, a note or a contract, `#step:7`',
      'warn: note 4, message 3: `[[C:fields]]` is no link and shows as written: a link is `#step:7`, `#note:12` or `#contract:3`',
      'warn: note 4, message 3: a ``` fence is never closed, so all after it shows as code: end it with ``` on a line of its own',
      'ok: prose, 1 contract, 1 tour, 2 steps, 3 notes, 3 chunks',
    },
  }, 'good#note:5 goes to another review, read as the editor reads it; warnings only')
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
