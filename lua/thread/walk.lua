--- Walking: going through a tour, a stop at a time. A step is its card in
--- the code, with its notes on their lines; a stage or a page opens as a
--- page in the centred float, and the next step takes you back to the code.
---
--- While a walk is on, `L`/`H` go to the next and previous stop, `r`
--- replies in the one you are on and `q` ends it. They are set globally when it starts and put back when it ends,
--- as tour.nvim does. The code window's winbar says where you are.
---
--- Starting a walk from inside one (a reply whose answer is a tour of its
--- own) puts the first one aside; ending the inner one goes back to it.

local config = require 'thread.config'
local store = require 'thread.store'
local tour = require 'thread.tour'

local M = {}

---@class thread.WalkState
---@field owner integer  the thread whose tour this is
---@field n integer      the stop you are on; 0 is the overview
---@field win integer    the code window
---@field saved table<string, table|false>|nil  lhs -> the mapping it had
---@field bufs table<integer, table<string, table|false>>|nil  the same for buffers whose own mappings would win
---@field bar string|nil  the code window's winbar before
---@field outer thread.WalkState|nil  the walk this one was started from
---@type thread.WalkState|nil
local W

local function notify(msg, level)
  vim.notify('thread: ' .. msg, level or vim.log.levels.INFO)
end

---@return { owner: integer, n: integer, depth: integer }|nil
function M.state()
  if not W then
    return nil
  end
  local depth, w = 1, W.outer
  while w do
    depth, w = depth + 1, w.outer
  end
  return { owner = W.owner, n = W.n, depth = depth }
end

