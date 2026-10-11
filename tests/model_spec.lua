-- Tours, statuses, the text helpers and diagrams, without a window.

local R = require 'tests.runner'
local test, eq = R.test, R.eq

local store = require 'thread.store'
local tour = require 'thread.tour'
local render = require 'thread.render'

local function agent(text, extra)
  return vim.tbl_extend('force', { from = 'agent', text = text }, extra or {})
end

-- 1 your question, answered with a tour of two stages and three steps; 5 a
-- reply in its second step, whose answer leads to a tour of its own; 9 a
-- standalone tour.
local function sample()
  return {
    id = 'x',
    data = {
      threads = {
        { id = 1, file = 'a.lua', line = 1, text = 'x', messages = { { from = 'you', round = 1, text = 'how?' }, agent('overview', { walk = {
          { stage = 'Stage one', point = 'the point', body = 'why' },
          { file = 'a.lua', line = 2, text = 'y', title = 'step a', body = 'a' },
          { file = 'b.lua', line = 3, text = 'z', body = 'Step b says so. More.' },
          { stage = 'Stage two' },
          { file = 'c.lua', line = 1, text = 'w', body = 'c' },
        } }) } },
        { id = 5, file = 'b.lua', line = 3, text = 'z', on = { thread = 1, step = 3 }, messages = { { from = 'you', round = 1, text = 'why?' }, agent('see', { walk = { { file = 'b.lua', line = 9, text = 'v', body = 'deeper' } } }) } },
        { id = 9, title = 'Standalone', messages = { agent('tour', { walk = { { file = 'a.lua', line = 5, text = 'u', body = 'only step' } } }) } },
      },
    },
  }
end

test('status: info until you talk', function()
  local b = sample()
  eq(store.status(store.find(b, 9)), 'info', 'agent-only tour')
  eq(store.status(store.find(b, 5)), 'answered', 'a reply in a stop')
  eq(store.status(store.find(b, 1)), 'answered', 'your question')
  eq(store.status { messages = { { from = 'you', text = 'q' } } }, 'waiting', 'saved is with the agent')
  eq(store.status { messages = { { from = 'you', text = 'q', round = 1 } } }, 'waiting', 'sent')
end)

test('tour: outline numbers stages and steps', function()
  local list = tour.of(store.find(sample(), 1))
  local items, stages, steps = tour.outline(list)
  eq({ stages, steps }, { 2, 3 }, 'counts')
  eq({ items[3].stage, items[3].step }, { 1, 2 }, 'step b is step 2, in stage 1')
  eq(tour.describe(list), '2 stages · 3 steps', 'size')
  eq(tour.position(list, 4), 'stage 2/2', 'a stage')
  eq(tour.position(list, 5), 'step 3/3', 'a step')
  eq(tour.title(list[3]), 'Step b says so.', 'title from the first sentence')
  eq(tour.body(list[1]), '**the point**\n\nwhy', 'a stage\'s point first')
end)

test('tour: every thread with a walk is a tour', function()
  eq(vim.tbl_map(function(c)
    return c.id
  end, tour.tours(sample())), { 1, 5, 9 }, 'tours')
end)

test('tour: a reply belongs to its stop', function()
  local b = sample()
  eq(tour.thread_at(b, 1, 3).id, 5, 'the thread in stop 3')
  eq(tour.thread_at(b, 1, 2), nil, 'no one replied in stop 2')
  local owner, stop, n = tour.owner(b, store.find(b, 5))
  eq({ owner.id, stop.text, n }, { 1, 'z', 3 }, 'owner and stop')
  eq(tour.talks(b, 1), 1, 'one conversation')
end)

test('tour: a stop is drawn as a thread', function()
  local b = sample()
  local d = tour.display(b, store.find(b, 1), 3)
  eq(d.real.id, 5, 'the reply thread behind it')
  eq(#d.messages, 3, 'the stop\'s words, then the conversation')
  eq(d.messages[1].text, 'Step b says so. More.', 'the stop first')
  eq(store.status(d), 'answered', 'status from the conversation')
  local v = tour.display(b, store.find(b, 1), 2)
  eq({ v.virtual, v.id, store.status(v) }, { true, 's1.2', 'info' }, 'a stand-in until you reply')
  eq(#tour.cards(b), 5, 'every step of every tour is a card')
end)

test('title falls back to the first message', function()
  eq(store.title { messages = { { from = 'you', text = '  first `line`\nsecond' } } }, 'first line', 'title')
  eq(store.title { title = 'Named', messages = {} }, 'Named', 'given title')
end)

test('verdict badge', function()
  local v = render.verdict_of { messages = { agent('x', { verdict = 'risk', severity = 'low' }) } }
  eq(v.text, 'RISK · low', 'text')
  eq(v.hl, 'ThreadVerdictWarn', 'colour')
end)

test('diagram: a node anchored by symbol is refused', function()
  local d, err = require('thread.diagram').validate { kind = 'flow', nodes = { { id = 'a', label = 'x', file = 'a.lua', symbol = 'M.get' } }, edges = {} }
  eq(d, nil, 'refused')
  eq(type(err) == 'string' and err:find('symbol', 1, true) ~= nil, true, 'the message names the field: ' .. tostring(err))
end)
