--- The code: every open review's notes and steps where they are in each
--- buffer on screen. A sign on each line one covers; above its first line,
--- only for what the cursor is on, a note's bubble or its line, a step's
--- line or, asked for, its card; and the step walked, its card. The rest
--- are only their signs, so a review does not bury the code. The notes of what the cursor is on show on
--- their lines, and a review's diff is drawn in when you ask, or while you
--- walk one of its steps. Drawing them is thread.code.paint's; here are
--- what locates them again, and the keys.

local actions = require 'thread.actions'
local anchor = require 'thread.base.anchor'
local chunk = require 'thread.model.chunk'
local config = require 'thread.config'
local draw = require 'thread.draw'
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
require 'thread.code.write'

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
    -- Drawing one can close another, a float over a card.
    local buf = vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win)
    if buf and not seen[buf] and vim.api.nvim_win_get_config(win).relative == '' then
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

--- Tab on what the cursor is on: a card cut short, whole; else closed to
--- its sign; closed, open again, cut short as it was.
function M.fold()
  local p = M.here()
  if not p then
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  local hung = (S.hung[buf] or {})[p.key]
  if S.closed[p.key] then
    S.closed[p.key] = nil
  elseif hung and hung.more and not S.whole[p.key] then
    S.whole[p.key] = true
  else
    S.closed[p.key], S.whole[p.key] = true, nil
  end
  paint.paint(buf)
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
  S.closed[p.key], S.whole[p.key] = nil, nil
  paint.paint(vim.api.nvim_get_current_buf())
end

--- Every note open, and every step of the tour walked; or only what the
--- cursor is on again. Either way, what Tab closed opens.
---@return 'one'|'all'
function M.toggle()
  S.mode = S.mode == 'one' and 'all' or 'one'
  S.closed, S.whole, S.counts, S.hidden = {}, {}, {}, false
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

--- Go into a step's or a note's bubble in the current window, in a float
--- laid over it: the cursor on its first link with `link`, else at its
--- top. Its card open first, if Tab closed it.
---@param target thread.Target
local function enter(target)
  local buf = vim.api.nvim_get_current_buf()
  local r = assert(target.review)
  local key = target.step and place.key(r, target.step, 'step') or place.key(r, assert(target.note), 'note')
  local p = nil ---@type thread.Placed|nil
  for _, q in ipairs(S.placed[buf] or {}) do
    p = p or ((q.key == key and not q.gone) and q or nil)
  end
  if not p then
    vim.notify 'thread: its card is not in this window'
    return
  end
  S.closed[p.key] = nil
  -- Whole while you are in it, the float over it as tall.
  S.inside = p.key
  paint.paint(buf)
  -- The float lies over the rows its card hangs in: with none, as when
  -- the step walked leads its line, it would lie over the code.
  local cur = S.current[buf] and S.current[buf].key
  if paint.sizes(S.placed[buf] or {}, cur, paint.walking())[p.key] ~= 'card' then
    vim.notify(p.note and 'thread: the step walked holds this line; the note is a row in its card' or 'thread: its card is not drawn here')
    S.inside = nil
    paint.paint(buf)
    return
  end
  local lines, parts, mine_row = paint.inside(buf, p)
  local code_win = vim.api.nvim_get_current_win()
  -- The keys that went in, pressed again inside: out, and the next link.
  local k = config.options.walk or {}
  local again = {} ---@type table<string, fun()>
  for _, lhs in pairs { walk = k.enter, zone = (config.options.zone or {}).enter } do
    again[lhs] = function()
      inside.close(true)
    end
  end
  if k.links then
    again[k.links] = function()
      inside.link(1)
    end
  end
  local page = (config.options.zone or {}).page
  if page then
    again[page] = function()
      inside.close(true)
      M.focus()
    end
  end
  -- Reply in it, or edit or delete a message of yours in it, in place:
  -- out of the float, the editor in the card.
  local c = paint.conversation(p)
  ---@param more table|nil
  local function write(more)
    local part = inside.here()
    inside.close(true)
    go.open('compose', vim.tbl_extend('force', { replies = { { review = p.review, conversation = part and part.conversation or c } } }, more or {}), 'code')
  end
  again.r = function()
    write()
  end
  ---@param field 'edit'|'unsay'
  local function mine(field)
    local part = inside.here()
    local pc, i = part and part.conversation, part and part.message
    if not (pc and i and conversation.editable(pc, i)) then
      vim.notify 'thread: put the cursor on a message of yours the agent has not answered'
      return
    end
    write { [field] = i }
  end
  again.e = function()
    mine 'edit'
  end
  again.d = function()
    mine 'unsay'
  end
  inside.open {
    win = vim.api.nvim_get_current_win(),
    line = p.line,
    review = p.review,
    lines = lines,
    parts = parts,
    mine = mine_row,
    link = target.link,
    keys = again,
    -- Out of it, it folds back to how it hung, still in view: folding,
    -- the rows above the window's first line would be lost.
    on_close = function()
      if S.inside ~= p.key then
        return
      end
      S.inside = nil
      paint.paint(buf)
      local hung = (S.hung[buf] or {})[p.key]
      if hung and vim.api.nvim_win_is_valid(code_win) then
        vim.api.nvim_win_call(code_win, function()
          if vim.fn.winsaveview().topline == p.line then
            vim.fn.winrestview { topline = p.line, topfill = math.min(hung.rows, vim.api.nvim_win_get_height(code_win) - 1) }
          end
        end)
      end
    end,
  }
  if target.link and not vim.iter(parts):any(draw.goes) then
    vim.notify('thread: this ' .. (target.step and 'step' or 'note') .. ' has no links')
  end
end

--- Go into the bubble of the note the cursor is on, or the card of the step
--- walked; a step not walked is only its line.
function M.enter_here()
  local p = M.here()
  if not p then
    return
  end
  local w = paint.walking()
  if p.step and not (w and w.review == p.review.id and w.step == p.step.id) then
    vim.notify 'thread: a step has a card only while you walk it'
    return
  end
  enter { review = p.review, tour = p.tour, step = p.step, note = p.note }
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

--- The note the cursor is on's next (or previous) in its review, in the
--- code: what L and H do on a note, as they do between a walk's steps.
---@param d 1|-1
function M.side(d)
  local p = M.here()
  if not (p and p.note) then
    return
  end
  local to = find.beside(p.review, p.note, d)
  if not to then
    vim.notify('thread: the ' .. (d > 0 and 'last' or 'first') .. ' note in the code')
    return
  end
  open_at { review = p.review, note = to.note, chunk = to.chunk }
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
  -- L and H only on a note: on a step's lines they stay yours, a walk
  -- has its own.
  for name, d in pairs { next_note = 1, prev_note = -1 } do
    if z[name] then
      keys.zone(
        z[name],
        function()
          M.side(d)
        end,
        'Thread: ' .. name,
        function()
          local p = on() and M.here()
          return p and p.note ~= nil or false
        end
      )
    end
  end
  for name, fn in pairs {
    focus = M.focus,
    page = M.focus,
    fold = M.fold,
    enter = M.enter_here,
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
