--- What the glyphs mean and what every key does, in a float over Home.

local float = require 'thread.ui.float'
local labels = require 'thread.legacy.labels'
local sheet = require 'thread.ui.sheet'
local text = require 'thread.base.text'

local M = {}

local ns = vim.api.nvim_create_namespace 'thread.home.help'

local KEYS = {
  {
    'Moving',
    {
      { 'j / k', 'next / previous thread' },
      { 'H / L', 'the tab to the left / right (also tab / S-tab)' },
      { '1 2', 'threads · tours' },
      { '3 4', 'the review of a diff · closed' },
      { 'h / l', 'less / more of the history' },
      { 'o', 'open the thread: j/k step through it, o or Esc back' },
      { '', "in review: j/k go from review to review, o into one's groups" },
      { 'w / b', 'inside: next / previous underlined name; ⏎ shows its code' },
      { '', 'n its next match, + / - more or fewer lines of it' },
      { '+ / -', 'more or less of its code, up to the whole function' },
      { 'J', 'walk the tour its answer leads to, or the one it is in, from where you left off' },
      { 'h / l', 'in the float: the threads either side' },
      { '/', 'show only threads that mention something; Esc clears' },
      { 'g', 'group by file, by whose turn, or by round' },
    },
  },
  {
    'Acting',
    {
      { 'r', 'reply here: <C-s> saves, <C-c> cancels' },
      { 'c', 'close, or reopen a closed one; a tour or a review too' },
      { 'space', 'mark threads: then c and r act on all of them' },
      { '⏎', 'go to the code, or the place a change is; on a stop walk from it;' },
      { '', "on a diagram box its code; in review a group's page" },
      { 'a / d', 'review: accept a group / pick the diff to review' },
      { 'u', 'on a change: what undoing it puts back; again, undo it' },
      { 'B', 'the batches' },
      { 'q / Esc', 'close Home' },
    },
  },
}

--- The help, written into a sheet.
local function content(single)
  local P = sheet.new { indent = 4 }
  local function head(s)
    P.add ''
    P.chunks({ { s, 'ThreadTitle' } }, 2)
  end
  local function legend(g, hl, what)
    P.chunks { { g, hl }, { '  ' .. what, 'ThreadKeyLabel' } }
  end
  head 'Whose move'
  for _, g in ipairs {
    { labels.glyph('answered', true), 'ThreadSignAnswered', 'your move: the agent answered, something new in it' },
    { labels.glyph 'answered', 'ThreadSignAnswered', 'your move: read, yours to reply or close' },
    { labels.glyph 'waiting', 'ThreadSignWaiting', "the agent's move: it has your message" },
    { labels.glyph('info', true), 'ThreadSignInfoNew', 'a tour or explanation the agent started, new' },
    { labels.glyph 'info', 'ThreadSignInfo', "a tour or explanation, read; nobody's move" },
    { '▶', 'ThreadLeads', 'its answer leads to a tour you can walk' },
    { '▸', 'ThreadSignInfo', "in the code's margin: a tour's stop; ▎ is a thread" },
    { labels.glyph 'closed', 'ThreadSignDone', 'closed' },
    { '!', 'DiagnosticWarn', 'its line is gone from the file' },
  } do
    legend(g[1], g[2], g[3])
  end
  P.chunks {
    { 'deep blue', 'ThreadSignAnswered' },
    { ' is your move, ', 'ThreadKeyLabel' },
    { 'pink', 'ThreadSignWaiting' },
    { " the agent's, ", 'ThreadKeyLabel' },
    { 'light blue', 'ThreadSignInfoNew' },
    { ' a tour', 'ThreadKeyLabel' },
  }
  head 'Who said what'
  for _, w in ipairs { { { from = 'you' }, 'you' }, { { from = 'agent' }, 'the agent' }, { { from = 'agent' }, 'the agent, not read yet (lit)', true } } do
    local g, hl = labels.who(w[1], w[3])
    legend(g, hl, w[2])
  end
  P.chunks { { 'the last five messages show as these shapes, oldest first', 'ThreadKeyLabel' } }
  P.chunks { { '+2', 'ThreadAdded' }, { ' ' }, { '−1', 'ThreadRemoved' }, { '  how the code there changed since you sent it', 'ThreadKeyLabel' } }
  for _, section in ipairs(KEYS) do
    head(section[1])
    for _, k in ipairs(section[2]) do
      local what = k[1] == 'q / Esc' and single and 'back to the code' or k[2]
      P.chunks { { text.pad(k[1], 12), 'ThreadKey' }, { what, 'ThreadKeyLabel' } }
    end
  end
  P.add ''
  return P
end

--- Open the help over Home; `done` runs once it closes.
---@param single boolean  Home is a thread focused from the code
---@param done fun()
function M.open(single, done)
  local P = content(single)
  local width = 0
  for _, l in ipairs(P.lines) do
    width = math.max(width, text.width(l) + 2)
  end
  local win
  local function close()
    if vim.api.nvim_win_is_valid(win) then
      float.close(win)
      done()
    end
  end
  local keys = {}
  for _, lhs in ipairs { 'q', '?', '<Esc>', '<CR>' } do
    keys[lhs] = close
  end
  local cfg = float.centred(width, #P.lines)
  cfg.title, cfg.title_pos, cfg.zindex = ' Help ', 'center', 60
  local buf
  win, buf = float.open { win = cfg, keys = keys, on_leave = close }
  P.apply(buf, ns)
end

return M
