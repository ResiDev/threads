-- How things are marked: glyphs, badges, keys as hints.

local R = require 'tests.runner'
local config = require 'thread.config'
local look = require 'thread.ui.look'

R.test('verdict, kind and risk badges', function()
  local v = look.verdict_of { messages = { { from = 'agent', text = 'x', verdict = 'risk', severity = 'low' } } }
  R.eq(v, { text = 'RISK · low', hl = 'ThreadVerdictWarn' })
  R.eq(look.verdict_of { messages = { { from = 'agent', text = 'x' } } }, nil, 'no verdict')
  R.eq(look.kind_badge 'fix', { ' fix ', 'ThreadVerdictBad' })
  R.eq(look.kind_badge 'other', { ' other ', 'ThreadKindQuiet' }, 'an unknown kind is quiet')
  R.eq(look.risk('high', true), { '●', 'ThreadRiskHigh' })
  R.eq(look.risk 'low', { '○ low risk', 'ThreadRiskLow' })
end)

R.test('glyphs without nerd font icons', function()
  local icons = config.options.ui.icons
  config.options.ui.icons = false
  R.eq({ look.glyph('answered', true) }, { '●', 'ThreadSignAnswered' })
  R.eq({ look.glyph 'waiting' }, { '◔', 'ThreadSignWaiting' })
  R.eq({ look.glyph('open', false, true) }, { '!', 'DiagnosticWarn' }, 'a line that is gone')
  R.eq({ look.label({ from = 'agent' }, true) }, { '△', 'ThreadAgentNew' })
  config.options.ui.icons = icons
end)

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
