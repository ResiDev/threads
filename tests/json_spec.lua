-- JSON as people and agents edit it: keys in a schema's order, lists kept
-- lists. Then a review's own schema.

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

local REVIEW = require('thread.model.review').SCHEMA

---@param s string
---@return string[]
local function keys(s)
  local out = {}
  for key in s:gmatch '"([%w_]+)":' do
    out[#out + 1] = key
  end
  return out
end

R.test('json, a review: every empty list it can hold stays a list', function()
  local v = {
    contracts = { { dependents = {}, messages = {} } },
    tours = { { steps = {} }, { steps = { { messages = { { changes = {} } } } } } },
    notes = {},
    chunks = {},
    introduction = { diagrams = { d = { kind = 'flow', nodes = {}, edges = {} } } },
  }
  local again = json.encode(json.decode(json.encode(v, REVIEW)), REVIEW)
  for _, key in ipairs { 'dependents', 'messages', 'steps', 'changes', 'notes', 'chunks', 'nodes', 'edges' } do
    R.ok(again:find('"' .. key .. '": []', 1, true), key .. ' stays []:\n' .. again)
  end
end)

R.test('json, a review: it reads top to bottom, and each part says what it is before what it holds', function()
  R.eq(
    keys(
      json.encode(
        { chunks = {}, notes = {}, tours = {}, contracts = {}, introduction = { text = 'i' }, status = 'open', diff = { of = 'staged' }, title = 't' },
        REVIEW
      )
    ),
    { 'title', 'status', 'diff', 'of', 'introduction', 'text', 'contracts', 'tours', 'notes', 'chunks' },
    'a review'
  )
  R.eq(
    keys(json.encode({ rev = 'head', to = 'end', from = 'x', line = 1, file = 'a', id = 'c' }, REVIEW)),
    { 'id', 'file', 'line', 'from', 'to', 'rev' },
    'a chunk'
  )
  R.eq(
    keys(json.encode({ messages = {}, severity = 'low', issue = 'bug', chunk = 'c', status = 'open', title = 't', kind = 'issue', id = 1 }, REVIEW)),
    { 'id', 'title', 'kind', 'issue', 'severity', 'status', 'chunk', 'messages' },
    'a note'
  )
  R.eq(keys(json.encode({ changes = {}, prose = { text = 'x' }, at = 'now', from = 'you' }, REVIEW)), { 'from', 'at', 'prose', 'text', 'changes' }, 'a message')
  R.eq(
    keys(
      json.encode(
        { messages = {}, dependents = {}, prose = {}, why = 'w', source = { after = 'a', before = 'b', change = 'changed' }, kind = 'k', name = 'n', id = 1 },
        REVIEW
      )
    ),
    { 'id', 'name', 'kind', 'why', 'source', 'change', 'before', 'after', 'prose', 'dependents', 'messages' },
    'a contract'
  )
end)
