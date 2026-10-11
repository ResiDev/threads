--- One thread focused from the code, in a float in the middle: all of it,
--- nothing around it. Its title says which threads h and l go to, its
--- footer lists its keys, and once you step with h and l a strip under it
--- shows the threads either side.

local float = require 'thread.float'
local look = require 'thread.look'
local model = require 'thread.home.model'
local sheet = require 'thread.sheet'
local store = require 'thread.store'
local text = require 'thread.text'
local thread = require 'thread.home.thread'
local tour = require 'thread.tour'

local M = {}

local ns = vim.api.nvim_create_namespace 'thread.home.strip'

--- The thread, open in full; and which threads h and l go to.
function M.draw(P, S, batch, width)
  local t = model.collect(batch, nil, S.single)[1]
  if not t then
    P.add ''
    return
  end
  -- Round the ends: h on the first goes to the last.
  S.prev, S.next = nil, nil
  local list = model.neighbours(batch, S.single)
  for i, n in ipairs(list) do
    if n.c.id == S.single and #list > 1 then
      S.prev, S.next = list[(i - 2) % #list + 1], list[i % #list + 1]
    end
  end
  for _, n in ipairs { S.prev, S.next } do
    n.status, n.unseen = store.status(n.c), store.unseen(batch, n.c)
  end
  S.order, S.focus = { t.c.id }, t.c.id
  if S.seen_at[t.c.id] == nil then
    S.seen_at[t.c.id] = store.seen_count(batch, t.c)
  end
  S.row_of[t.c.id] = 1
  P.own(t.c.id)
  thread.draw(P, S, t, #t.c.messages, width)
  S.focused_thread, S.focused_level = t, #t.c.messages
end

--- The float's title: the focused thread's glyph, id, name and dots on
--- the left; on the right, the threads h and l go to.
function M.title(S)
  local t = S.focused_thread
  if not t then
    return ' '
  end
  local width = vim.api.nvim_win_get_width(S.win)
  local g, ghl = look.glyph(t.status, t.unseen, t.anchored and not t.line)
  local left = { { ' ' } }
  -- The way back up: the tour it is in, by name.
  local batch = store.active()
  local owner = batch and t.c.on and tour.owner(batch, t.c)
  if owner then
    vim.list_extend(left, { { text.fit(store.title(owner), 18), 'ThreadCrumb' }, { ' › ', 'ThreadCrumb' } })
  end
  vim.list_extend(left, { { g, ghl }, { ' ' .. t.c.id .. ' ', 'ThreadMeta' } })
  left[#left + 1] = { text.fit(store.title(t.c), math.max(10, math.floor(width * (owner and 0.3 or 0.4)))), 'ThreadTitle' }
  left[#left + 1] = { ' ' }
  vim.list_extend(left, look.dots(t.c.messages, S.seen_at[t.c.id] or t.seen or 0))
  left[#left + 1] = { ' ' }
  -- Each neighbour gets half of what is left, its name cut to fit.
  local room = math.floor((width - text.width(left) - 12) / 2)
  local right = {}
  local function side(n, before)
    if not n then
      return
    end
    local ng, nhl = look.glyph(n.status, n.unseen, n.anchored and not n.line)
    local name = text.fit(store.title(n.c), math.max(6, room - 6))
    if before then
      vim.list_extend(right, { { ' h', 'ThreadKey' }, { ' ← ', 'ThreadKeyLabel' }, { ng, nhl }, { ' ' .. name .. ' ', 'ThreadKeyLabel' } })
    else
      vim.list_extend(right, { { ' ' .. name .. ' ', 'ThreadKeyLabel' }, { ng, nhl }, { ' → ', 'ThreadKeyLabel' }, { 'l ', 'ThreadKey' } })
    end
  end
  if room >= 10 then
    side(S.prev, true)
    if S.prev and S.next then
      right[#right + 1] = { '─', 'FloatBorder' }
    end
    side(S.next, false)
  end
  local fill = width - text.width(left) - text.width(right) - 1
  if #right > 0 and fill > 0 then
    left[#left + 1] = { string.rep('─', fill), 'FloatBorder' }
    vim.list_extend(left, right)
  end
  return left
end

--- The float's footer: the thread's keys, or a reply's.
function M.footer(S)
  if S.reply then
    return look.footer { { '<C-s>', 'save' }, { '<C-c>', 'cancel' } }
  end
  return look.footer(vim.list_extend(vim.deepcopy(S.single_keys or {}), { { '?', 'help' } }))
end

--- In the middle of the editor, as tall as the thread up to nearly all of
--- it: the code it covers is drawn at its top.
function M.place(S)
  local width = math.min(vim.o.columns - 8, 110)
  vim.api.nvim_win_set_config(S.win, { width = width })
  local height = math.max(3, math.min(float.max_height(4), vim.api.nvim_win_text_height(S.win, {}).all))
  vim.api.nvim_win_set_config(S.win, float.centred(width, height))
end

--- Under the float, once you step with h and l: the threads they go
--- through, a few either side, `▸` on this one.
function M.strip(S)
  if not (S.single and S.strip_on and vim.api.nvim_win_is_valid(S.win)) then
    return
  end
  local batch = store.active()
  if not batch then
    return
  end
  local list = model.neighbours(batch, S.single)
  local at = 1
  for i, n in ipairs(list) do
    if n.c.id == S.single then
      at = i
    end
  end
  local lo = math.max(1, math.min(at - 3, #list - 6))
  local cfg = vim.api.nvim_win_get_config(S.win)
  local P = sheet.new()
  for i = lo, math.min(#list, lo + 6) do
    local n, here = list[i], i == at
    local g, ghl = look.glyph(store.status(n.c), store.unseen(batch, n.c), false)
    local where = n.anchored and (vim.fs.basename(n.c.file) .. ':' .. (n.line or '–')) or 'general'
    local chunks = { { ' ' }, { here and '▸' or ' ', 'ThreadFocus' }, { ' ' }, { g, ghl }, { string.format(' %3d  ', n.c.id) } }
    local name = text.fit(store.title(n.c), cfg.width - text.width(chunks) - text.width(where) - 4)
    chunks[#chunks + 1] = { name, here and 'ThreadTitle' or 'ThreadMeta' }
    chunks[#chunks + 1] = { string.rep(' ', math.max(2, cfg.width - text.width(chunks) - text.width(where) - 1)) }
    chunks[#chunks + 1] = { where, 'LineNr' }
    P.chunks(chunks, 0)
  end
  if not (S.strip and vim.api.nvim_win_is_valid(S.strip.win)) then
    local win, buf = float.open {
      enter = false,
      win = { width = cfg.width, focusable = false, zindex = 60 },
      wo = { winhighlight = 'NormalFloat:Normal,FloatBorder:ThreadTabRule' },
    }
    S.strip = { win = win, buf = buf }
  end
  P.apply(S.strip.buf, ns)
  -- Under the float when there is room; else over its foot.
  local below = cfg.row + cfg.height + 2
  local max = vim.o.lines - vim.o.cmdheight - 1
  vim.api.nvim_win_set_config(S.strip.win, {
    relative = 'editor',
    row = below + #P.lines + 2 <= max and below or (max - #P.lines - 2),
    col = cfg.col,
    width = cfg.width,
    height = #P.lines,
    title = { { ' h ← threads → l ', 'ThreadKeyLabel' } },
    title_pos = 'center',
  })
end

return M
