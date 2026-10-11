local here = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(here)
package.path = here .. '/?.lua;' .. package.path
vim.g.mapleader = ' '
vim.cmd('runtime plugin/thread.lua')
