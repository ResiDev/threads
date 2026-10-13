-- THREAD_REBUILD=1: the rebuild's surfaces in place of today's, in a
-- Neovim of their own, as `make try` starts one.

local R = require 'tests.runner'
local H = require 'tests.helpers'

--- Run `lua` in a new headless Neovim with the rebuild on, in `cwd`;
--- what it writes to stdout.
---@param cwd string
---@param lua string
---@return string
local function child(cwd, lua)
  local out = vim
    .system({ vim.v.progpath, '--headless', '--clean', '-u', H.root .. '/tests/minimal_init.lua', '-c', 'lua ' .. lua, '-c', 'qa!' }, {
      cwd = cwd,
      env = { THREAD_REBUILD = '1' },
      text = true,
    })
    :wait()
  return (out.stdout or '') .. (out.stderr or '')
end

R.test('THREAD_REBUILD=1: :Thread home opens the screen at the review there is', function()
  H.reset()
  local root = H.repo { ['a.lua'] = { 'x' } }
  H.review('one', {
    title = 'The only one',
    threads = {
      { id = 1, title = 'A', messages = { { from = 'agent', text = 'a' } } },
      { id = 2, title = 'B', messages = { { from = 'agent', text = 'b' } } },
    },
  })
  local said = child(root, "vim.cmd 'Thread home'; io.stdout:write(vim.bo.filetype, '|', table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\\n'))")
  R.ok(said:find '^thread%-screen|', 'the screen: ' .. said)
  R.ok(said:find('The only one', 1, true) and said:find('#2', 1, true), 'one review: opened on it\n' .. said)
end)
