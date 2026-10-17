-- thread.model.review: a review file as the agent writes it, read and
-- checked once, every problem said for the agent, and written back.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local file = require 'thread.store.file'
local json = require 'thread.base.json'
local review = require 'thread.model.review'

local AT = '2026-10-11T10:00:00'

--- A review with one of everything, on H.fixture, every chunk pointed at.
---@return table
local function full()
  return {
    title = 'The store',
    introduction = {
      text = 'Reads and writes go through #contract:1.\n\n{{diagram:shape}}',
      diagrams = {
        shape = {
          kind = 'flow',
          nodes = { { id = 'get', label = 'M.get', chunk = 'get' }, { id = 'set', label = 'M.set' } },
          edges = { { from = 'get', to = 'set' } },
        },
      },
    },
    contracts = {
      {
        id = 1,
        name = 'M.set(store, key, value)',
        kind = 'function',
        source = { change = 'changed', before = { lang = 'lua', text = 'function M.set(store, key)' }, after = 'set' },
        why = 'A write takes its value.',
        prose = { text = 'It takes a value now.' },
        dependents = { { chunk = 'caller', impact = 'adapted', text = 'Passes one.' }, { chunk = 'get', impact = 'none' } },
      },
    },
    tours = {
      {
        title = 'Reading',
        colour = 'teal',
        introduction = { text = 'How a read goes.' },
        steps = {
          { id = 1, title = 'get reads the store', chunk = 'get', messages = {} },
          {
            id = 2,
            title = 'Nothing is cached',
            text = { text = 'See #note:1.' },
            messages = { { from = 'you', at = AT, prose = { text = 'Why not?' } } },
          },
        },
      },
    },
    notes = {
      {
        id = 1,
        kind = 'issue',
        issue = 'flaw',
        severity = 'low',
        status = 'open',
        title = 'The cache is thrown away',
        chunk = 'cache',
        messages = { { from = 'agent', prose = { text = 'A new table each call.' } } },
      },
      { id = 2, kind = 'comment', title = 'Nice', messages = { { from = 'you', at = AT, prose = { text = 'Nice.' } } } },
    },
    chunks = {
      { id = 'get', file = 'store.lua', line = 3, from = 'function M.get(store, key)', to = 'end', rev = 'now' },
      { id = 'set', file = 'store.lua', line = 8, from = 'function M.set(store, key, value)', to = 'end', rev = 'now' },
      { id = 'cache', file = 'store.lua', line = 4, from = '  local cache = {}', rev = 'now' },
      { id = 'caller', file = 'main.lua', line = 2, from = 'store.set({}, "a", 1)', rev = 'now' },
    },
  }
end

---@param data table
---@return table|nil review, string[] errors, string[] warnings
local function parse(data)
  local r, p = review.parse(data, 'r')
  return r, p.errors, p.warnings
end

R.test('review.parse: one of everything reads, with nothing to say, and what it leaves out filled in', function()
  local r, errors, warnings = parse(full())
  R.eq({ errors, warnings }, { {}, {} }, 'no problems')
  r = assert(r)
  R.eq(
    { r.id, r.status, r.contracts[1].messages, r.notes[2].status },
    { 'r', 'open', {}, nil },
    "open; a contract's conversation empty; a comment has no status"
  )
  R.eq(r.tours[1].steps[2].messages[1].prose.text, 'Why not?', 'a message, its prose')
end)

R.test('review.parse: anything not a request is refused, and its type said', function()
  R.eq({ parse(nil) }, { nil, { 'the review: must be a JSON object' }, {} }, 'not an object')
  R.eq(select(2, parse { title = 'T', tours = {}, chunks = { 'x' } }), { 'the chunk at place 1: must be an object' }, 'a chunk as a string')
end)

