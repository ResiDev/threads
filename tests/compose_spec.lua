-- thread.compose: the float you write in. A thread you start goes in the
-- review you pick as you save it.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local go = require 'thread.go'
local review = require 'thread.model.review'
require 'thread.compose'

local function written()
  H.reset()
  H.mute()
  H.repo { ['a.lua'] = { 'local M = {}', 'return M' } }
  H.review('older', { title = 'Older', threads = { { id = 1, title = 'x', messages = { { from = 'agent', text = 'x' } } } } })
  H.review('closed', { title = 'Closed', status = 'closed' })
end

--- vim.ui.select and vim.ui.input answering as given, for `fn`.
---@param pick integer|nil  the item picked; nil: none
---@param title string|nil  what is typed for a title
---@param fn fun()
---@return string[] offered
local function answering(pick, title, fn)
  local select, input = vim.ui.select, vim.ui.input
  local offered = {}
  vim.ui.select = function(items, _, cb)
    offered = items
    cb(pick and items[pick], pick)
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.ui.input = function(_, cb)
    cb(title)
  end
  local ok, err = pcall(fn)
  vim.ui.select, vim.ui.input = select, input
  assert(ok, err)
  return offered
end

R.test('compose: a question goes in the open review you pick, or a new one you name', function()
  written()
  local offered = answering(1, nil, function()
    go.open('compose', {})
    H.type_in 'In general?'
    H.press '<C-s>'
  end)
  R.eq(offered, { 'Older', 'A new review…' }, 'the open reviews, then a new one')
  local t = assert(review.read 'older').threads[2]
  R.eq({ t and t.chunk, t and t.messages[1].text }, { nil, 'In general?' }, 'in Older, on no line')
  answering(2, 'Fresh one', function()
    go.open('compose', { chunk = { file = 'a.lua', line = 2, text = 'return M' } })
    H.type_in 'Why return?'
    H.press '<C-s>'
  end)
  local n = assert(review.read 'fresh-one')
  R.eq({ n.title, n.threads[1].chunk.line, n.threads[1].messages[1].text }, { 'Fresh one', 2, 'Why return?' }, 'a new review')
end)

R.test('compose: nothing picked saves nothing, and what you wrote is in the unnamed register', function()
  written()
  answering(nil, nil, function()
    go.open('compose', {})
    H.type_in 'Lost?'
    H.press '<C-s>'
  end)
  R.eq(#assert(review.read 'older').threads, 1, 'nothing saved')
  R.eq(vim.fn.getreg '"', 'Lost?', 'kept')
end)

R.test('compose: q throws it away; going to another window saves it', function()
  written()
  local r = assert(review.read 'older')
  local c = require('thread.model.thread').conversation(r.threads[1])
  go.open('compose', { replies = { { review = r, conversation = c } } })
  H.type_in 'Never mind.'
  H.press 'q'
  R.eq(#assert(review.read 'older').threads[1].messages, 1, 'thrown away')
  go.open('compose', { replies = { { review = r, conversation = c } } })
  H.type_in 'Kept.'
  vim.cmd 'wincmd p'
  H.settle()
  local m = assert(review.read 'older').threads[1].messages
  R.eq(m[#m].text, 'Kept.', 'saved on leaving')
end)
