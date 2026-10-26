-- thread.trail: gb back to where you were before thread took you
-- elsewhere, gi forward again, with the keys a person presses.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local go = require 'thread.go'
local review = require 'thread.model.review'
local screen = require 'thread.screen'
local thread = require 'thread'
local trail = require 'thread.trail'
local walk = require 'thread.walk'

--- H.world, set up as a person has it, with store.lua open on `line`.
---@param line integer
local function world(line)
  H.reset()
  H.mute()
  vim.o.columns, vim.o.lines = 100, 50
  thread.setup {}
  trail.clear()
  H.world()
  vim.cmd.edit 'store.lua'
  require('thread.code').refresh()
  vim.api.nvim_win_set_cursor(0, { line, 0 })
end

--- Where you are: on the screen, its place and what it is on, and
--- whether over the code; walking, the step; else the file and line.
---@return string
local function where()
  local S = screen.state()
  if S and vim.api.nvim_get_current_win() == S.win then
    local on = S.note and ' ' .. S.note or S.step and ' ' .. S.step or ''
    return 'screen ' .. S.place .. on .. (S.over and ' over' or '')
  end
  local w = walk.state()
  local at = string.format('%s:%d', vim.fn.expand '%:t', vim.api.nvim_win_get_cursor(0)[1])
  return w and string.format('walk %s, %s', w.step, at) or at
end

R.test('trail: gb from the screen back to the line of code you opened it from, gi to the screen again', function()
  world(5)
  H.press '<leader>hh'
  R.eq(where(), 'screen overview', 'the one review, on its Overview')
  H.press 'gb'
  R.eq(where(), 'store.lua:5', 'back on the line')
  H.press 'gi'
  R.eq(where(), 'screen overview', 'forward to the screen')
end)

R.test('trail: gb goes back from page to page and to the code under them, the row kept; gi forward again', function()
  world(4)
  H.press '<CR>'
  H.settle()
  R.eq(where(), 'screen note 1 over', "the note on the cache's page, over the code")
  local row = vim.api.nvim_win_get_cursor(0)[1]
  H.press 'L'
  local next_note = where()
  R.ok(next_note ~= 'screen note 1 over' and vim.startswith(next_note, 'screen note '), 'L, the next note: ' .. next_note)
  H.press 'gb'
  R.eq({ where(), vim.api.nvim_win_get_cursor(0)[1] }, { 'screen note 1 over', row }, 'back on the first, on the row it was on')
  H.press 'gb'
  R.eq(where(), 'store.lua:4', 'back in the code')
  H.press 'gb'
  R.eq(where(), 'store.lua:4', 'nowhere further back: it stays')
  H.press 'gigi'
  R.eq(where(), next_note, 'forward twice')
end)

R.test('trail: a walk is kept at the step you left it on, not each step; gb walks on from it', function()
  world(1)
  local r = assert(review.read 'screens')
  go.open('walk', { review = r, tour = r.tours[1], step = r.tours[1].steps[1] })
  R.eq(where(), 'walk 1, store.lua:3', 'on step 1')
  H.press 'L'
  R.eq(where(), 'walk 2, store.lua:4', 'on step 2')
  vim.api.nvim_win_set_cursor(0, { 6, 0 })
  H.press 'U'
  R.eq(where(), 'screen overview', 'up to the review, the walk over')
  H.press 'gb'
  R.eq(where(), 'walk 2, store.lua:6', 'walking again, on step 2, the cursor where it was')
  H.press 'gb'
  R.eq(where(), 'walk 2, store.lua:1', 'then where the walk started, which stays on')
  walk.stop()
end)

R.test('trail: ]h is kept, so gb comes back from it', function()
  world(1)
  H.press ']h'
  local went = where()
  R.ok(went ~= 'store.lua:1', ']h went: ' .. went)
  H.press 'gb'
  R.eq(where(), 'store.lua:1', 'back')
end)

R.test("trail: gi with nowhere ahead is the editor's, and once you write, forward is forgotten", function()
  world(1)
  H.press 'Aone<Esc>3G'
  H.press 'gitwo<Esc>'
  R.eq(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]:sub(-6), 'onetwo', 'gi: insert where you last did')
  vim.cmd 'silent! undo'
  vim.cmd 'silent! undo'
  H.press '<leader>hh'
  H.press 'gb'
  H.press 'Athree<Esc>G'
  H.press 'gifour<Esc>'
  R.eq(where(), 'store.lua:1', 'still in the code, not forward to the screen')
  R.ok(vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]:find('threefour', 1, true), 'written where you last did')
  vim.cmd 'silent! edit!'
end)
