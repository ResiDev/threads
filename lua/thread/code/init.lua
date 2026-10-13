--- The code: every open review's threads and steps where they are in each
--- buffer on screen. A sign on each line one covers; above its first line
--- a thread's bubble, its card from draw/, or its line; a step's card
--- while it is walked or asked for, its line while the cursor is on it,
--- else only its sign, so a tour does not bury the code. The notes of
--- what the cursor is on show on their lines, and a review's diff is
--- drawn in when you ask, or while you walk one of its steps.

local actions = require 'thread.actions'
local anchor = require 'thread.base.anchor'
local card = require 'thread.code.card'
local chunk = require 'thread.model.chunk'
local config = require 'thread.config'
local diff_changes = require('thread.base.diff').changes
local find = require 'thread.code.find'
local go = require 'thread.go'
local keys = require 'thread.ui.keys'
local marks = require 'thread.code.marks'
local place = require 'thread.code.place'
local repo = require 'thread.base.repo'
local review = require 'thread.model.review'
local source = require 'thread.base.source'
local text = require 'thread.base.text'
local thread = require 'thread.model.thread'

local M = {}

M.ns = vim.api.nvim_create_namespace 'thread.code'

--- Where a walk is, as the walk answers `walking`.
---@class thread.Walking
---@field review string
---@field thread integer
---@field step integer

-- 'card': each at its own size; 'line': each a line.
local mode = 'card' ---@type 'card'|'line'
-- Signs only.
local hidden = false
-- A thread's or step's size set with Tab, by its key.
local sized = {} ---@type table<string, 'card'|'line'>
-- The reviews whose diff is drawn in, by id.
local diffs = {} ---@type table<string, true>
-- Where everything sits, by buffer, as last located.
local placed = {} ---@type table<integer, thread.Placed[]>
-- What the cursor is on, by buffer: its key; whether picked by hand; how
-- many of its messages its card has shown you, once it is on screen.
local current = {} ---@type table<integer, { key: string, pinned: boolean|nil, shown: integer|nil }>

---@return thread.Walking|nil
local function walking()
  return go.ask 'walking'
end

---@param p thread.Placed
---@return thread.Conversation
local function conversation(p)
  return thread.conversation(p.thread, p.step, p.tour)
end

--- Whether the walk is on this step.
---@param p thread.Placed
---@param w thread.Walking|nil
---@return boolean
local function walked(p, w)
  return w ~= nil and p.step ~= nil and w.review == p.review.id and w.thread == p.thread.id and w.step == p.step.id
end

--- The columns a buffer's window has for text.
---@param buf integer
---@return integer
local function room(buf)
  local win = vim.fn.bufwinid(buf)
  if win == -1 then
    return 100
  end
  return vim.api.nvim_win_get_width(win) - vim.fn.getwininfo(win)[1].textoff
end

--- How big each is drawn: a card, a line, or only its sign.
---@param list thread.Placed[]
---@param cur string|nil  the key of the one the cursor is on
---@param w thread.Walking|nil
---@return table<string, 'card'|'line'|'sign'>
local function sizes(list, cur, w)
  local out = {} ---@type table<string, 'card'|'line'|'sign'>
  for _, p in ipairs(list) do
    local size ---@type 'card'|'line'|'sign'
    if hidden then
      size = 'sign'
    elseif p.gone then
      size = 'line'
    elseif walked(p, w) then
      size = sized[p.key] or 'card'
    elseif p.step then
      size = sized[p.key] or (p.key == cur and 'line' or 'sign')
    elseif w and p.review.id ~= w.review then
      -- Walking, the other reviews' threads fold to a line.
      size = sized[p.key] or 'line'
    else
      size = sized[p.key] or mode
    end
    out[p.key] = size
  end
  -- On a line several share, the one you are on, or walk, at its size;
  -- the rest a line each.
  local lead = {} ---@type table<integer, string>
  for _, p in ipairs(list) do
    if out[p.key] ~= 'sign' and (not lead[p.line] or p.key == cur or walked(p, w)) then
      lead[p.line] = p.key
    end
  end
  for _, p in ipairs(list) do
    if out[p.key] == 'card' and lead[p.line] ~= p.key then
      out[p.key] = 'line'
    end
  end
  return out
