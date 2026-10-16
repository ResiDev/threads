--- Drawing what the code has located in a buffer, and what it keeps
--- between draws: a sign on each line something covers; above each first
--- line a note's bubble or a step's card, its line, or nothing; the diffs
--- drawn in. A bubble or card is drawn again only when what it is drawn
--- from has changed, and only near what a window shows; the rest when
--- scrolled to.

local chunk = require 'thread.model.chunk'
local conversation = require 'thread.model.conversation'
local diff_changes = require('thread.base.diff').changes
local go = require 'thread.go'
local hang = require 'thread.code.hang'
local marks = require 'thread.code.marks'
local names = require 'thread.code.names'
local place = require 'thread.code.place'
local review = require 'thread.model.review'
local text = require 'thread.base.text'

local M = {}

M.ns = vim.api.nvim_create_namespace 'thread.code'

--- What the code keeps between draws.
---@class thread.CodeState
---@field mode 'card'|'line'  each at its own size, or each a line
---@field hidden boolean  signs only
---@field sized table<string, 'card'|'line'>  a note's or step's size set with Tab, by its key
---@field counts table<string, integer>  how many messages its card shows, set with zone.more and zone.less, by its key
---@field diffs table<string, true>  the reviews whose diff is drawn in, by id
---@field placed table<integer, thread.Placed[]>  where everything sits, by buffer, as last located
---@field current table<integer, { key: string, pinned: boolean|nil, shown: integer|nil }>  what the cursor is on, by buffer: its key; whether picked by hand; how many of its messages its card has shown you, once it is on screen
---@field hung table<integer, table<string, { id: integer, sig: string, shown: integer|nil }>>  what hangs in each buffer, by key: its mark, and what it was drawn from

---@type thread.CodeState
M.S = { mode = 'card', hidden = false, sized = {}, counts = {}, diffs = {}, placed = {}, current = {}, hung = {} }
local S = M.S

--- Back to every bubble at its own size, shown, no diff drawn, nothing
--- located: as it starts.
function M.reset()
  S.mode, S.hidden, S.sized, S.counts, S.diffs, S.placed, S.current, S.hung = 'card', false, {}, {}, {}, {}, {}, {}
end

---@return thread.Walking|nil
function M.walking()
  return go.ask 'walking'
end

---@param p thread.Placed
---@return thread.Conversation
function M.conversation(p)
  return hang.conversation(p)
end

--- Whether the walk is on this step.
---@param p thread.Placed
---@param w thread.Walking|nil
---@return boolean
local function walked(p, w)
  return w ~= nil and p.step ~= nil and w.review == p.review.id and w.step == p.step.id
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
function M.sizes(list, cur, w)
  local out = {} ---@type table<string, 'card'|'line'|'sign'>
  for _, p in ipairs(list) do
    local size ---@type 'card'|'line'|'sign'
    if S.hidden then
      size = 'sign'
    elseif p.gone then
      size = 'line'
    elseif walked(p, w) then
      size = S.sized[p.key] or 'card'
    elseif p.step then
      size = S.sized[p.key] or (p.key == cur and 'line' or 'sign')
    elseif w and p.review.id ~= w.review then
      -- Walking, the other reviews' notes fold to a line.
      size = S.sized[p.key] or 'line'
    else
      size = S.sized[p.key] or S.mode
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

--- Leaving what the cursor was on: what its card showed you is read.
---@param list thread.Placed[]
---@param before { key: string, shown: integer|nil }|nil
local function leave(list, before)
  if not (before and before.shown) then
    return
  end
  for _, p in ipairs(list) do
    if p.key == before.key then
      conversation.mark_read(p.review, M.conversation(p), before.shown)
    end
  end
end

--- What the cursor is on is `key`, picked by hand (S-Tab, ]h): it stays
--- on top on its line. The one it leaves is read as moving off it is.
---@param buf integer
---@param key string
function M.pick(buf, key)
  local before = S.current[buf]
  local same = before ~= nil and before.key == key
  if not same then
    leave(S.placed[buf] or {}, before)
  end
  S.current[buf] = { key = key, pinned = true, shown = same and before.shown or nil }
end

--- What a buffer's cursor is on, worked out again: true when it changed.
--- Leaving a note or step whose card showed you all it had new reads it.
---@param buf integer
---@return boolean
function M.track(buf)
  local list = S.placed[buf] or {}
  local win = vim.api.nvim_get_current_win()
  local now ---@type { key: string, pinned: boolean|nil, shown: integer|nil }|nil
  if vim.api.nvim_win_get_buf(win) == buf then
    local here = place.covering(list, vim.api.nvim_win_get_cursor(win)[1])
    local keep = S.current[buf]
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
  local before = S.current[buf]
  if (before and before.key) == (now and now.key) then
    return false
  end
  leave(list, before)
  S.current[buf] = now
  return true
end

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

--- How one is drawn above its line: set in to the line's indent, as wide
--- as the window has room for, active while the cursor is on it or it is
--- walked.
---@param buf integer
---@param p thread.Placed
---@param w thread.Walking|nil
---@param cur string|nil  the key of the one the cursor is on
---@param here integer  how many cover the cursor's line
---@param width integer
---@return thread.HangOpts
local function opts(buf, p, w, cur, here, width)
  local line = vim.api.nvim_buf_get_lines(buf, p.line - 1, p.line, false)[1] or ''
  return {
    indent = line:match '^%s*$' and 0 or text.width(line:match '^%s*'),
    room = width,
    active = p.key == cur or walked(p, w),
    here = here,
    walk = walked(p, w) and w or nil,
    messages = S.counts[p.key],
  }
