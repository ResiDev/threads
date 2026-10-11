-- Home: keys that act on the row you are on.

local R = require 'tests.runner'
local H = require 'tests.helpers'

R.test('home: a in the review tab accepts the group you are on', function()
  H.reset()
  local root = H.repo { ['main.lua'] = { 'local x = 1' } }
  vim.fn.writefile({ 'local x = 2' }, root .. '/main.lua')
  H.batch {
    {
      id = 1,
      title = 'Review',
      status = 'open',
      messages = {
        {
          from = 'agent',
          text = 'One change.',
          review = {
            diff = { of = 'uncommitted' },
            groups = { { title = 'two now', kind = 'fix', risk = 'low', body = 'b', hunks = { { file = 'main.lua', text = 'local x = 2', line = 1 } } } },
          },
        },
      },
    },
  }
  local store, review, home = require 'thread.store', require 'thread.review', require 'thread.home'
  require('thread.review.diff').invalidate()
  home.open { view = 'review' }
  H.settle()
  H.press 'j' -- from the review's row to its group's
  H.settle()
  H.press 'a'
  H.settle()
  local owner = store.find(store.active(), 1)
  local group = review.work(review.of(owner)).groups[1]
  R.eq(review.state(store.active(), 1, group), 'accepted', 'the group is accepted')
  home.close()
end)

R.test('home.open: focus moves the cursor to that thread when Home is already open', function()
  H.reset()
  H.repo { ['a.lua'] = { 'x', 'y' } }
  H.batch {
    { id = 1, file = 'a.lua', line = 1, text = 'x', status = 'open', messages = { { from = 'you', text = 'the first question' } } },
    { id = 2, file = 'a.lua', line = 2, text = 'y', status = 'open', messages = { { from = 'you', text = 'the second question' } } },
  }
  local home = require 'thread.home'
  home.open()
  H.settle()
  R.ok(vim.api.nvim_get_current_line():find('the first question', 1, true), 'on the first: ' .. vim.api.nvim_get_current_line())
  home.open { focus = 2 }
  H.settle()
  R.ok(vim.api.nvim_get_current_line():find('the second question', 1, true), 'on the second: ' .. vim.api.nvim_get_current_line())
  home.close()
end)
