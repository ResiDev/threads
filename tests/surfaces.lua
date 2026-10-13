-- The rebuild's surfaces as text, on the reviews agents wrote
-- (tests/reviews/) and the code they are about (9cde8c4): each window,
-- its lines and its marks, then the screen. Compared with
-- tests/surfaces/<name>.txt; `make surfaces` checks, `UPDATE=1 make
-- surfaces` writes them. Read a diff before writing it.

local H = require 'tests.helpers'

vim.o.columns, vim.o.lines = 120, 40
vim.o.signcolumn = 'yes:2'
H.mute()
H.freeze_time '2026-10-14T09:00:00'

local root = vim.fn.tempname()
H.git(H.root, { 'clone', '-q', '--shared', '--no-checkout', H.root, root })
H.git(root, { 'checkout', '-q', '9cde8c4' })
vim.fn.mkdir(root .. '/.threads', 'p')
vim.fn.writefile({ '/.threads/' }, root .. '/.git/info/exclude', 'a')
for _, path in ipairs(vim.fn.globpath(H.root, 'tests/reviews/*.json', false, true)) do
  vim.fn.writefile(vim.fn.readfile(path), root .. '/.threads/' .. vim.fs.basename(path))
end
vim.cmd('cd ' .. vim.fn.fnameescape(root))

require('thread.config').setup { rebuild = true, ui = { icons = false } }
local go = require 'thread.go'
local review = require 'thread.model.review'
local thread = require 'thread.model.thread'
require 'thread.screen'
require 'thread.compose'

local shots = require('tests.capture').new(H.root .. '/tests/surfaces', root)
local shot = shots.shot

local skill = assert(review.read 'the-skill-on-format-2-and-stage-2-fixes')

go.open('home', {})
shot 'home'
H.press 'j'
H.press 'j'
H.press 'j'
H.press 'j'
H.press 'j'
H.press 'j'
shot 'home-second-review'
H.press '?'
shot 'home-help'
H.press 'q'
H.press 'q'

go.open('review', { review = skill })
shot 'review'
go.open('thread', { review = skill, thread = skill.threads[2] })
shot 'thread'
H.press 'r'
shot 'compose-reply'
H.press '<Esc>'
H.press 'q'

vim.cmd.edit 'skills/answering-threads/show.lua'
vim.api.nvim_win_set_cursor(0, { 56, 0 })
go.open('focus', { review = skill, thread = skill.threads[1] })
shot 'focus'
H.press '<Esc>'

local t = skill.threads[1]
local s, x = thread.step(t, 3)
go.open('page', { review = skill, thread = t, tour = x, step = s })
shot 'page'
H.press '<Esc>'

shots.finish 'surfaces'
