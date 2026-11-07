-- thread.model: what is worked out from a topic and never written: what
-- touches what, a contract's blast radius, its threads' kinds, every piece
-- of prose, the chunks it is about; and diagrams, checked.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local contract = require 'thread.model.contract'
local diagram = require 'thread.model.diagram'
local thread = require 'thread.model.thread'
local model_prose = require 'thread.model.prose'
local topic = require 'thread.model.topic'
local touch = require 'thread.model.touch'

---@param id string
---@param line integer
---@param from string
---@param to string|nil
---@return table
local function chunk(id, line, from, to)
  return { id = id, file = 'store.lua', line = line, from = from, to = to, rev = 'now' }
end

---@param id integer
---@param title string
---@param at string|nil  its chunk
---@return table
local function step(id, title, at)
  return { id = id, title = title, text = { text = title }, chunk = at, messages = {} }
end

---@param id integer
---@param at string|nil
---@return table
local function question(id, at)
  return { id = id, kind = 'question', status = 'open', title = 'q' .. id, chunk = at, messages = { { from = 'agent', prose = { text = 'q' } } } }
end

--- A topic of H.fixture: contract 1 is M.get, its body a dependent;
--- contract 2 is M.set, in no one's way. Tour 1 walks get, a line inside
--- it and a page; tour 2 walks main.lua.
---@return thread.Topic
local function sample()
  local r, p = topic.parse({
    title = 'Touches',
    contracts = {
      {
        id = 1,
        name = 'M.get',
        kind = 'function',
        source = { change = 'changed', before = { lang = 'lua', text = 'function M.get(store)' }, after = 'get' },
        prose = { text = 'p' },
        dependents = { { chunk = 'body', impact = 'missed', text = 'It reads a key.' }, { chunk = 'get', impact = 'none' } },
      },
      {
        id = 2,
        name = 'M.set',
        kind = 'function',
        source = { change = 'added', after = 'set' },
        prose = { text = 'p' },
        dependents = { { chunk = 'caller', impact = 'adapted', text = 'Calls it.' } },
      },
    },
    tours = {
      {
        id = 2,
        title = 'Reading',
        colour = 'teal',
        introduction = { text = 'i' },
        steps = { step(1, 'get', 'get'), step(2, 'the cache', 'cache'), step(3, 'a page') },
      },
      { id = 1, title = 'Calling', colour = 'sky', introduction = { text = 'i' }, steps = { step(4, 'main', 'main') } },
    },
    threads = { question(1, 'cache'), question(2, 'body'), question(3), question(4, 'set') },
    chunks = {
      chunk('get', 3, 'function M.get(store, key)', 'end'),
      chunk('cache', 4, '  local cache = {}'),
      chunk('body', 5, '  return store[key]'),
      chunk('set', 8, 'function M.set(store, key, value)', 'end'),
      { id = 'caller', file = 'main.lua', line = 2, from = 'store.set({}, "a", 1)', rev = 'now' },
      { id = 'main', file = 'main.lua', line = 1, from = 'local store = require "store"', rev = 'now' },
    },
  }, 'touches')
  return assert(r, table.concat(p.errors, '\n'))
end

R.test('touch.index: each tour, step, thread and contract its chunks and files; which contracts each touches, by id or by line', function()
  H.reset()
  H.repo(H.fixture)
  local r = sample()
  local T = touch.index(r)
  local reading, calling = r.tours[1], r.tours[2]
  local get, set = r.contracts[1], r.contracts[2]
  local function ids(list)
    return vim.tbl_map(function(x)
      return x.id
    end, list)
  end
  R.eq(ids(T.chunks[get]), { 'get', 'body' }, "a contract's: its sides', then its dependents', each once")
  R.eq(ids(T.chunks[reading]), { 'get', 'cache' }, "a tour's: its steps'")
  R.eq({ T.files[reading], T.files[calling], T.files[set], T.files[reading.steps[3]] }, {
    { ['store.lua'] = true },
    { ['main.lua'] = true },
    { ['store.lua'] = true, ['main.lua'] = true },
    {},
  }, 'files; a page none')
  R.eq(
    { T.contracts[reading.steps[1]], T.contracts[reading.steps[2]], T.contracts[reading.steps[3]] },
    { { get }, { get }, {} },
    'a step: by its chunk, or a line inside one'
  )
  R.eq(
    { T.contracts[calling], T.contracts[r.threads[3]], T.contracts[r.threads[4]] },
    { {}, {}, { set } },
    'main.lua line 1 is no dependent; a thread on no line touches none'
  )
  R.eq(
    touch.related(T, get),
    { [reading] = true, [reading.steps[1]] = true, [reading.steps[2]] = true, [r.threads[1]] = true, [r.threads[2]] = true },
    'a contract: what touches it'
  )
  R.eq(touch.related(T, reading.steps[1]), { [get] = true }, 'a step: its contracts')
  R.eq(touch.related(T, {}), nil, 'something on neither side')
end)

R.test("touch.threads_on: the threads on a step's chunk or on lines inside it; none on a page", function()
  H.reset()
  H.repo(H.fixture)
  local r = sample()
  local function ids(s)
    return vim.tbl_map(function(n)
      return n.id
    end, touch.threads_on(r, s))
  end
  R.eq({ ids(r.tours[1].steps[1]), ids(r.tours[1].steps[2]), ids(r.tours[1].steps[3]) }, { { 1, 2 }, { 1 }, {} }, 'each')
end)

