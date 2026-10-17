-- thread.nvim alone, as `make view` drives it with CONFIG=clean: from this
-- checkout, set up with its defaults, the code coloured as an editor
-- colours it, and your leader.
local here = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(here)
vim.g.mapleader = ' '
vim.o.termguicolors = true
vim.o.number = true
vim.o.signcolumn = 'yes'
vim.cmd 'filetype plugin indent on'
vim.cmd 'syntax on'
vim.cmd 'runtime plugin/thread.lua'
require('thread').setup {}
