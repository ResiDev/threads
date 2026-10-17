--- Walking: going through a tour a step at a time. It opens on the
--- tour's briefing, a float saying what the steps are for; a step on code
--- is its card in the code, whole, and its review's diff drawn in; a step
--- on no line, or whose lines are gone, is its page, the screen in a
--- float. While a walk is on, its keys (config `walk`) lie over yours: `L`
--- and `H` the next and previous step, `H` from the first back to the
--- briefing, `B` the briefing from any step; and the code window's
--- winbar says where you are. Ending it puts both back.
---
--- In the code, the names a step's text puts in backticks are lit in its
--- chunk; and two things are on as a walk starts, each turned off and on
--- again for the rest of it: dim (`gz`), the code but the step's chunk
--- dimmed; and its review's diff drawn in (`<leader>hg`). `go` goes into
--- the step's card, to follow its links; `gw` goes in on the first.

local chunk = require 'thread.model.chunk'
local config = require 'thread.config'
local conversation = require 'thread.model.conversation'
local go = require 'thread.go'
local help = require 'thread.ui.help'
local keys = require 'thread.ui.keys'
local labels = require 'thread.draw.labels'
local look = require 'thread.ui.look'
local review = require 'thread.model.review'
local step = require 'thread.model.step'
local text = require 'thread.base.text'
local tour = require 'thread.model.tour'

local M = {}

---@class thread.Walk : thread.Walking
---@field win integer   the code window
---@field keys thread.Overlay|nil
---@field bar string|nil  the code window's winbar before

local W ---@type thread.Walk|nil

---@param msg string
local function say(msg)
  vim.notify('thread: ' .. msg)
end

--- The walk's review, tour and step, read afresh; nil once the review or
--- the tour has gone, the step nil on the briefing or once it has gone.
---@return thread.Review|nil, thread.Tour|nil, thread.Step|nil
local function at()
  if not W then
    return nil
  end
  local r = review.read(W.review)
  local x = r and r.tours[W.tour]
  if not (r and x) then
    return nil
  end
  local s = W.step and review.step(r, W.step) or nil
  return r, x, s
end

--- Where the walk is, for the code to draw.
---@return thread.Walking|nil
function M.state()
  return W and { review = W.review, tour = W.tour, step = W.step, dim = W.dim, diff = W.diff, removed = W.removed } or nil
end

