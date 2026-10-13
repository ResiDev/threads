-- How today's screens label things (thread.legacy.labels): glyphs and badges.

local R = require 'tests.runner'
local config = require 'thread.config'
local labels = require 'thread.legacy.labels'

R.test('verdict, kind and risk badges', function()
  local v = labels.verdict_of { messages = { { from = 'agent', text = 'x', verdict = 'risk', severity = 'low' } } }
  R.eq(v, { text = 'RISK · low', hl = 'ThreadVerdictWarn' })
  R.eq(labels.verdict_of { messages = { { from = 'agent', text = 'x' } } }, nil, 'no verdict')
  R.eq(labels.kind_badge 'fix', { ' fix ', 'ThreadVerdictBad' })
  R.eq(labels.kind_badge 'other', { ' other ', 'ThreadKindQuiet' }, 'an unknown kind is quiet')
  R.eq(labels.risk('high', true), { '●', 'ThreadRiskHigh' })
  R.eq(labels.risk 'low', { '○ low risk', 'ThreadRiskLow' })
end)

R.test('glyphs without nerd font icons', function()
  local icons = config.options.ui.icons
  config.options.ui.icons = false
  R.eq({ labels.glyph('answered', true) }, { '●', 'ThreadSignAnswered' })
  R.eq({ labels.glyph 'waiting' }, { '◔', 'ThreadSignWaiting' })
  R.eq({ labels.glyph('open', false, true) }, { '!', 'DiagnosticWarn' }, 'a line that is gone')
  R.eq({ labels.label({ from = 'agent' }, true) }, { '△', 'ThreadAgentNew' })
  config.options.ui.icons = icons
end)