R.test('review.parse: a field from a shape before this one says where it went; an unknown one, what there is', function()
  local data = full()
  data.format, data.threads = 3, {}
  data.chunks[1].text = 'function M.get(store, key)'
  data.tours[1].bogus = 1
  data.tours[1].steps[1].kind = 'feat'
  data.tours[1].steps[2].messages[1].text = 'Why not?'
  local r, errors = parse(data)
  R.eq(r, nil, 'not read')
  R.eq(errors, {
    'the review: `format` is not a field; a review has no format number: write it as the skill says',
    "the review: `threads` is not a field; a review's `tours` walk the change, and anything else is one of its `notes`",
    'chunk get: `text` is not a field; it quotes its first line in `from`, and its last in `to`',
    'tour 1: `bogus` is not a field (it has title, colour, introduction, steps)',
    'tour 1, step 1: `kind` is not a field; a step is a claim; what kind of change it is goes in its tour or its text',
    'tour 1, step 2, message 1: `text` is not a field; what it says is its `prose`, `{ "text": "..." }`',
  }, 'each, where it is')
end)

R.test('review.parse: a chunk id nothing in the pool has, wherever it is pointed at', function()
  local data = full()
  data.introduction.diagrams.shape.nodes[1].chunk = 'w'
  data.contracts[1].source.after = 'y'
  data.contracts[1].dependents[1].chunk = 'x'
  data.tours[1].steps[1].chunk = 'nope'
  data.notes[1].chunk = 'gone'
  data.notes[1].messages[1].changes = { 'cache', 'z' }
  local r, errors = parse(data)
  R.eq(r, nil, 'not read')
  R.eq(errors, {
    'the review, introduction, diagram shape: nodes[1].chunk is "w", which is not one of the review\'s chunks',
    'contract 1, source: its `after` is "y", which is not one of the review\'s chunks',
    'contract 1, dependent 1: its `chunk` is "x", which is not one of the review\'s chunks',
    'tour 1, step 1: its `chunk` is "nope", which is not one of the review\'s chunks',
    'note 1: its `chunk` is "gone", which is not one of the review\'s chunks',
    'note 1, message 1: its `changes[2]` is "z", which is not one of the review\'s chunks',
  }, 'each')
end)

R.test('review.parse: prose places a chunk and a diagram it has, outside a fence; a diagram never placed is a warning', function()
  local data = full()
  data.introduction.text = 'No diagram here.'
  data.tours[1].steps[2].text = { text = 'See:\n\n{{chunk:nope}}\n\n  {{diagram:none}}  \n\n```\n{{chunk:quoted}}\n```' }
  local r, errors, warnings = parse(data)
  R.eq(r, nil, 'not read')
  R.eq(errors, {
    'step 2, text: line 3, `{{chunk:nope}}`: no chunk has that id',
    'step 2, text: line 5, `{{diagram:none}}`: its `diagrams` have none by that name',
  }, 'what names nothing; not what a fence quotes')
  R.eq(warnings, {
    'the review, introduction: the diagram "shape" is never placed: put `{{diagram:shape}}` alone on a line where it goes',
  }, 'the diagram left out')
  data = full()
  data.tours[1].steps[2].text = { text = 'Here:\n\n{{chunk:cache}}' }
  data.notes[1].chunk = nil
  r, errors = parse(data)
  R.eq({ r ~= nil, errors }, { true, {} }, 'a chunk placed in prose is one pointed at')
end)

R.test('review.parse: a dependent the change missed is an issue too, on its chunk', function()
  local data = full()
  data.contracts[1].dependents[1] = { chunk = 'caller', impact = 'missed', text = 'Still passes two.' }
  local r, errors, warnings = parse(data)
  R.eq({ r ~= nil, errors, warnings }, {
    true,
    {},
    { 'contract 1, dependent 1: missed, so it is an issue too: give it a note of kind `issue` on chunk caller' },
  }, 'with no issue on it, a warning')
  data = full()
  data.contracts[1].dependents[1] = { chunk = 'caller', impact = 'missed', text = 'Still passes two.' }
  data.notes[1].chunk = 'caller'
  r, errors, warnings = parse(data)
  R.eq(
    { r ~= nil, errors, warnings },
    { true, {}, { 'chunk cache: nothing points at it: a step, a note, a contract or `{{chunk:cache}}` would' } },
    'an issue on it'
  )
end)

