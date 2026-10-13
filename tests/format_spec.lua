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
                  { title = 'The map', text = 'It ignores `furthest`.', chunk = { file = 'a.lua', line = 3, text = 'return M' } },
                  { title = 'On no line', text = 'A page.' },
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
