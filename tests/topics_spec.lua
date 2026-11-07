-- The topics agents wrote (tests/topics/) keep reading as the model
-- changes: each reads with nothing to warn of, and every link in them goes
-- somewhere. None yet: they are written with the new skill, and until
-- then this says so and tests nothing.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local check = require 'thread.prose.check'
local json = require 'thread.base.json'
local topic = require 'thread.model.topic'

local paths = vim.fn.globpath(H.root, 'tests/topics/*.json', false, true)
if #paths == 0 then
  io.stdout:write 'tests/topics: no topics yet, skipped\n'
  return
end

--- Each topic there, read as it is on disk, and why one does not read.
---@return table<string, thread.Topic>, table<string, string[]>
local function read_all()
  local topics, broken = {}, {} ---@type table<string, thread.Topic>, table<string, string[]>
  for _, path in ipairs(paths) do
    local id = vim.fn.fnamemodify(path, ':t:r')
    local raw = json.decode(table.concat(vim.fn.readfile(path), '\n'))
    local r, p = topic.parse(raw, id)
    if r then
      topics[id] = r
    else
      broken[id] = p.errors
    end
  end
  return topics, broken
end

R.test('tests/topics: each topic an agent wrote reads, with no warnings', function()
  for _, path in ipairs(paths) do
    local id = vim.fn.fnamemodify(path, ':t:r')
    local r, p = topic.parse(json.decode(table.concat(vim.fn.readfile(path), '\n')), id)
    R.ok(r, id .. ':\n  ' .. table.concat(p.errors, '\n  '))
    R.eq(p.warnings, {}, id)
  end
end)

R.test('tests/topics: every link and fence an agent wrote is sound, links to other topics too', function()
  local topics, broken = read_all()
  local get = function(id)
    return topics[id], broken[id] and table.concat(broken[id], '; ') or nil
  end
  for id, r in pairs(topics) do
    local p = check.topic(r, get)
    R.eq({ p.errors, p.warnings }, { {}, {} }, id)
  end
end)