--- The keys a walk is for, as its bar and the step's card list them, the
--- card the one that goes into it too; its others work unsaid (KEYS.md).
--- On a step whose lines the diff removed, the diff stays drawn turned
--- off, and says so.
---@param card boolean
---@return { [1]: string, [2]: string }[]
local function hints(card)
  local w = assert(W)
  local k = config.options.walk
  local diff = w.removed and not w.diff and 'diff kept' or look.toggle('diff', w.diff)
  local show = look.show_key
  local on = w.step ~= nil
  local out = {}
  for _, h in ipairs {
    { on and k.next and k.prev and (show(k.next) .. '/' .. show(k.prev)), 'next/prev' },
    { not on and show(k.next), 'next' },
    { card and show(k.enter), 'enter' },
    { on and show(k.dim), look.toggle('dim', w.dim) },
    { on and show(config.options.mappings.diff), diff },
    { show(k.help), 'keys' },
    { show(k.quit), 'end' },
  } do
    if h[1] then
      out[#out + 1] = h
    end
  end
  return out
end

---@param s string
---@return string
local function esc(s)
  return (s:gsub('%%', '%%%%'))
end

--- The winbar: the review, the tour and the step, its track, how far,
--- and the keys a walk is for.
---@return string
function M.bar()
  local r, x, s = at()
  if not (r and x) then
    return ''
  end
  local parts = { '%#ThreadWalkBar# ▶ ', esc(text.fit(r.title, 28)), ' › ', esc(text.fit(x.title, 24)), '%<' }
  local here = s and s.title or 'briefing'
  parts[#parts + 1] = ' › %#ThreadWalkBarHere#' .. esc(text.fit(here, 40)) .. '%#ThreadWalkBar#  '
  local hl = { ThreadLeads = 'ThreadWalkBarHere', ThreadTitle = 'ThreadWalkBarKey', ThreadMeta = 'ThreadWalkBar' }
  for _, c in ipairs(labels.track(r, x, s)) do
    parts[#parts + 1] = '%#' .. (hl[c[2]] or 'ThreadWalkBar') .. '#' .. esc(c[1])
  end
  local n = 0
  for i, other in ipairs(x.steps) do
    n = other == s and i or n
  end
  parts[#parts + 1] = '%#ThreadWalkBar# ' .. (s and ('step ' .. n .. '/' .. #x.steps) or (#x.steps .. ' steps')) .. '   %='
  for _, key in ipairs(hints(false)) do
    parts[#parts + 1] = '%#ThreadWalkBarKey#' .. esc(key[1]) .. '%#ThreadWalkBar# ' .. key[2] .. '  '
  end
  return table.concat(parts)
end

-- The winbar is an expression, so it follows the walk without being set
-- again.
local BAR = "%{%v:lua.require'thread.walk'.bar()%}"

--- A window to show code in: the walk's own, else one that is not a float.
---@return integer
local function code_win()
  if W and vim.api.nvim_win_is_valid(W.win) then
    return W.win
  end
  local cur = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_config(cur).relative == '' then
    return cur
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(win).relative == '' then
      return win
    end
  end
  return cur
end

--- Whether a key the walk lays over yours is meant here: in the code
--- window, or the float of a step's page or a briefing, as the screen
--- answers `page`; elsewhere, Home too, it is your own.
---@return boolean
local function in_walk()
  if W ~= nil and vim.api.nvim_get_current_win() == W.win then
    return true
  end
  local page = go.ask 'page'
  return page ~= nil and page == vim.api.nvim_get_current_buf()
end

--- What was shown of the step you leave is read.
local function leave()
  local r, x, s = at()
  if r and x and s and #s.messages > 0 then
    conversation.mark_read(r, conversation.of_step(s, x))
  end
end

--- Show where the walk is: the briefing in a float; a step's card in the
--- code, or its page.
local function show()
  local w = assert(W)
  local r, x, s = at()
  if not (r and x) or (w.step and not s) then
    M.stop()
    return
  end
  w.win = code_win()
  if w.bar == nil then
    w.bar = vim.wo[w.win].winbar
  end
  vim.wo[w.win].winbar = BAR
  local c = s and review.chunk(r, s.chunk)
  local spec = chunk.spec(r.diff)
  local found = c and chunk.locate(c, spec)
  local now = c and found and chunk.now(c, spec)
  w.removed = now and now.removed or false
  if not s then
    go.open('briefing', { review = r, tour = x })
  elseif found then
    -- Found in its version: the code shows it in the working tree, or in
    -- the file as it was then when it reads otherwise now.
    step.walk(r, s)
    go.close 'screen'
    vim.api.nvim_set_current_win(w.win)
    go.open('code', { review = r, tour = x, step = s, chunk = c })
  else
    step.walk(r, s)
    go.open('page', { review = r, tour = x, step = s })
  end
  if w.keys then
    -- The code's buffer, and the float's when it is open: the walk's keys
    -- over their own.
    w.keys.cover(vim.api.nvim_win_get_buf(w.win))
    w.keys.cover(vim.api.nvim_get_current_buf())
  end
  vim.api.nvim_exec_autocmds('User', { pattern = 'ThreadWalk', modeline = false })
end

--- Go to a step of the tour you walk, or with none its briefing.
---@param id integer|nil
function M.go(id)
  if not W then
    return
  end
  if W.step ~= id then
    leave()
  end
  W.step = id
  show()
end

--- The next or previous step; from the briefing, the first; from the
--- first, back to the briefing.
---@param d 1|-1
local function move(d)
  local _, x, s = at()
  if not x then
    return
  end
  if not s then
    if d > 0 and x.steps[1] then
      M.go(x.steps[1].id)
    else
      say(d > 0 and 'this tour has no steps' or 'the briefing is where the tour starts')
    end
    return
  end
  for i, other in ipairs(x.steps) do
    if other == s then
      local to = x.steps[i + d]
      if to then
        M.go(to.id)
      elseif d < 0 then
        M.go(nil)
      else
        local k = look.show_key(config.options.walk.quit) or ':Thread stop'
        say('the end of the tour · ' .. k .. ' ends the walk')
      end
      return
    end
  end
end

--- Reply in the step you are on.
local function reply()
  local r, x, s = at()
  if r and x and s then
    go.open('compose', { replies = { { review = r, conversation = conversation.of_step(s, x) } } })
  end
end

--- Turn the dimming or the diff off for the rest of the walk, or on again.
---@param what 'dim'|'diff'
---@return boolean on
function M.toggle(what)
  if not W then
    return false
  end
  W[what] = not W[what]
  if what == 'diff' and not W.diff and W.removed then
    say 'the diff stays drawn: this step is on lines it removed'
  end
  vim.api.nvim_exec_autocmds('User', { pattern = 'ThreadWalk', modeline = false })
  return W[what]
end

--- Every key a walk has, and a step's card's, in a float.
local function keys_help()
  local k = config.options.walk
  local z = config.options.zone or {}
  local diff = config.options.mappings.diff
  ---@param list { [1]: string|false|nil, [2]: string }[]
  ---@return { [1]: string, [2]: string }[]
  local function rows(list)
    local out = {}
    for _, r in ipairs(list) do
      if r[1] then
        out[#out + 1] = { (look.show_key(r[1]):gsub('<CR>', '⏎')), r[2] }
      end
    end
    return out
  end
  help.open('A walk', {
    {
      head = 'Walking',
      rows = rows {
        { k.next, 'the next step; from the briefing, the first' },
        { k.prev, 'the previous step; from the first, the briefing' },
        { k.briefing, "the tour's briefing, from any step" },
        { k.map, "the tour's outline" },
        { k.reply, 'reply in the step' },
        { k.up, "back to the review's screen; the walk ends" },
        { k.quit, 'end the walk' },
      },
    },
    {
      head = 'In the code',
      rows = rows {
        { k.dim, "dim: the code but the step's chunk dimmed, off or on" },
        { diff, "the review's diff drawn in, off or on" },
        { k.enter, "into the step's card: w and b go between its links, ⏎ follows one, q comes out" },
        { k.links, 'into the card, on its first link' },
        { z.focus, "on the step's lines: its page, over the code" },
        { z.fold, 'close the card to its sign, or open it again' },
        { z.next, 'where cards stack on a line, the next on top' },
      },
    },
    {
      head = 'Yours',
      rows = { { 'J / K', 'never the walk’s: K is still your hover' } },
    },
  })
end

--- Whether the cursor is in the code window, where a step's card is.
---@return boolean
local function in_code()
  return W ~= nil and vim.api.nvim_get_current_win() == W.win
end

--- Into the step's card in the code; with `link`, on its first link.
---@param link boolean
local function enter(link)
  local r, x, s = at()
  if r and x and s then
    go.open('card', { review = r, tour = x, step = s, link = link })
  end
end

--- Back to the review, on the screen; the walk ends.
local function up()
  local r = at()
  M.stop()
  if r then
    go.open('review', { review = r })
  end
end

--- The walk's keys, each your own outside the walk where it says so.
---@return { lhs: string, fn: fun(), desc: string }[]
local function walk_keys()
  local k = config.options.walk or {}
  local out = {}
  ---@param name string
  ---@param fn fun()
  ---@param here boolean|fun(): boolean  only in the walk's window or its float; or only where this says
  local function add(name, fn, here)
    local lhs = k[name]
    if not lhs then
      return
    end
    local meant = here == true and in_walk or here or nil
    out[#out + 1] = {
      lhs = lhs,
      desc = 'Thread walk: ' .. name,
      fn = function()
        if meant and not meant() then
          vim.api.nvim_feedkeys(vim.keycode(lhs), 'n', false)
          return
        end
        fn()
      end,
    }
  end
  add('next', function()
    move(1)
  end, false)
  add('prev', function()
    move(-1)
  end, false)
  add('briefing', function()
    M.go(nil)
  end, true)
  add('quit', M.stop, false)
  add('reply', reply, true)
  add('up', up, true)
  add('help', keys_help, true)
  add('dim', function()
    M.toggle 'dim'
  end, true)
  add('map', function()
    go.open('map', {})
  end, true)
  add('enter', function()
    enter(false)
  end, in_code)
  add('links', function()
    enter(true)
  end, in_code)
  return out
end

--- Start walking: from a step; or a tour, on its briefing the first time,
--- or when asked for it, and from the first step you have not walked
--- after; or the review's first tour so.
---@param target thread.Target
function M.start(target)
  local r = target.review
  if not r then
    return
  end
  local s, x = target.step, target.tour
  if s and not x then
    s, x = review.step(r, s.id)
  end
  x = x or r.tours[1]
  if not x then
    say(r.title .. ' has no tour')
    return
  end
  local place = review.tour_place(r, x)
  if not place then
    return
  end
  local id = s and s.id or nil
  -- A tour you have walked some of picks up where you left off.
  if not s and not target.briefing and tour.walked(r, x) > 0 then
    local i = tour.next(r, x)
    if i then
      id = x.steps[i].id
      say('picking up where you left off: ' .. x.steps[i].title)
    end
  end
  if W and W.review == r.id and W.tour == place then
    M.go(id)
    return
  end
  if W then
    M.stop()
  end
  W = { review = r.id, tour = place, step = id, win = code_win(), dim = true, diff = true, removed = false }
  W.keys = keys.overlay(walk_keys())
  show()
end

--- End the walk: its keys and the winbar back as they were.
function M.stop()
  if not W then
    return
  end
  leave()
  local w = W
  W = nil
  if w.keys then
    w.keys.restore()
  end
  if vim.api.nvim_win_is_valid(w.win) then
    vim.wo[w.win].winbar = (w.bar ~= BAR and w.bar) or ''
  end
  go.close 'screen'
  vim.api.nvim_exec_autocmds('User', { pattern = 'ThreadWalk', modeline = false })
end

vim.api.nvim_create_autocmd('BufWinEnter', {
  group = vim.api.nvim_create_augroup('thread.walk', { clear = true }),
  callback = function()
    local win = vim.api.nvim_get_current_win()
    if W and win == W.win then
      vim.wo[win].winbar = BAR
      if W.keys then
        W.keys.cover(vim.api.nvim_get_current_buf())
      end
    elseif vim.wo[win].winbar == BAR then
      vim.wo[win].winbar = ''
    end
  end,
})

go.register('walk', {
  open = {
    walk = M.start,
  },
})
go.answer('walking', M.state)
go.answer('walk hints', function()
  return W and hints(true) or nil
end)

return M
