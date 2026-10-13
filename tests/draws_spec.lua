-- The reviews agents wrote (tests/reviews/), drawn as text on the code
-- they are about (9cde8c4): each review's line and overview, every thread
-- whole and as a card, and the steps of its first two threads whole and
-- as cards. Compared with tests/draws/<review>.txt, so a change to what
-- they draw fails; `UPDATE=1 make test SPEC=draws` writes them. Read a
-- diff before writing it.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local config = require 'thread.config'
local json = require 'thread.base.json'
local review = require 'thread.model.review'
local review_draw = require 'thread.draw.review'
local sheet = require 'thread.ui.sheet'
local spec_of = require('thread.model.chunk').spec
local step_draw = require 'thread.draw.step'
local thread = require 'thread.model.thread'
local thread_draw = require 'thread.draw.thread'

local WIDTH, CARD = 96, 72

---@diagnostic disable-next-line: deprecated
local diff = vim.text and vim.text.diff or vim.diff

--- A review drawn, every part under a heading of its own.
---@param r thread.Review
---@return string[]
local function drawn(r)
  local spec = spec_of(r.diff)
  local P = sheet.new()
  ---@param what string
  local function heading(what)
    if #P.lines > 0 then
      P.add ''
    end
    P.add('==== ' .. what)
  end
  heading 'line'
  review_draw.line(P, r, { width = WIDTH })
  heading 'overview'
  review_draw.overview(P, r, { width = WIDTH })
  for k, t in ipairs(r.threads) do
    heading('#' .. t.id .. ' whole')
    thread_draw.whole(P, r, t, { width = WIDTH, spec = spec })
    heading('#' .. t.id .. ' card')
    thread_draw.card(P, r, t, { width = CARD, spec = spec })
    for _, x in ipairs(k <= 2 and thread.tours(t) or {}) do
      for _, s in ipairs(x.steps) do
        heading('#' .. t.id .. '.' .. s.id .. ' whole')
        step_draw.whole(P, r, t, x, s, { width = WIDTH, spec = spec })
        heading('#' .. t.id .. '.' .. s.id .. ' card')
        step_draw.card(P, r, t, x, s, { width = CARD, spec = spec })
      end
    end
  end
  return P.lines
end

R.test('tests/reviews: drawn on the code they are about, as tests/draws/ has them', function()
  H.reset()
  local at = vim.fn.tempname()
  H.git(H.root, { 'clone', '-q', '--shared', '--no-checkout', H.root, at })
  H.git(at, { 'checkout', '-q', '9cde8c4' })
  vim.cmd('cd ' .. vim.fn.fnameescape(at))
  local restore = H.freeze_time '2026-10-14T09:00:00'
  local icons = config.options.ui.icons
  config.options.ui.icons = false
  local failures = {}
  local ok, err = pcall(function()
    for _, path in ipairs(vim.fn.globpath(H.root, 'tests/reviews/*.json', false, true)) do
      local id = vim.fn.fnamemodify(path, ':t:r')
      local r = assert(review.parse(assert(json.decode(table.concat(vim.fn.readfile(path), '\n'))), id))
      local got = drawn(r)
      local file = H.root .. '/tests/draws/' .. id .. '.txt'
      local want = vim.fn.filereadable(file) == 1 and vim.fn.readfile(file) or nil
      if vim.env.UPDATE == '1' then
        vim.fn.mkdir(vim.fs.dirname(file), 'p')
        vim.fn.writefile(got, file)
      elseif not vim.deep_equal(got, want) then
        local d = diff(table.concat(want or {}, '\n') .. '\n', table.concat(got, '\n') .. '\n', { ctxlen = 2 })
        failures[#failures + 1] = id .. ':\n' .. tostring(d)
      end
    end
  end)
  config.options.ui.icons = icons
  restore()
  vim.cmd('cd ' .. vim.fn.fnameescape(H.root))
  vim.fn.delete(at, 'rf')
  R.ok(ok, err)
  R.ok(#failures == 0, 'drawn otherwise than tests/draws/ has it:\n' .. table.concat(failures, '\n'))
end)
