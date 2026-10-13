-- Code: the scope around a line.

local R = require 'tests.runner'

local function tree(lines, lang)
  return vim.treesitter.get_string_parser(table.concat(lines, '\n'), lang):parse()[1]:root()
end

R.test('code.enclosing: a call is not a scope', function()
  local root = tree({ 'local function outer()', '  print(1)', '  helper(', '    2', '  )', 'end' }, 'lua')
  R.eq({ require('thread.base.code').enclosing(root, 4, 4) }, { 1, 6 }, 'the function around the call')
end)

R.test('code.enclosing: nothing around top-level code', function()
  local root = tree({ 'local x = 1', 'print(x)' }, 'lua')
  R.eq({ require('thread.base.code').enclosing(root, 2, 2) }, {}, 'no scope')
end)

R.test('dimming: a thread on a call keeps the whole function lit', function()
  local H = require 'tests.helpers'
  H.reset()
  H.repo { ['a.lua'] = { 'local x = 1', '', 'local function outer()', '  print(1)', '  helper(', '    2', '  )', 'end', '', 'return x' } }
  H.batch { { id = 1, file = 'a.lua', line = 6, text = '    2', status = 'open', messages = { { from = 'you', text = 'why 2?' } } } }
  vim.cmd.edit 'a.lua'
  vim.api.nvim_win_set_cursor(0, { 6, 0 })
  local render = require 'thread.legacy.render'
  render.dim()
  H.settle()
  local dimmed = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, render.ns, 0, -1, { details = true })) do
    if m[4].hl_group == 'ThreadDim' then
      dimmed[#dimmed + 1] = { m[2], m[4].end_row }
    end
  end
  render.dim()
  R.eq(dimmed, { { 0, 2 }, { 8, 10 } }, 'dimmed rows: before and after outer()')
end)
