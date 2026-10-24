--- Every drawer over a whole review, and drawing plainly, for the tests
--- that draw all of one: tests/draws_spec.lua and tests/fuzz.lua.

local H = require 'tests.helpers'

local config = require 'thread.config'
local contract_draw = require 'thread.draw.contract'
local contracts_draw = require 'thread.draw.contracts'
local draw = require 'thread.draw'
local note_draw = require 'thread.draw.note'
local review_draw = require 'thread.draw.review'
local sheet = require 'thread.ui.sheet'
local step_draw = require 'thread.draw.step'
local tabs = require 'thread.screen.tabs'
local touch = require 'thread.model.touch'
local tour_draw = require 'thread.draw.tour'

local M = {}

--- A review drawn by every drawer, each under a heading of its own,
--- `width` columns wide: its line; each of its tabs, and each with every
--- part opened; each contract's row and page; each tour's line,
--- outline, briefing and section; each step's line, block, card and
--- whole; each note's row, line, card and whole.
---@param r thread.Review
---@param width integer
---@return string[] lines, thread.Sheet sheet  the sheet too, to put in a buffer
function M.drawn(r, width)
  local P = sheet.new()
  local o = { width = width }
  ---@param what string
  local function heading(what)
    if #P.lines > 0 then
      P.add ''
    end
    P.add('==== ' .. what)
  end
  heading 'line'
  review_draw.line(P, r, o)
  local T = touch.index(r)
  for _, tab in ipairs(tabs.LIST) do
    heading('tab ' .. tab.id)
    tab.draw(P, r, { indent = 0, width = width, open = {}, touches = T })
  end
  -- Opened: every tour and step, and on a tab whose items open under
  -- the cursor, its first.
  local open = {} ---@type table<string, true>
  for _, x in ipairs(r.tours) do
    open[draw.key { kind = 'tour', first = 0, last = 0, tour = x }] = true
    for _, s in ipairs(x.steps) do
      open['step:' .. s.id] = true
    end
  end
  local first = {
    note = r.notes[1] and draw.key { kind = 'note', first = 0, last = 0, note = r.notes[1] },
    tour = r.tours[1] and draw.key { kind = 'tour', first = 0, last = 0, tour = r.tours[1] },
    contract = r.contracts[1] and draw.key { kind = 'contract', first = 0, last = 0, contract = r.contracts[1] },
  }
  for _, tab in ipairs(tabs.LIST) do
    heading('tab ' .. tab.id .. ', every part opened')
    tab.draw(P, r, { indent = 0, width = width, open = open, here = tab.noun and first[tab.noun] or nil, touches = T })
  end
  heading 'contracts'
  contracts_draw.draw(P, r.contracts, { width = width, all = true, review = r })
  for _, c in ipairs(r.contracts) do
    heading('contract ' .. c.id)
    contract_draw.page(P, r, c, o)
  end
  for place, x in ipairs(r.tours) do
    heading('tour ' .. place)
    tour_draw.line(P, r, x, { width = width, place = place })
    tour_draw.outline(P, r, x, { width = width, place = place, here = x.steps[1] })
    heading('tour ' .. place .. ', briefing')
    tour_draw.briefing(P, r, x, { width = width, place = place })
    heading('tour ' .. place .. ', row and steps')
    tour_draw.head(P, r, x, { width = width, indent = 0, place = place })
    tour_draw.steps(P, r, x, { width = width - 3, indent = 3, place = place })
    for _, s in ipairs(x.steps) do
      heading('step ' .. s.id)
      step_draw.line(P, r, x, s, o)
      heading('step ' .. s.id .. ', card')
      step_draw.card(P, r, x, s, o)
      heading('step ' .. s.id .. ', whole')
      step_draw.whole(P, r, x, s, o)
    end
  end
  for _, n in ipairs(r.notes) do
    heading('note ' .. n.id)
    note_draw.row(P, r, n, o)
    note_draw.line(P, r, n, o)
    heading('note ' .. n.id .. ', card')
    note_draw.card(P, r, n, o)
    heading('note ' .. n.id .. ', whole')
    note_draw.whole(P, r, n, { width = width, code = true })
  end
  return P.lines, P
end

--- The rows of `lines` wider than `width`, headings aside.
---@param lines string[]
---@param width integer
---@return string[]
function M.wide(lines, width)
  return vim.tbl_filter(function(l)
    return vim.fn.strdisplaywidth(l) > width and not l:find '^===='
  end, lines)
end

--- `fn` with plain shapes for icons and the time held still.
---@param fn fun()
function M.plainly(fn)
  local restore = H.freeze_time '2026-10-14T09:00:00'
  local icons = config.options.ui.icons
  config.options.ui.icons = false
  local ok, err = pcall(fn)
  config.options.ui.icons = icons
  restore()
  if not ok then
    error(err, 0)
  end
end

return M