R.test('contract: its sign, its chunks, its names by id, and its blast radius by impact, the furthest reached first', function()
  local r = sample()
  local get, set = r.contracts[1], r.contracts[2]
  R.eq({ contract.sign(get), contract.sign(set), contract.sign { source = { change = 'removed' } } }, { '~', '+', '−' }, 'signs')
  R.eq(contract.chunks(set), { 'set', 'caller' }, 'chunks')
  R.eq(contract.names(r), { 'M.get', 'M.set' }, 'names')
  R.eq(
    vim.tbl_map(function(g)
      return { g.impact, #g.dependents }
    end, contract.radius(get)),
    { { 'missed', 1 }, { 'none', 1 } },
    'missed first; an impact none has left out'
  )
  R.eq(contract.radius { dependents = nil }, {}, 'no dependents')
end)

R.test('prose.split: a lead, the text it opens with, up to the first heading, placement, fence or table; the rest after', function()
  local lead, rest = model_prose.split { text = 'It breaks.\nAgree?\n\n## Why\n\nBecause.', diagrams = { d = {} } }
  R.eq({ lead, rest }, {
    { text = 'It breaks.\nAgree?', diagrams = { d = {} } },
    { text = '## Why\n\nBecause.', diagrams = { d = {} } },
  }, 'up to the heading, the diagrams with each')
  R.eq({ model_prose.split { text = 'It breaks:\n\n{{chunk:a}}' } }, { { text = 'It breaks:' }, { text = '{{chunk:a}}' } }, 'up to an excerpt')
  R.eq({ model_prose.split { text = '```\nx\n```' } }, { nil, { text = '```\nx\n```' } }, 'none before a fence')
  R.eq({ model_prose.split { text = 'All lead.' } }, { { text = 'All lead.' }, nil }, 'no rest')
end)

R.test('thread: settled is a status other than open; a comment never is; its kind as a person says it', function()
  R.eq({ thread.closed { status = 'fixed' }, thread.closed { status = 'open' }, thread.closed { kind = 'comment' } }, { true, false, false }, 'closed')
  R.eq({ thread.open { status = 'open' }, thread.open { kind = 'comment' } }, { true, false }, 'open')
  R.eq({ thread.noun 'issue', thread.noun('issue', 1), thread.noun('question', 3) }, { 'issue', '1 issue', '3 questions' }, 'nouns')
end)

R.test('topic.prose: every piece of prose, where it is and whose; topic.about: the chunks it is about, each once', function()
  local r = sample()
  r.introduction = { text = 'intro' }
  table.insert(r.threads[1].messages, { from = 'you', prose = { text = 'mine' } })
  R.eq(
    vim.tbl_map(function(x)
      return x.where .. ' ' .. x.from
    end, topic.prose(r)),
    {
      'the topic, introduction agent',
      'contract 1, prose agent',
      'contract 1, dependent 1 agent',
      'contract 2, prose agent',
      'contract 2, dependent 1 agent',
      'tour 1, introduction agent',
      'step 1, text agent',
      'step 2, text agent',
      'step 3, text agent',
      'tour 2, introduction agent',
      'step 4, text agent',
      'thread 1, message 1 agent',
      'thread 1, message 2 you',
      'thread 2, message 1 agent',
      'thread 3, message 1 agent',
      'thread 4, message 1 agent',
    },
    'each'
  )
  R.eq(
    vim.tbl_map(function(c)
      return c.id
    end, topic.about(r)),
    { 'get', 'body', 'set', 'caller', 'cache', 'main' },
    "contracts', steps', threads'"
  )
end)

R.test('diagram.validate: a node is on code by a chunk of the topic, with its file beside it; an old anchor is refused', function()
  local function file(id)
    return id == 'get' and 'store.lua' or nil
  end
  local d = assert(
    diagram.validate(
      { kind = 'flow', nodes = { { id = 'a', label = 'get', chunk = 'get' }, { id = 'b', label = 'b' } }, edges = { { from = 'a', to = 'b' } } },
      file
    )
  )
  R.eq(d.nodes[1], { id = 'a', label = 'get', chunk = 'get', file = 'store.lua' }, 'its file beside it')
  R.eq(
    select(2, diagram.validate({ kind = 'flow', nodes = { { id = 'a', label = 'x', chunk = 'gone' } } }, file)),
    'nodes[1].chunk is "gone", which is not one of the topic\'s chunks',
    'a chunk there is not'
  )
  for _, field in ipairs { 'file', 'symbol', 'step' } do
    local _, err = diagram.validate({ kind = 'flow', nodes = { { id = 'a', label = 'x', [field] = 'v' } } }, file)
    R.eq(err, 'nodes[1].' .. field .. " is not a field: a node is on code by `chunk`, the id of one of the topic's chunks", field)
  end
  R.eq(select(2, diagram.validate({ kind = 'pie' }, file)), 'its `kind` must be "calls", "sequence" or "flow", got "pie"', 'a kind')
  R.eq(
    select(2, diagram.validate({ kind = 'flow', nodes = { { id = 'a', label = 'x' } }, edges = { { from = 'a', to = 'z' } } }, file)),
    'edges[1].to "z" is not a node id',
    'an edge to nothing'
  )
end)
