-- thread.model.review: a review file as the agent writes it, read and
-- checked once, and written back.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local file = require 'thread.store.file'
local review = require 'thread.model.review'

--- The sketch in DIRECTION.md, near enough.
local function sketch()
  return {
    format = 2,
    title = 'Tours pick up where you left off',
    diff = { base = 'HEAD' },
    introduction = 'Two things changed.',
    threads = {
      {
        id = 1,
        title = 'Walking a tour again resumes it',
        chunk = { file = 'a.lua', line = 1, text = 'local M = {}' },
        kind = 'feat',
        risk = 'medium',
        risk_why = 'the .seen file gains a field',
        messages = {
          {
            from = 'agent',
            text = 'Why it changed.',
            tours = {
              {
                title = 'Every caller',
                steps = {
                  { id = 1, title = 'The map', text = 'It ignores `furthest`.', chunk = { file = 'a.lua', line = 3, text = 'return M' } },
                  { id = 2, title = 'On no line', text = 'A page.' },
                },
              },
            },
          },
        },
        checks = { { text = 'Walked it twice: on step 2.', run = 'make test' } },
      },
    },
  }
end

--- The agent writes a review file.
---@param id string
---@param data table
local function agent_writes(id, data)
  vim.fn.mkdir(file.dir(), 'p')
  vim.fn.writefile({ vim.json.encode(data) }, file.dir() .. '/' .. id .. '.json')
end

