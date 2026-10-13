--- Walking: going through a tour a step at a time. A step on code is its
--- card in the code, whole, its notes on their lines and its review's
--- diff drawn in; a step on no line, or whose line is gone, is its page,
--- the screen in a float. While a walk is on, its keys (config `walk`)
--- lie over yours, `L` and `H` the next and previous step, and the code
--- window's winbar says where you are; ending it puts both back. Walking a
--- tour again picks up at the first step you have not walked.

local chunk = require 'thread.model.chunk'
local config = require 'thread.config'
local go = require 'thread.go'
local keys = require 'thread.ui.keys'
local labels = require 'thread.draw.labels'
local look = require 'thread.ui.look'
local review = require 'thread.model.review'
local step = require 'thread.model.step'
local text = require 'thread.base.text'
local thread = require 'thread.model.thread'
local tour = require 'thread.model.tour'

local M = {}

---@class thread.Walk
---@field review string
---@field thread integer
---@field tour integer  its place among the thread's tours
---@field step integer  the step's id
---@field win integer   the code window
---@field keys thread.Overlay|nil
---@field bar string|nil  the code window's winbar before

local W ---@type thread.Walk|nil

---@param msg string
local function say(msg)
  vim.notify('thread: ' .. msg)
end

--- The walk's review, thread, tour and step, read afresh; nil once any
--- of them has gone.
---@return thread.Review|nil, thread.Thread|nil, thread.Tour|nil, thread.Step|nil
local function at()
  if not W then
    return nil
  end
  local r = review.read(W.review)
  local t = r and review.find(r, W.thread)
  if not (r and t) then
    return nil
  end
  local x = thread.tours(t)[W.tour]
  local s = x and thread.step(t, W.step)
  if not (x and s) then
    return nil
  end
  return r, t, x, s
end

--- Where the walk is, for the code to draw.
---@return thread.Walking|nil
function M.state()
  return W and { review = W.review, thread = W.thread, step = W.step } or nil
end

local function esc(s)
  return (s:gsub('%%', '%%%%'))
end

