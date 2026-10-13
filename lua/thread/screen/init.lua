--- The screen: one window at four depths, the reviews (Home), a review, a
--- thread, a step. Full screen it is Home and what is under it; in a
--- float over the code it is a thread focused from there, or a step's
--- page. The cursor goes from item to item, a thread, a step, a file,
--- the one it is on lit; `o` opens an item and lets the cursor in to read
--- it line by line. Its keys (thread.screen.keys) act on the part under
--- the cursor, and a level with one child opens as the child. What you
--- have not read in a thread or a step stays lit until you leave it.

local draw = require 'thread.draw'
local float = require 'thread.ui.float'
local go = require 'thread.go'
local keys = require 'thread.screen.keys'
local look = require 'thread.ui.look'
local review = require 'thread.model.review'
local sheet = require 'thread.ui.sheet'
local thread = require 'thread.model.thread'
local view = require 'thread.screen.view'

local M = {}

local ns = vim.api.nvim_create_namespace 'thread.screen'
local ns_item = vim.api.nvim_create_namespace 'thread.screen.item'

---@alias thread.Depth 'home'|'review'|'thread'|'step'

--- Where the screen is: the depth, and the review, thread and step.
---@class thread.ScreenAt
---@field depth thread.Depth
---@field review string|nil  its id
---@field thread integer|nil
---@field step integer|nil

---@class thread.ScreenState: thread.ScreenAt
---@field win integer
---@field buf integer
---@field over integer|nil  in a float over the code: the window it came from
---@field focus string|nil  Home: the review you are on
---@field query string|nil  Home: only what mentions it
---@field show 'open'|'closed'|'all'  Home: which reviews
---@field marked table<string, { review: string, thread: integer }>  threads picked with space, by `<review>#<id>`
---@field parts thread.Part[]
---@field reading thread.ScreenAt|nil  a thread or step drawn whole, read when you leave it
---@field open table<string, true>  the items opened, by draw.key
---@field opened string|nil  the item `o` opened, which `o` or Esc closes
---@field free boolean  the cursor let into an item, moving by lines
---@field files boolean  a review's or a thread's chunks laid out by file
---@field drawing boolean

local S ---@type thread.ScreenState|nil

---@return boolean
function M.is_open()
  return S ~= nil and vim.api.nvim_win_is_valid(S.win)
end

--- The screen's state, while it is open.
---@return thread.ScreenState|nil
function M.state()
  return M.is_open() and S or nil
end

--- The review, thread, tour and step the screen is at, read afresh.
---@return thread.Review|nil, thread.Thread|nil, thread.Tour|nil, thread.Step|nil
function M.at()
  if not S then
    return nil
  end
  local r = S.review and review.read(S.review) or nil
  local t = r and S.thread and review.find(r, S.thread) or nil
  local s, x ---@type thread.Step|nil, thread.Tour|nil
  if t and S.step then
    s, x = thread.step(t, S.step)
  end
  return r, t, x, s
end

--- The part under the cursor, and the cursor's row and byte column.
---@return thread.Part|nil, integer, integer
function M.here()
  if not M.is_open() then
    return nil, 0, 0
  end
  local s = assert(S)
  local cur = vim.api.nvim_win_get_cursor(s.win)
  return draw.at(s.parts, cur[1] - 1, cur[2]), cur[1] - 1, cur[2]
end

--- One of what j and k step through: its part, and its rows, up to the
--- next item's, the blank rows at its end left out.
---@class thread.ScreenItem
---@field part thread.Part
---@field first integer  0-based
---@field last integer

