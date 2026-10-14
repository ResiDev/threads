--- What the screen's signs mean and what its keys do, in a float over it.

local float = require 'thread.ui.float'
local labels = require 'thread.draw.labels'
local sheet = require 'thread.ui.sheet'
local text = require 'thread.base.text'

local M = {}

local ns = vim.api.nvim_create_namespace 'thread.screen.help'

-- What each key does, at each depth it acts.
local KEYS = {
  { 'j / k', 'the next / previous item: a thread, a step, a file, a chunk' },
  { '} / {', 'the next / previous section: a review at Home, a group in a review, a tour in a thread, a file' },
  {
    'tab',
    'fold: at Home, each review’s first three threads, all of them, or none; in a review, on a group’s heading that group, a tree or a card, elsewhere every group; on a contract, the whole list; in a thread, on a tour that tour, a row or a tree, on the tours’ rule every tour, on a message every message, on a chunk every chunk’s code',
  },
  { 'o', 'open the item and read it line by line; o, tab or Esc again goes back to items' },
  { 'J / ⏎', 'down a level, into what is under the cursor: a review, a thread, a group’s first thread, a link, a line of code, a step to walk from' },
  { 'K / -', 'up a level: a step to its thread, a thread to its review, a review to Home' },
  { 'f', 'a review’s or a thread’s chunks by file, what each says under it; again by thread' },
  { 'r', 'reply in the thread or the step you are on' },
  { 'a', 'accept its chunk, which folds its code away; on a thread’s head, every chunk in it; again takes it back' },
  { 'c', 'close the thread, saying how, or open it again, wherever in it you are; on a review’s line, the review' },
  { 'space', 'mark threads in a list: then r, a and c act on each' },
  { 'n', 'a new thread: on the line of code under the cursor, else on no line' },
  { 'w', 'walk the thread’s tour in the code, from where you left off' },
  { 'p', 'a step’s page' },
  { 'L / H', 'the next / previous thread; in a step’s page, the next / previous step' },
  { '/', 'Home: only what mentions something; Esc clears it' },
  { 'C', 'Home: the closed reviews; again, the open ones' },
  { 'N', 'Home: a new review' },
  { 'q / Esc', 'close' },
}

--- The help, written into a sheet.
---@return thread.Sheet
local function content()
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
    { { labels.state(false, nil, false) }, 'nobody’s move' },
    { { labels.state(true, nil, false) }, 'closed' },
  } do
    local glyph, hl = g[1][1], g[1][2]
    P.chunks { { glyph, hl }, { '  ' .. g[2], 'ThreadKeyLabel' } }
  end
  head 'Keys'
  for _, k in ipairs(KEYS) do
    P.chunks { { text.pad(k[1], 10), 'ThreadKey' }, { k[2], 'ThreadKeyLabel' } }
  end
  P.add ''
  return P
end

--- Open the help over the screen; `done` runs once it closes.
---@param _ thread.ScreenState
---@param done fun()
function M.open(_, done)
  local P = content()
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
  local cfg = float.centred(math.min(width, vim.o.columns - 4), #P.lines)
  local buf
  win, buf = float.open { win = vim.tbl_extend('force', cfg, { title = ' Help ', title_pos = 'center', zindex = 60 }), keys = keys, on_leave = close }
  P.apply(buf, ns)
end

return M
