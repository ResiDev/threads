-- Keys thread.nvim lays over yours: the global mapping is the one kept,
-- whatever the current buffer maps.

local R = require 'tests.runner'
local H = require 'tests.helpers'

R.test('walk: a buffer of its own L does not cost you your global L', function()
  H.reset()
  H.repo { ['a.lua'] = { 'x' } }
  vim.keymap.set('n', 'L', '<Cmd>let g:thread_test_L = "global"<CR>', { desc = 'mine' })
  vim.cmd.edit 'a.lua'
  vim.keymap.set('n', 'L', '<Cmd>let g:thread_test_L = "buffer"<CR>', { buffer = 0 })
  H.batch {
    { id = 1, title = 't', status = 'open', messages = { { from = 'agent', text = 'x', walk = { { file = 'a.lua', line = 1, text = 'x', body = 'b' } } } } },
  }
  local walk = require 'thread.legacy.walk'
  walk.start(1, 1)
  H.settle()
  walk.stop()
  H.settle()
  local g = require('thread.ui.keys').global 'L'
  R.eq(g and g.desc, 'mine', 'the global L is back')
  R.eq(vim.fn.maparg('L', 'n', false, true).buffer, 1, 'and the buffer has its own')
  vim.keymap.del('n', 'L')
  vim.keymap.del('n', 'L', { buffer = 0 })
end)

R.test("Enter off a thread does what the global Enter did, not a buffer's", function()
  H.reset()
  H.repo { ['a.lua'] = { 'x' } }
  pcall(vim.keymap.del, 'n', '<CR>')
  vim.keymap.set('n', '<CR>', function()
    vim.g.thread_test_enter = 'global'
  end, { desc = 'global enter' })
  local dashboard = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(dashboard)
  vim.keymap.set('n', '<CR>', function()
    vim.g.thread_test_enter = 'dashboard'
  end, { buffer = dashboard })
  -- Set up afresh while the "dashboard" is current, as at VeryLazy.
  package.loaded['thread'] = nil
  require('thread').setup {}
  vim.cmd.edit 'a.lua'
  vim.g.thread_test_enter = nil
  H.press '<CR>'
  H.settle()
  R.eq(vim.g.thread_test_enter, 'global', 'the global Enter ran')
end)

R.test('keys: an overlay covers global and buffer keys, and gives both back', function()
  H.reset()
  local keys = require 'thread.ui.keys'
  vim.keymap.set('n', 'Q', '<Cmd>let g:was = "global"<CR>')
  local buf = vim.api.nvim_create_buf(true, false)
  vim.keymap.set('n', 'Q', '<Cmd>let g:was = "buffer"<CR>', { buffer = buf })
  local hits = 0
  local o = keys.overlay { {
    lhs = 'Q',
    fn = function()
      hits = hits + 1
    end,
    desc = 'test',
  } }
  vim.api.nvim_set_current_buf(buf)
  o.cover(buf)
  H.press 'Q'
  R.eq(hits, 1, 'the overlay wins over the buffer key')
  o.restore()
  H.press 'Q'
  R.eq(vim.g.was, 'buffer', 'the buffer key is back')
  vim.cmd 'enew'
  H.press 'Q'
  R.eq(vim.g.was, 'global', 'and the global one')
  vim.keymap.del('n', 'Q')
end)