--- The winbar: the thread, the tour and the step, its track, how far, and
--- the keys.
---@return string
function M.bar()
  local r, t, x, s = at()
  if not (r and t and x and s) then
    return ''
  end
  local parts = { '%#ThreadWalkBar# ▶ ', esc(text.fit(t.title or ('#' .. t.id), 28)), ' › ', esc(text.fit(x.title, 24)), '%<' }
  parts[#parts + 1] = ' › %#ThreadWalkBarHere#' .. esc(text.fit(s.title, 40)) .. '%#ThreadWalkBar#  '
  local hl = { ThreadLeads = 'ThreadWalkBarHere', ThreadTitle = 'ThreadWalkBarKey', ThreadMeta = 'ThreadWalkBar' }
  for _, c in ipairs(labels.track(r, t, x, s)) do
    parts[#parts + 1] = '%#' .. (hl[c[2]] or 'ThreadWalkBar') .. '#' .. esc(c[1])
  end
  local n = 0
  for i, other in ipairs(x.steps) do
    n = other == s and i or n
  end
  parts[#parts + 1] = '%#ThreadWalkBar# step ' .. n .. '/' .. #x.steps .. '   %='
  local k = config.options.walk
  for _, key in ipairs { { k.next, 'next' }, { k.prev, 'prev' }, { k.reply, 'reply' }, { k.map, 'tour' }, { k.up, 'thread' }, { k.quit, 'end' } } do
    local shown = key[1] and look.show_key(key[1])
    if shown then
      parts[#parts + 1] = '%#ThreadWalkBarKey#' .. esc(shown) .. '%#ThreadWalkBar# ' .. key[2] .. '  '
    end
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
--- window or the page; elsewhere it is your own.
---@return boolean
local function in_walk()
  local win = vim.api.nvim_get_current_win()
  return (W ~= nil and win == W.win) or vim.bo.filetype == 'thread-screen'
end

--- What was shown of the step you leave is read.
local function leave()
  local r, t, x, s = at()
  if r and t and s and #s.messages > 0 then
    thread.mark_read(r, thread.conversation(t, s, x))
  end
end

--- Show the step the walk is on: its card in the code, or its page.
local function show()
  local w = assert(W)
  local r, t, x, s = at()
  if not (r and t and x and s) then
    M.stop()
    return
  end
  step.walk(r, t, s)
  w.win = code_win()
  if w.bar == nil then
    w.bar = vim.wo[w.win].winbar
  end
  vim.wo[w.win].winbar = BAR
  local found = s.chunk and chunk.locate(s.chunk, chunk.spec(r.diff))
  if found then
    go.close 'screen'
    vim.api.nvim_set_current_win(w.win)
    go.open('code', { review = r, thread = t, tour = x, step = s, chunk = s.chunk })
  else
    go.open('page', { review = r, thread = t, tour = x, step = s })
  end
  if w.keys then
    -- The code's buffer, and the page's when it is open: the walk's keys
    -- over their own.
    w.keys.cover(vim.api.nvim_win_get_buf(w.win))
    w.keys.cover(vim.api.nvim_get_current_buf())
  end
  vim.api.nvim_exec_autocmds('User', { pattern = 'ThreadWalk', modeline = false })
end

--- Go to a step of the tour you walk.
---@param id integer
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

---@param d 1|-1
local function move(d)
  local _, _, x, s = at()
  if not (x and s) then
    return
  end
  for i, other in ipairs(x.steps) do
    if other == s then
      local to = x.steps[i + d]
      if not to then
        local k = look.show_key(config.options.walk.quit) or ':Thread stop'
        say(d > 0 and ('the end of the tour · ' .. k .. ' ends the walk') or 'the start of the tour')
        return
      end
      M.go(to.id)
      return
    end
  end
end

--- Reply in the step you are on.
local function reply()
  local r, t, x, s = at()
  if r and t and s then
    go.open('compose', { replies = { { review = r, conversation = thread.conversation(t, s, x) } } })
  end
end

--- Back to the thread, on the screen; the walk ends.
local function up()
  local r, t = at()
  M.stop()
  if r and t then
    go.open('thread', { review = r, thread = t })
  end
end

--- The walk's keys, each your own outside the walk where it says so.
---@return { lhs: string, fn: fun(), desc: string }[]
local function walk_keys()
  local k = config.options.walk or {}
  local out = {}
  ---@param name string
  ---@param fn fun()
  ---@param here boolean  only in the walk's window or its page
  local function add(name, fn, here)
    local lhs = k[name]
    if not lhs then
      return
    end
    out[#out + 1] = {
      lhs = lhs,
      desc = 'Thread walk: ' .. name,
      fn = function()
        if here and not in_walk() then
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
  add('quit', M.stop, false)
  add('reply', reply, true)
  add('up', up, true)
  add('map', function()
    go.open('map', {})
  end, true)
  return out
end

--- Start walking: from a step, or a tour from where you left off, or a
--- thread's first tour from where you left off.
---@param target thread.Target
function M.start(target)
  local r, t = target.review, target.thread
  if not (r and t) then
    return
  end
  local tours = thread.tours(t)
  local s, x = target.step, target.tour
  if s and not x then
    s, x = thread.step(t, s.id)
  end
  x = x or tours[1]
  if not x then
    say('#' .. t.id .. ' has no tour')
    return
  end
  if not s then
    local i = tour.next(r, t, x)
    if i and i > 1 then
      say('picking up where you left off: ' .. x.steps[i].title)
    end
    s = x.steps[i or 1]
  end
  if not s then
    return
  end
  local place = 0
  for i, other in ipairs(tours) do
    place = other == x and i or place
  end
  if W and W.review == r.id and W.thread == t.id and W.tour == place then
    M.go(s.id)
    return
  end
  if W then
    M.stop()
  end
  W = { review = r.id, thread = t.id, tour = place, step = s.id, win = code_win() }
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

return M
