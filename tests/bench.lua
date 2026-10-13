-- How long the code takes to draw a big file under many threads: 20 000
-- lines, three open reviews of twenty threads, each with a tour of ten
-- steps. Not part of `make check`; run `make bench` after changing code/
-- or what it asks of model/. LINES=2000 for a smaller file.

local H = require 'tests.helpers'
H.reset()
H.mute()
vim.o.columns, vim.o.lines = 160, 50
local N = tonumber(vim.env.LINES or '') or 20000
local lines = {}
for i = 1, N do
  lines[i] = string.format('local v%05d = compute(%d) -- line %d', i, i, i)
end
H.repo { ['big.lua'] = lines }
require('thread').setup { rebuild = true }
local code = require 'thread.code'
local k = 0
for ri = 1, 3 do
  local threads = {}
  for ti = 1, 20 do
    local steps = {}
    for si = 1, 10 do
      k = k + 1
      local l = (k * 37) % N + 1
      steps[si] = { id = si, title = 'step ' .. si, text = 's', chunk = { file = 'big.lua', line = l, text = lines[l] }, messages = {} }
    end
    k = k + 1
    local l = (k * 53) % N + 1
    local tours = { { title = 'T', steps = steps } }
    threads[ti] = {
      id = ti,
      title = 'thread ' .. ti,
      chunk = { file = 'big.lua', line = l, text = lines[l] },
      messages = { { from = 'agent', text = 'a tour', tours = tours } },
    }
  end
  H.review('r' .. ri, { title = 'R' .. ri, threads = threads })
end
vim.cmd.edit 'big.lua'
---@param f fun()
---@return number
local function ms(f)
  local t = vim.uv.hrtime()
  f()
  return (vim.uv.hrtime() - t) / 1e6
end
code.refresh()
local buf = vim.api.nvim_get_current_buf()
local on = require('thread.code.place').locate(buf)[1].line
print(string.format('%d lines, 660 chunks', N))
print(string.format('refresh:               %6.1f ms', ms(code.refresh)))
vim.api.nvim_win_set_cursor(0, { on, 0 })
print(string.format('onto a thread:         %6.1f ms', ms(code.cursor_moved)))
vim.api.nvim_win_set_cursor(0, { on + 1, 0 })
print(string.format('off it:                %6.1f ms', ms(code.cursor_moved)))
vim.api.nvim_buf_set_lines(buf, 0, 0, false, { '-- edited' })
print(string.format('refresh after an edit: %6.1f ms', ms(code.refresh)))
vim.cmd 'qa!'
