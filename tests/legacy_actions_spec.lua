-- Actions on threads: going to one.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local function on_b()
  H.reset()
  H.repo { ['a.lua'] = { 'x' }, ['b.lua'] = { 'one', 'two' } }
  H.batch { { id = 1, file = 'b.lua', line = 2, text = 'two', status = 'open', messages = { { from = 'you', text = 'here' } } } }
  local store = require 'thread.legacy.store'
  return store.find(store.active(), 1)
end

local function landed()
  R.eq(vim.fn.expand '%:t', 'b.lua', 'in the thread file')
  R.eq(vim.api.nvim_win_get_cursor(0)[1], 2, 'on its line')
  R.eq(vim.bo.filetype, 'lua', 'its filetype')
end

R.test('jump: goes to the thread from a modified buffer, hidden off', function()
  local t = on_b()
  vim.o.hidden = false
  vim.cmd.edit 'a.lua'
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'changed' })
  local ok, err = pcall(require('thread.legacy.actions').jump, t)
  vim.o.hidden = true
  R.ok(ok, 'no error: ' .. tostring(err))
  landed()
end)

R.test("jump: another plugin's autocmd that throws does not stop it", function()
  local t = on_b()
  vim.cmd.edit 'a.lua'
  local group = vim.api.nvim_create_augroup('thread_test_throws', {})
  vim.api.nvim_create_autocmd('BufReadPost', {
    group = group,
    pattern = '*/b.lua',
    callback = function()
      error 'boom'
    end,
  })
  local ok, err = pcall(require('thread.legacy.actions').jump, t)
  vim.api.nvim_del_augroup_by_id(group)
  R.ok(ok, 'no error: ' .. tostring(err))
  landed()
end)
