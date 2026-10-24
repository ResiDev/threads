--- What the screen's signs mean and what its keys do, in a float over it.

local help = require 'thread.ui.help'
local labels = require 'thread.draw.labels'

local M = {}

-- What each key does, at each depth it acts.
local KEYS = {
  { 'j / k', 'the next / previous item: a tour, a step, a note, a file, a chunk' },
  { '} / {', 'the next / previous section: a review at Home, a tour or a section of Notes in a review, a file' },
  {
    'tab',
    'fold: at Home, each review’s first three of what wants you, all of it, or none; on a contract’s page, it against as it was',
  },
  { 'o', 'open the item and read it line by line; o, tab or Esc again goes back to items' },
  {
    'J / ⏎',
    'down a level, into what is under the cursor: a review, a note’s page, a contract’s page, a link, a line of code, a tour or a step to walk from',
  },
  { 'K / -', 'up a level: a note, a contract, a step or a briefing to its review, a review to Home' },
  { 'r', 'reply in the note, the step or the contract you are on' },
  { 'a', 'accept its chunk, which folds its code away; on a tour, every step’s chunk; again takes it back' },
  { 's', 'settle the note, saying how by its kind, or open it again; on a review’s line, close the review' },
  { 'space', 'mark notes in a review: then r, a and s act on each' },
  { 'n', 'a new note: on the line of code under the cursor, else on no line' },
  { 'w / b', 'the next / previous link, or name in backticks, in the text' },
  { 't', 'walk a tour in the code, from its briefing, or from where you left off; on a page, to a tour its prose places' },
  { 'c', 'on a page, to a contract its prose places; ⏎ there opens it' },
  { 'p', 'a step’s page' },
  { 'L / H', 'in a review, the next / previous tab; on a page, the next / previous note, contract or step; from a briefing, its first step' },
  { '/', 'Home: only what mentions something; Esc clears it' },
  { 'C', 'Home: the closed reviews; again, the open ones' },
  { 'N', 'Home: a new review' },
  { 'q / Esc', 'close' },
}

--- Open the help over the screen; `done` runs once it closes.
---@param _ thread.ScreenState
---@param done fun()
function M.open(_, done)
  local signs = {} ---@type thread.Chunks[]
  for _, g in ipairs {
    { { labels.state(false, 'you', true) }, 'your move, something new in it' },
    { { labels.state(false, 'you', false) }, 'your move' },
    { { labels.state(false, 'agent', false) }, "the agent's move: it has your message" },
    { { labels.state(false, nil, true) }, 'nobody’s move, something new: the agent explaining' },
    { { labels.state(false, nil, false) }, 'nobody’s move, all read: no mark' },
    { { labels.state(true, nil, false) }, 'settled' },
  } do
    local glyph, hl = g[1][1], g[1][2]
    signs[#signs + 1] = { { glyph, hl }, { '  ' .. g[2], 'ThreadKeyLabel' } }
  end
  help.open('Help', { { head = 'Whose move', lines = signs }, { head = 'Keys', rows = KEYS } }, done)
end

return M
