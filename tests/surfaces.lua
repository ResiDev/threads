-- The surfaces as text, over H.world(): each window, its lines and its
-- marks, then the screen. Compared with tests/surfaces/<name>.txt; `make
-- surfaces` checks, `UPDATE=1 make surfaces` writes them. Read a diff
-- before writing it.
--
-- Headless, Neovim's screen stays 80 by 24 whatever 'columns' and 'lines'
-- say, and a float past it is drawn wrong. So this runs itself again in a
-- Neovim embedded with a screen of its own, 120 by 40: a UI attached to it
-- over a socket of its own, what it is sent thrown away, since only a
-- channel that is not RPC can take what a UI is sent. Time is held still
-- and the plain glyphs are used, so the same review draws the same every
-- run.

local COLUMNS, LINES = 120, 40

if not vim.env.THREAD_SURFACES then
  local here = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
  local init = vim.fn.fnamemodify(here, ':h') .. '/minimal_init.lua'
  local sock = vim.fn.tempname() .. '.sock'
  local child = vim.fn.jobstart({ vim.v.progpath, '--embed', '--clean', '-u', init, '--listen', sock }, {
    rpc = true,
    env = { THREAD_SURFACES = '1' },
    on_stderr = function(_, data)
      io.stdout:write(table.concat(data, '\n'))
    end,
  })
  vim.rpcrequest(child, 'nvim_eval', '1')
  local ui = vim.fn.sockconnect('pipe', sock, { on_data = function() end })
  vim.fn.chansend(ui, vim.mpack.encode { 0, 1, 'nvim_ui_attach', { COLUMNS, LINES, { ext_linegrid = true } } })
  vim.wait(5000, function()
    return vim.rpcrequest(child, 'nvim_eval', '&lines') == LINES
  end)
  -- It ends Neovim when done, so the request never hears back.
  pcall(vim.rpcrequest, child, 'nvim_exec_lua', 'dofile(...)', { here })
  local code = vim.fn.jobwait({ child }, 60000)[1]
  vim.cmd(code == 0 and 'qa!' or 'cquit 1')
  return
end

-- Embedded, stdout is how it talks to the Neovim that started it: what it
-- says goes to stderr, which that one prints.
io.stdout = io.stderr

local H = require 'tests.helpers'

vim.o.signcolumn = 'yes:2'
-- Compose starts in insert mode; saying so is not what is captured.
vim.o.showmode = false
H.mute()
H.freeze_time '2026-10-11T12:00:00'

require('thread.config').setup { ui = { icons = false } }
local root = H.world()

local go = require 'thread.go'
local review = require 'thread.model.review'
require 'thread.screen'
require 'thread.compose'
require 'thread.map'
local code = require 'thread.code'
code.setup()
local walk = require 'thread.walk'

local shots = require('tests.capture').new(H.root .. '/tests/surfaces', root, function(bar)
  return bar:find('thread.walk', 1, true) and walk.bar() or bar
end)
local shot = shots.shot

local r = assert(review.read 'screens')

-- The screen, full.
go.open('home', { review = r })
shot 'home'
H.press '?'
shot 'home-help'
H.press 'q'
H.press '<CR>'
shot 'review'
go.open('note', { review = r, note = review.note(r, 1) })
shot 'note'
go.open('contract', { review = r, contract = review.contract(r, 1) })
shot 'contract'
go.open('note', { review = r, note = review.note(r, 2) })
H.press 'r'
shot 'compose-reply'
H.press '<Esc>'
H.press 'q'

-- Over the code.
vim.cmd.edit 'store.lua'
code.refresh()
vim.api.nvim_win_set_cursor(0, { 4, 0 })
code.cursor_moved()
shot 'code-note'
local s, x = review.step(r, 2)
go.open('page', { review = r, tour = x, step = s })
shot 'step'
H.press '<Esc>'
go.open('map', {})
shot 'map'
H.press 'q'

-- A walk.
go.open('walk', { review = r, tour = r.tours[1] })
shot 'briefing'
H.press 'L'
shot 'code-step'
H.press 'M'
shot 'walk-map'
H.press 'q'
H.press 'q'

shots.finish 'surfaces'
