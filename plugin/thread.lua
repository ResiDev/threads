if vim.g.loaded_thread_nvim then
  return
end
vim.g.loaded_thread_nvim = true

vim.api.nvim_create_user_command('Thread', function(cmd)
  local thread = require 'thread'
  thread.ensure()
  local sub = cmd.fargs[1] or 'home'
  local fn = thread.commands[sub]
  if not fn then
    vim.notify('thread: no subcommand ' .. sub, vim.log.levels.ERROR)
    return
  end
  fn(cmd)
end, {
  nargs = '*',
  range = true,
  desc = 'thread.nvim: home (default), batches, add, ask, open, reply, close, map, walk, stop, dim, diff, import, send, toggle, hide, next, prev, new, changes',
  complete = function(arg, line)
    local sub = line:match '^%S*%s+(%S+)%s'
    if sub == 'import' then
      return vim.tbl_filter(function(name)
        return name:find(arg, 1, true) == 1
      end, require('thread.import').names())
    elseif sub then
      return {}
    end
    return vim.tbl_filter(function(name)
      return name:find(arg, 1, true) == 1
    end, vim.tbl_keys(require('thread').commands))
  end,
})
