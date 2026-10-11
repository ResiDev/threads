-- The batch file's JSON: a fixed key order, lists kept lists.

local R = require 'tests.runner'
local json = require 'thread.json'

R.test('json: empty review and diagram lists stay lists', function()
  local v = {
    review = { groups = { { title = 'g', hunks = {}, affected = {}, tests = {} } } },
    diagram = { kind = 'flow', nodes = {}, edges = {} },
  }
  local again = json.encode(json.decode(json.encode(v)))
  for _, key in ipairs { 'hunks', 'affected', 'tests', 'nodes', 'edges' } do
    R.ok(again:find('"' .. key .. '": []', 1, true), key .. ' stays []:\n' .. again)
  end
end)

R.test('json: a review reads top to bottom', function()
  local s = json.encode {
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
  }
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
