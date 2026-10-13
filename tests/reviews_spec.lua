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

R.test('tests/reviews: every link an agent wrote goes to a thread or a step there is', function()
  local link = require 'thread.prose.link'
  local prose = require 'thread.prose'
  local reviews = {} ---@type table<string, thread.Review>
  for _, path in ipairs(vim.fn.globpath(H.root, 'tests/reviews/*.json', false, true)) do
    local id = vim.fn.fnamemodify(path, ':t:r')
    reviews[id] = assert(review.parse(assert(json.decode(table.concat(vim.fn.readfile(path), '\n'))), id))
  end
  local n, bad = 0, {}
  ---@param r thread.Review
  ---@param s string
  local function read(r, s)
    for _, b in ipairs(prose.parse(s)) do
      for _, sp in ipairs(b.spans or {}) do
        if sp.link then
          n = n + 1
          local _, why = link.follow(sp.link, r, function(other)
            return reviews[other]
          end)
          bad[#bad + 1] = why and (r.id .. ': ' .. why) or nil
        end
      end
    end
  end
  -- What is prose: a text, an introduction, a note; not a chunk's quote,
  -- nor a check's shell line.
  ---@param r thread.Review
  ---@param v any
  local function walk(r, v)
    if type(v) ~= 'table' then
      return
    end
    for k, x in pairs(v) do
      if type(x) == 'string' and (k == 'introduction' or k == 'note' or (k == 'text' and not v.file)) then
        read(r, x)
      else
        walk(r, x)
      end
    end
  end
  for _, r in pairs(reviews) do
    walk(r, r)
  end
  R.ok(n > 20, 'links found: ' .. n)
  R.eq(bad, {}, 'each goes somewhere')
end)
