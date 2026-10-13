-- The skill's show.lua, run as the agent runs it: what waits for it, and
-- whether a review it wrote reads.

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

--- A repository with a change to a.lua not committed yet: line 3 changed.
---@return string root
local function changed()
  H.reset()
  local root = H.repo { ['a.lua'] = { 'local M = {}', 'local x = 1', 'local y = 2', 'local z = 3', 'return M' } }
  vim.fn.writefile({ 'local M = {}', 'local x = 1', 'local y = 20', 'local z = 3', 'return M' }, root .. '/a.lua')
  return root
end

---@param from 'you'|'agent'
---@param text string|nil
local function says(from, text)
  return { from = from, text = text or (from .. ' said') }
end

R.test('show.lua: what waits for the agent, a step too, with its code; nothing in a closed review', function()
  local root = changed()
  put(root, 'open', {
    format = 2,
    title = 'Open',
    diff = { of = 'uncommitted' },
    threads = {
      { id = 1, chunk = { file = 'a.lua', line = 1, text = 'local M = {}' }, messages = { says('you', 'why a table?') } },
      {
        id = 2,
        title = 'The change',
        messages = {
          {
            from = 'agent',
            text = 'y went up.',
            tours = {
              {
                title = 'What changed',
                steps = {
                  { title = 'x stays', text = 'Untouched.' },
                  {
                    title = 'y is 20',
                    text = 'Ten times.',
                    chunk = { file = 'a.lua', line = 3, text = 'local y = 20' },
                    messages = { says('you', 'why ten?') },
                  },
                },
              },
            },
          },
        },
      },
      { id = 3, title = 'Answered', messages = { says 'you', says 'agent' } },
    },
  })
  put(root, 'shut', { format = 2, title = 'Shut', status = 'closed', threads = { { id = 1, messages = { says 'you' } } } })
  put(root, 'old', { title = 'A batch', threads = {} })
  local out = show(root, {}).stdout
  R.ok(out:find('review open  "Open"  2 waiting', 1, true), 'the open review, and how many wait:\n' .. out)
  R.ok(out:find('#1  (no title yet: give it one)  a.lua:1', 1, true), 'your thread, on its line')
  R.ok(out:find('>    1  local M = {}', 1, true), 'its line, marked')
  R.ok(out:find('#2.2  step "y is 20", in tour "What changed" of #2 "The change"', 1, true), 'the step you replied in')
  R.ok(out:find('>    3 + local y = 20', 1, true), 'its hunk, its line marked')
  R.ok(out:find('     3 - local y = 2', 1, true), 'with what it replaced')
  R.ok(out:find('the thread begins: y went up.', 1, true), "the thread's introduction, for context")
  R.ok(out:find('reply in: threads[2].messages[1].tours[1].steps[2].messages, counting from 1', 1, true), 'where to write')
  R.ok(out:find('reply in: threads[1].messages,', 1, true), "and a thread's own")
  R.ok(out:find('you: why ten?', 1, true), 'what you asked')
  R.ok(not out:find('#3', 1, true), 'not a thread that is your move')
  R.ok(not out:find('review shut', 1, true), 'not a closed review')
  R.ok(out:find('cannot read old (1 error; --check old says them)', 1, true), 'one it cannot read, named')
  R.ok(out:find('2 waiting for you, in 1 open review', 1, true), 'the count')
  R.ok(show(root, { 'shut' }).stdout:find('review shut is closed', 1, true), 'naming a closed one says so')
  R.eq(vim.fn.filereadable(root .. '/.threads/open.seen'), 0, 'nothing written')
end)

R.test("show.lua: a chunk far down a long hunk is shown, with the hunk's rows around it", function()
  H.reset()
  local before, after = {}, {}
  for n = 1, 100 do
    before[n], after[n] = 'old ' .. n, 'new ' .. n
  end
  local root = H.repo { ['b.lua'] = before }
  vim.fn.writefile(after, root .. '/b.lua')
  put(root, 'long', {
    format = 2,
    title = 'Long',
    diff = { of = 'uncommitted' },
    threads = { { id = 1, chunk = { file = 'b.lua', line = 50, text = 'new 50' }, messages = { says('you', 'this one?') } } },
  })
  local out = show(root, {}).stdout
  R.ok(out:find('>   50 + new 50', 1, true), 'its line, marked:\n' .. out)
  R.ok(out:find('lines above', 1, true) and out:find('lines below', 1, true), 'the rest, counted')
end)

