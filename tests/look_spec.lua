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

R.test("a name lit in the code keeps its own colour, lifted, on ThreadNamed's wash; one with none is ThreadNamed", function()
  local theme = require 'thread.ui.theme'
  vim.o.background = 'dark'
  vim.api.nvim_set_hl(0, 'Normal', { fg = 0xc0caf5, bg = 0x1e2030 })
  theme.apply()
  local group = theme.named(0x7aa2f7)
  local def = vim.api.nvim_get_hl(0, { name = group, link = false })
  R.eq(def.fg, theme.blend(0xffffff, 0x7aa2f7, theme.LIFT), 'lifted towards white on dark')
  R.eq({ def.bg, def.bold }, { vim.api.nvim_get_hl(0, { name = 'ThreadNamed' }).bg, true }, 'the wash and bold of ThreadNamed')
  R.eq(theme.named(0x7aa2f7), group, 'one group a colour')
  R.eq(theme.named(nil), 'ThreadNamed', 'no colour: ThreadNamed')
end)
