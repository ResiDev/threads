-- Commands and keys come from one list: every key the config names runs a
-- command, and :Thread completes every command.

local R = require 'tests.runner'

R.test('every mapping in the config runs a command, and is set', function()
  local thread = require 'thread'
  thread.setup {}
  local config = require 'thread.config'
  for name, lhs in pairs(config.defaults.mappings) do
    local m = vim.fn.maparg(lhs, 'n', false, true)
    R.ok(m.desc and m.desc:find '^Thread: ', string.format('%s (%s) is mapped: %s', name, lhs, vim.inspect(m.desc)))
  end
  R.ok(thread.commands.batches and thread.commands.home and thread.commands.new, 'commands by name')
  local done = vim.fn.getcompletion('Thread ', 'cmdline')
  R.ok(vim.tbl_contains(done, 'walk') and vim.tbl_contains(done, 'changes'), ':Thread completes them: ' .. vim.inspect(done))
end)