R.test('review.parse: the sketch reads, with what it leaves out filled in', function()
  local r, p = review.parse(sketch(), 'tours')
  R.eq({ p.errors, p.warnings }, { {}, {} }, 'no problems')
  r = assert(r)
  R.eq({ r.id, r.status, #r.rounds, r.threads[1].status }, { 'tours', 'open', 0, 'open' }, 'open, no rounds')
  R.eq(r.threads[1].messages[1].tours[1].steps[2].messages, {}, "a step's conversation starts empty")
end)

R.test('review.parse: the old shape is told to write format 2', function()
  local r, p = review.parse({ title = 'Old', threads = {} }, 'old')
  R.eq(r, nil, 'not read')
  R.eq(#p.errors, 1, 'one error')
  R.ok(p.errors[1]:find('"format": 2', 1, true), p.errors[1])
end)

R.test('review.parse: every problem says where it is and what to write', function()
  local data = sketch()
  local t = data.threads[1]
  t.status = 'closed'
  t.messages[1].walk = {}
  t.messages[1].tours[1].steps[1].messages = { { from = 'agent', text = 'x', tours = {} } }
  t.messages[1].tours[1].steps[2].chunk = { file = 'a.lua', line = 0, text = 'a\nb' }
  t.messages[1].tours[1].steps[2].diagram = { kind = 'flow', nodes = { { id = 'a', label = 'A', step = 1 } }, edges = {} }
  t.messages[2] = { from = 'you', text = 'mine', tours = {} }
  data.threads[2] = { id = 1, messages = { { from = 'them', text = 'x' } } }
  local r, p = review.parse(data, 'bad')
  R.eq(r, nil, 'not read')
  R.eq(p.errors, {
    'thread 1: `status` is "open", "fixed", "won\'t fix", "not a problem", not "closed"',
    "thread 1, message 1: `walk` is not a field; a message's tours are its `tours`",
    "thread 1, message 1, tour 1, step 1, message 1: a step's messages carry no tours: the back and forth stops a level down",
    'thread 1, message 1, tour 1, step 2, chunk: `line` must be a whole number, 1 or more',
    'thread 1, message 1, tour 1, step 2, chunk: `text` is one line, quoted as it reads',
    'thread 1, message 1, tour 1, step 2, diagram: nodes[1].step is gone: a node links to code, with `file`, `text` and `line`',
    "thread 1, message 2: only the agent's messages carry tours",
    'thread 1, message 1: `from` is "you", "agent", not "them"',
    'thread 1: its id is used twice',
  }, 'each, where it is')
end)

R.test('review.parse: a step has an id, which no other step of its thread has, in any tour', function()
  local data = sketch()
  local steps = data.threads[1].messages[1].tours[1].steps
  steps[1].id = nil
  data.threads[1].messages[2] = { from = 'agent', text = 'More.', tours = { { title = 'Again', steps = { { id = 2, title = 'Twice', text = 'x' } } } } }
  local r, p = review.parse(data, 'ids')
  R.eq(r, nil, 'not read')
  R.eq(p.errors, {
    'thread 1, message 1, tour 1, step 1: no `id`: number it the highest step id in its thread plus one',
    'thread 1: step id 2 is used twice, by message 1, tour 1, step 2 and message 2, tour 1, step 1: each step has its own',
  }, 'each said')
end)

R.test("review.parse: groups have names of their own, a palette colour, and a thread names one of the review's", function()
  local data = sketch()
  data.groups = {
    { name = 'Saving', colour = 'orange', summary = 'Everything goes through one verb.' },
    { name = 'Saving', colour = 'red' },
    { colour = 'teal' },
  }
  data.threads[1].group = 'Drawing'
  data.threads[1].messages[1].tours[1].colour = 'red'
  local r, p = review.parse(data, 'groups')
  R.eq(r, nil, 'not read')
  R.eq(p.errors, {
    'the review, group 2: `colour` is "orange", "yellow", "lime", "teal", "sky", "blue", "violet", "pink", not "red"',
    'the review, group 2: group 1 is called "Saving" too: each group has its own name',
    'the review, group 3: no `name`',
    'thread 1, message 1, tour 1: `colour` is "orange", "yellow", "lime", "teal", "sky", "blue", "violet", "pink", not "red"',
    'thread 1: its `group` is "Drawing", which the review\'s `groups` do not name (they are "Saving", "Saving")',
  }, 'each said')
  data = sketch()
  data.groups = { { name = 'Saving' } }
  r, p = review.parse(data, 'ungrouped')
  R.ok(r, 'read')
  R.eq(p.warnings, { 'thread 1: no `group`: it is listed after the groups, with the threads in none' }, 'a thread in none, warned')
end)

R.test('review.parse: contracts have ids of their own, a change, and chunks; a thread touches those its chunks share a line with', function()
  local contract = require 'thread.model.contract'
  local data = sketch()
  data.contracts = {
    { id = 'the-map', name = 'M', kind = 'module', change = 'changed', after = 'one table', at = { file = 'a.lua', line = 1, text = 'local M = {}' } },
    { id = 'the-map', name = 'M again', change = 'moved' },
    { id = 'two words', name = 'x', change = 'added', before = 'none' },
  }
  local r, p = review.parse(data, 'contracts')
  R.eq(r, nil, 'not read')
  R.eq(p.errors, {
    'the review, contract 2: contract 1 has the id "the-map" too: each has its own',
    'the review, contract 2: `change` is "added", "changed", "removed", "relied on", not "moved"',
    'the review, contract 3: its `id` is "two words": letters, digits, `-`, `_` and `.` only, so `[[two words]]` finds it',
  }, 'each said')
  data = sketch()
  data.contracts = {
    { id = 'top', name = 'M', kind = 'a table, in its own words', change = 'changed', at = { file = 'a.lua', line = 1, text = 'local M = {}' } },
    { id = 'end', name = 'return M', change = 'relied on', uses = { { file = 'a.lua', line = 2, lines = 2, text = '' } } },
    { id = 'elsewhere', name = 'b', change = 'added', at = { file = 'b.lua', line = 3, text = 'b' } },
  }
  r, p = review.parse(data, 'contracts')
  R.ok(r, 'read: ' .. vim.inspect(p.errors))
  r = assert(r)
  local t = r.threads[1]
  R.eq(
    vim.tbl_map(function(c)
      return c.id
    end, contract.touched(r, { t.chunk, t.messages[1].tours[1].steps[1].chunk })),
    { 'top', 'end' },
    "the thread's own chunk and its step's, by line; not another file's"
  )
  R.eq(contract.names(r).top, 'M', 'a name by its id')
end)

R.test('touch.index: each thread, tour, step, group and contract its files; a contract its threads, tours and groups, and theirs it', function()
  local touch = require 'thread.model.touch'
  local data = sketch()
  data.groups = { { name = 'Saving' } }
  data.threads[1].group = 'Saving'
  data.contracts = {
    { id = 'end', name = 'return M', change = 'relied on', uses = { { file = 'a.lua', line = 3, text = 'return M' } } },
    { id = 'else', name = 'b', change = 'added', at = { file = 'b.lua', line = 1, text = 'b' } },
  }
  local r = assert(review.parse(data, 'touch'))
  local T = touch.index(r)
  local t = r.threads[1]
  local x = t.messages[1].tours[1]
  local g = r.groups[1]
  local ending, other = r.contracts[1], r.contracts[2]
  R.eq({ T.files[t], T.files[x], T.files[x.steps[2]], T.files[g], T.files[other] }, {
    { ['a.lua'] = true },
    { ['a.lua'] = true },
    {},
    { ['a.lua'] = true },
    { ['b.lua'] = true },
  }, 'files, a step on no line none')
  R.eq({ T.contracts[t], T.contracts[x], T.contracts[g] }, { { ending }, { ending }, { ending } }, 'what each touches, by line')
  R.eq(touch.related(T, ending), { [t] = true, [x] = true, [g] = true }, 'a contract: its thread, tour and group')
  R.eq(touch.related(T, other), {}, 'one nothing touches: none')
  R.eq(touch.related(T, x.steps[1]), nil, 'a step is on neither side')
end)

R.test("review.grouped: in the groups' order, the open first in each, then those in none; with no groups, the file's order", function()
  local function t(id, group, status)
    return { id = id, title = 'T' .. id, group = group, status = status, messages = { { from = 'agent', text = 'x' } } }
  end
  local r = assert(review.parse({ format = 2, title = 'G', threads = { t(1), t(2, nil, 'fixed'), t(3) } }, 'none'))
  R.eq(#review.grouped(r), 1, 'no groups: one list')
  R.eq(
    vim.tbl_map(function(x)
      return x.id
    end, review.ordered(r)),
    { 1, 2, 3 },
    "in the file's order, the closed where they are"
  )
  local data
  data = {
    format = 2,
    title = 'G',
    groups = { { name = 'a' }, { name = 'b' }, { name = 'empty' } },
    threads = { t(1, 'b'), t(2, 'a', 'fixed'), t(3), t(4, 'a'), t(5, 'b') },
  }
  r = assert(review.parse(data, 'some'))
  R.eq(
    vim.tbl_map(function(g)
      return { g.group and g.group.name or false, vim.tbl_map(function(x)
        return x.id
      end, g.threads) }
    end, review.grouped(r)),
    { { 'a', { 4, 2 } }, { 'b', { 1, 5 } }, { false, { 3 } } },
    'by group, the closed last, an empty group left out'
  )
  R.eq(
    vim.tbl_map(function(x)
      return x.id
    end, review.ordered(r)),
    { 4, 2, 1, 5, 3 },
    'the order H and L go in'
  )
end)

R.test("model/diagram: format 1's links on a node only when legacy asks", function()
  local diagram = require 'thread.model.diagram'
  local d = { kind = 'flow', nodes = { { id = 'a', label = 'A', stage = 2 } }, edges = {} }
  R.eq(select(2, diagram.validate(d)), 'nodes[1].stage is gone: a node links to code, with `file`, `text` and `line`', 'format 2')
  R.eq(diagram.validate(d, { old_links = true }).nodes[1].stage, 2, 'legacy')
end)

R.test('review.parse: what could say more is a warning, and it still reads', function()
  local data = sketch()
  local t = data.threads[1]
  t.title, t.risk_why = nil, nil
  t.messages[1].tours[1].steps[1].text = nil
  local r, p = review.parse(data, 'warned')
  R.ok(r, 'read')
  R.eq(p.warnings, {
    'thread 1: a medium risk with no `risk_why`',
    'thread 1, message 1, tour 1, step 1: no `text`',
    'thread 1: no `title`',
  }, 'warnings')
end)

R.test("review.read: the same table until its file changes, then the agent's afresh", function()
  H.reset()
  H.repo { ['a.lua'] = { 'local M = {}', '', 'return M' } }
  agent_writes('tours', sketch())
  local r = assert(review.read 'tours')
  R.eq(review.read 'tours', r, 'held')
  r.threads[1].status = 'fixed'
  review.save(r)
  R.eq(review.read 'tours', r, 'still, after our own write')
  local data = sketch()
  data.title = 'Renamed'
  agent_writes('tours', data)
  vim.uv.fs_utime(file.dir() .. '/tours.json', os.time() + 5, os.time() + 5)
  local again = assert(review.read 'tours')
  R.ok(again ~= r, 'read afresh')
  R.eq(again.title, 'Renamed', 'as the agent wrote it')
end)

R.test('review.save: what was read is written back as format 2, without its id', function()
  H.reset()
  H.repo { ['a.lua'] = { 'x' } }
  agent_writes('small', { format = 2, title = 'Small', threads = { { id = 3, messages = { { from = 'you', text = 'Why?' } } } } })
  review.save(assert(review.read 'small'))
  R.eq(vim.fn.readfile(file.dir() .. '/small.json'), {
    '{',
    '  "format": 2,',
    '  "title": "Small",',
    '  "status": "open",',
    '  "rounds": [],',
    '  "threads": [',
    '    {',
    '      "id": 3,',
    '      "status": "open",',
    '      "messages": [',
    '        {',
    '          "from": "you",',
    '          "text": "Why?"',
    '        }',
    '      ]',
    '    }',
    '  ]',
    '}',
  }, 'the file')
end)

R.test('review.list: the newest message first, and those that cannot be read apart', function()
  H.reset()
  H.repo { ['a.lua'] = { 'x' } }
  local function one(title, at)
    return { format = 2, title = title, threads = { { id = 1, messages = { { from = 'you', text = 'q', at = at } } } } }
  end
  agent_writes('old', one('Old', '2026-10-01T10:00:00'))
  agent_writes('new', one('New', '2026-10-12T10:00:00'))
  agent_writes('broken', { format = 2, threads = {} })
  local reviews, broken = review.list()
  R.eq(
    vim.tbl_map(function(r)
      return r.id
    end, reviews),
    { 'new', 'old' },
    'newest first'
  )
  R.eq(broken, { broken = { 'the review: no `title`' } }, 'and why one is not read')
end)

R.test('review.create: a review needs a title, and its id comes from it', function()
  H.reset()
  H.repo { ['a.lua'] = { 'x' } }
  R.ok(not pcall(review.create, '  '), 'no title, no review')
  local r = review.create 'How auth works'
  R.eq(r.id, 'how-auth-works', 'its id')
  R.eq(review.read 'how-auth-works', r, 'on disk, and held')
  review.remove(r)
  R.eq(file.ids(), {}, 'and gone again')
end)
