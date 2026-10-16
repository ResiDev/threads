-- The reviews agents wrote (tests/reviews/) keep reading as the model
-- changes: each reads with nothing to warn of, and every link in them goes
-- somewhere. None yet: they are written with the new skill, and until
-- then this says so and tests nothing.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local check = require 'thread.prose.check'
local json = require 'thread.base.json'
local review = require 'thread.model.review'

local paths = vim.fn.globpath(H.root, 'tests/reviews/*.json', false, true)
if #paths == 0 then
  io.stdout:write 'tests/reviews: no reviews yet, skipped\n'
  return
end

--- Each review there, read as it is on disk, and why one does not read.
---@return table<string, thread.Review>, table<string, string[]>
local function read_all()
  local reviews, broken = {}, {} ---@type table<string, thread.Review>, table<string, string[]>
  for _, path in ipairs(paths) do
    local id = vim.fn.fnamemodify(path, ':t:r')
    local raw = json.decode(table.concat(vim.fn.readfile(path), '\n'))
    local r, p = review.parse(raw, id)
    if r then
      reviews[id] = r
    else
      broken[id] = p.errors
    end
  end
  return reviews, broken
end

R.test('tests/reviews: each review an agent wrote reads, with no warnings', function()
  for _, path in ipairs(paths) do
    local id = vim.fn.fnamemodify(path, ':t:r')
    local r, p = review.parse(json.decode(table.concat(vim.fn.readfile(path), '\n')), id)
    R.ok(r, id .. ':\n  ' .. table.concat(p.errors, '\n  '))
    R.eq(p.warnings, {}, id)
  end
end)

R.test('tests/reviews: every link and fence an agent wrote is sound, links to other reviews too', function()
  local reviews, broken = read_all()
  local get = function(id)
    return reviews[id], broken[id] and table.concat(broken[id], '; ') or nil
  end
  for id, r in pairs(reviews) do
    local p = check.review(r, get)
    R.eq({ p.errors, p.warnings }, { {}, {} }, id)
  end
end)