R.test('review.parse: a contract’s why and its dependents’ text are prose, read as the rest is; why is one line, its row', function()
  local data = full()
  data.contracts[1].why = '{{chunk:nope}}'
  data.contracts[1].dependents[1].text = 'Passes one.\n\n{{chunk:gone}}'
  local r, errors = parse(data)
  R.eq({ r, errors }, {
    nil,
    {
      'contract 1, why: line 1, `{{chunk:nope}}`: no chunk has that id',
      'contract 1, dependent 1: line 3, `{{chunk:gone}}`: no chunk has that id',
    },
  }, 'each read')
  data = full()
  data.contracts[1].why = 'It takes a value.\nAnd more.'
  R.eq(select(2, parse(data)), { 'contract 1: `why` is one line, with no line breaks or tabs' }, 'why on two lines')
end)

R.test('review.parse: what is not prose or code is one line, each drawn as a row: no line breaks, no tabs', function()
  local data = full()
  data.title = 'The\nstore'
  data.contracts[1].name = 'M.set(store,\tkey)'
  data.contracts[1].kind = 'function\r'
  data.contracts[1].source.before.lang = 'lu\na'
  data.tours[1].title = 'Read\ting'
  data.tours[1].steps[1].title = 'get reads\nthe store'
  data.notes[1].title = 'The cache\27[31m'
  data.chunks[1].file = 'store\t.lua'
  local _, errors = parse(data)
  local function one_line(where, name)
    return string.format('%s: `%s` is one line, with no line breaks or tabs', where, name)
  end
  R.eq(errors, {
    one_line('the review', 'title'),
    one_line('chunk get', 'file'),
    one_line('contract 1', 'name'),
    one_line('contract 1', 'kind'),
    one_line('contract 1, source, before', 'lang'),
    one_line('tour 1', 'title'),
    one_line('tour 1, step 1', 'title'),
    one_line('note 1', 'title'),
  }, 'each')
  data = full()
  data.introduction.diagrams.shape.nodes[2].label = 'M.set\n(store)'
  R.eq(select(2, parse(data)), {}, "a flow's box may have lines")
  data = full()
  data.introduction.diagrams.shape.nodes[2].label = 'M.set\n\t(store)'
  R.eq(select(2, parse(data)), { 'the review, introduction, diagram shape: nodes[2].label: each of its lines has no tabs' }, 'but no tabs')
  data = full()
  data.introduction.diagrams.shape.edges[1].label = 'calls\tit'
  R.eq(select(2, parse(data)), { 'the review, introduction, diagram shape: edges[1].label must be a single-line string, with no tabs' }, 'an edge')
  data = full()
  data.chunks[1].from = '\tfunction M.get(store, key)'
  R.eq(select(2, parse(data)), {}, 'code is quoted as it reads, tabs and all')
end)

R.test('review.parse: a diagram’s objects are exact, as the rest is', function()
  local data = full()
  data.introduction.diagrams.shape.directon = 'right'
  local _, errors = parse(data)
  R.eq(errors, { 'the review, introduction, diagram shape: `directon` is not a field (it has kind, nodes, edges, direction)' }, 'the diagram')
  data = full()
  data.introduction.diagrams.shape.edges[1].colour = 'red'
  _, errors = parse(data)
  R.eq(errors, { 'the review, introduction, diagram shape: edges[1].colour is not a field (it has from, to, label, dashed)' }, 'an edge')
end)

