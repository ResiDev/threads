--- The screen: one window at its depths, the reviews (Home), a review, a
--- note, a contract, a step, a tour's briefing. Full screen it is Home
--- and what is under it; in a float over the code it is a note opened
--- from there, a step's page or a briefing the walk shows. The cursor
--- goes from item to item, a tour, a step, a note, a file, the one it is
--- on lit; `o` opens an item and lets the cursor in to read it line by
--- line. Its keys (thread.screen.keys) act on the part under the cursor.
--- What you have not read in a conversation stays lit until you leave it.

local conversation = require 'thread.model.conversation'
local draw = require 'thread.draw'
local float = require 'thread.ui.float'
local frame = require 'thread.screen.frame'
local go = require 'thread.go'
local keys = require 'thread.screen.keys'
local review = require 'thread.model.review'
local sheet = require 'thread.ui.sheet'
local side = require 'thread.draw.side'
local tabs = require 'thread.screen.tabs'
local touch = require 'thread.model.touch'
local text = require 'thread.base.text'
local view = require 'thread.screen.view'

local M = {}

local ns = vim.api.nvim_create_namespace 'thread.screen'
local ns_item = vim.api.nvim_create_namespace 'thread.screen.item'
local ns_writing = vim.api.nvim_create_namespace 'thread.screen.writing' -- the rows made for what you write in place

---@alias thread.Depth 'home'|'review'|'note'|'contract'|'step'|'tour'

--- Where the screen is: the depth, and the review and what in it, by id;
--- a tour by its place among the review's.
---@class thread.ScreenAt
---@field depth thread.Depth
---@field review string|nil  its id
---@field note integer|nil
---@field contract integer|nil
---@field step integer|nil
---@field tour integer|nil
---@field tab thread.TabId|nil  a review: the tab shown; none, the one it was on, or its first

---@class thread.ScreenState: thread.ScreenAt
---@field win integer
---@field buf integer
---@field frame thread.FrameWins
---@field here string|nil  a review's tab: the item opened under the cursor, by draw.key
---@field span { from: integer, to: integer }|nil  a review's tab: the columns its item under the cursor is lit across
---@field over integer|nil  in a float over the code: the window it came from
---@field focus string|nil  Home: the review you are on
---@field query string|nil  Home: only what mentions it
---@field show 'open'|'closed'  Home: which reviews
---@field fold thread.Fold  Home: how much of each review shows
---@field marked table<string, { review: string, note: integer }>  notes picked with space, by `<review>#note:<id>`
---@field parts thread.Part[]
---@field reading thread.ScreenAt|nil  a note, a contract or a step drawn whole, read when you leave it
---@field open table<string, true>  the items opened, by draw.key
---@field opened string|nil  the item `o` opened, which `o` or Esc closes
---@field free boolean  the cursor let into an item, moving by lines
---@field against boolean  a contract's page: the contract against as it was, not only as it is
---@field drawing boolean
---@field feet string|nil  the keys on the bottom edge as last set
---@field side thread.SheetSide|nil  the files beside what is drawn
---@field touches thread.Touches|nil  what touches what in the review drawn

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

--- What the screen is at, read afresh: its review, and the note, the
--- contract, the step and its tour, or the tour, it is on.
---@class thread.ScreenObjects
---@field review thread.Review|nil
---@field note thread.Note|nil
---@field contract thread.Contract|nil
---@field tour thread.Tour|nil
---@field step thread.Step|nil

---@return thread.ScreenObjects
function M.at()
  if not S then
    return {}
  end
  local r = S.review and review.read(S.review) or nil
  if not r then
    return {}
  end
  local out = { review = r } ---@type thread.ScreenObjects
  out.note = S.note and review.note(r, S.note) or nil
  out.contract = S.contract and review.contract(r, S.contract) or nil
  if S.step then
    out.step, out.tour = review.step(r, S.step)
  elseif S.tour then
    out.tour = r.tours[S.tour]
  end
  return out
end

