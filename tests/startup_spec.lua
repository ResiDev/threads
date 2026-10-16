-- A fresh Neovim: the plugin loaded as a person loads it, with no
-- setup() call, `:Thread home` opens the screen.

local R = require 'tests.runner'
local H = require 'tests.helpers'

--- Run `lua` in a new headless Neovim in `cwd`; what it writes.
---@param cwd string
---@param lua string
---@return string
local function child(cwd, lua)
  local out = vim
    .system({ vim.v.progpath, '--headless', '--clean', '-u', H.root .. '/tests/minimal_init.lua', '-c', 'lua ' .. lua, '-c', 'qa!' }, { cwd = cwd, text = true })
    :wait()
  return (out.stdout or '') .. (out.stderr or '')
end

local SHOW = "vim.cmd 'Thread home'; io.stdout:write(vim.bo.filetype, '|', table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\\n'))"

R.test(':Thread home, in a fresh Neovim: the screen, opened on the only review there is', function()
  H.reset()
  local root = H.world()
  local said = child(root, SHOW)
  R.ok(said:find '^thread%-screen|', 'the screen: ' .. said)
  R.ok(
    said:find('Screens', 1, true) and said:find('Reading', 1, true) and said:find('the value of a', 1, true),
    'on the review, its tours and contracts:\n' .. said
  )
end)

R.test(':Thread home, in a fresh Neovim: with two reviews, Home lists them both', function()
  H.reset()
  local root = H.world()
  H.review('second', H.draft { title = 'The second' })
  local said = child(root, SHOW)
  R.ok(said:find '^thread%-screen|', 'the screen: ' .. said)
  R.ok(said:find('Screens', 1, true) and said:find('The second', 1, true), 'both:\n' .. said)
end)