R.test('review.parse: a null in a list, read from the file, is a thing in it that is not one, and the list a list', function()
  local diagrams = 'the review, introduction: `diagrams` is an object: each diagram by its name'
  for text, want in pairs {
    ['{ "title": "T", "introduction": { "text": "hi", "diagrams": [null, { "kind": "flow" }] } }'] = { diagrams },
    ['{ "title": "T", "introduction": { "text": "hi", "diagrams": [null] } }'] = { diagrams },
    ['{ "title": "T", "notes": [null] }'] = { 'the note at place 1: must be an object' },
    ['{ "title": "T", "notes": [{ "id": 1, "kind": "comment", "title": "c", "messages": [null] }] }'] = {
      'note 1, message 1: must be an object',
    },
  } do
    local ok, r, errors = pcall(parse, json.decode(text))
    R.ok(ok, text .. ': ' .. tostring(r))
    R.eq({ r, errors }, { nil, want }, text)
  end
end)

R.test('review.parse: ids are each their own, steps across every tour', function()
  local data = full()
  data.chunks[5] = vim.deepcopy(data.chunks[1])
  data.contracts[2] = vim.deepcopy(data.contracts[1])
  data.tours[2] = vim.deepcopy(data.tours[1])
  data.tours[2].colour = 'orange'
  table.remove(data.tours[2].steps)
  data.notes[3] = vim.deepcopy(data.notes[1])
  local r, errors = parse(data)
  R.eq(r, nil, 'not read')
  R.eq(errors, {
    'chunk get: its id is used twice: each chunk has its own',
    'contract 1: its id is used twice: each contract has its own',
    "tour 2, step 1: its id 1 is tour 1, step 1's too: each step has its own",
    'note 1: its id is used twice: each note has its own',
  }, 'each')
end)

R.test("review.parse: a note's status is one of its kind's; a comment has none; only an issue has `issue` and `severity`", function()
  local data = full()
  local function note(id, kind, extra)
    local n = { id = id, kind = kind, title = 'n' .. id, messages = { { from = 'agent', prose = { text = 'x' } } } }
    return vim.tbl_extend('force', n, extra or {})
  end
  data.notes = {
    note(1, 'issue', { issue = 'bug', severity = 'high', status = 'agreed', chunk = 'cache' }),
    note(2, 'comment', { status = 'open' }),
    note(3, 'decision', { status = 'agreed', issue = 'bug' }),
    note(4, 'issue', { status = 'open' }),
    note(5, 'question'),
    note(6, 'fix', { status = 'checked', messages = {} }),
    note(7, 'idea', { status = 'open' }),
  }
  local r, errors = parse(data)
  R.eq(r, nil, 'not read')
  R.eq(errors, {
    'note 1: `status` is "open", "fixed", "won\'t fix", "not a problem", not "agreed"',
    'note 2: a comment asks for nothing, so it has no `status`',
    'note 3: only an issue has `issue`; this is a decision',
    'note 4: no `issue`',
    'note 4: no `severity`',
    'note 5: no `status`',
    'note 6: no `messages`: the first says what it is',
    'note 7: `kind` is "issue", "decision", "question", "suggestion", "fix", "comment", not "idea"',
  }, 'each')
end)

R.test("review.parse: a contract's source has the sides its change does; a dependent the change reached says what it cost", function()
  local data = full()
  local function contract(id, source, dependents)
    return { id = id, name = 'c' .. id, kind = 'function', source = source, prose = { text = 'p' }, dependents = dependents }
  end
  data.contracts = {
    contract(1, { change = 'changed', before = { lang = 'lua', text = 'x' }, after = 'set' }, {
      { chunk = 'caller', impact = 'missed' },
      { chunk = 'get', impact = 'none' },
      { chunk = 'get', impact = 'reworked', text = '  ' },
      { impact = 'gone' },
    }),
    contract(2, { change = 'added', before = 'set' }),
    contract(3, { change = 'removed', before = { text = 'x' } }),
    contract(4, nil),
    contract(5, { change = 'moved' }),
  }
  local r, errors = parse(data)
  R.eq(r, nil, 'not read')
  R.eq(errors, {
    'contract 1, dependent 1: missed, so it says in `text` what it had to do and what it cost',
    'contract 1, dependent 3: reworked, so it says in `text` what it had to do and what it cost',
    'contract 1, dependent 4: no `chunk`: the line that uses the contract',
    'contract 1, dependent 4: `impact` is "missed", "reworked", "adapted", "none", not "gone"',
    'contract 2, source: added, so it has no `before`',
    'contract 2, source: added, so it has `after`',
    'contract 3, source, before: no `lang`',
    'contract 4: no `source`: the contract as it was and as it is',
    'contract 5, source: `change` is "added", "changed", "removed", not "moved"',
  }, 'each')
end)

