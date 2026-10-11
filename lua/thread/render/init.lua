--- Threads in the code: a bubble above each thread's first line holding its
--- messages, and a bar in the sign column over every line it covers. The code
--- itself is never changed.
---
--- A bubble is as big as you make it: one line, or its last messages in full
--- (the default shows everything you have not read). The thread the cursor
--- is on lights up: its lines washed, its border bright, its keys listed
--- under it, and its notes on their lines.
---
--- A step of a tour is drawn the same way, as a card (thread.tour.display).
--- Until you reply in it it stays quiet, a sign only, unless it is the stop
--- you are walking or the cursor is on it: ten steps must not bury the code
--- in bubbles.

local bubble = require 'thread.render.bubble'
local look = require 'thread.look'
local marks = require 'thread.render.marks'
local place = require 'thread.render.place'
local store = require 'thread.store'
local text = require 'thread.text'
local tour = require 'thread.tour'

local M = {}

M.ns = vim.api.nvim_create_namespace 'thread'

-- 'full': each bubble at its own size; 'line': every bubble one line.
local mode = 'full'
-- Hidden: signs only, whatever the mode.
local hidden = false
-- batch id .. ':' .. comment id -> messages shown in full; 0 is one line.
local levels = {}
-- Dim everything but the thread you are on.
local dimming = false
-- thread id -> true: its changes drawn into the code.
local drawn = {}


----------------------------------------------------------------------
-- Sizes
----------------------------------------------------------------------

local function key_of(batch, comment)
  return (batch and batch.id or '') .. ':' .. comment.id
end