end

--- What a buffer's cursor is on, worked out again: true when it changed.
--- Leaving a thread whose card showed you all it had new reads it.
---@param buf integer
---@return boolean
local function track(buf)
  local list = placed[buf] or {}
  local win = vim.api.nvim_get_current_win()
  local now ---@type { key: string, pinned: boolean|nil, shown: integer|nil }|nil
  if vim.api.nvim_win_get_buf(win) == buf then
    local here = place.covering(list, vim.api.nvim_win_get_cursor(win)[1])
    local keep = current[buf]
    local pick = here[1]
    for _, p in ipairs(here) do
      if keep and keep.pinned and p.key == keep.key then
        pick = p
      end
    end
    if pick then
      now = { key = pick.key, pinned = keep and keep.pinned and keep.key == pick.key, shown = (keep and keep.key == pick.key) and keep.shown or nil }
    end
  end
  local before = current[buf]
  if (before and before.key) == (now and now.key) then
    return false
  end
  if before and before.shown then
    for _, p in ipairs(list) do
      if p.key == before.key then
        thread.mark_read(p.review, conversation(p), before.shown)
      end
    end
  end
  current[buf] = now
  return true
end

-- The cards drawn in each buffer, by key: their mark, and what they were
-- drawn from, so one that would come out the same is left as it is.
local cards = {} ---@type table<integer, table<string, { id: integer, sig: string, shown: integer|nil }>>

--- The windows showing a buffer: the lines each shows, and its cursor's.
---@param buf integer
---@return { win: integer, top: integer, bot: integer, cursor: integer }[]
local function views(buf)
  local out = {}
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.api.nvim_win_get_config(win).relative == '' then
      out[#out + 1] = { win = win, top = vim.fn.line('w0', win), bot = vim.fn.line('w$', win), cursor = vim.api.nvim_win_get_cursor(win)[1] }
    end
  end
  return out
end

--- Whether a line is near enough to what a window shows to draw its card
--- now: a window's height from its view or its cursor (the cursor moves
--- before the window scrolls to it). The rest are drawn when scrolled to.
---@param seen { win: integer, top: integer, bot: integer, cursor: integer }[]
---@param line integer
---@return boolean
local function near(seen, line)
  if #seen == 0 then
    return true
  end
  for _, v in ipairs(seen) do
    local h = v.bot - v.top + 1
    if (line >= v.top - h and line <= v.bot + h) or math.abs(line - v.cursor) <= h then
      return true
    end
  end
  return false
end

--- A card above the first line shows only as filler the window is
--- scrolled up to, and moving back to the top never scrolls there. So
--- while the top of the file is in view, near the cursor, show it.
---@param buf integer
local function show_top(buf)
  local fill = 0
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, M.ns, { 0, 0 }, { 0, -1 }, { details = true })) do
    if m[4].virt_lines and m[4].virt_lines_above then
      fill = fill + #m[4].virt_lines
    end
  end
  if fill == 0 then
    return
  end
  for _, v in ipairs(views(buf)) do
    vim.api.nvim_win_call(v.win, function()
      local view = vim.fn.winsaveview()
      if v.top == 1 and view.topfill == 0 and view.lnum <= vim.api.nvim_win_get_height(v.win) / 2 then
        vim.fn.winrestview { topline = 1, topfill = fill }
      end
    end)
  end
end

--- Whether the rows a card hangs above its line are on screen in some
--- window.
---@param buf integer
---@param line integer
---@param rows integer
---@return boolean
local function in_view(buf, line, rows)
  for _, v in ipairs(views(buf)) do
    if line > v.top and line <= v.bot then
      return true
    end
    if line == v.top and vim.api.nvim_win_call(v.win, vim.fn.winsaveview).topfill >= rows then
      return true
    end
  end
  return false
end

