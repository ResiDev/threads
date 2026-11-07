-- thread.go: surfaces open each other by name, and a part of a drawing
-- opens where it belongs.

local R = require 'tests.runner'
local H = require 'tests.helpers'

-- Its own go, so the surfaces registered here are gone after it.
local real = package.loaded['thread.go']
package.loaded['thread.go'] = nil
local go = require 'thread.go'
package.loaded['thread.go'] = real
local diagram = require 'thread.prose.diagram'
local topic = require 'thread.model.topic'
local sheet = require 'thread.ui.sheet'

--- Surfaces that only record what they were asked: `screen` opens the
--- screen's names, `code` the code, `walk` a walk, `compose` a float.
---@return { name: string, target: thread.Target }[] opened, string[] closed
local function surfaces()
  local opened, closed = {}, {}
  local function thread(n)
    return function(target)
      opened[#opened + 1] = { name = n, target = target }
    end
  end
  local names = {
    screen = { 'home', 'topic', 'thread', 'contract', 'focus', 'page', 'briefing' },
    code = { 'code' },
    walk = { 'walk' },
    compose = { 'compose' },
  }
  for surface, list in pairs(names) do
    local open = {}
    for _, n in ipairs(list) do
      open[n] = thread(n)
    end
    go.register(surface, {
      open = open,
      close = function()
        closed[#closed + 1] = surface
      end,
    })
  end
  return opened, closed
end

--- H.world's topic, and another beside it with a thread of its own.
---@return thread.Topic
local function world()
  H.reset()
  H.world()
  H.topic(
    'other',
    H.draft {
      threads = { { id = 7, kind = 'question', status = 'open', title = 'Elsewhere', messages = { { from = 'agent', prose = { text = 'x' } } } } },
    }
  )
  return assert(topic.read 'screens')
end

---@param kind thread.PartKind
---@param fields table|nil
---@return thread.Part
local function part(kind, fields)
  return vim.tbl_extend('force', { kind = kind, first = 0, last = 0 }, fields or {})
end

---@param opened { name: string, target: thread.Target }[]
---@return string[]
local function names(opened)
  return vim.tbl_map(function(o)
    return o.name
  end, opened)
end

R.test('go.open: the surface that registered the name opens it; the one asking makes way, not for a float over it', function()
  local opened, closed = surfaces()
  go.open('code', { chunk = { id = 'x', file = 'a.lua', line = 1, from = '', rev = 'now' } }, 'screen')
  R.eq({ opened[1].name, closed }, { 'code', { 'screen' } }, 'the screen made way for the code')
  go.open('thread', {}, 'screen')
  R.eq(#closed, 1, 'the screen opening its own: nothing closed')
  go.open('compose', {}, 'screen')
  R.eq(#closed, 1, 'compose opens over the screen')
end)

R.test('go.follow: #step: walks to the step in its tour, #thread: and #contract: open their pages', function()
  local opened = surfaces()
  local r = world()
  R.eq(go.follow(r, { kind = 'step', id = 4 }), true, 'followed')
  local t = opened[1].target
  R.eq({ opened[1].name, t.topic.id, t.tour.title, t.step.id }, { 'walk', 'screens', 'Writing', 4 }, 'walked to step 4, in Writing')
  go.follow(r, { kind = 'thread', id = 2 })
  R.eq({ opened[2].name, opened[2].target.thread.id }, { 'thread', 2 }, 'thread 2')
  go.follow(r, { kind = 'contract', id = 1 })
  R.eq({ opened[3].name, opened[3].target.contract.name }, { 'contract', 'the value of a' }, 'contract 1')
end)

R.test("go.follow: another topic's thread opens there; one to nothing says why and opens nothing", function()
  local opened = surfaces()
  local r = world()
  R.eq(go.press(r, part('link', { link = { topic = 'other', kind = 'thread', id = 7 } }), 0, 0), true, 'followed')
  R.eq({ opened[1].name, opened[1].target.topic.id, opened[1].target.thread.title }, { 'thread', 'other', 'Elsewhere' }, 'other#thread:7')
  local ok, why = go.follow(r, { kind = 'thread', id = 9 })
  R.eq({ ok, why }, { false, '`#thread:9` goes to no thread; if it is no link, put it in backticks' }, 'no thread 9')
  ok, why = go.follow(r, { topic = 'nowhere', kind = 'step', id = 1 })
  R.eq({ ok, why }, { false, '`nowhere#step:1` goes to no topic nowhere' }, 'no such topic')
  R.eq(#opened, 1, 'nothing more opened')
end)

R.test('go.press: a seam link opens seam on its target in the repository, handing it the buffer pressed in; without seam, says so and opens nothing', function()
  local opened = surfaces()
  local r = world()
  local seam_link = part('link', { link = { kind = 'seam', target = 'src/store.ts:save@Map' } })
  package.loaded['seam'] = nil
  local ok, why = go.press(r, seam_link, 0, 0)
  R.eq({ ok, why }, { false, 'seam.nvim is not installed, so seam links go nowhere' }, 'no seam')
  local shown = {}
  package.loaded['seam'] = {
    show = function(target, o)
      shown[#shown + 1] = { target, o }
    end,
  }
  local page = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(page)
  ok = go.press(r, seam_link, 0, 0)
  package.loaded['seam'] = nil
  R.eq(
    { ok, shown },
    { true, { { 'src/store.ts:save@Map', { root = require('thread.base.repo').root(), from = page } } } },
    'seam shows the target, in the repository, the buffer pressed in as the one you came from'
  )
  R.eq(#opened, 0, 'no surface of thread opened')
end)

R.test('go.press: a chunk, a line and a change go to the code; one whose lines went says so', function()
  local opened = surfaces()
  local r = world()
  local s = assert(topic.step(r, 1))
  go.press(r, part('chunk', { step = s, chunk = topic.chunk(r, 'get') }), 0, 0)
  local t = opened[1].target
  R.eq({ opened[1].name, t.chunk.id, t.step.id, t.topic.id }, { 'code', 'get', 1, 'screens' }, 'a chunk, with the step it is in')
  go.press(r, part('line', { chunk = { id = '', file = 'store.lua', line = 5, from = '  return store[key]', rev = 'now' } }), 0, 0)
  R.eq({ opened[2].name, opened[2].target.chunk.line }, { 'code', 5 }, 'a line')
  go.press(r, part('change', { chunk = topic.chunk(r, 'main-set') }), 0, 0)
  R.eq({ opened[3].name, opened[3].target.chunk.id }, { 'code', 'main-set' }, 'a change')
  local ok, why = go.press(r, part('chunk', { chunk = topic.chunk(r, 'gone') }), 0, 0)
  R.eq({ ok, why, #opened }, { false, 'store.lua no longer has those lines', 3 }, 'gone: why, nothing opened')
end)

R.test('go.press: an excerpt at its chunk', function()
  local opened = surfaces()
  local r = world()
  go.press(r, part('excerpt', { excerpt = { id = 'cache', chunk = topic.chunk(r, 'cache') } }), 0, 0)
  R.eq({ opened[1].name, opened[1].target.chunk.id }, { 'code', 'cache' }, 'the excerpt')
  R.eq(go.press(r, part('excerpt', { excerpt = { id = 'nope' } }), 0, 0), false, 'an excerpt of no chunk goes nowhere')
end)

R.test("go.press: a diagram's box goes to its chunk's code; off a box, nowhere", function()
  local opened = surfaces()
  local r = world()
  local d = assert(require('thread.model.diagram').validate(assert(r.introduction).diagrams.shape, function()
    return 'main.lua'
  end))
  local P = sheet.new()
  local drawn = diagram.draw(P, d, 60, 2)
  local row, col
  for i, l in ipairs(P.lines) do
    local at = l:find('M.set', 1, true)
    if at then
      row, col = i - 1, at - 1
    end
  end
  assert(row, table.concat(P.lines, '\n'))
  R.eq(go.press(r, part('diagram', { first = drawn.first, last = drawn.last, diagram = drawn }), row, col), true, 'on M.set')
  R.eq({ opened[1].name, opened[1].target.chunk.id }, { 'code', 'set' }, "its box's chunk")
  R.eq(go.press(r, part('diagram', { first = drawn.first, last = drawn.last, diagram = drawn }), drawn.first, 0), false, 'off a box')
end)

R.test('go.press: a name in backticks goes to where the code defines it, near its step; one found nowhere says so', function()
  local opened = surfaces()
  local r = world()
  require('thread.prose.name').reset()
  go.press(r, part('name', { s = 0, e = 5, name = 'M.set', step = topic.step(r, 4) }), 0, 0)
  local c = opened[1] and opened[1].target.chunk
  R.eq({ opened[1] and opened[1].name, c and c.file, c and c.line, c and c.from }, { 'code', 'store.lua', 8, 'function M.set(store, key, value)' }, 'M.set')
  local ok, why = go.press(r, part('name', { s = 0, e = 5, name = 'nowhere_at_all' }), 0, 0)
  R.eq({ ok, why }, { false, '`nowhere_at_all` names nothing found in the code' }, 'not found')
end)

R.test('go.press: a contract opens its page; a step and a tour walk; a thread and a topic open on the screen; a message goes nowhere', function()
  local opened = surfaces()
  local r = world()
  local x = r.tours[2]
  go.press(r, part('contract', { contract = r.contracts[1] }), 0, 0)
  go.press(r, part('step', { tour = x, step = x.steps[2] }), 0, 0)
  go.press(r, part('tour', { tour = x }), 0, 0)
  go.press(r, part('thread', { thread = topic.thread(r, 2) }), 0, 0)
  go.press(r, part('topic', { topic = r }), 0, 0)
  R.eq(names(opened), { 'contract', 'walk', 'walk', 'thread', 'topic' }, 'where each went')
  R.eq({ opened[2].target.step.id, opened[3].target.step, opened[3].target.tour.title }, { 5, nil, 'Writing' }, 'the step; the tour from its briefing')
  R.eq(opened[4].target.thread.id, 2, 'thread 2')
  R.eq(go.press(r, part('message', { message = 1 }), 0, 0), false, 'a message goes nowhere')
end)

R.test('go.ask: what a surface answers, nil when none does', function()
  R.eq(go.ask 'nobody-answers', nil, 'none')
  go.answer('walking', function(x)
    return 'on ' .. x
  end)
  R.eq(go.ask('walking', 3), 'on 3', 'answered')
end)
