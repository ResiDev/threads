-- The reviews agents wrote (tests/reviews/) stay format 2 as the model
-- changes: each reads, with nothing to warn of.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local json = require 'thread.base.json'
local review = require 'thread.model.review'

R.test('tests/reviews: each review an agent wrote reads, with no warnings', function()
  local paths = vim.fn.globpath(H.root, 'tests/reviews/*.json', false, true)
  R.ok(#paths > 0, 'some reviews')
  for _, path in ipairs(paths) do
    local id = vim.fn.fnamemodify(path, ':t:r')
    local raw = assert(json.decode(table.concat(vim.fn.readfile(path), '\n')))
    local r, p = review.parse(raw, id)
    R.ok(r, id .. ':\n  ' .. table.concat(p.errors, '\n  '))
    R.eq(p.warnings, {}, id)
  end
end)
