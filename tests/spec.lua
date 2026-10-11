-- Unit tests: the tree, statuses, and the text helpers. Run with `make test`.

local failures, count = 0, 0
local function test(name, fn)
  count = count + 1
  local ok, err = pcall(fn)
  if not ok then
    failures = failures + 1
    io.stderr:write('FAIL ' .. name .. ': ' .. tostring(err) .. '\n')
  end
end
local function eq(actual, expected, what)
  if not vim.deep_equal(actual, expected) then
    error(string.format('%s: expected %s, got %s', what or 'value', vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

local store = require 'thread.store'
local tree = require 'thread.tree'
local render = require 'thread.render'

local function agent(text, extra)
  return vim.tbl_extend('force', { from = 'agent', text = text }, extra or {})
end

-- 1 your question, answered with two stages; stage 3 leads to steps 4 and 5;
-- stage 6 to step 7; step 5 has a reply that led to 8; 9 a standalone tour.
local function sample()
  return {
    id = 'x',
    data = {
      threads = {
        { id = 1, file = 'a.lua', line = 1, text = 'x', messages = { { from = 'you', round = 1, text = 'how?' }, agent('overview', { children = { 3, 6 } }) } },
        { id = 3, title = 'Stage one', messages = { agent('point', { children = { 4, 5 } }) } },
        { id = 4, file = 'a.lua', line = 2, text = 'y', messages = { agent 'step a' } },
        { id = 5, file = 'b.lua', line = 3, text = 'z', messages = { agent 'step b', { from = 'you', text = 'why?' }, agent('see', { children = { 8 } }) } },
        { id = 6, title = 'Stage two', messages = { agent('point', { children = { 7 } }) } },
        { id = 7, file = 'c.lua', line = 1, text = 'w', messages = { agent 'step c' } },
        { id = 8, file = 'b.lua', line = 9, text = 'v', messages = { agent 'deeper' } },
        { id = 9, title = 'Standalone', messages = { agent('tour', { children = { 10 } }) } },
        { id = 10, file = 'a.lua', line = 5, text = 'u', messages = { agent 'only step' } },
      },
    },
  }
end

test('status: info until you talk', function()
  local b = sample()
  eq(store.status(store.find(b, 4)), 'info', 'agent-only step')
  eq(store.status(store.find(b, 5)), 'answered', 'step you replied in')
  eq(store.status(store.find(b, 1)), 'answered', 'your question')
  eq(store.status { messages = { { from = 'you', text = 'q' } } }, 'draft', 'unsent')
  eq(store.status { messages = { { from = 'you', text = 'q', round = 1 } } }, 'waiting', 'sent')
end)

test('tree: parents and children', function()
  local b = sample()
  eq(tree.parent(b, 4).id, 3, 'step under its stage')
  eq(tree.parent(b, 3).id, 1, 'stage under the question')
  eq(tree.parent(b, 1), nil, 'the question is a root')
  eq(vim.tbl_map(function(c)
    return c.id
  end, tree.children(b, store.find(b, 1))), { 3, 6 }, 'children in order')
end)

test('tree: head climbs through stages', function()
  local b = sample()
  eq(tree.head(b, 4).id, 1, 'a step under a stage walks under the question')
  eq(tree.head(b, 3).id, 1, 'a stage too')
  eq(tree.head(b, 8).id, 5, 'a reply that led somewhere is its own walk')
  eq(tree.head(b, 10).id, 9, 'a standalone tour')
end)

test('tree: the walk goes through stages, not steps', function()
  local b = sample()
  local ids = vim.tbl_map(function(item)
    return item.c.id
  end, tree.walk(b, store.find(b, 1)))
  eq(ids, { 3, 4, 5, 6, 7 }, 'walk order')
  local head, list, index = tree.position(b, 5)
  eq({ head.id, index }, { 1, 3 }, 'position')
  eq({ tree.step_of(list, index) }, { 2, 3 }, 'step 2 of 3')
  eq(tree.describe(list), '2 stages · 3 steps', 'size')
end)

test('tree: tours are the topmost threads that lead somewhere', function()
  local b = sample()
  local ids = vim.tbl_map(function(c)
    return c.id
  end, tree.tours(b))
  table.sort(ids)
  eq(ids, { 1, 5, 9 }, 'question, step that led on, standalone')
end)

test('tree: one parent each, first claim wins', function()
  local b = sample()
  b.data.threads[#b.data.threads + 1] = { id = 11, messages = { agent('steal', { children = { 4 } }) } }
  eq(tree.parent(b, 4).id, 3, 'kept by its first parent')
  eq(#tree.children(b, store.find(b, 11)), 0, 'the second claim leads nowhere')
end)

test('tree: path is the breadcrumb', function()
  local b = sample()
  eq(vim.tbl_map(function(c)
    return c.id
  end, tree.path(b, 4)), { 1, 3, 4 }, 'path')
end)

test('title falls back to the first message', function()
  eq(store.title { messages = { { from = 'you', text = '  first `line`\nsecond' } } }, 'first line', 'title')
  eq(store.title { title = 'Named', messages = {} }, 'Named', 'given title')
end)

test('wrap: bold runs and excerpts', function()
  local rows = render.wrap('**A point that runs long enough to wrap** then plain', 20)
  eq(rows[1].bold, false, 'first row starts outside')
  eq(rows[2].bold, true, 'the run carries over')
  local segs = render.segments(vim.deepcopy(rows[1]))
  eq(segs[1][2], 'ThreadPoint', 'bold chunk')
  eq(segs[1][1]:find('*', 1, true), nil, 'markers dropped')
  local ex = render.wrap('see\n\n```code\n{ "file": "a.lua", "text": "x", "lines": 3 }\n```\n\nafter', 40)
  local found
  for _, r in ipairs(ex) do
    found = found or r.excerpt
  end
  eq(found and found.file, 'a.lua', 'excerpt anchor read from the fence')
end)

test('verdict badge', function()
  local v = render.verdict_of { messages = { agent('x', { verdict = 'risk', severity = 'low' }) } }
  eq(v.text, 'RISK · low', 'text')
  eq(v.hl, 'ThreadVerdictWarn', 'colour')
end)

io.stdout:write(string.format('%d tests, %d failed\n', count, failures))
if failures > 0 then
  vim.cmd 'cquit 1'
end
vim.cmd 'qa!'
