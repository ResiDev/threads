-- Every drawer over whole reviews: H.world's, which has a thing of every
-- kind, and the reviews agents wrote (tests/reviews/), each on a clone of
-- the code it is about. Drawn at a few widths, none fails and no row is
-- wider than its width. The agents' reviews are also compared with
-- tests/draws/<review>.txt, so a change to what they draw fails;
-- `UPDATE=1 make test SPEC=draws` writes them. Read a diff before writing
-- it.

local R = require 'tests.runner'
local H = require 'tests.helpers'
local D = require 'tests.drawn'

local json = require 'thread.base.json'
local review = require 'thread.model.review'

-- The widths drawn at: narrow, a split, and wide enough for the files
-- down the right.
local WIDTHS = { 40, 80, 140 }

-- What the agents' reviews are drawn at and compared at.
local WIDTH = 96

-- Where a review in tests/reviews/ with no diff's head is drawn: each
-- other is drawn on its head, where its chunks are found.
local AT = 'HEAD'

---@diagnostic disable-next-line: deprecated
local diff = vim.text and vim.text.diff or vim.diff

R.test('draws: every drawer draws all of a review, at every width, no row wider than it', function()
  H.reset()
  D.plainly(function()
    H.world()
    local r = assert(review.read 'screens')
    for _, width in ipairs(WIDTHS) do
      local ok, lines = pcall(D.drawn, r, width)
      R.ok(ok, width .. ' columns: ' .. tostring(lines))
      R.eq(D.wide(lines, width), {}, 'rows past ' .. width .. ' columns')
    end
  end)
end)

local reviews = vim.fn.globpath(H.root, 'tests/reviews/*.json', false, true)

if #reviews == 0 then
  io.stdout:write 'draws: no reviews in tests/reviews/, so none drawn\n'
  return
end

--- Each review in tests/reviews/, read, on a clone of the code it is
--- about checked out at its diff's head, plainly.
---@param fn fun(r: thread.Review, id: string)
local function each(fn)
  H.reset()
  local at = vim.fn.tempname()
  H.git(H.root, { 'clone', '-q', '--shared', '--no-checkout', H.root, at })
  local ok, err = pcall(D.plainly, function()
    for _, path in ipairs(reviews) do
      local id = vim.fn.fnamemodify(path, ':t:r')
      local raw = assert(json.decode(table.concat(vim.fn.readfile(path), '\n')))
      H.git(at, { 'checkout', '-q', '--force', type(raw.diff) == 'table' and raw.diff.head or AT })
      vim.cmd('cd ' .. vim.fn.fnameescape(at))
      local r, p = review.parse(raw, id)
      fn(assert(r, id .. ': ' .. table.concat(p.errors, '\n')), id)
    end
  end)
  vim.cmd('cd ' .. vim.fn.fnameescape(H.root))
  vim.fn.delete(at, 'rf')
  R.ok(ok, err)
end

R.test('tests/reviews: drawn on the code they are about, as tests/draws/ has them', function()
  local failures = {}
  each(function(r, id)
    local got = D.drawn(r, WIDTH)
    local file = H.root .. '/tests/draws/' .. id .. '.txt'
    local want = vim.fn.filereadable(file) == 1 and vim.fn.readfile(file) or nil
    if vim.env.UPDATE == '1' then
      vim.fn.mkdir(vim.fs.dirname(file), 'p')
      vim.fn.writefile(got, file)
    elseif not want then
      failures[#failures + 1] = id .. ': not recorded; UPDATE=1 make test SPEC=draws writes it'
    elseif not vim.deep_equal(got, want) then
      local d = diff(table.concat(want, '\n') .. '\n', table.concat(got, '\n') .. '\n', { ctxlen = 2 })
      failures[#failures + 1] = id .. ':\n' .. tostring(d)
    end
  end)
  R.ok(#failures == 0, 'drawn otherwise than tests/draws/ has it:\n' .. table.concat(failures, '\n'))
end)

R.test('tests/reviews: drawn at every width, no row is wider', function()
  local rows = {}
  each(function(r, id)
    for _, width in ipairs(WIDTHS) do
      for _, l in ipairs(D.wide(D.drawn(r, width), width)) do
        rows[#rows + 1] = id .. ' at ' .. width .. ': ' .. l
      end
    end
  end)
  R.eq(rows, {}, 'rows past their width')
end)
