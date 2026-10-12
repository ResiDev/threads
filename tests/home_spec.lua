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
  H.press 'o' -- from the review's row into its groups
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

--- Two threads on store.lua, the first answered with a name that points at
--- code; Home open on it.
local function two_threads()
  H.reset()
  H.repo(H.fixture)
  H.batch {
    {
      id = 1,
      file = 'store.lua',
      line = 3,
      text = 'function M.get(store, key)',
      status = 'open',
      messages = { { from = 'you', text = 'How does get work?' }, { from = 'agent', text = 'It reads the store.\n\nWrites go through `M.set` instead.' } },
    },
    { id = 2, file = 'store.lua', line = 8, text = 'function M.set(store, key, value)', status = 'open', messages = { { from = 'you', text = 'And set?' } } },
  }
  local home = require 'thread.home'
  home.open()
  H.settle()
  return home, home._state()
end

R.test('home: inside a thread, j/k step through its parts and ⏎ opens a name', function()
  local home, S = two_threads()
  R.eq(S.focus, 1, 'the answered thread is focused first')
  H.press 'o'
  H.settle()
  R.eq(S.inside and S.inside.id, 1, 'inside it')
  local kinds = vim.tbl_map(function(it)
    return it.kind
  end, S.items)
  R.eq(kinds, { 'code', 'message', 'message' }, 'its code and each message are parts')
  R.eq(S.items[S.inside.item].index, 2, 'on the first message not seen')
  H.press 'w'
  H.settle()
  R.ok(S.inside.ref, 'w goes to the name')
  H.press '<CR>'
  H.settle()
  H.must_see('function M.set(store, key, value)', '⏎ shows the code the name points to')
  H.press '+'
  H.settle()
  R.eq(S.ref_size[S.inside.ref], 3, '+ shows more of it')
  H.press '<CR>'
  H.settle()
  R.ok(not H.on_screen 'function M.set(store, key, value)', '⏎ again hides it')
  H.press '<Esc>'
  H.settle()
  R.eq(S.inside, nil, 'Esc comes back out')
  home.close()
end)

R.test('home: space marks, c closes every marked thread, Esc unmarks', function()
  local home, S = two_threads()
  local store = require 'thread.store'
  H.press 'G'
  H.settle()
  H.press '<Space>'
  H.settle()
  R.eq(vim.tbl_count(S.marked), 1, 'one marked')
  H.press 'gg'
  H.settle()
  H.press '<Space>'
  H.settle()
  R.eq(vim.tbl_count(S.marked), 2, 'two marked')
  H.press 'c'
  H.settle()
  local batch = store.active()
  R.eq({ store.status(store.find(batch, 1)), store.status(store.find(batch, 2)) }, { 'closed', 'closed' }, 'both closed')
  R.eq(next(S.marked), nil, 'and unmarked')
  home.close()
end)

R.test('home: r replies in place, <C-s> sends it', function()
  local home, S = two_threads()
  local store = require 'thread.store'
  H.press 'r'
  H.settle()
  R.ok(S.reply, 'replying')
  vim.api.nvim_put({ 'Thanks, clear.' }, 'c', false, false)
  H.press '<C-s>'
  H.settle()
  local c = store.find(store.active(), 1)
  R.eq(c.messages[#c.messages].text, 'Thanks, clear.', 'the reply is sent')
  R.eq(store.status(c), 'waiting', 'and with the agent')
  home.close()
end)

R.test('home: / narrows to the threads that mention it', function()
  local home, S = two_threads()
  local input = vim.fn.input
  vim.fn.input = function()
    return 'And set'
  end
  H.press '/'
  H.settle()
  vim.fn.input = input
  R.eq(S.query, 'And set', 'the search is kept')
  R.eq(S.order, { 2 }, 'only the thread that says it')
  H.press '<Esc>'
  H.settle()
  R.eq(S.query, nil, 'Esc clears it')
  home.close()
end)

R.test('home: ⏎ on a #link focuses the thread it names', function()
  local home = two_threads()
  local store = require 'thread.store'
  local batch = store.active()
  store.find(batch, 1).messages[2].text = 'See #2 for set.'
  store.save(batch)
  home.draw()
  local row, line = H.on_screen 'See #2'
  R.ok(row, 'the link is on screen')
  local lnum
  for i, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    local col = l:find('#2', 1, true)
    if col then
      lnum = i
      vim.api.nvim_win_set_cursor(0, { i, col })
    end
  end
  R.ok(lnum, 'found in the buffer: ' .. tostring(line))
  H.press '<CR>'
  H.settle()
  R.eq(home._state() and home._state().single, 2, 'thread 2, focused')
  home.close()
end)
