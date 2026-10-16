--- The code: every open review's notes and steps where they are in each
--- buffer on screen. A sign on each line one covers; above its first line
--- a note's bubble or its line; a step's card while it is walked or
--- asked for, its line while the cursor is on it, else only its sign, so a
--- tour does not bury the code. The notes of what the cursor is on show on
--- their lines, and a review's diff is drawn in when you ask, or while you
--- walk one of its steps. Drawing them is thread.code.paint's; here are
--- what locates them again, and the keys.

local actions = require 'thread.actions'
local anchor = require 'thread.base.anchor'
local chunk = require 'thread.model.chunk'
local config = require 'thread.config'
local find = require 'thread.code.find'
local go = require 'thread.go'
local hang = require 'thread.code.hang'
local inside = require 'thread.code.inside'
local keys = require 'thread.ui.keys'
local paint = require 'thread.code.paint'
local place = require 'thread.code.place'
local repo = require 'thread.base.repo'
local source = require 'thread.base.source'
local conversation = require 'thread.model.conversation'

local M = {}

M.ns = paint.ns
local S = paint.S

--- Draw what was last located in a buffer.
M.paint = paint.paint

--- Locate everything in a buffer again, and draw it.
---@param buf integer
function M.draw(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    S.placed[buf], S.current[buf] = nil, nil
    return
  end
  S.placed[buf] = place.locate(buf)
  paint.track(buf)
  paint.paint(buf)
end

--- Draw every buffer on screen again.
function M.refresh()
  local seen = {} ---@type table<integer, true>
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if not seen[buf] and vim.api.nvim_win_get_config(win).relative == '' then
      seen[buf] = true
      M.draw(buf)
    end
  end
  -- A buffer no window shows is forgotten, what its card showed you read.
  for buf in pairs(S.placed) do
    if not seen[buf] then
      local now = S.current[buf]
      if now and now.shown then
        for _, p in ipairs(S.placed[buf]) do
          if p.key == now.key then
            conversation.mark_read(p.review, paint.conversation(p), now.shown)
          end
        end
      end
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
      end
      S.placed[buf], S.current[buf], S.hung[buf] = nil, nil, nil
    end
  end
end

local pending = false

--- Draw every buffer again, soon: many changes at once draw once.
function M.schedule()
  if pending then
    return
  end
  pending = true
  vim.defer_fn(function()
    pending = false
    M.refresh()
  end, 30)
end

--- The cursor moved: light up what it is on now, if that changed.
function M.cursor_moved()
  local buf = vim.api.nvim_get_current_buf()
  if S.placed[buf] and paint.track(buf) then
    paint.paint(buf)
  end
end

--- What the cursor is on in the current buffer.
---@return thread.Placed|nil, integer  and how many cover its line
function M.here()
  local buf = vim.api.nvim_get_current_buf()
  if not S.placed[buf] then
    M.draw(buf)
  end
  local list = S.placed[buf] or {}
  local here = place.covering(list, vim.api.nvim_win_get_cursor(0)[1])
  local cur = S.current[buf]
  for _, p in ipairs(here) do
    if cur and p.key == cur.key then
      return p, #here
    end
  end
  return here[1], #here
end

--- Bring the next of those on the cursor's line to the top.
---@param n integer
function M.cycle(n)
  local buf = vim.api.nvim_get_current_buf()
  local here = place.covering(S.placed[buf] or {}, vim.api.nvim_win_get_cursor(0)[1])
  if #here < 2 then
    return
  end
  local at = 1
  for i, p in ipairs(here) do
    if S.current[buf] and p.key == S.current[buf].key then
      at = i
    end
  end
  paint.pick(buf, here[(at - 1 + n) % #here + 1].key)
  paint.paint(buf)
end

--- What the cursor is on, as a card or as a line.
function M.fold()
  local p = M.here()
  if not p then
    return
  end
  local size = paint.sizes(S.placed[vim.api.nvim_get_current_buf()] or {}, p.key, paint.walking())[p.key]
  S.sized[p.key] = size == 'card' and 'line' or 'card'
  paint.paint(vim.api.nvim_get_current_buf())
end

--- A message more (or fewer) on the card of what the cursor is on.
---@param d 1|-1
function M.resize(d)
  local p = M.here()
  if not p then
    return
  end
  local n = #paint.conversation(p).messages
  S.counts[p.key] = math.max(1, math.min(n, (S.counts[p.key] or hang.messages(p)) + d))
  S.sized[p.key] = 'card'
  paint.paint(vim.api.nvim_get_current_buf())
end

--- Every bubble at its own size, or a line each.
---@return 'card'|'line'
function M.toggle()
  S.mode = S.mode == 'card' and 'line' or 'card'
  S.sized, S.counts, S.hidden = {}, {}, false
  M.refresh()
  return S.mode
end

--- Hide everything but the signs, or show it again.
---@return boolean shown
function M.hide()
  S.hidden = not S.hidden
  M.refresh()
  return not S.hidden
end

--- Draw the diff of the review of what the cursor is on, or stop.
---@return boolean|nil on  nil when the cursor is on nothing of a diff's
function M.diff_here()
  local p = M.here()
  if not (p and p.review.diff) then
    return nil
  end
  local id = p.review.id
  S.diffs[id] = not S.diffs[id] or nil
  M.refresh()
  return S.diffs[id] == true
end

--- Open what the cursor is on: a note's page or a step's, in a float.
function M.focus()
  local p = M.here()
  if not p then
    return
  end
  if p.step then
    go.open('page', { review = p.review, tour = p.tour, step = p.step }, 'code')
  else
    go.open('focus', { review = p.review, note = p.note }, 'code')
  end
end

--- Go into a step's card in the current window, in a float laid over
--- it: the cursor on its first link with `link`, else at its top. Its
--- card whole first, if Tab folded it to a line.
---@param target thread.Target
local function enter(target)
  local buf = vim.api.nvim_get_current_buf()
  local s = assert(target.step)
  local p = nil ---@type thread.Placed|nil
  for _, q in ipairs(S.placed[buf] or {}) do
    p = p or ((q.step and q.step.id == s.id and q.review.id == assert(target.review).id and not q.gone) and q or nil)
  end
  if not p then
    vim.notify 'thread: its card is not in this window'
    return
  end
  if S.sized[p.key] == 'line' then
    S.sized[p.key] = nil
  end
  paint.paint(buf)
  local lines, parts = paint.inside(buf, p)
  -- The keys that went in, pressed again inside: out, and the next link.
  local k = config.options.walk or {}
  local again = {} ---@type table<string, fun()>
  if k.enter then
    again[k.enter] = function()
      inside.close(true)
    end
  end
  if k.links then
    again[k.links] = function()
      inside.link(1)
    end
  end
  inside.open { win = vim.api.nvim_get_current_win(), line = p.line, review = p.review, lines = lines, parts = parts, link = target.link, keys = again }
  if target.link and not vim.iter(parts):any(function(q)
    return q.kind == 'link' or q.kind == 'name'
  end) then
    vim.notify 'thread: this step has no links'
  end
end

--- Walk from the step the cursor is on.
---@return boolean  whether there is one to walk
function M.walk_here()
  local p = M.here()
  if not (p and p.step) then
    return false
  end
  go.open('walk', { review = p.review, tour = p.tour, step = p.step }, 'code')
  return true
end

--- Reply in what the cursor is on.
function M.reply()
  local p = M.here()
  if p then
    go.open('compose', { replies = { { review = p.review, conversation = paint.conversation(p) } } }, 'code')
  end
end

--- Settle the note the cursor is on, asking how, by its kind; a
--- comment has nothing to settle.
function M.close_here()
  local p = M.here()
  local n = p and p.note
  if not (p and n) then
    return
  end
  local ways = actions.settles(n)
  if #ways == 0 then
    vim.notify 'thread: a comment has nothing to settle'
    return
  end
  vim.ui.select(ways, { prompt = 'Settle note ' .. n.id .. ' as' }, function(status)
    if status then
      actions.set_status(p.review, n, status)
    end
  end)
end

--- Start a note on lines of the current buffer.
---@param from integer
---@param to integer
function M.add(from, to)
  local a, err = anchor.capture(vim.api.nvim_get_current_buf(), from, to)
  if not a then
    vim.notify('thread: ' .. (err or 'no line here'), vim.log.levels.WARN)
    return
  end
  go.open('compose', { anchor = a }, 'code')
end

--- A window to show code in: this one if it holds a file, else one that does.
---@return integer
local function code_win()
  local cur = vim.api.nvim_get_current_win()
  ---@param w integer
  ---@return boolean
  local function fits(w)
    local buf = vim.api.nvim_win_get_buf(w)
    return vim.api.nvim_win_get_config(w).relative == '' and (vim.bo[buf].buftype == '' or source.of_buf(buf) ~= nil)
  end
  if fits(cur) then
    return cur
  end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if fits(w) then
      return w
    end
  end
  return cur
end

--- Go to a chunk in the code, its review's diff drawn when it is on
--- lines the diff removed. One read at a revision is in the working tree
--- where the code shows it, else in the file as it was then.
---@param target thread.Target
local function open_at(target)
  local c = assert(target.chunk)
  local r = target.review
  local spec = r and chunk.spec(r.diff)
  local now = chunk.now(c, spec)
  local at = now ---@type { line: integer }|nil
  local rev ---@type string|nil
  if not now then
    local resolved = chunk.resolve(c, spec)
    rev = resolved or nil
    at = chunk.locate(c, spec)
  end
  vim.api.nvim_set_current_win(code_win())
  local then_buf = rev and source.at_rev(rev, c.file)
  if then_buf then
    vim.api.nvim_win_set_buf(0, then_buf)
  else
    local path = repo.path(c.file)
    if vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':p') ~= vim.fn.fnamemodify(path, ':p') then
      vim.cmd.edit(vim.fn.fnameescape(path))
    end
  end
  if now and now.removed and r then
    S.diffs[r.id] = true
  end
  -- The cursor there first: bubbles and cards are drawn near it.
  pcall(vim.api.nvim_win_set_cursor, 0, { at and at.line or c.line, 0 })
  local buf = vim.api.nvim_get_current_buf()
  M.draw(buf)
  -- What it was opened for is the one lit, of all on its line.
  local of = target.step or target.note
  if r and of then
    local key = place.key(r, of, target.step and 'step' or 'note')
    for _, p in ipairs(S.placed[buf] or {}) do
      if p.key == key then
        paint.pick(buf, key)
        paint.paint(buf)
      end
    end
  end
  vim.cmd 'normal! zz'
  M.cursor_moved()
end

--- The next (or previous) conversation that wants you, or with `all` any
--- open one, round the ends.
---@param d 1|-1
---@param all boolean|nil
function M.next(d, all)
  -- From the one the cursor is on, else from its line.
  local on = M.here()
  local line = on and on.line or vim.api.nvim_win_get_cursor(0)[1]
  local s = find.next(d, all == true, source.of_buf(vim.api.nvim_get_current_buf()), line, on and on.key)
  if not s then
    vim.notify('thread: ' .. (all and 'no conversation is on a line' or 'nothing on a line wants you'))
    return
  end
  local c = s.conversation
  open_at { review = s.review, tour = c.tour, step = c.step, note = c.note, chunk = s.chunk }
end

--- Back to every bubble at its own size, shown, no diff drawn, nothing
--- located: as it starts.
function M.reset()
  paint.reset()
end

--- Its autocmds and the keys that act on what the cursor is on.
function M.setup()
  local group = vim.api.nvim_create_augroup('thread.code', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinResized', 'TextChanged', 'InsertLeave' }, { group = group, callback = M.schedule })
  vim.api.nvim_create_autocmd('CursorMoved', { group = group, callback = M.cursor_moved })
  -- Cards come into reach as you scroll, and the top line's into view.
  vim.api.nvim_create_autocmd('WinScrolled', {
    group = group,
    callback = function()
      local done = {} ---@type table<integer, true>
      for id in pairs(vim.v.event) do
        local win = tonumber(id)
        local buf = win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win)
        if buf and S.placed[buf] and not done[buf] then
          done[buf] = true
          paint.paint(buf)
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd('User', { group = group, pattern = { 'ThreadChanged', 'ThreadWalk' }, callback = M.schedule })
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = group,
    callback = function(ev)
      find.requote(ev.buf)
    end,
  })
  local z = config.options.zone or {}
  local function on()
    return source.of_buf(0) ~= nil and not S.hidden and M.here() ~= nil
  end
  for name, fn in pairs {
    focus = M.focus,
    fold = M.fold,
    next = function()
      M.cycle(1)
    end,
    more = function()
      M.resize(1)
    end,
    less = function()
      M.resize(-1)
    end,
  } do
    if z[name] then
      keys.zone(z[name], fn, 'Thread: ' .. name, on)
    end
  end
end

go.register('code', { open = { code = open_at, card = enter }, close = inside.close })

return M
