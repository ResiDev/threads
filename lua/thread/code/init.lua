--- The code: every open review's threads and steps where they are in each
--- buffer on screen. A sign on each line one covers; above its first line
--- a thread's bubble, its card from draw/, or its line; a step's card
--- while it is walked or asked for, its line while the cursor is on it,
--- else only its sign, so a tour does not bury the code. The notes of
--- what the cursor is on show on their lines, and a review's diff is
--- drawn in when you ask, or while you walk one of its steps.

local actions = require 'thread.actions'
local anchor = require 'thread.base.anchor'
local bubble = require 'thread.code.bubble'
local chunk = require 'thread.model.chunk'
local config = require 'thread.config'
local find = require 'thread.code.find'
local go = require 'thread.go'
local keys = require 'thread.ui.keys'
local labels = require 'thread.draw.labels'
local look = require 'thread.ui.look'
local marks = require 'thread.code.marks'
local message = require 'thread.draw.message'
local place = require 'thread.code.place'
local repo = require 'thread.base.repo'
local review = require 'thread.model.review'
local sheet = require 'thread.ui.sheet'
local source = require 'thread.base.source'
local step_draw = require 'thread.draw.step'
local text = require 'thread.base.text'
local thread = require 'thread.model.thread'
local thread_draw = require 'thread.draw.thread'

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
-- What the cursor is on, by buffer: its key; whether picked by hand; whether
-- its card has shown all you had not read.
local current = {} ---@type table<integer, { key: string, pinned: boolean|nil, shown: boolean|nil }>

-- An inactive frame's colour, by the colour of whose move it is.
local BORDER = {
  ThreadSignAnswered = 'ThreadBorderAnswered',
  ThreadSignWaiting = 'ThreadBorderWaiting',
  ThreadSignInfo = 'ThreadBorderInfo',
  ThreadSignInfoNew = 'ThreadBorderInfo',
  ThreadSignDone = 'ThreadSignDone',
}

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

--- The colour of whose move a conversation is, for its sign and frame.
---@param p thread.Placed
---@return string
local function colour(p)
  if p.gone then
    return 'DiagnosticWarn'
  end
  if p.step and #p.step.messages == 0 then
    return 'ThreadSignInfo'
  end
  local _, hl = labels.conversation(p.review, conversation(p))
  return hl
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