--- The items on the screen, top to bottom.
---@return thread.ScreenItem[]
function M.items()
  if not M.is_open() then
    return {}
  end
  local s = assert(S)
  local seen, list = {}, {} ---@type table<integer, true>, thread.Part[]
  for _, p in ipairs(s.parts) do
    if p.item and not seen[p.first] then
      seen[p.first] = true
      list[#list + 1] = p
    end
  end
  table.sort(list, function(a, b)
    return a.first < b.first
  end)
  local lines = vim.api.nvim_buf_get_lines(s.buf, 0, -1, false)
  local out = {} ---@type thread.ScreenItem[]
  for i, p in ipairs(list) do
    local last = list[i + 1] and (list[i + 1].first - 1) or math.max(p.first, p.last)
    while last > p.first and vim.trim(lines[last + 1] or '') == '' do
      last = last - 1
    end
    out[i] = { part = p, first = p.first, last = last }
  end
  return out
end

--- The item the cursor is in, and its place among them.
---@return thread.ScreenItem|nil, integer
function M.item()
  local list = M.items()
  if not M.is_open() then
    return nil, 0
  end
  local row = vim.api.nvim_win_get_cursor(assert(S).win)[1] - 1
  local at = 0
  for i, it in ipairs(list) do
    if it.first <= row then
      at = i
    end
  end
  return list[at], at
end

--- Light the item the cursor is in; none while it reads line by line.
function M.light()
  if not M.is_open() then
    return
  end
  local s = assert(S)
  vim.api.nvim_buf_clear_namespace(s.buf, ns_item, 0, -1)
  vim.wo[s.win].cursorline = s.free
  if s.free then
    return
  end
  local it = M.item()
  if not it then
    return
  end
  for row = it.first, it.last do
    vim.api.nvim_buf_set_extmark(s.buf, ns_item, row, 0, {
      virt_text = { { '▎', 'ThreadItemBar' } },
      virt_text_win_col = 0,
      line_hl_group = 'ThreadItem',
      priority = 5,
    })
  end
end

--- Whether two parts are the same thing, drawn again.
---@param a thread.Part
---@param b thread.Part
---@return boolean
local function same(a, b)
  return a.kind == b.kind
    and (a.review and a.review.id) == (b.review and b.review.id)
    and (a.thread and a.thread.id) == (b.thread and b.thread.id)
    and (a.step and a.step.id) == (b.step and b.step.id)
    and a.message == b.message
    and a.s == b.s
    and (a.chunk and a.chunk.line) == (b.chunk and b.chunk.line)
end

--- Where it says you are, for its title.
---@return string
local function title()
  local s = assert(S)
  local r, t, _, st = M.at()
  local function named(th)
    return '#' .. th.id .. (th.title and (' ' .. th.title) or '')
  end
  if s.depth == 'home' then
    return ' Home' .. (s.show == 'open' and '' or (' · ' .. s.show)) .. (s.query and (' · /' .. s.query) or '') .. ' '
  elseif s.depth == 'review' then
    return ' Home › ' .. (r and r.title or '') .. ' '
  elseif s.depth == 'thread' and t then
    return (s.over and ' ' or (' ' .. (r and r.title or '') .. ' › ')) .. named(t) .. ' '
  elseif st and t then
    return ' ' .. named(t) .. ' › ' .. st.title .. ' '
  end
  return ' '
end

--- Draw it again where it is, the cursor kept on what it was on.
function M.draw()
  if not M.is_open() then
    return
  end
  local s = assert(S)
  s.drawing = true
  local was, row, col = M.here()
  local r, t, x, st = M.at()
  -- What went from the file takes you up to what is left, which you are
  -- reading now.
  if s.depth == 'step' and not st then
    s.depth, s.step = t and 'thread' or 'review', nil
    s.reading = t and { depth = 'thread', review = s.review, thread = s.thread } or nil
  end
  if s.depth == 'thread' and not t then
    s.depth, s.thread = r and 'review' or 'home', nil
  end
  if s.depth == 'review' and not r then
    s.depth, s.review = 'home', nil
  end
  local width = vim.api.nvim_win_get_width(s.win) - 2 * view.INDENT
  local P = sheet.new { priority = 15 }
  local o = { width = width, open = s.open, files = s.files }
  if s.depth == 'home' then
    s.parts = view.home(P, { width = width, focus = s.focus, query = s.query, show = s.show })
  elseif s.depth == 'review' then
    s.parts = view.review(P, assert(r), o)
  elseif s.depth == 'thread' then
    s.parts = view.thread(P, assert(r), assert(t), o)
  else
    s.parts = view.step(P, assert(r), assert(t), assert(x), assert(st), width)
  end
  P.add ''
  P.apply(s.buf, ns)
  for _, p in ipairs(s.parts) do
    if p.kind == 'thread' and p.review and s.marked[p.review.id .. '#' .. p.thread.id] then
      vim.api.nvim_buf_set_extmark(
        s.buf,
        ns,
        p.first,
        0,
        { virt_text = { { '▌', 'ThreadMarkedBar' } }, virt_text_pos = 'overlay', line_hl_group = 'ThreadMarked' }
      )
    end
  end
  vim.api.nvim_win_set_config(s.win, { title = title(), title_pos = 'left', footer = look.footer(keys.footer(s)), footer_pos = 'right' })
  if s.over then
    local cfg = float.centred(vim.api.nvim_win_get_width(s.win), #P.lines)
    vim.api.nvim_win_set_config(s.win, { relative = 'editor', row = cfg.row, col = cfg.col, height = cfg.height })
  end
  if was then
    for _, p in ipairs(s.parts) do
      if same(was, p) then
        row = p.first + (row - was.first)
        break
      end
    end
  end
  pcall(vim.api.nvim_win_set_cursor, s.win, { math.max(1, math.min(row + 1, #P.lines)), col })
  M.light()
  s.drawing = false
end

--- What you were reading there is read now.
local function leave()
  local s = assert(S)
  local was = s.reading
  s.reading = nil
  local r = was and was.review and review.read(was.review)
  local t = r and was and review.find(r, assert(was.thread))
  if not (r and t and was) then
    return
  end
  local st, x ---@type thread.Step|nil, thread.Tour|nil
  if was.step then
    st, x = thread.step(t, was.step)
    if not st then
      return
    end
  end
  thread.mark_read(r, thread.conversation(t, st, x))
end

--- Put the cursor on where a depth starts: in a thread or a step, the
--- first message you have not read; in a review, its first thread; at
--- Home, the review you are on.
local function land()
  local s = assert(S)
  local r, t, x, st = M.at()
  local c = t and thread.conversation(t, st, x)
  local read = r and c and thread.read(r, c) or 0
  local pick ---@type thread.Part|nil
  for _, p in ipairs(s.parts) do
    local m = c and p.kind == 'message' and p.step == st and p.message and c.messages[p.message]
    local want = (s.depth == 'home' and p.kind == 'review' and p.review and (p.review.id == s.focus or not s.focus))
      or (s.depth == 'review' and p.kind == 'thread')
      or (m and m.from == 'agent' and assert(p.message) > read)
    if want then
      pick = p
      break
    end
  end
  local first = M.items()[1]
  vim.api.nvim_win_set_cursor(s.win, { (pick and pick.first or first and first.first or 0) + 1, 0 })
  M.light()
  if s.depth == 'home' and pick and pick.review and s.focus ~= pick.review.id then
    s.focus = pick.review.id
    M.draw()
  end
end

--- Go to a depth, leaving what you were reading read.
---@param at thread.ScreenAt
function M.move(at)
  local s = assert(S)
  leave()
  s.depth, s.review, s.thread, s.step = at.depth, at.review, at.thread, at.step
  s.open, s.opened, s.free = {}, nil, false
  local r = at.review and review.read(at.review)
  -- A level with one child opens as the child.
  if s.depth == 'review' and r and #r.threads == 1 then
    s.depth, s.thread = 'thread', r.threads[1].id
  end
  if s.depth == 'home' then
    s.focus = at.review or s.focus
  end
  if s.depth == 'thread' or s.depth == 'step' then
    s.reading = { depth = s.depth, review = s.review, thread = s.thread, step = s.step }
  end
  s.parts = {}
  M.draw()
  land()
end

--- Close it, leaving what you were reading read; from a float, back to
--- the code it was opened over.
function M.close()
  if not S then
    return
  end
  local s = S
  -- Closed by :q or <C-w>c too: its window has gone by now.
  leave()
  S = nil
  float.close(s.win)
  if s.over and vim.api.nvim_win_is_valid(s.over) then
    vim.api.nvim_set_current_win(s.over)
  end
end

--- A new window for it: the whole editor, or a float over the code.
---@param over boolean
local function start(over)
  M.close()
  local from = vim.api.nvim_get_current_win()
  local cfg = over and float.centred(math.min(vim.o.columns - 8, 100), 10) or float.full()
  local win, buf = float.open {
    filetype = 'thread-screen',
    win = vim.tbl_extend('force', cfg, { title = ' ', footer = ' ', zindex = over and 45 or 40 }),
    wo = { wrap = false, cursorline = true, number = false, signcolumn = 'no' },
  }
  S = {
    win = win,
    buf = buf,
    over = over and from or nil,
    depth = 'home',
    show = 'open',
    marked = {},
    parts = {},
    drawing = false,
    open = {},
    free = false,
    files = false,
  }
  keys.map(buf, M)
  local group = vim.api.nvim_create_augroup('thread.screen', { clear = true })
  vim.api.nvim_create_autocmd('CursorMoved', {
    group = group,
    buffer = buf,
    callback = function()
      local s = S
      if not s or s.drawing then
        return
      end
      M.light()
      if s.depth ~= 'home' then
        return
      end
      -- At Home, the review you are on opens under its line.
      local p = M.here()
      local id = p and p.review and p.review.id
      if id and id ~= s.focus then
        s.focus = id
        vim.schedule(M.draw)
      end
    end,
  })
  vim.api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'ThreadChanged',
    callback = function(ev)
      local s = S
      if s and (s.depth == 'home' or not ev.data or ev.data.id == s.review) then
        vim.schedule(M.draw)
      end
    end,
  })
  vim.api.nvim_create_autocmd('VimResized', {
    group = group,
    callback = function()
      local s = S
      if s and not s.over and vim.api.nvim_win_is_valid(s.win) then
        vim.api.nvim_win_set_config(s.win, float.full())
        M.draw()
      end
    end,
  })
  vim.api.nvim_create_autocmd('WinLeave', {
    group = group,
    buffer = buf,
    callback = function()
      vim.schedule(function()
        local s = S
        local now = vim.api.nvim_get_current_win()
        -- A float over it (compose, the help) leaves it open; another
        -- window closes it, with no going back to where it came from.
        if s and s.win == win and now ~= win and vim.api.nvim_win_get_config(now).relative == '' then
          s.over = nil
          M.close()
        end
      end)
    end,
  })
end

--- Open the screen at a depth: full, or in a float over the code.
---@param at thread.ScreenAt
---@param over boolean|nil
function M.open(at, over)
  if not (M.is_open() and (S and S.over ~= nil) == (over == true)) then
    start(over == true)
  end
  vim.api.nvim_set_current_win(assert(S).win)
  M.move(at)
end

--- One review open, and nothing else to list: Home opens on it.
---@return string|nil
local function only()
  local list, broken = review.list()
  local open = vim.tbl_filter(function(r)
    return r.status == 'open'
  end, list)
  return (#open == 1 and next(broken) == nil) and open[1].id or nil
end

go.register('screen', {
  open = {
    home = function(target)
      local id = target.review and target.review.id
      local one = not id and only()
      M.open(one and { depth = 'review', review = one } or { depth = 'home', review = id })
    end,
    review = function(target)
      M.open { depth = 'review', review = assert(target.review).id }
    end,
    thread = function(target)
      M.open { depth = 'thread', review = assert(target.review).id, thread = assert(target.thread).id }
    end,
    focus = function(target)
      M.open({ depth = 'thread', review = assert(target.review).id, thread = assert(target.thread).id }, true)
    end,
    page = function(target)
      M.open({ depth = 'step', review = assert(target.review).id, thread = assert(target.thread).id, step = assert(target.step).id }, true)
    end,
  },
  close = M.close,
})
-- The buffer a step's page is in, while one is open.
go.answer('page', function()
  local s = M.state()
  return s and s.depth == 'step' and s.buf or nil
end)

return M