--- How many of a thread's messages its bubble shows in full; 0 is one line.
---@param batch thread.Batch|nil
---@param comment thread.Comment
---@return integer
function M.level(batch, comment)
  local set = levels[key_of(batch, comment)]
  if set then
    return math.min(set, #comment.messages)
  end
  if mode == 'line' or store.status(comment) == 'closed' then
    return 0
  end
  -- Everything you have not read, and at least the last message.
  local seen = batch and store.seen_count(batch, comment) or 0
  return math.max(1, math.min(#comment.messages, #comment.messages - seen))
end

--- Whether a thread's size was set by hand.
function M.set_level(batch, comment)
  return levels[key_of(batch, comment)] ~= nil
end

--- A thread's bubble to one line, or whole.
---@param batch thread.Batch
---@param comment thread.Comment
function M.fold(batch, comment)
  local whole = M.level(batch, comment) == 0
  -- The stop you are walking shows whole until set otherwise.
  local w = require('thread.walk').state()
  if comment.stop and w and w.owner == comment.stop.owner and w.n == comment.stop.n and not M.set_level(batch, comment) then
    whole = false
  end
  levels[key_of(batch, comment)] = whole and #comment.messages or 0
end

--- Show `n` more (or fewer) of a thread's messages.
---@param batch thread.Batch
---@param comment thread.Comment
---@param n integer
function M.resize(batch, comment, n)
  local cur = M.level(batch, comment)
  levels[key_of(batch, comment)] = math.max(0, math.min(#comment.messages, cur + n))
end

----------------------------------------------------------------------
-- Drawing
----------------------------------------------------------------------

--- Where a stop sits in its tour, for its card's top edge: `step 2/4`
--- and the tour's name.
local function crumb_of(batch, c)
  if not c.stop then
    return nil
  end
  local owner = store.find(batch, c.stop.owner)
  local list = owner and tour.of(owner)
  if not list then
    return nil
  end
  local pos = tour.position(list, c.stop.n)
  return { pos = pos, count = pos:gsub('^%a+ ', ''), head = store.title(owner), owner = owner.id, track = look.progress(list, c.stop.n) }
end

--- `2 stages · 4 steps`, when the thread's answer leads to a tour.
local function leads_of(c)
  local list = tour.of(c.real or c)
  return list and tour.describe(list) or nil
end

--- A stop no one has replied in, that you are not walking or on: a sign.
local function quiet(c, walk, is_cur)
  if is_cur or not c.virtual then
    return false
  end
  return not (walk and walk.owner == c.stop.owner and walk.n == c.stop.n)
end

local function room_for(bufnr)
  local win = vim.fn.bufwinid(bufnr)
  if win == -1 then
    return 100
  end
  return vim.api.nvim_win_get_width(win) - vim.fn.getwininfo(win)[1].textoff
end

--- Draw the bubbles and signs where they were last located.
---@param bufnr integer
function M.paint(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    place.placed[bufnr] = nil
    return
  end
  vim.api.nvim_buf_clear_namespace(bufnr, M.ns, 0, -1)
  -- A review's diff first, so the cards hang above its removed lines.
  require('thread.review').paint(bufnr, M.ns)
  local placed = place.placed[bufnr] or {}
  if #placed == 0 then
    return
  end
  local batch = store.active()
  local room = room_for(bufnr)
  local a = place.current(bufnr)
  local cur = a and a.id
  local walk = require('thread.walk').state()

  -- Which threads show a bubble: steps no one is walking or talking in
  -- stay quiet, a sign only.
  local shown = {}
  for _, p in ipairs(placed) do
    shown[p.comment.id] = not quiet(p.comment, walk, p.comment.id == cur)
  end

  -- Signs: one per line, deeper where threads overlap, in the colour of
  -- the current thread where it covers the line, else the innermost.
  local first, last = math.huge, 0
  for _, p in ipairs(placed) do
    first, last = math.min(first, p.line), math.max(last, p.to)
  end
  for lnum = first, last do
    local here = place.covering(placed, lnum)
    if #here > 0 then
      local pick = here[1]
      local open = 0
      for _, p in ipairs(here) do
        if p.comment.id == cur then
          pick = p
        end
        if store.status(p.comment) ~= 'closed' then
          open = open + 1
        end
      end
      local status = store.status(pick.comment)
      -- A thread is a bar; a tour's stop an arrow, in the light blue of
      -- tours until someone replies in it.
      local sign = open == 0 and ' ·' or open > 1 and '▎▎' or ' ▎'
      if pick.comment.stop and open > 0 then
        sign = open > 1 and '▎▸' or ' ▸'
      end
      pcall(vim.api.nvim_buf_set_extmark, bufnr, M.ns, lnum - 1, 0, {
        sign_text = pick.stale and ' !' or sign,
        sign_hl_group = pick.stale and 'DiagnosticWarn' or (bubble.both(pick.comment) and 'ThreadSignBoth') or bubble.SIGN[status],
        line_hl_group = pick.comment.id == cur and not hidden and 'ThreadZone' or nil,
        priority = 20,
      })
    end
  end
  if hidden then
    return
  end

  -- The thread in focus here: the stop being walked when it is in this
  -- buffer, else the one the cursor is on. Its notes and its scope.
  local function walked(c)
    return walk and c.stop and c.stop.owner == walk.owner and c.stop.n == walk.n
  end
  local focus
  for _, p in ipairs(placed) do
    if walked(p.comment) then
      focus = p
    end
  end
  if not focus then
    for _, p in ipairs(placed) do
      if p.comment.id == cur then
        focus = p
      end
    end
  end
  if focus and not focus.stale then
    marks.notes(bufnr, focus.comment, room)
    if dimming then
      marks.dim(bufnr, focus.line, focus.to)
    end
  end
  for _, p in ipairs(placed) do
    if drawn[(p.comment.real or p.comment).id] and batch then
      marks.changes(bufnr, batch, p.comment)
    end
  end

  -- Threads on the same line stack: the current one at its size, the
  -- others one line each, so a stack never pushes the code off screen.
  local lead_of = {}
  for _, p in ipairs(placed) do
    if shown[p.comment.id] and (not lead_of[p.line] or p.comment.id == cur or walked(p.comment)) then
      lead_of[p.line] = p.comment.id
    end
  end
  -- Virtual lines placed later sit above earlier ones on the same line, so
  -- walk backwards: the lowest-numbered thread ends up on top.
  for i = #placed, 1, -1 do
    local p = placed[i]
    local c = p.comment
    if shown[c.id] then
      local row = p.line - 1
      local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ''
      local indent = line:match '^%s*$' and 0 or text.width(line:match '^%s*')
      local level = M.level(batch, c)
      if lead_of[p.line] ~= c.id then
        level = 0
      end
      local crumb = batch and crumb_of(batch, c)
      local walking = walked(c)
      if walking and not M.set_level(batch, c) then
        -- The stop you are walking: its words and all the talk in it.
        level = #c.messages
      elseif c.virtual and not M.set_level(batch, c) then
        -- A stop you are not walking: one line under the cursor, enough
        -- to say what it is; Tab shows it whole.
        level = 0
      elseif walk and not (c.stop and c.stop.owner == walk.owner) and not M.set_level(batch, c) then
        -- Walking a tour, every other thread folds to a line.
        level = 0
      end
      local seen = batch and store.seen_count(batch, c) or #c.messages
      local is_cur = c.id == cur
      if is_cur then
        -- Read once it has all been on screen: everything after `seen`.
        a.full = level > 0 and #c.messages - level <= seen
      end
      pcall(vim.api.nvim_buf_set_extmark, bufnr, M.ns, row, 0, {
        virt_lines = bubble.draw(c, indent, room, {
          level = level,
          active = is_cur or walking,
          here = a and a.here,
          seen = seen,
          stale = p.stale,
          crumb = crumb,
          walking = walking,
          leads = leads_of(c),
        }),
        virt_lines_above = true,
        priority = 110,
      })
    end
  end
end

--- Bring the next (or previous) thread covering the cursor's line on top.
---@param n integer
---@return thread.Comment|nil
function M.cycle(n)
  local c = place.cycle(n)
  if c then
    M.paint(vim.api.nvim_get_current_buf())
  end
  return c
end

--- Locate the comments in a buffer again, and draw them.
---@param bufnr integer
function M.draw(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    place.placed[bufnr] = nil
    return
  end
  place.placed[bufnr] = place.locate(bufnr)
  place.track(bufnr)
  M.paint(bufnr)
end

--- Redraw every buffer on screen.
function M.refresh()
  local seen = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if not seen[buf] then
      seen[buf] = true
      M.draw(buf)
    end
  end
  for buf in pairs(place.placed) do
    if not seen[buf] and vim.api.nvim_buf_is_valid(buf) then
      M.draw(buf)
    end
  end
end

local pending = false
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

--- The cursor moved: light up the comment it is on now, if that changed.
function M.cursor_moved()
  local buf = vim.api.nvim_get_current_buf()
  if place.placed[buf] and place.track(buf) then
    M.paint(buf)
  end
  M.show_top()
end

--- A card above the first line shows only as filler the window is
--- scrolled up to, and moving the cursor back to the top never scrolls
--- there. So while the top of the file is in view, near the cursor, show it.
function M.show_top()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  if not place.placed[buf] or vim.fn.line('w0', win) ~= 1 then
    return
  end
  local view = vim.fn.winsaveview()
  if view.topfill > 0 or view.lnum > vim.api.nvim_win_get_height(win) / 2 then
    return
  end
  local fill = 0
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, M.ns, { 0, 0 }, { 0, -1 }, { details = true })) do
    if m[4].virt_lines and m[4].virt_lines_above then
      fill = fill + #m[4].virt_lines
    end
  end
  if fill > 0 then
    vim.fn.winrestview { topline = 1, topfill = fill }
  end
end

--- Every bubble at its own size, or one line each.
---@return 'full'|'line'
function M.toggle()
  mode = mode == 'full' and 'line' or 'full'
  -- A new mode applies to every bubble: sizes set by hand go.
  levels = {}
  hidden = false
  M.refresh()
  return mode
end

---@return 'full'|'line'
function M.mode()
  return mode
end

--- Hide every bubble, leaving the signs, or show them again.
---@return boolean visible
function M.hide()
  hidden = not hidden
  M.refresh()
  return not hidden
end

function M.visible()
  return not hidden
end

--- Dim everything but the thread in focus, or stop.
---@return boolean on
function M.dim()
  dimming = not dimming
  M.refresh()
  return dimming
end

function M.dimming()
  return dimming
end

--- Draw a thread's changes into the code, or stop.
---@param id integer
---@return boolean on
function M.toggle_drawn(id)
  drawn[id] = not drawn[id] or nil
  M.refresh()
  return drawn[id] == true
end

--- After a save, re-quote comments that only matched loosely, so the next
--- edit starts from the line as it is now.
---@param bufnr integer
function M.follow(bufnr)
  local batch = store.active()
  if not batch then
    return
  end
  local changed = false
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for _, p in ipairs(place.locate(bufnr)) do
    -- A stop no one replied in belongs to the agent's message: left alone.
    local c = p.comment.real or p.comment
    if not p.stale and not p.comment.virtual and (c.line ~= p.line or (p.confidence < 1 and lines[p.line] ~= c.text)) then
      c.line = p.line
      if c.text ~= '' then
        c.text = lines[p.line]
      end
      changed = true
    end
  end
  if changed then
    store.save(batch)
  end
end

return M