end

--- A card as it hangs in a buffer, drawn again for the float that goes
--- into it, with that float's keys: its rows, and what in them goes
--- somewhere.
---@param buf integer
---@param p thread.Placed
---@return thread.VirtChunk[][], thread.Part[]
function M.inside(buf, p)
  local cur = S.current[buf] and S.current[buf].key
  local o = opts(buf, p, M.walking(), cur, 1, room(buf))
  o.active, o.inside = true, true
  local lines, _, parts = hang.draw(p, 'card', o)
  return lines, parts
end

--- Draw what was last located in a buffer.
---@param buf integer
function M.paint(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    S.placed[buf], S.current[buf], S.hung[buf] = nil, nil, nil
    return
  end
  local list = S.placed[buf] or {}
  local w = M.walking()
  local drawn = S.hung[buf] or {}
  S.hung[buf] = drawn
  -- Everything but the bubbles and cards is drawn again each time: it is
  -- cheap.
  local keep = {} ---@type table<integer, true>
  for _, c in pairs(drawn) do
    keep[c.id] = true
  end
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, M.ns, 0, -1, {})) do
    if not keep[m[1]] then
      vim.api.nvim_buf_del_extmark(buf, M.ns, m[1])
    end
  end
  -- The diffs drawn in, the removed line a note or step is on ended with
  -- its glyph and label.
  local shown = vim.deepcopy(S.diffs)
  if w then
    -- Walking, its review's diff is drawn unless turned off; a step on
    -- lines the diff removed is there only with it.
    local removed = false
    for _, q in ipairs(list) do
      removed = removed or (q.old ~= nil and walked(q, w))
    end
    shown[w.review] = (w.diff or removed) or nil
  end
  for id in pairs(shown) do
    local r = review.read(id)
    local spec = r and chunk.spec(r.diff)
    if r and spec then
      local said = {} ---@type table<integer, string[]>
      for _, p in ipairs(list) do
        if p.old and p.review.id == id then
          said[p.old] = { '  ' .. (p.step and ('▸ step ' .. p.step.id) or ('▎ note ' .. assert(p.note).id)), hang.colour(p) }
        end
      end
      marks.diff(buf, M.ns, spec, said)
    end
  end
  local cur = S.current[buf] and S.current[buf].key
  local size = M.sizes(list, cur, w)
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
    signs[#signs + 1] = { line = line, text = (#here > 1 and '▎' or ' ') .. glyph, hl = hang.colour(pick), zone = pick.key == cur and not S.hidden }
  end
  marks.signs(buf, M.ns, signs)
  -- The step walked: the names its text puts in backticks lit in its
  -- chunk; with focus on, all but the chunk washed quiet. Not a chunk not
  -- found: dimming around a guess would lend it confidence.
  for _, p in ipairs(list) do
    if w and walked(p, w) and not p.gone then
      if w.focus then
        marks.dim(buf, M.ns, p.line, p.to)
      end
      if not p.old then
        names.paint(buf, M.ns, p.line, p.to, names.of(assert(p.step), p.review))
      end
    end
  end
  -- The bubbles and cards: each drawn again only when what it is drawn from has
  -- changed, and only near what a window shows.
  local width = room(buf)
  local seen = views(buf)
  local here = vim.api.nvim_win_get_buf(0) == buf and #place.covering(list, vim.api.nvim_win_get_cursor(0)[1]) or 0
  local tick, minute = vim.api.nvim_buf_get_changedtick(buf), math.floor(os.time() / 60)
  local stamps = {} ---@type table<thread.Review, string>
  local rank = {} ---@type table<integer, integer>
  local want = {} ---@type table<string, true>
  for _, p in ipairs(list) do
    local s = S.hidden and 'sign' or size[p.key]
    if s ~= 'sign' then
      ---@cast s 'card'|'line'
      want[p.key] = true
      -- Stacked on a line, the first on top: a lower priority sits higher.
      -- Above a removed line, above the diff's removed lines too.
      rank[p.line] = (rank[p.line] or 0) + 1
      local priority = (p.old and 80 or 110) + math.min(rank[p.line], 9)
      local o = opts(buf, p, w, cur, here, width)
      stamps[p.review] = stamps[p.review] or review.stamp(p.review)
      local sig = table.concat({
        s,
        o.active and ('on' .. here) or 'off',
        o.walk and ('walked' .. (o.walk.focus and ' focus' or '') .. (o.walk.diff and ' diff' or '')) or '',
        o.indent,
        width,
        priority,
        p.line,
        p.gone and 'gone' or '',
        S.counts[p.key] or '',
        stamps[p.review],
        diff_changes(),
        tick,
        minute,
      }, ' ')
      local had = drawn[p.key]
      local at = had and vim.api.nvim_buf_get_extmark_by_id(buf, M.ns, had.id, {})
      local same = had and had.sig == sig and at and at[1] == p.line - 1
      if not same and (had or near(seen, p.line)) then
        local lines, read = hang.draw(p, s, o)
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
  local now = S.current[buf]
  local mark = now and drawn[now.key]
  if now and mark and mark.shown then
    local at = vim.api.nvim_buf_get_extmark_by_id(buf, M.ns, mark.id, { details = true })
    if at[1] and in_view(buf, at[1] + 1, #((at[3] or {}).virt_lines or {})) then
      now.shown = math.max(now.shown or 0, mark.shown)
    end
  end
end

return M
