-- Every drawer over whole reviews: H.world's, which has a thing of every
-- kind, and the reviews agents wrote (tests/reviews/), each on a clone of
-- the code it is about. Drawn at a few widths, none fails and no row is
-- wider than its width. The agents' reviews are also compared with
-- tests/draws/<review>.txt, so a change to what they draw fails;
-- `UPDATE=1 make test SPEC=draws` writes them. Read a diff before writing
-- it.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local config = require 'thread.config'
local contract_draw = require 'thread.draw.contract'
local contracts_draw = require 'thread.draw.contracts'
local files_draw = require 'thread.draw.files'
local json = require 'thread.base.json'
local note = require 'thread.model.note'
local note_draw = require 'thread.draw.note'
local review = require 'thread.model.review'
local review_draw = require 'thread.draw.review'
local sheet = require 'thread.ui.sheet'
local step_draw = require 'thread.draw.step'
local tour_draw = require 'thread.draw.tour'

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

--- A review drawn by every drawer, each under a heading of its own,
--- `width` columns wide: its line, its overview folded, opened and by
--- file; each contract's row and page; each tour's line, outline,
--- briefing and section; each step's line, block, card and whole; each
--- note's row, line, card and whole.
---@param r thread.Review
---@param width integer
---@return string[]
local function drawn(r, width)
  local P = sheet.new()
  local o = { width = width }
  ---@param what string
  local function heading(what)
    if #P.lines > 0 then
      P.add ''
    end
    P.add('==== ' .. what)
  end
  heading 'line'
  review_draw.line(P, r, o)
  heading 'overview'
  review_draw.overview(P, r, o)
  heading 'overview, every part opened'
  local open = {} ---@type table<string, true>
  for _, kind in ipairs(note.KINDS) do
    open[review_draw.kind_key(kind)] = true
  end
  for _, x in ipairs(r.tours) do
    for _, s in ipairs(x.steps) do
      open['step:' .. s.id] = true
    end
  end
  review_draw.overview(P, r, { width = width, tours = true, contracts = true, open = open, code = true })
  heading 'overview, by file'
  review_draw.overview(P, r, { width = width, files = true, code = true })
  heading 'files'
  files_draw.draw(P, r, files_draw.of_review(r), { width = width, tours = true })
  heading 'contracts'
  contracts_draw.draw(P, r.contracts, { width = width, all = true, review = r })
  for _, c in ipairs(r.contracts) do
    heading('contract ' .. c.id)
    contract_draw.page(P, r, c, o)
  end
  for place, x in ipairs(r.tours) do
    heading('tour ' .. place)
    tour_draw.line(P, r, x, { width = width, place = place })
    tour_draw.outline(P, r, x, { width = width, place = place, here = x.steps[1] })
    heading('tour ' .. place .. ', briefing')
    tour_draw.briefing(P, r, x, { width = width, place = place })
    heading('tour ' .. place .. ', section')
    tour_draw.section(P, r, x, { width = width, place = place })
    tour_draw.section(P, r, x, { width = width, place = place, folded = true })
    for _, s in ipairs(x.steps) do
      heading('step ' .. s.id)
      step_draw.line(P, r, x, s, o)
      step_draw.block(P, r, x, s, { width = width, open = true })
      heading('step ' .. s.id .. ', card')
      step_draw.card(P, r, x, s, o)
      heading('step ' .. s.id .. ', whole')
      step_draw.whole(P, r, x, s, o)
    end
  end
  for _, n in ipairs(r.notes) do
    heading('note ' .. n.id)
    note_draw.row(P, r, n, o)
    note_draw.line(P, r, n, o)
    heading('note ' .. n.id .. ', card')
    note_draw.card(P, r, n, o)
    heading('note ' .. n.id .. ', whole')
    note_draw.whole(P, r, n, { width = width, code = true })
  end
  return P.lines
end

--- The rows of `lines` wider than `width`, headings aside.
---@param lines string[]
---@param width integer
---@return string[]
local function wide(lines, width)
  return vim.tbl_filter(function(l)
    return vim.fn.strdisplaywidth(l) > width and not l:find '^===='
  end, lines)
end

--- `fn` with plain shapes for icons and the time held still.
---@param fn fun()
local function plainly(fn)
  local restore = H.freeze_time '2026-10-14T09:00:00'
  local icons = config.options.ui.icons
  config.options.ui.icons = false
  local ok, err = pcall(fn)
  config.options.ui.icons = icons
  restore()
  if not ok then
    error(err, 0)
  end
end

R.test('draws: every drawer draws all of a review, at every width, no row wider than it', function()
  H.reset()
  plainly(function()
    H.world()
    local r = assert(review.read 'screens')
    for _, width in ipairs(WIDTHS) do
      local ok, lines = pcall(drawn, r, width)
      R.ok(ok, width .. ' columns: ' .. tostring(lines))
      R.eq(wide(lines, width), {}, 'rows past ' .. width .. ' columns')
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
  local ok, err = pcall(plainly, function()
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
    local got = drawn(r, WIDTH)
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
      for _, l in ipairs(wide(drawn(r, width), width)) do
        rows[#rows + 1] = id .. ' at ' .. width .. ': ' .. l
      end
    end
  end)
  R.eq(rows, {}, 'rows past their width')
end)
