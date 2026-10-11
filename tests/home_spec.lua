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
  review.invalidate()
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