local function walk_keys()
  local keys = config.options.walk or {}
  local out = {}
  -- `up` (K) only while walking a review: elsewhere K is the code's hover.
  local batch = W and store.active()
  local owner = batch and store.find(batch, W.owner)
  local rv = owner and tour.is_review(owner)
  for action, fn in pairs { next = M.next, prev = M.prev, quit = M.stop, reply = M.reply, map = M.map, up = M.up } do
    if keys[action] and (action ~= 'up' or rv) then
      out[#out + 1] = { lhs = keys[action], fn = fn, action = action }
    end
  end
  return out
end

local function set_keys()
  if W.saved then
    return
  end
  W.saved = {}
  for _, k in ipairs(walk_keys()) do
    local old = vim.fn.maparg(k.lhs, 'n', false, true)
    W.saved[k.lhs] = (old and old.lhs and old.buffer ~= 1) and old or false
    vim.keymap.set('n', k.lhs, k.fn, { desc = 'Thread walk: ' .. k.action })
  end
end

--- A buffer's own mapping wins over a global one: the snacks dashboard's
--- `L` opens Lazy. So the buffer the walk's window shows gets the walk's
--- keys too, and gets its own back when the walk ends.
local function cover(buf)
  W.bufs = W.bufs or {}
  if W.bufs[buf] or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  W.bufs[buf] = {}
  for _, k in ipairs(walk_keys()) do
    local old = vim.api.nvim_buf_call(buf, function()
      return vim.fn.maparg(k.lhs, 'n', false, true)
    end)
    W.bufs[buf][k.lhs] = (old and old.lhs and old.buffer == 1) and old or false
    vim.keymap.set('n', k.lhs, k.fn, { buffer = buf, desc = 'Thread walk: ' .. k.action })
  end
end

local function restore_keys(w)
  for lhs, old in pairs(w and w.saved or {}) do
    pcall(vim.keymap.del, 'n', lhs)
    if old then
      pcall(vim.fn.mapset, 'n', false, old)
    end
  end
  for buf, saved in pairs(w and w.bufs or {}) do
    if vim.api.nvim_buf_is_valid(buf) then
      for lhs, old in pairs(saved) do
        pcall(vim.keymap.del, 'n', lhs, { buffer = buf })
        if old then
          vim.api.nvim_buf_call(buf, function()
            pcall(vim.fn.mapset, 'n', false, old)
          end)
        end
      end
    end
  end
  if w then
    w.saved, w.bufs = nil, nil
  end
end

local function esc(s)
  return (s:gsub('%%', '%%%%'))
end

--- The winbar: the tour, the stage you are in, where you are, and the keys.
local function winbar(batch)
  local owner = store.find(batch, W.owner)
  local list = owner and tour.of(owner)
  if not list then
    return ''
  end
  local items = tour.outline(list)
  local here = items[W.n]
  local stage
  for i = W.n, 1, -1 do
    if items[i] and items[i].kind == 'stage' then
      stage = items[i]
      break
    end
  end
  local function fit(str, w)
    if vim.fn.strchars(str) <= w then
      return str
    end
    return vim.fn.strcharpart(str, 0, w - 1) .. '…'
  end
  local parts = { '%#ThreadWalkBar# ▶ ' }
  if W.outer then
    parts[#parts + 1] = '… › '
  end
  parts[#parts + 1] = esc(fit(store.title(owner), 28))
  if stage then
    parts[#parts + 1] = ' › ' .. stage.stage .. ' ' .. esc(fit(tour.title(stage.e), 24))
  end
  parts[#parts + 1] = '%<'
  if here and here.kind ~= 'stage' then
    parts[#parts + 1] = ' › %#ThreadWalkBarHere#' .. esc(fit(tour.title(here.e), 36)) .. '%#ThreadWalkBar#'
  end
  parts[#parts + 1] = '  '
  local bar = { done = 'ThreadWalkBarHere', here = 'ThreadWalkBarKey', left = 'ThreadWalkBar' }
  for _, t in ipairs(tour.track(list, W.n)) do
    parts[#parts + 1] = '%#' .. bar[t[2]] .. '#' .. t[1]
  end
  parts[#parts + 1] = '%#ThreadWalkBar#'
  parts[#parts + 1] = ' ' .. (W.n == 0 and 'overview' or tour.position(list, W.n)) .. '   '
  parts[#parts + 1] = '%='
  local keys = config.options.walk
  local render = require 'thread.render'
  local rv = tour.is_review(owner)
  local list_keys = rv and { { keys.next, 'next' }, { keys.prev, 'prev' }, { keys.reply, 'reply' }, { keys.up, 'the review' }, { keys.quit, 'end' } }
    or { { keys.next, 'next' }, { keys.prev, 'prev' }, { keys.reply, 'reply' }, { keys.map, 'tour' }, { keys.quit, W.outer and 'back' or 'end' }, { '⏎', 'open' } }
  for _, k in ipairs(list_keys) do
    local key = k[1] and render.show_key(k[1])
    if key then
      parts[#parts + 1] = '%#ThreadWalkBarKey#' .. esc(key) .. '%#ThreadWalkBar# ' .. k[2] .. '  '
    end
  end
  return table.concat(parts)
end

-- The winbar is an expression, so it follows the walk without being set
-- again. Window options are kept per buffer too, so a buffer entering the
-- walk's window gets it and any other window that still has it loses it.
local BAR = "%{%v:lua.require'thread.walk'.bar()%}"

--- What the winbar shows: where the walk is, or nothing.
function M.bar()
  local batch = W and store.active()
  return batch and winbar(batch) or ''
end

local function set_bar()
  if not vim.api.nvim_win_is_valid(W.win) then
    return
  end
  if W.bar == nil then
    W.bar = vim.wo[W.win].winbar
  end
  vim.wo[W.win].winbar = BAR
  pcall(vim.api.nvim__redraw, { win = W.win, winbar = true })
end

local function restore_bar(w)
  if w and vim.api.nvim_win_is_valid(w.win) then
    vim.wo[w.win].winbar = (w.bar ~= BAR and w.bar) or ''
  end
end

vim.api.nvim_create_autocmd('BufWinEnter', {
  group = vim.api.nvim_create_augroup('thread.walkbar', { clear = true }),
  callback = function()
    local win = vim.api.nvim_get_current_win()
    if W and win == W.win then
      vim.wo[win].winbar = BAR
      if W.saved then
        cover(vim.api.nvim_get_current_buf())
      end
    elseif vim.wo[win].winbar == BAR then
      vim.wo[win].winbar = ''
    end
  end,
})

--- A window to show code in: the walk's own, or else any that is not a float.
local function code_win()
  if W and W.win and vim.api.nvim_win_is_valid(W.win) then
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
  return vim.api.nvim_get_current_win()
end

--- Show the stop you are on: a step in the code, anything else as a page.
local function show(batch)
  local owner = store.find(batch, W.owner)
  local list = owner and tour.of(owner)
  local e = list and list[W.n]
  local page = require 'thread.page'
  W.win = code_win()
  set_bar()
  local review = require 'thread.review'
  local kind = e and tour.kind(e)
  if owner and review.of(owner) then
    if kind ~= 'step' and kind ~= 'aside' then
      -- A review's groups are on its screen, not walked.
      local id, at = W.owner, W.n
      M.stop()
      return require('thread.review_page').open { owner = id, n = at > 0 and at or nil }
    end
    -- A review: its diff drawn into the code for as long as you walk it.
    review.show(owner.id)
  end
  if kind == 'step' or kind == 'aside' then
    page.close()
    vim.api.nvim_set_current_win(W.win)
    store.visit(batch, W.owner, W.n)
    local d = tour.display(batch, owner, W.n)
    local there = require('thread.actions').jump(d, { quiet = true })
    cover(vim.api.nvim_win_get_buf(W.win))
    require('thread.render').refresh()
    if not there then
      -- Its line moved or went: the step as a page, saying so, and the
      -- walk goes on from there.
      page.open(W.owner, W.n)
    end
  else
    if vim.api.nvim_win_is_valid(W.win) then
      cover(vim.api.nvim_win_get_buf(W.win))
    end
    if W.n > 0 then
      store.visit(batch, W.owner, W.n)
    end
    page.open(W.owner, W.n)
    require('thread.render').refresh()
  end
  require('thread.map').refresh()
end

--- Go to stop `n` of the tour being walked.
---@param n integer
function M.go(n)
  local batch = store.active()
  if not (W and batch) then
    return
  end
  W.n = n
  set_keys()
  show(batch)
end

--- Start walking `owner`'s tour at stop `n`: the overview when its thread
--- is about no line, else the first stop. From inside another walk, that
--- one is put aside until this one ends.
---@param owner integer|nil  none: the thread under the cursor
---@param n integer|nil
function M.start(owner, n)
  local batch = store.active()
  if not batch then
    return notify 'no batch yet'
  end
  if not owner then
    local c = require('thread.render').at_cursor()
    if c and c.stop then
      owner, n = c.stop.owner, n or c.stop.n
    elseif c then
      owner = c.id
    end
  end
  local o = owner and store.find(batch, owner)
  if not o then
    return notify 'no thread here to walk'
  end
  if not tour.leads(o) then
    -- A reply in a stop: the tour it is in.
    local up, _, at = tour.owner(batch, o)
    if not up then
      return notify 'this thread leads to no tour'
    end
    o, n = up, n or at
  end
  if not n then
    -- Where you left off: the first stop not yet been to after the
    -- furthest you got, else any not yet been to; the start when you have
    -- been to none, or all.
    local list = tour.of(o)
    local furthest, first = 0, nil
    local is_review = tour.is_review(o)
    local function off(i)
      -- Not on the path: a list off it, or a review's group (its screen).
      return tour.kind(list[i]) == 'aside' or (is_review and tour.kind(list[i]) ~= 'step')
    end
    for i = 1, #list do
      if store.visited(batch, o.id, i) and not off(i) then
        furthest = i
      end
    end
    for i = 1, #list do
      local j = (furthest + i - 1) % #list + 1
      if not first and not off(j) and not store.visited(batch, o.id, j) then
        first = j
      end
    end
    if furthest > 0 and first then
      n = first
      notify(string.format('picking up where you left off: %s', tour.position(list, first)))
    else
      n = store.anchored(o) and 1 or 0
    end
  end
  if W and W.owner == o.id then
    return M.go(n)
  end
  local outer = W
  if outer then
    restore_keys(outer)
  end
  W = { owner = o.id, n = n, win = outer and outer.win or code_win(), outer = outer, bar = outer and outer.bar }
  M.go(n)
end

local function move(d)
  if not W then
    return
  end
  local batch = store.active()
  local owner = batch and store.find(batch, W.owner)
  local list = owner and tour.of(owner)
  if not list then
    return M.stop()
  end
  local here = list[W.n]
  if tour.is_review(owner) then
    -- A review: from hunk to hunk, on into the next group's; in a list off
    -- the path, through that list.
    local i = W.n + d
    while list[i] do
      local e = list[i]
      if here and here.aside then
        if e.aside == here.aside and e.review.group == here.review.group then
          return M.go(i)
        end
      elseif tour.kind(e) == 'step' then
        return M.go(i)
      end
      i = i + d
    end
    local k = require('thread.render').show_key(config.options.walk.up) or 'K'
    return notify((d > 0 and 'the last' or 'the first') .. (here and here.aside and (' of the ' .. here.aside) or ' hunk') .. ' · ' .. k .. ' back to the review')
  end
  local to = W.n + d
  if to > #list then
    return notify(string.format('the end of the tour · %s ends the walk', require('thread.render').show_key(config.options.walk.quit) or ':Thread stop'))
  end
  if to < 0 or (to == 0 and store.anchored(owner)) then
    return notify 'the start of the tour'
  end
  M.go(to)
end

function M.next()
  move(1)
end

function M.prev()
  move(-1)
end

--- Reply in the stop you are on; on the overview, in the thread that
--- leads to the tour. Anywhere but the walk's window or its page, `r` is
--- Vim's own.
function M.reply()
  if not W then
    return
  end
  local page = require 'thread.page'
  if vim.api.nvim_get_current_win() ~= W.win and vim.bo.filetype ~= 'thread-page' then
    return vim.api.nvim_feedkeys(config.options.walk.reply or 'r', 'n', false)
  end
  if W.n == 0 then
    local batch = store.active()
    local o = batch and store.find(batch, W.owner)
    if o then
      page.close()
      require('thread.home').focus { comment = o, reply = true }
    end
    return
  end
  require('thread.actions').reply_stop(W.owner, W.n)
end

--- The tour as a list, every stop: in the page when one is open, else
--- the map in the corner, to jump by letter.
function M.map()
  if not W then
    return
  end
  if vim.api.nvim_get_current_win() ~= W.win and vim.bo.filetype ~= 'thread-page' then
    return vim.api.nvim_feedkeys(config.options.walk.map or 'M', 'n', false)
  end
  local batch = store.active()
  local owner = batch and store.find(batch, W.owner)
  if owner and tour.is_review(owner) then
    return M.up()
  end
  require('thread.map').pin()
end

--- `K`: out of walking a review, back to its screen, on the hunk you were
--- on. Walking a tour, and outside the walk's window, `K` is Vim's own.
function M.up()
  local batch = W and store.active()
  local owner = batch and store.find(batch, W.owner)
  if not (owner and tour.is_review(owner)) or vim.api.nvim_get_current_win() ~= W.win then
    return vim.api.nvim_feedkeys(config.options.walk.up or 'K', 'n', false)
  end
  local id, n = W.owner, W.n
  M.stop()
  require('thread.review_page').open { owner = id, n = n }
end

--- End the walk: back to the one it was started from, if any; else the
--- keys and the winbar go back to what they were.
function M.stop()
  if not W then
    return
  end
  local was = W
  restore_keys(was)
  require('thread.page').close()
  W = was.outer
  if W then
    notify 'back in the tour you were walking'
    M.go(W.n)
    return
  end
  restore_bar(was)
  local review = require 'thread.review'
  if review.showing() == was.owner then
    review.show(nil)
  end
  require('thread.map').refresh()
  require('thread.render').refresh()
end

return M