--- Draw what was last located in a buffer.
---@param buf integer
function M.paint(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    placed[buf], current[buf], cards[buf] = nil, nil, nil
    return
  end
  local list = placed[buf] or {}
  local w = walking()
  local drawn = cards[buf] or {}
  cards[buf] = drawn
  -- Everything but the cards is drawn again each time: it is cheap.
  local keep = {} ---@type table<integer, true>
  for _, c in pairs(drawn) do
    keep[c.id] = true
  end
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, M.ns, 0, -1, {})) do
    if not keep[m[1]] then
      vim.api.nvim_buf_del_extmark(buf, M.ns, m[1])
    end
  end
  -- The diffs drawn in, the removed line a thread or step is on ended with
  -- its glyph and number.
  local shown = vim.deepcopy(diffs)
  if w then
    shown[w.review] = true
  end
  for id in pairs(shown) do
    local r = review.read(id)
    local spec = r and chunk.spec(r.diff)
    if r and spec then
      local said = {} ---@type table<integer, string[]>
      for _, p in ipairs(list) do
        if p.old and p.review.id == id then
          said[p.old] = { '  ' .. (p.step and '▸' or '▎') .. ' #' .. p.thread.id .. (p.step and ('.' .. p.step.id) or ''), card.colour(p) }
        end
      end
      marks.diff(buf, M.ns, spec, said)
    end
  end
  local cur = current[buf] and current[buf].key
  local size = sizes(list, cur, w)
  -- A sign on each line something covers, of the one innermost there.
  local on = {} ---@type table<integer, thread.Placed[]>
  for _, p in ipairs(list) do
    for line = p.line, p.to do
      on[line] = on[line] or {}
      table.insert(on[line], p)
    end
  end
  local signs = {} ---@type thread.Sign[]
  for line, all in pairs(on) do
    local here = #all > 1 and place.covering(all, line) or all
    local pick = here[1]
    for _, p in ipairs(here) do
      if p.key == cur then
        pick = p
      end
    end
    local glyph = pick.gone and '!' or pick.step and '▸' or '▎'
    signs[#signs + 1] = { line = line, text = (#here > 1 and '▎' or ' ') .. glyph, hl = card.colour(pick), zone = pick.key == cur and not hidden }
  end
  marks.signs(buf, M.ns, signs)
  -- The notes of the step walked here, else of what the cursor is on.
  local focus ---@type thread.Placed|nil
  for _, p in ipairs(list) do
    if walked(p, w) or (not focus and p.key == cur) then
      focus = p
    end
  end
  if focus and not focus.gone and not hidden then
    local notes = focus.step and focus.step.notes
    if not focus.step then
      for i = #focus.thread.messages, 1, -1 do
        notes = notes or focus.thread.messages[i].notes
      end
    end
    marks.notes(buf, M.ns, notes or {}, chunk.spec(focus.review.diff), room(buf))
  end
  -- The cards: each drawn again only when what it is drawn from has
  -- changed, and only near what a window shows.
  local width = room(buf)
  local seen = views(buf)
  local here = vim.api.nvim_win_get_buf(0) == buf and #place.covering(list, vim.api.nvim_win_get_cursor(0)[1]) or 0
  local tick, minute = vim.api.nvim_buf_get_changedtick(buf), math.floor(os.time() / 60)
  local stamps = {} ---@type table<thread.Review, string>
  local rank = {} ---@type table<integer, integer>
  local want = {} ---@type table<string, true>
  for _, p in ipairs(list) do
    local s = hidden and 'sign' or size[p.key]
    if s ~= 'sign' then
      ---@cast s 'card'|'line'
      want[p.key] = true
      -- Stacked on a line, the first on top: a lower priority sits higher.
      -- Above a removed line, above the diff's removed lines too.
      rank[p.line] = (rank[p.line] or 0) + 1
      local priority = (p.old and 80 or 110) + math.min(rank[p.line], 9)
      local line = vim.api.nvim_buf_get_lines(buf, p.line - 1, p.line, false)[1] or ''
      local indent = line:match '^%s*$' and 0 or text.width(line:match '^%s*')
      local o = { indent = indent, room = width, active = p.key == cur or walked(p, w), here = here, walked = walked(p, w) }
      stamps[p.review] = stamps[p.review] or review.stamp(p.review)
      local sig = table.concat({
        s,
        o.active and ('on' .. here) or 'off',
        o.walked and 'walked' or '',
        indent,
        width,
        priority,
        p.line,
        p.gone and 'gone' or '',
        stamps[p.review],
        diff_changes(),
        tick,
        minute,
      }, ' ')
      local had = drawn[p.key]
      local at = had and vim.api.nvim_buf_get_extmark_by_id(buf, M.ns, had.id, {})
      local same = had and had.sig == sig and at and at[1] == p.line - 1
      if not same and (had or near(seen, p.line)) then
        local lines, read = card.draw(p, s, o)
        local ok, id = pcall(vim.api.nvim_buf_set_extmark, buf, M.ns, p.line - 1, 0, {
          id = had and had.id or nil,
          virt_lines = lines,
          virt_lines_above = true,
          priority = priority,
        })
        drawn[p.key] = ok and { id = id, sig = sig, shown = read } or nil
      end
    end
  end
  for key, c in pairs(drawn) do
    if not want[key] then
      pcall(vim.api.nvim_buf_del_extmark, buf, M.ns, c.id)
      drawn[key] = nil
    end
  end
  show_top(buf)
  -- What the cursor is on has shown you what it had new once its card is
  -- on screen.
  local now = current[buf]
  local mark = now and drawn[now.key]
  if now and mark and mark.shown then
    local at = vim.api.nvim_buf_get_extmark_by_id(buf, M.ns, mark.id, { details = true })
    if at[1] and in_view(buf, at[1] + 1, #((at[3] or {}).virt_lines or {})) then
      now.shown = math.max(now.shown or 0, mark.shown)
    end
  end
end

--- Locate everything in a buffer again, and draw it.
---@param buf integer
function M.draw(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    placed[buf], current[buf] = nil, nil
    return
  end
  placed[buf] = place.locate(buf)
  track(buf)
  M.paint(buf)
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
  for buf in pairs(placed) do
    if not seen[buf] then
      local now = current[buf]
      if now and now.shown then
        for _, p in ipairs(placed[buf]) do
          if p.key == now.key then
            thread.mark_read(p.review, conversation(p), now.shown)
          end
        end
      end
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
      end
      placed[buf], current[buf], cards[buf] = nil, nil, nil
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
  if placed[buf] and track(buf) then
    M.paint(buf)
  end
end

--- What the cursor is on in the current buffer.
---@return thread.Placed|nil, integer  and how many cover its line
function M.here()
  local buf = vim.api.nvim_get_current_buf()
  if not placed[buf] then
    M.draw(buf)
  end
  local list = placed[buf] or {}
  local here = place.covering(list, vim.api.nvim_win_get_cursor(0)[1])
  local cur = current[buf]
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
  local here = place.covering(placed[buf] or {}, vim.api.nvim_win_get_cursor(0)[1])
  if #here < 2 then
    return
  end
  local at = 1
  for i, p in ipairs(here) do
    if current[buf] and p.key == current[buf].key then
      at = i
    end
  end
  current[buf] = { key = here[(at - 1 + n) % #here + 1].key, pinned = true }
  M.paint(buf)
end

--- What the cursor is on, as a card or as a line.
function M.fold()
  local p = M.here()
  if not p then
    return
  end
  local size = sizes(placed[vim.api.nvim_get_current_buf()] or {}, p.key, walking())[p.key]
  sized[p.key] = size == 'card' and 'line' or 'card'
  M.paint(vim.api.nvim_get_current_buf())
end

--- Every bubble at its own size, or a line each.
---@return 'card'|'line'
function M.toggle()
  mode = mode == 'card' and 'line' or 'card'
  sized, hidden = {}, false
  M.refresh()
  return mode
end

--- Hide everything but the signs, or show it again.
---@return boolean shown
function M.hide()
  hidden = not hidden
  M.refresh()
  return not hidden
end

--- Draw the diff of the review of what the cursor is on, or stop.
---@return boolean|nil on  nil when the cursor is on nothing of a diff's
function M.diff_here()
  local p = M.here()
  if not (p and p.review.diff) then
    return nil
  end
  local id = p.review.id
  diffs[id] = not diffs[id] or nil
  M.refresh()
  return diffs[id] == true
end

--- Open what the cursor is on: a thread focused in a float, a step's page.
function M.focus()
  local p = M.here()
  if not p then
    return
  end
  if p.step then
    go.open('page', { review = p.review, thread = p.thread, tour = p.tour, step = p.step }, 'code')
  else
    go.open('focus', { review = p.review, thread = p.thread }, 'code')
  end
end

--- Walk from what the cursor is on: a step, or a thread's tour from where
--- you left off.
---@return boolean  whether there is one to walk
function M.walk_here()
  local p = M.here()
  if not p or (not p.step and #thread.tours(p.thread) == 0) then
    return false
  end
  go.open('walk', { review = p.review, thread = p.thread, tour = p.tour, step = p.step }, 'code')
  return true
end

--- Reply in what the cursor is on.
function M.reply()
  local p = M.here()
  if p then
    go.open('compose', { replies = { { review = p.review, conversation = conversation(p) } } }, 'code')
  end
end

--- Close the thread the cursor is on, asking how; open it again if it is
--- closed.
function M.close_here()
  local p = M.here()
  if not p then
    return
  end
  vim.ui.select(actions.CLOSED, { prompt = 'Close #' .. p.thread.id .. ' as' }, function(status)
    if status then
      actions.set_status(p.review, p.thread, status)
    end
  end)
end

--- Start a thread on lines of the current buffer.
---@param from integer
---@param to integer
function M.add(from, to)
  local a, err = anchor.capture(vim.api.nvim_get_current_buf(), from, to)
  if not a then
    vim.notify('thread: ' .. (err or 'no line here'), vim.log.levels.WARN)
    return
  end
  go.open('compose', { chunk = { file = a.file, line = a.line, lines = a.lines, text = a.text, rev = a.rev } }, 'code')
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

--- Go to a chunk in the code, its review's diff drawn when it is on a
--- line the diff removed. One quoted at a revision is in the working tree
--- while its line is still there, else in the file as it was then.
---@param target thread.Target
local function open_at(target)
  local c = assert(target.chunk)
  local r = target.review
  local at = chunk.now(c)
  local rev = not at and c.side ~= 'old' and c.rev or nil
  at = at or chunk.locate(c, r and chunk.spec(r.diff))
  vim.api.nvim_set_current_win(code_win())
  local buf = rev and source.at_rev(rev, c.file)
  if buf then
    vim.api.nvim_win_set_buf(0, buf)
  else
    local path = repo.path(c.file)
    if vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':p') ~= vim.fn.fnamemodify(path, ':p') then
      vim.cmd.edit(vim.fn.fnameescape(path))
    end
  end
  if at and at.old and r then
    diffs[r.id] = true
  end
  -- The cursor there first: cards are drawn near it.
  pcall(vim.api.nvim_win_set_cursor, 0, { at and at.line or c.line, 0 })
  M.draw(vim.api.nvim_get_current_buf())
  vim.cmd 'normal! zz'
  M.cursor_moved()
end

--- The next (or previous) conversation that wants you, or with `all` any
--- open one, round the ends.
---@param d 1|-1
---@param all boolean|nil
function M.next(d, all)
  local s = find.next(d, all == true, source.of_buf(vim.api.nvim_get_current_buf()), vim.api.nvim_win_get_cursor(0)[1])
  if not s then
    vim.notify('thread: ' .. (all and 'no open thread is on a line' or 'nothing on a line wants you'))
    return
  end
  open_at { review = s.review, chunk = s.chunk }
end

--- Back to every bubble at its own size, shown, no diff drawn, nothing
--- located: as it starts.
function M.reset()
  mode, hidden, sized, diffs, placed, current, cards = 'card', false, {}, {}, {}, {}, {}
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
        if buf and placed[buf] and not done[buf] then
          done[buf] = true
          M.paint(buf)
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
    return source.of_buf(0) ~= nil and not hidden and M.here() ~= nil
  end
  for name, fn in pairs {
    focus = M.focus,
    fold = M.fold,
    next = function()
      M.cycle(1)
    end,
  } do
    if z[name] then
      keys.zone(z[name], fn, 'Thread: ' .. name, on)
    end
  end
end

go.register('code', { open = { code = open_at } })

return M
