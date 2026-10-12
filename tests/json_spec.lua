-- JSON as people and agents edit it: keys in a schema's order, lists kept
-- lists. Then the batch file's own schema.

local R = require 'tests.runner'
local json = require 'thread.base.json'

local SCHEMA = { order = { 'title', 'items', 'note' }, lists = { items = true } }

R.test("json: keys in the schema's order, any others after them, sorted", function()
  local s = json.encode({ zeta = 1, note = 'n', alpha = 2, title = 't' }, SCHEMA)
  local keys = {}
  for key in s:gmatch '"([%w_]+)":' do
    keys[#keys + 1] = key
  end
  R.eq(keys, { 'title', 'note', 'alpha', 'zeta' }, 'key order')
end)

R.test('json: an empty list the schema names stays a list', function()
  local again = json.encode(json.decode(json.encode({ items = {}, other = {} }, SCHEMA)), SCHEMA)
  R.ok(again:find('"items": []', 1, true), 'items stays []:\n' .. again)
  R.ok(again:find('"other": {}', 1, true), 'anything else is an object:\n' .. again)
end)

local BATCH = require('thread.legacy.store.file').SCHEMA

R.test('json, the batch file: empty review and diagram lists stay lists', function()
  local v = {
    review = { groups = { { title = 'g', hunks = {}, affected = {}, tests = {} } } },
    diagram = { kind = 'flow', nodes = {}, edges = {} },
  }
  local again = json.encode(json.decode(json.encode(v, BATCH)), BATCH)
  for _, key in ipairs { 'hunks', 'affected', 'tests', 'nodes', 'edges' } do
    R.ok(again:find('"' .. key .. '": []', 1, true), key .. ' stays []:\n' .. again)
  end
end)

R.test('json, the batch file: a review reads top to bottom', function()
  local s = json.encode({
    review = {
      groups = {
        {
          tests = {},
          affected = {},
          hunks = { { note = 'n', text = 'x', line = 1, file = 'a' } },
          body = 'b',
          risk_why = 'w',
          risk = 'low',
          kind = 'fix',
          title = 'g',
        },
      },
      diff = { of = 'uncommitted' },
    },
  }, BATCH)
  local seen = {}
  for key in s:gmatch '"([%w_]+)":' do
    seen[#seen + 1] = key
  end
  R.eq(
    seen,
    { 'review', 'diff', 'of', 'groups', 'title', 'kind', 'risk', 'risk_why', 'body', 'hunks', 'file', 'line', 'text', 'note', 'affected', 'tests' },
    'key order'
  )
end)
