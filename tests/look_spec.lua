-- How things are marked: keys as hints, note numbers, the colours.

local R = require 'tests.runner'
local look = require 'thread.ui.look'

R.test('keys as hints and as a footer', function()
  local list = { { 'j/k', 'move' }, { 'q', 'quit' } }
  R.eq(look.hints(list), {
    { 'j/k', 'ThreadKey' },
    { ' move', 'ThreadKeyLabel' },
    { '  ', 'ThreadKeyLabel' },
    { 'q', 'ThreadKey' },
    { ' quit', 'ThreadKeyLabel' },
  })
  local foot = look.footer(list)
  R.eq(foot[1], { ' ' }, 'a space before')
  R.eq(foot[#foot], { ' ' }, 'and after')
  R.eq(look.num(3), '③')
  R.eq(look.num(21), '(21)')
end)

R.test("the colours borrow the colorscheme's own groups", function()
  vim.api.nvim_set_hl(0, 'Comment', { fg = 0x123456 })
  vim.api.nvim_set_hl(0, 'NonText', { fg = 0x654321 })
  R.eq(require('thread.ui.theme').palette().muted, 0x123456, "muted is your comments' colour")
end)