--- The conversation the screen's depth is about: its note's, its
--- contract's or its step's.
---@param o thread.ScreenObjects
---@return thread.Conversation|nil
local function about(o)
  if o.note then
    return conversation.of_note(o.note)
  elseif o.contract then
    return conversation.of_contract(o.contract)
  elseif o.step then
    return conversation.of_step(o.step, o.tour)
  end
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
    if p.alone then
      last = math.min(last, math.max(p.first, p.last))
    end
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

--- On a tab whose items open under the cursor, the item it is in
--- opened, drawn again when that is another; whether it was.
---@param it thread.ScreenItem|nil
---@return boolean
local function open_here(it)
  local s = assert(S)
  if s.depth ~= 'review' or s.free or s.drawing or not tabs.get(s.tab or 'overview').opens then
    return false
  end
  local key = it and it.part.kind == tabs.get(s.tab or 'overview').noun and draw.key(it.part) or s.here
  if key == s.here then
    return false
  end
  s.here = key
  M.draw()
  return true
end

--- Light row `row` across `span`'s columns, where a line may stop short.
---@param s thread.ScreenState
---@param row integer
---@param span { from: integer, to: integer }
local function wash(s, row, span)
  local line = vim.api.nvim_buf_get_lines(s.buf, row, row + 1, false)[1] or ''
  local w = vim.fn.strdisplaywidth(line)
  if #line > span.from then
    vim.api.nvim_buf_set_extmark(s.buf, ns_item, row, span.from, { end_col = #line, hl_group = 'ThreadItem', priority = 5 })
  end
  local pad = span.to - math.max(w, span.from)
  if pad > 0 then
    vim.api.nvim_buf_set_extmark(s.buf, ns_item, row, 0, {
      virt_text = { { string.rep(' ', pad), 'ThreadItem' } },
      virt_text_win_col = math.max(w, span.from),
      priority = 5,
    })
  end
  vim.api.nvim_buf_set_extmark(s.buf, ns_item, row, 0, {
    virt_text = { { '▎', 'ThreadItemBar' } },
    virt_text_win_col = span.from,
    priority = 6,
  })
end

--- Light the item the cursor is in; none while it reads line by line.
function M.light()
  if not M.is_open() then
    return
  end
  local s = assert(S)
  local it = not s.free and M.item() or nil
  if open_here(it) then
    return
  end
  vim.api.nvim_buf_clear_namespace(s.buf, ns_item, 0, -1)
  vim.wo[s.win].cursorline = s.free
  local T = s.touches
  local owner = it and T and side.owner(it.part)
  -- The files beside it, those the item touches lit.
  if s.side then
    local shown = { top = vim.fn.line('w0', s.win) - 1, bottom = vim.fn.line('w$', s.win) - 1 }
    side.paint(s.buf, ns_item, s.side, it and T and side.of(T, it.part) or nil, shown)
  end
  if not it then
    return
  end
  for row = it.first, it.last do
    if s.depth == 'review' and s.span then
      wash(s, row, s.span)
    else
      vim.api.nvim_buf_set_extmark(s.buf, ns_item, row, 0, {
        virt_text = { { '▎', 'ThreadItemBar' } },
        virt_text_win_col = 0,
        line_hl_group = 'ThreadItem',
        priority = 5,
      })
    end
  end
  -- What is on the other side of it, marked: a contract's tours, steps
  -- and notes; a tour's, a step's or a note's contracts.
  local related = owner and touch.related(assert(T), owner)
  if related then
    for _, p in ipairs(s.parts) do
      local other = p.item and p ~= it.part and side.owner(p)
      if other and related[other] then
        vim.api.nvim_buf_set_extmark(s.buf, ns_item, p.first, 0, {
          virt_text = { { '▎', 'ThreadRelatedBar' } },
          virt_text_win_col = 0,
          priority = 5,
        })
      end
    end
  end
end

--- Whether two parts are the same thing, drawn again.
---@param a thread.Part
---@param b thread.Part
---@return boolean
local function same(a, b)
  return a.kind == b.kind
    and (a.review and a.review.id) == (b.review and b.review.id)
    and (a.note and a.note.id) == (b.note and b.note.id)
    and (a.step and a.step.id) == (b.step and b.step.id)
    and (a.contract and a.contract.id) == (b.contract and b.contract.id)
    and a.message == b.message
    and a.s == b.s
    and (a.chunk and a.chunk.line) == (b.chunk and b.chunk.line)
    and draw.key(a) == draw.key(b)
end

--- Where `x` is in `list`.
---@generic T
---@param list T[]
---@param x T
---@return integer
local function place(list, x)
  for i, other in ipairs(list) do
    if other == x then
      return i
    end
  end
  return 0
end

--- The top row: a review's tabs, the one shown lit; elsewhere where
--- you are. On a page, what is on the page already is left out; instead,
--- where H and L go, the start of each's title, the next pushed to the
--- right.
---@param width integer  the window's
---@return thread.Chunks
local function title(width)
  local s = assert(S)
  local o = M.at()
  local r = o.review
  -- Over the code the row is the border's, a line across it.
  local rule = s.over and '─' or ' '
  if s.depth == 'home' then
    return { { ' Home' .. (s.show == 'open' and '' or (' · ' .. s.show)) .. (s.query and (' · /' .. s.query) or '') .. ' ', 'ThreadCrumbHere' } }
  elseif s.depth == 'review' and r then
    local titles, here = {}, 1 ---@type string[], integer
    for i, t in ipairs(tabs.LIST) do
      titles[i] = t.title
      here = t.id == s.tab and i or here
    end
    return frame.tabs(titles, here, r.title, width)
  end
  local here, before, after ---@type string, string|nil, string|nil
  if not r then
    return {}
  elseif s.depth == 'contract' and o.contract then
    here = r.title
    local i = place(r.contracts, o.contract)
    before = r.contracts[i - 1] and r.contracts[i - 1].name
    after = r.contracts[i + 1] and r.contracts[i + 1].name
  elseif s.depth == 'note' and o.note then
    here = s.over and '' or r.title
    local i = place(r.notes, o.note)
    local p, n = r.notes[i - 1], r.notes[i + 1]
    before = p and ('note ' .. p.id .. ' ' .. p.title)
    after = n and ('note ' .. n.id .. ' ' .. n.title)
  elseif s.depth == 'step' and o.tour and o.step then
    here = o.tour.title
    local i = place(o.tour.steps, o.step)
    local p, n = o.tour.steps[i - 1], o.tour.steps[i + 1]
    before = p and (p.id .. ' ' .. p.title) or 'briefing'
    after = n and (n.id .. ' ' .. n.title)
  elseif s.depth == 'tour' and o.tour then
    here = r.title
    local n = o.tour.steps[1]
    after = n and (n.id .. ' ' .. n.title)
  else
    return {}
  end
  local out = {} ---@type thread.Chunks
  local room = width - 2
  if here ~= '' then
    here = text.fit(here, math.floor(room / 3))
    out[#out + 1] = { ' ' .. here .. ' ', 'FloatTitle' }
    room = room - text.width(here) - 2
  end
  -- Each side: `─ H ‹ title… ` and ` title… › L ─`.
  local each = math.floor((room - 4) / 2) - 8
  local left = before and { { rule .. ' ', 'FloatBorder' }, { 'H', 'ThreadKey' }, { ' ‹ ' .. text.fit(before, each) .. ' ', 'ThreadMeta' } } or {}
  local right = after and { { ' ' .. text.fit(after, each) .. ' › ', 'ThreadMeta' }, { 'L', 'ThreadKey' }, { ' ' .. rule, 'FloatBorder' } } or {}
  vim.list_extend(out, left)
  local used = 0
  for _, c in ipairs(out) do
    used = used + text.width(c[1])
  end
  for _, c in ipairs(right) do
    used = used + text.width(c[1])
  end
  if #right > 0 then
    out[#out + 1] = { string.rep(rule, math.max(1, width - 2 - used)), 'FloatBorder' }
    vim.list_extend(out, right)
  end
  return out
end

--- Where the item the cursor is in is among the tab's: `2 of 8`.
---@return string|nil
local function position()
  local s = assert(S)
  local noun = s.depth == 'review' and s.tab and tabs.get(s.tab).noun
  if not noun then
    return nil
  end
  local it = M.item()
  local list = vim.tbl_filter(function(x)
    return x.part.kind == noun
  end, M.items())
  for i, x in ipairs(list) do
    if it and x.first == it.first then
      return i .. ' of ' .. #list
    end
  end
end

--- The bottom rows: the keys for the depth and what the cursor is on,
--- and where it is; set again only when they change, unless `always`.
---@param always boolean|nil
local function feet(always)
  local s = assert(S)
  local said = { keys = keys.footer(s, (M.here())), at = position() } ---@type thread.FrameFoot
  local key = vim.inspect(said)
  if always or key ~= s.feet then
    s.feet = key
    frame.bottom(s.frame, said)
  end
end

--- Draw it again where it is, the cursor kept on what it was on.
function M.draw()
  if not M.is_open() then
    return
  end
  local s = assert(S)
  s.drawing = true
  local was, row, col = M.here()
  local o = M.at()
  local r = o.review
  -- What went from the file takes you up to its review.
  local gone = (s.depth == 'note' and not o.note)
    or (s.depth == 'contract' and not o.contract)
    or (s.depth == 'step' and not o.step)
    or (s.depth == 'tour' and not o.tour)
  if gone then
    s.depth, s.note, s.contract, s.step, s.tour, s.reading = r and 'review' or 'home', nil, nil, nil, nil, nil
  end
  if s.depth == 'review' and not r then
    s.depth, s.review = 'home', nil
  end
  local whole = vim.api.nvim_win_get_width(s.win)
  local width = whole - 2 * view.INDENT
  local P = sheet.new { priority = 15 }
  -- What touches what, once a draw, for the drawers and for lighting.
  s.touches = r and s.depth ~= 'home' and touch.index(r) or nil
  local v = { width = width, open = s.open, here = s.here, against = s.against, touches = s.touches }
  if s.depth == 'home' then
    s.parts = view.home(P, { width = width, query = s.query, show = s.show, fold = s.fold })
  elseif s.depth == 'review' then
    local tab = tabs.get(s.tab or 'overview')
    s.parts = view.review(P, assert(r), tab, whole, v)
    -- The item under the cursor lit across its column, two either side.
    local f = tabs.frame(tab, whole)
    s.span = { from = math.max(0, f.indent - 2), to = f.indent + f.width + 2 }
  elseif s.depth == 'note' then
    s.parts = view.note(P, assert(r), assert(o.note), v)
  elseif s.depth == 'contract' then
    s.parts = view.contract(P, assert(r), assert(o.contract), v)
  elseif s.depth == 'tour' then
    s.parts = view.tour(P, assert(r), assert(o.tour), assert(s.tour), width)
  else
    s.parts = view.step(P, assert(r), assert(o.tour), assert(o.step), width)
  end
  P.add ''
  P.apply(s.buf, ns)
  s.side = P.side
  for _, p in ipairs(s.parts) do
    if p.kind == 'note' and p.item and p.review and p.note and s.marked[p.review.id .. '#note:' .. p.note.id] then
      vim.api.nvim_buf_set_extmark(
        s.buf,
        ns,
        p.first,
        0,
        { virt_text = { { '▌', 'ThreadMarkedBar' } }, virt_text_pos = 'overlay', line_hl_group = 'ThreadMarked' }
      )
    end
  end
  frame.top(s.frame, title(whole))
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
  feet(true)
  s.drawing = false
end

--- What you were reading there is read now.
local function leave()
  local s = assert(S)
  local was = s.reading
  s.reading = nil
  local r = was and was.review and review.read(was.review)
  if not (r and was) then
    return
  end
  local o = { review = r } ---@type thread.ScreenObjects
  o.note = was.note and review.note(r, was.note) or nil
  o.contract = was.contract and review.contract(r, was.contract) or nil
  if was.step then
    o.step, o.tour = review.step(r, was.step)
  end
  local c = about(o)
  if c then
    conversation.mark_read(r, c)
  end
end

--- Put the cursor on where a depth starts: on a page, the first message
--- you have not read; in a review, its first tour, or note; at Home, the
--- review you are on.
local function land()
  local s = assert(S)
  local o = M.at()
  local c = s.depth ~= 'review' and about(o) or nil
  local read = o.review and c and conversation.read(o.review, c) or 0
  local pick ---@type thread.Part|nil
  for _, p in ipairs(s.parts) do
    local m = c and p.kind == 'message' and p.conversation and p.conversation.name == c.name and p.message and c.messages[p.message]
    local want = (s.depth == 'home' and p.kind == 'review' and p.review and (p.review.id == s.focus or not s.focus))
      or (s.depth == 'review' and p.item)
      or (m and m.from == 'agent' and assert(p.message) > read)
    if want then
      pick = p
      break
    end
  end
  local first = M.items()[1]
  vim.api.nvim_win_set_cursor(s.win, { (pick and pick.first or first and first.first or 0) + 1, 0 })
  M.light()
  if s.depth == 'home' and pick and pick.review then
    s.focus = pick.review.id
  end
end

--- Go to a depth, leaving what you were reading read.
---@param at thread.ScreenAt
function M.move(at)
  local s = assert(S)
  leave()
  -- A review opens on the tab asked for, else on the one it was on.
  local tab = at.tab or (at.review == s.review and s.tab) or 'overview'
  s.depth, s.review, s.note, s.contract, s.step, s.tour, s.tab = at.depth, at.review, at.note, at.contract, at.step, at.tour, tab
  s.open, s.opened, s.free, s.against, s.here = {}, nil, false, false, nil
  -- Marks are for the list they were made in: elsewhere r, a and c would
  -- act on them, not on what you look at.
  s.marked = {}
  if s.depth == 'home' then
    s.focus = at.review or s.focus
  end
  if s.depth == 'note' or s.depth == 'step' or s.depth == 'contract' then
    s.reading = { depth = s.depth, review = s.review, note = s.note, step = s.step, contract = s.contract }
  end
  s.parts = {}
  M.draw()
  land()
end

--- Show another of a review's tabs.
---@param id thread.TabId
function M.show(id)
  local s = assert(S)
  s.tab, s.open, s.opened, s.free, s.marked, s.here = id, {}, nil, false, {}, nil
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
  frame.close(s.frame)
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
  local f = frame.open(over)
  local win, buf = f.win, f.buf
  S = {
    win = win,
    buf = buf,
    frame = f,
    over = over and from or nil,
    depth = 'home',
    show = 'open',
    fold = 'some',
    marked = {},
    parts = {},
    drawing = false,
    open = {},
    free = false,
    against = false,
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
      feet()
      if s.depth ~= 'home' then
        return
      end
      -- At Home, the review you are on: back at Home, the cursor lands on it.
      local p = M.here()
      s.focus = p and p.review and p.review.id or s.focus
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
  -- The files beside stay in view as the window scrolls.
  vim.api.nvim_create_autocmd('WinScrolled', {
    group = group,
    callback = function(ev)
      local s = S
      if s and not s.drawing and tonumber(ev.match) == s.win then
        M.light()
      end
    end,
  })
  vim.api.nvim_create_autocmd('VimResized', {
    group = group,
    callback = function()
      local s = S
      if s and not s.over and vim.api.nvim_win_is_valid(s.win) then
        frame.place(s.frame, s.frame.rows)
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
    note = function(target)
      M.open { depth = 'note', review = assert(target.review).id, note = assert(target.note).id }
    end,
    -- A contract's page; on its page already, the code its new side is
    -- read from, else its old: the first that is a chunk.
    contract = function(target)
      local r, c = assert(target.review), assert(target.contract)
      local s = M.state()
      if s and s.depth == 'contract' and s.review == r.id and s.contract == c.id then
        local ch = nil ---@type thread.Chunk|nil
        for _, source in ipairs { c.source.after, c.source.before } do
          ch = ch or (type(source) == 'string' and review.chunk(r, source) or nil)
        end
        if ch then
          go.open('code', { review = r, chunk = ch }, 'screen')
        else
          vim.notify('thread: ' .. c.name .. ' is written out, in no one place in the code')
        end
        return
      end
      M.open { depth = 'contract', review = r.id, contract = c.id }
    end,
    focus = function(target)
      M.open({ depth = 'note', review = assert(target.review).id, note = assert(target.note).id }, true)
    end,
    page = function(target)
      M.open({ depth = 'step', review = assert(target.review).id, step = assert(target.step).id }, true)
    end,
    briefing = function(target)
      local r, x = assert(target.review), assert(target.tour)
      M.open({ depth = 'tour', review = r.id, tour = review.tour_place(r, x) or 0 }, true)
    end,
  },
  close = M.close,
})
-- Where you write your next message in a conversation it shows: go's
-- thread.ReplyAt.
go.answer('reply_at', function(r, c, i)
  local s = M.state()
  if not (s and s.review == r.id) then
    return nil
  end
  for _, p in ipairs(s.parts) do
    local here = p.conversation and p.conversation.name == c.name
    if here and (i and (p.kind == 'message' and p.message == i) or (not i and p.kind == 'reply')) then
      local row = p.first
      ---@param rows integer
      local function room(rows)
        if not M.is_open() then
          return
        end
        local lines = vim.api.nvim_buf_line_count(s.buf)
        if s.over then
          local cfg = float.centred(vim.api.nvim_win_get_width(s.win), lines + rows)
          vim.api.nvim_win_set_config(s.win, { relative = 'editor', row = cfg.row, col = cfg.col, height = cfg.height })
        end
        -- Scrolled so the row and the rows under it show, the most read
        -- above them that fits. Counted from above the row, so rows
        -- already put under it are not counted twice.
        local height = vim.api.nvim_win_get_height(s.win)
        ---@param top integer
        ---@return integer
        local function from(top)
          return (top < row and vim.api.nvim_win_text_height(s.win, { start_row = top, end_row = row - 1 }).all or 0) + 1 + rows
        end
        local top = row
        while top > 0 and from(top - 1) <= height do
          top = top - 1
        end
        local was = vim.api.nvim_win_call(s.win, vim.fn.winsaveview).topline - 1
        -- The cursor goes there too: left above, the window would scroll
        -- back to it, and what you write would be pinned to its edge.
        if was > row or from(was) > height then
          vim.api.nvim_win_call(s.win, function()
            vim.fn.winrestview { topline = top + 1, lnum = row + 1, col = 0 }
          end)
        end
      end
      local cols = assert(p.cols)
      -- The rows hang under the message, editing; else under the place.
      local after = i and p.last or row
      ---@type thread.ReplyAt
      return {
        col = cols.col,
        width = cols.width,
        covers = i and (p.last - p.first + 1) or nil,
        put = function(rows, top)
          if not M.is_open() then
            return nil
          end
          vim.api.nvim_buf_clear_namespace(s.buf, ns_writing, 0, -1)
          vim.api.nvim_buf_set_extmark(s.buf, ns_writing, after, 0, { virt_lines = rows })
          room(after - row + #rows)
          return { relative = 'win', win = s.win, bufpos = { after, 0 }, row = 1 + top, col = cols.col }
        end,
        clear = function()
          if M.is_open() then
            vim.api.nvim_buf_clear_namespace(s.buf, ns_writing, 0, -1)
            room(0)
          end
        end,
      }
    end
  end
end)

go.answer('page', function()
  local s = M.state()
  return s and s.over and (s.depth == 'step' or s.depth == 'tour') and s.buf or nil
end)

return M
