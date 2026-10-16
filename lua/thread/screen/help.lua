--- What the screen's signs mean and what its keys do, in a float over it.

local float = require 'thread.ui.float'
local labels = require 'thread.draw.labels'
local sheet = require 'thread.ui.sheet'
local text = require 'thread.base.text'

local M = {}

local ns = vim.api.nvim_create_namespace 'thread.screen.help'

-- What each key does, at each depth it acts.
local KEYS = {
  { 'j / k', 'the next / previous item: a tour, a step, a note, a file, a chunk' },
  { '} / {', 'the next / previous section: a review at Home, a tour or a kind of note in a review, a file' },
  {
    'tab',
    'fold: at Home, each review’s first three of what wants you, all of it, or none; in a review, on a tour that tour, on the tours’ rule every tour, on a contract the whole list, on a kind of note its settled notes, on a step or a chunk every chunk’s code, elsewhere the introduction',
  },
  { 'o', 'open the item and read it line by line; o, tab or Esc again goes back to items' },
  {
    'J / ⏎',
    'down a level, into what is under the cursor: a review, a note’s page, a contract’s page, a link, a line of code, a tour or a step to walk from',
  },
  { 'K / -', 'up a level: a note, a contract, a step or a briefing to its review, a review to Home' },
  { 'f', 'a review’s chunks by file, what each says under it; again by tour' },
  { 'r', 'reply in the note, the step or the contract you are on' },
  { 'a', 'accept its chunk, which folds its code away; on a tour, every step’s chunk; again takes it back' },
  { 'c', 'settle the note, saying how by its kind, or open it again; on a review’s line, close the review' },
  { 'space', 'mark notes in a review: then r, a and c act on each' },
  { 'n', 'a new note: on the line of code under the cursor, else on no line' },
  { 'w / b', 'the next / previous link, or name in backticks, in the text' },
  { 't', 'walk a tour in the code, from its briefing, or from where you left off' },
  { 'p', 'a step’s page' },
  { 'L / H', 'the next / previous note, contract or step; from a briefing, its first step' },
  { '/', 'Home: only what mentions something; Esc clears it' },
  { 'C', 'Home: the closed reviews; again, the open ones' },
  { 'N', 'Home: a new review' },
  { 'q / Esc', 'close' },
}

-- Columns the keys take, before what each does.
local KEY = 10

-- The help is this wide at most, so a description reads as lines, not one
-- row across the screen.
local WIDEST = 96

--- The help, written into a sheet `width` wide: each description wrapped
--- under itself, so none runs past the float's edge.
---@param width integer
---@return thread.Sheet
local function content(width)
  local P = sheet.new { indent = 4 }
  ---@param s string
  local function head(s)
    P.add ''
    P.chunks({ { s, 'ThreadTitle' } }, 2)
  end
  head 'Whose move'
  for _, g in ipairs {
    { { labels.state(false, 'you', true) }, 'your move, something new in it' },
    { { labels.state(false, 'you', false) }, 'your move' },
    { { labels.state(false, 'agent', false) }, "the agent's move: it has your message" },
    { { labels.state(false, nil, true) }, 'nobody’s move, something new: the agent explaining' },
    { { labels.state(false, nil, false) }, 'nobody’s move, all read: no mark' },
    { { labels.state(true, nil, false) }, 'settled' },
  } do
    local glyph, hl = g[1][1], g[1][2]
    P.chunks { { glyph, hl }, { '  ' .. g[2], 'ThreadKeyLabel' } }
  end
  head 'Keys'
  -- The float's border and a column either side of the text.
  local room = math.max(20, width - 4 - KEY - 2)
  for _, k in ipairs(KEYS) do
    for i, row in ipairs(text.wrap(k[2], room)) do
      P.chunks { { text.pad(i == 1 and k[1] or '', KEY), 'ThreadKey' }, { row, 'ThreadKeyLabel' } }
    end
  end
  P.add ''
  return P
end

--- Open the help over the screen; `done` runs once it closes.
---@param _ thread.ScreenState
---@param done fun()
function M.open(_, done)
  local P = content(math.min(WIDEST, vim.o.columns - 4))
  local width = 0
  for _, l in ipairs(P.lines) do
    width = math.max(width, text.width(l) + 2)
  end
  local win ---@type integer
  local function close()
    if vim.api.nvim_win_is_valid(win) then
      float.close(win)
      done()
    end
  end
  local keys = {} ---@type table<string, fun()>
  for _, lhs in ipairs { 'q', '?', '<Esc>', '<CR>' } do
    keys[lhs] = close
  end
  local cfg = float.centred(width, #P.lines)
  local buf
  win, buf = float.open { win = vim.tbl_extend('force', cfg, { title = ' Help ', title_pos = 'center', zindex = 60 }), keys = keys, on_leave = close }
  P.apply(buf, ns)
end

return M