R.test("review.parse: prose is an object; a message is yours or the agent's, at a time, and only the agent's has changes", function()
  local data = full()
  data.introduction = 'Two things.'
  local messages = data.tours[1].steps[2].messages
  messages[1].changes = { 'get' }
  messages[2] = { from = 'them', prose = { text = 'x' } }
  messages[3] = { from = 'agent', at = 'yesterday', prose = { text = 'x' } }
  messages[4] = { from = 'agent' }
  local r, errors = parse(data)
  R.eq(r, nil, 'not read')
  R.eq(errors, {
    'the review, introduction: prose is an object, `{ "text": "..." }`, with its `diagrams` beside the text',
    "tour 1, step 2, message 1: only the agent's messages have `changes`",
    'tour 1, step 2, message 2: `from` is "you", "agent", not "them"',
    'tour 1, step 2, message 3: `at` is "yesterday": a time, `2026-10-13T10:00:00`',
    'tour 1, step 2, message 4: no `prose`',
  }, 'each')
end)

R.test('review.parse: a diff is `of` the working tree or from a `base`; a tour has its colour, its briefing and its steps', function()
  local data = full()
  data.diff = { of = 'uncommitted', base = 'HEAD' }
  data.tours[2] = { title = 'Writing', colour = 'red', steps = {} }
  local _, errors = parse(data)
  R.eq(errors, {
    'the review, diff: `of` or a `base`, not both',
    'tour 2: `colour` is "orange", "yellow", "lime", "teal", "sky", "blue", "violet", "pink", "rose", "amber", "green", "mint", "cyan", "indigo", "purple", "magenta", not "red"',
    'tour 2: no `introduction`',
    'tour 2: no `steps`',
  }, 'each')
  data = full()
  data.diff = { head = 'main' }
  R.eq(select(2, parse(data)), {
    'the review, diff: needs `of` (unstaged, staged, uncommitted) or a `base`; a review of the code as it stands has no `diff`',
  }, 'a head alone')
end)

R.test('review.parse: what could say more is a warning, and it still reads', function()
  local data = full()
  data.tours[2] = {
    title = 'Writing',
    colour = 'teal',
    introduction = { text = 'Writes.' },
    steps = { { id = 3, title = 'A page with nothing on it', messages = {} } },
  }
  data.chunks[5] = { id = 'spare', file = 'store.lua', line = 12, from = 'return M', rev = 'now' }
  local r, errors, warnings = parse(data)
  R.eq({ r ~= nil, errors }, { true, {} }, 'read')
  R.eq(warnings, {
    'tour 2, step 1: a page with no `text`: it says nothing but its title',
    'chunk spare: nothing points at it: a step, a note, a contract or `{{chunk:spare}}` would',
    "tour 2: its colour, teal, is tour 1's too: each tour has its own while there are 16 or fewer",
  }, 'warnings')
end)