--- The keys a card lists while the cursor is on it.
---@param p thread.Placed
---@param here integer  how many cover the cursor's line
---@param size 'card'|'line'
---@return thread.Chunks
local function hints(p, here, size)
  local z = config.options.zone or {}
  local list = {} ---@type { [1]: string, [2]: string }[]
  if z.focus then
    list[#list + 1] = { look.show_key(z.focus):gsub('<CR>', '⏎'), 'open' }
  end
  local walk = config.options.mappings.walk
  if walk and (p.step or #thread.tours(p.thread) > 0) then
    list[#list + 1] = { look.show_key(walk), p.step and 'walk from here' or 'walk it' }
  end
  if here > 1 and z.next then
    list[#list + 1] = { (look.show_key(z.next):gsub('<S%-Tab>', 'S-tab')), here == 2 and 'the other here' or ('next of ' .. here) }
  end
  if z.fold then
    list[#list + 1] = { (look.show_key(z.fold):gsub('<Tab>', 'tab')), size == 'line' and 'whole' or 'fold' }
  end
  return look.hints(list)
end

--- Draw one: as a card, framed, or as a line.
---@param p thread.Placed
---@param size 'card'|'line'
---@param o { indent: integer, room: integer, active: boolean, here: integer, walked: boolean }
---@return thread.VirtChunk[][]
local function drawn(p, size, o)
  local width = math.max(24, math.min(config.options.ui.width, o.room - o.indent - 6))
  local P = sheet.new()
  local r, t = p.review, p.thread
  if size == 'line' then
    if p.step then
      step_draw.line(P, r, t, assert(p.tour), p.step, { width = width + 4 })
    else
      thread_draw.line(P, r, t, { width = width + 4 })
    end
    if p.gone then
      local c = assert(t.chunk)
      P.chunks(text.fit_chunks({ { '  ! its line is gone; it read ', 'DiagnosticWarn' }, { vim.trim(c.text), 'ThreadMeta' } }, width + 4), 0)
    end
    return bubble.lines(P, o.indent)
  end
  if p.step then
    step_draw.card(P, r, t, assert(p.tour), p.step, { width = width, messages = o.walked and #p.step.messages or nil })
  else
    thread_draw.card(P, r, t, { width = width, messages = math.max(message.LAST, thread.unread(r, conversation(p))) })
  end
  local hl = colour(p)
  return bubble.frame(P, {
    indent = o.indent,
    width = width,
    border = o.active and hl or (BORDER[hl] or 'ThreadBorderInfo'),
    top = { { r.title, 'ThreadCrumb' } },
    keys = o.active and hints(p, o.here, size) or nil,
  })
end

--- What a buffer's cursor is on, worked out again: true when it changed.
--- Leaving a thread whose card showed you all it had new reads it.
---@param buf integer
---@return boolean
local function track(buf)
  local list = placed[buf] or {}
  local win = vim.api.nvim_get_current_win()
  local now ---@type { key: string, pinned: boolean|nil, shown: boolean|nil }|nil
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
      now = { key = pick.key, pinned = keep and keep.pinned and keep.key == pick.key, shown = keep and keep.key == pick.key and keep.shown }
    end
  end
  local before = current[buf]
  if (before and before.key) == (now and now.key) then
    return false
  end
  if before and before.shown then
    for _, p in ipairs(list) do
      if p.key == before.key then
        thread.mark_read(p.review, conversation(p))
      end
    end
  end
  current[buf] = now
  return true
end

--- Draw what was last located in a buffer.
---@param buf integer
function M.paint(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    placed[buf], current[buf] = nil, nil
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  local list = placed[buf] or {}
  local w = walking()
  -- The diffs first, so the cards hang above their removed lines.
  local shown = vim.deepcopy(diffs)
  if w then
    shown[w.review] = true
  end
  for id in pairs(shown) do
    local r = review.read(id)
    local spec = r and chunk.spec(r.diff)
    if spec then
      marks.diff(buf, M.ns, spec)
    end
  end
  if #list == 0 then
    return
  end
  local cur = current[buf] and current[buf].key
  local size = sizes(list, cur, w)
  local signs = {} ---@type thread.Sign[]
  local first, last = math.huge, 0
  for _, p in ipairs(list) do
    first, last = math.min(first, p.line), math.max(last, p.to)
  end
  for line = first, last do
    local here = place.covering(list, line)
    local pick = here[1]
    for _, p in ipairs(here) do
      if p.key == cur then
        pick = p
      end
    end
    if pick then
      local glyph = pick.gone and '!' or pick.step and '▸' or '▎'
      signs[#signs + 1] = { line = line, text = (#here > 1 and '▎' or ' ') .. glyph, hl = colour(pick), zone = pick.key == cur and not hidden }
    end
  end
  marks.signs(buf, M.ns, signs)
  if hidden then
    return
  end
  -- The notes of the step walked here, else of what the cursor is on.
  local focus ---@type thread.Placed|nil
  for _, p in ipairs(list) do
    if walked(p, w) or (not focus and p.key == cur) then
      focus = p
    end
  end
  if focus and not focus.gone then
    local notes = focus.step and focus.step.notes
    if not focus.step then
      for i = #focus.thread.messages, 1, -1 do
        notes = notes or focus.thread.messages[i].notes
      end
    end
    marks.notes(buf, M.ns, notes or {}, chunk.spec(focus.review.diff), room(buf))
  end
  local width = room(buf)
  local here = vim.api.nvim_win_get_buf(0) == buf and #place.covering(list, vim.api.nvim_win_get_cursor(0)[1]) or 0
  -- Virtual lines placed later sit above earlier ones on the same line:
  -- backwards, so the first ends on top.
  for i = #list, 1, -1 do
    local p = list[i]
    local s = size[p.key]
    if s ~= 'sign' then
      local line = vim.api.nvim_buf_get_lines(buf, p.line - 1, p.line, false)[1] or ''
      local indent = line:match '^%s*$' and 0 or text.width(line:match '^%s*')
      local active = p.key == cur or walked(p, w)
      if p.key == cur and s == 'card' then
        current[buf].shown = true
      end
      ---@cast s 'card'|'line'
      pcall(vim.api.nvim_buf_set_extmark, buf, M.ns, p.line - 1, 0, {
        virt_lines = drawn(p, s, { indent = indent, room = width, active = active, here = here, walked = walked(p, w) }),
        virt_lines_above = true,
        priority = 110,
      })
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
  for buf in pairs(placed) do
    if not seen[buf] then
      M.draw(buf)
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
    return vim.api.nvim_win_get_config(w).relative == '' and vim.bo[vim.api.nvim_win_get_buf(w)].buftype == ''
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
--- line the diff removed.
---@param target thread.Target
local function open_at(target)
  local c = assert(target.chunk)
  local r = target.review
  local at = chunk.locate(c, r and chunk.spec(r.diff))
  vim.api.nvim_set_current_win(code_win())
  local path = repo.path(c.file)
  if vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':p') ~= vim.fn.fnamemodify(path, ':p') then
    vim.cmd.edit(vim.fn.fnameescape(path))
  end
  if at and at.old and r then
    diffs[r.id] = true
  end
  M.draw(vim.api.nvim_get_current_buf())
  pcall(vim.api.nvim_win_set_cursor, 0, { at and at.line or c.line, 0 })
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
  mode, hidden, sized, diffs, placed, current = 'card', false, {}, {}, {}, {}
end

--- Its autocmds and the keys that act on what the cursor is on.
function M.setup()
  local group = vim.api.nvim_create_augroup('thread.code', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinResized', 'TextChanged', 'InsertLeave' }, { group = group, callback = M.schedule })
  vim.api.nvim_create_autocmd('CursorMoved', { group = group, callback = M.cursor_moved })
  vim.api.nvim_create_autocmd('User', { group = group, pattern = { 'ThreadChanged', 'ThreadWalk' }, callback = M.schedule })
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = group,
    callback = function(ev)
      find.requote(ev.buf)
    end,
  })
  local z = config.options.zone or {}
  local function on()
    return vim.bo.buftype == '' and not hidden and M.here() ~= nil
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