R.test('show.lua --check: passes a good review; says what is wrong with a bad one, and fails', function()
  local root = changed()
  local good = {
    format = 2,
    title = 'Good',
    diff = { of = 'uncommitted' },
    threads = {
      {
        id = 1,
        title = 'y',
        kind = 'fix',
        risk = 'low',
        chunk = { file = 'a.lua', line = 3, text = 'local y = 20' },
        messages = { says('agent', 'It is 20 now.') },
      },
    },
  }
  put(root, 'good', good)
  local ok = show(root, { '--check', 'good' })
  R.eq({ ok.code, ok.stdout }, { 0, 'ok: good, 1 thread\n' }, 'clean')

  local bad = vim.deepcopy(good)
  bad.threads[1].messages[1].walk = {}
  bad.threads[1].risk = 'medium'
  bad.threads[2] = { id = 2, chunk = { file = 'a.lua', line = 9, text = 'print("nothing like it")' }, messages = { says 'you' } }
  bad.threads[3] = { id = 3, chunk = { file = 'a.lua', line = 4, text = 'local z = 30' }, messages = { says 'you' } }
  put(root, 'bad', bad)
  local res = show(root, { '--check', 'bad' })
  R.eq(res.code, 1, 'fails')
  R.ok(
    res.stdout:find("error: thread 1, message 1: `walk` is not a field; a message's tours are its `tours`", 1, true),
    'a field of the old shape:\n' .. res.stdout
  )
  R.ok(res.stdout:find('warn: thread 1: a medium risk with no `risk_why`', 1, true), 'a warning')
  R.ok(res.stdout:find('bad: 1 error', 1, true), 'counted')

  bad.threads[1].messages[1].walk = nil
  put(root, 'bad', bad)
  res = show(root, { '--check', 'bad' })
  R.ok(res.stdout:find('error: thread 2, chunk: a.lua has no line reading "print(\\"nothing like it\\")"', 1, true), 'a chunk not in the code:\n' .. res.stdout)
  R.ok(
    res.stdout:find('warn: thread 3, chunk: no line of a.lua reads "local z = 30"; found by likeness: line 4 reads "local z = 3"', 1, true),
    'one found by likeness'
  )

  bad.threads[2], bad.threads[3] = nil, nil
  bad.threads[1].chunk = { file = 'a.lua', line = 1, text = 'local M = {}' }
  put(root, 'bad', bad)
  res = show(root, { '--check', 'bad' })
  R.ok(
    res.stdout:find('note: 1 hunk of the diff in no thread or step, so not in the review:\nnote:   a.lua:3 (+1 -1)\n', 1, true),
    'a hunk left out:\n' .. res.stdout
  )

  R.eq(show(root, { '--check', 'nope' }).code, 1, 'no such review')
end)

R.test('show.lua --check: reads the excerpts and links in what the agent wrote', function()
  local root = changed()
  local text = 'See #1.2, #2 and good#1.\n\n```code\n{ "file": "a.lua", "line": 3, "text": "print(42)" }\n```'
  put(root, 'good', { format = 2, title = 'Good', threads = { { id = 1, title = 't', messages = { says('agent', 'x') } } } })
  put(root, 'prose', { format = 2, title = 'Prose', threads = { { id = 1, title = 'y', messages = { says('agent', text) } } } })
  local res = show(root, { '--check', 'prose' })
  R.eq(res.code, 1, 'an excerpt not in the code fails it')
  R.eq(vim.split(vim.trim(res.stdout), '\n'), {
    'warn: thread 1, message 1: `#1.2` goes to no step: thread 1 has no tours',
    'warn: thread 1, message 1: `#2` goes to no thread',
    'error: thread 1, message 1, excerpt 1: a.lua has no line reading "print(42)" (if a change of yours rewrote it, quote it as it reads now)',
    'prose: 1 error',
  }, 'good#1 goes to another review, read as the editor reads it')
end)