R.test("review.read: the same table until its file changes, then the agent's afresh; why, when it cannot be read", function()
  H.reset()
  H.repo(H.fixture)
  local r = assert(H.agent_writes('store', full()))
  R.eq(review.read 'store', r, 'held')
  r.status = 'closed'
  review.save(r)
  R.eq(review.read 'store', r, 'still, after our own write')
  local data = full()
  data.title = 'Renamed'
  local again = assert(H.agent_writes('store', data))
  R.ok(again ~= r, 'read afresh')
  R.eq(again.title, 'Renamed', 'as the agent wrote it')
  data.title = nil
  R.eq({ H.agent_writes('store', data) }, { nil, { 'the review: no `title`' } }, 'broken')
  vim.fn.writefile({ '{ "title": ' }, file.dir() .. '/store.json')
  vim.uv.fs_utime(file.dir() .. '/store.json', os.time() + 10, os.time() + 10)
  local none, errors = review.read 'store'
  R.ok(none == nil and errors[1]:find('store.json is not valid JSON', 1, true), 'not JSON: ' .. vim.inspect(errors))
  R.eq({ review.read 'nothing' }, { nil, { 'no review nothing' } }, 'no file')
end)

R.test('review.save: what was read is written back in a fixed order, without its id, what the agent left out still out', function()
  H.reset()
  H.repo(H.fixture)
  local note = { id = 1, kind = 'question', status = 'open', title = 'Why?', messages = { { from = 'you', at = AT, prose = { text = 'Why?' } } } }
  review.save(assert(H.agent_writes('small', { notes = { note }, tours = {}, title = 'Small' })))
  R.eq(vim.fn.readfile(file.dir() .. '/small.json'), {
    '{',
    '  "title": "Small",',
    '  "status": "open",',
    '  "tours": [],',
    '  "notes": [',
    '    {',
    '      "id": 1,',
    '      "title": "Why?",',
    '      "kind": "question",',
    '      "status": "open",',
    '      "messages": [',
    '        {',
    '          "from": "you",',
    '          "at": "2026-10-11T10:00:00",',
    '          "prose": {',
    '            "text": "Why?"',
    '          }',
    '        }',
    '      ]',
    '    }',
    '  ],',
    '  "chunks": []',
    '}',
  }, 'the file')
end)

R.test('review.save: one of everything, written back, reads as it did', function()
  H.reset()
  H.repo(H.fixture)
  local r = assert(H.agent_writes('store', full()))
  review.save(r)
  local again, p = review.parse(assert(file.read 'store'), 'store')
  R.eq({ p.errors, p.warnings }, { {}, {} }, 'nothing to say')
  again = assert(again)
  R.eq(again.contracts[1].messages, {}, 'a contract with no conversation')
  R.eq(again.introduction, full().introduction, 'prose, its diagrams as written')
  R.eq(again.chunks, full().chunks, 'its chunks')
end)

R.test('review.list: the newest message first, and those that cannot be read apart', function()
  H.reset()
  H.repo(H.fixture)
  local function one(title, at)
    local n = { id = 1, kind = 'question', status = 'open', title = 'q', messages = { { from = 'you', at = at, prose = { text = 'q' } } } }
    return { title = title, tours = {}, notes = { n } }
  end
  H.agent_writes('old', one('Old', '2026-10-01T10:00:00'))
  H.agent_writes('new', one('New', '2026-10-12T10:00:00'))
  H.agent_writes('broken', { tours = {} })
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
  H.repo(H.fixture)
  R.ok(not pcall(review.create, '  '), 'no title, no review')
  local r = review.create 'How auth works'
  R.eq({ r.id, r.status, r.diff }, { 'how-auth-works', 'open', nil }, 'its id; open, about no diff')
  R.eq(review.read 'how-auth-works', r, 'on disk, and held')
  R.eq({ review.parse(assert(file.read 'how-auth-works'), 'x') ~= nil }, { true }, 'what it wrote reads')
  R.eq(review.create(' Pasted\tin\n').title, 'Pasted in', 'its title one line, as a title is')
  R.ok(review.read 'pasted-in', 'and reads')
  review.remove(assert(review.read 'pasted-in'))
  review.remove(r)
  R.eq({ file.ids(), (review.read 'how-auth-works') }, { {}, nil }, 'and gone again')
end)
