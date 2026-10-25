--- The screen: one window at a place (thread.screen.places), the reviews
--- (Home), a review's tabs, a note's, a contract's or a step's page, a
--- tour's briefing. Full screen it is Home and what is under it; in a
--- float over the code it is a note opened from there, a step's page or a
--- briefing the walk shows. The cursor
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
local places = require 'thread.screen.places'
local review = require 'thread.model.review'
local review_draw = require 'thread.draw.review'
local sheet = require 'thread.ui.sheet'
local side = require 'thread.draw.side'
local touch = require 'thread.model.touch'

local M = {}

local ns = vim.api.nvim_create_namespace 'thread.screen'
local ns_item = vim.api.nvim_create_namespace 'thread.screen.item'
local ns_writing = vim.api.nvim_create_namespace 'thread.screen.writing' -- the rows made for what you write in place

--- Where the screen is: a place, and the review and what in it the place
--- shows, by id, and nothing else: a note's id on a note's page alone. A
--- tour by its number among the review's listed.
---@class thread.ScreenAt
---@field place thread.PlaceId
---@field review string|nil  its id; at Home, the review you are on
---@field note integer|nil
---@field contract integer|nil
---@field step integer|nil
---@field tour integer|nil

---@class thread.ScreenState: thread.ScreenAt
---@field win integer
---@field buf integer
---@field frame thread.FrameWins
---@field last_tab thread.PlaceId  the review's tab last shown: a page goes back to it, and the review opens on it again
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
---@field lit boolean  an item or a link is lit under the cursor
---@field view thread.SourceView  a contract's page: how its change and its callers' show, kept from one contract to the next
---@field drawing boolean
---@field landing boolean|nil  the cursor put where a place starts, not moved by you
---@field feet string|nil  the keys on the bottom edge as last set
---@field side thread.SheetSide|nil  the files beside what is drawn
---@field touches thread.Touches|nil  what touches what in the review drawn

local S ---@type thread.ScreenState|nil

-- The view a contract's page showed last, for the screen opened again.
local last_view = 'split' ---@type thread.SourceView

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

--- The conversation the screen's page is about: its note's, its
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

--- What a place keeps in view as its items open: scrolled until all of
--- the block it names shows, or its top.
---@param s thread.ScreenState
---@param pl thread.Place
local function keep(s, pl)
  if not vim.api.nvim_win_is_valid(s.win) then
    return
  end
  for _, p in ipairs(pl.keep and s.parts or {}) do
    if p.kind == 'block' and p.name == pl.keep then
      -- The rows that show, the top row's bar left out.
      local top = vim.fn.line('w0', s.win) - 1
      local height = vim.fn.line('w$', s.win) - top
      if p.last >= top + height or p.first < top then
        local want = math.max(0, math.min(p.first, p.last + 1 - height))
        vim.api.nvim_win_call(s.win, function()
          vim.fn.winrestview { topline = want + 1 }
        end)
      end
      return
    end
  end
end

--- On a place that keeps a block in view, it in view again, while the
--- cursor is on an item of its that opens.
function M.keep()
  local s = S
  local p = M.here()
  if s and p and places.get(s.place).noun == p.kind then
    keep(s, places.get(s.place))
  end
end

--- On a tab whose items open under the cursor, the item it is in
--- opened, drawn again when that is another; whether it was.
---@param it thread.ScreenItem|nil
---@return boolean
local function open_here(it)
  local s = assert(S)
  local pl = places.get(s.place)
  if s.free or s.drawing or not pl.opens then
    return false
  end
  local key = it and it.part.kind == pl.noun and draw.key(it.part) or s.here
  if key == s.here then
    return false
  end
  s.here = key
  M.draw()
  if not s.landing then
    keep(s, pl)
  end
  return true
end

--- Light row `row` across `span`'s columns, where a line may stop short.
---@param s thread.ScreenState
---@param row integer
---@param span { from: integer, to: integer }
---@param group string|nil  its colour, else the item's
local function wash(s, row, span, group)
  group = group or 'ThreadItem'
  local line = vim.api.nvim_buf_get_lines(s.buf, row, row + 1, false)[1] or ''
  -- What of the line is in the span: the rest may be another column.
  local upto = #line
  for i = 1, vim.fn.strchars(line) do
    if vim.fn.strdisplaywidth(vim.fn.strcharpart(line, 0, i)) > span.to then
      upto = vim.fn.byteidx(line, i - 1)
      break
    end
  end
  local w = vim.fn.strdisplaywidth(line:sub(1, upto))
  if upto > span.from then
    vim.api.nvim_buf_set_extmark(s.buf, ns_item, row, span.from, { end_col = upto, hl_group = group, priority = 5 })
  end
  local pad = span.to - math.max(w, span.from)
  if pad > 0 then
    vim.api.nvim_buf_set_extmark(s.buf, ns_item, row, 0, {
      virt_text = { { string.rep(' ', pad), group } },
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
    side.paint(s.buf, ns_item, s.side, it and T and side.lit(s.side, T, it.part) or nil, shown, it and it.part)
  end
  -- On a review's tabs and pages, the link under the cursor washed: the
  -- cursor is hidden, so w and b would move unseen.
  local link = places.get(s.place).kind ~= 'home' and M.here()
  s.lit = it ~= nil
  if link and (link.kind == 'link' or link.kind == 'name') and link.s and link.e then
    vim.api.nvim_buf_set_extmark(s.buf, ns_item, link.first, link.s, { end_row = link.last, end_col = link.e, hl_group = 'ThreadLinkHere', priority = 20 })
    s.lit = true
  end
  -- What is lit says where you are, so the cursor is hidden; with
  -- nothing lit, or reading line by line, it shows.
  frame.cursor(s.frame, s.lit)
  if not it then
    return
  end
  for row = it.first, it.last do
    local span = it.part.span or s.span
    if it.part.bar then
      vim.api.nvim_buf_set_extmark(s.buf, ns_item, row, 0, {
        virt_text = { { '▎', 'ThreadItemBar' } },
        virt_text_win_col = s.span and s.span.from or 0,
        priority = 6,
      })
    elseif span then
      wash(s, row, span, it.part.wash)
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

--- The top row: Home's own; full screen, the review's tabs, the one the
--- place lights lit; else, on a page, what is here and where H and L go.
---@param width integer  the window's
---@return thread.Chunks
local function title(width)
  local s = assert(S)
  local o = M.at()
  local r = o.review
  local pl = places.get(s.place)
  if pl.top then
    return pl.top(s)
  elseif pl.tab and not s.over and r then
    local titles, lit = places.titles(pl, s)
    return frame.tabs(titles, lit, r.title, width)
  end
  local here, before, after ---@type string|nil, string|nil, string|nil
  if r and pl.beside then
    here, before, after = pl.beside(r, o, s)
  end
  return here and frame.beside(here, before, after, width, s.over ~= nil) or {}
end

--- Where the item the cursor is in is among the tab's: `2 of 8`.
---@return string|nil
local function position()
  local s = assert(S)
  local pl = places.get(s.place)
  if pl.position then
    local o = M.at()
    return o.review and pl.position(o.review, o, s) or nil
  end
  local noun = pl.noun
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

--- The bottom rows: the keys for the place and what the cursor is on,
--- and where it is; set again only when they change, unless `always`.
---@param always boolean|nil
local function feet(always)
  local s = assert(S)
  local p = M.here()
  local said = { keys = keys.footer(s, p), at = position() } ---@type thread.FrameFoot
  -- A tab that says what is under the cursor keeps its row, blank when
  -- nothing is, so the page does not jump as the cursor goes.
  local pl = places.get(s.place)
  if pl.line and s.review and vim.api.nvim_win_is_valid(s.win) then
    local r = review.read(s.review)
    local whole = vim.api.nvim_win_get_width(s.win)
    local pad = places.frame(pl, whole).indent
    local line = r and pl.line(r, p, s.touches or touch.index(r), whole - pad - 1)
    said.line = line and vim.list_extend({ { string.rep(' ', pad) } }, line) or {}
  end
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
  -- What went from the file takes you up to its review, on the tab it
  -- was on, or with it Home.
  local shows = places.get(s.place).shows
  if shows and not o[shows] then
    s.place, s.note, s.contract, s.step, s.tour, s.reading = r and s.last_tab or 'home', nil, nil, nil, nil, nil
    s.review = r and s.review
  end
  local pl = places.get(s.place)
  local whole = vim.api.nvim_win_get_width(s.win)
  local f = places.frame(pl, whole)
  local P = sheet.new { priority = 15 }
  -- What touches what, once a draw, for the drawers and for lighting.
  s.touches = r and pl.shows and touch.index(r) or nil
  P.add ''
  s.parts = pl.draw(P, o, f, s)
  if r and pl.shows then
    draw.within(s.parts, 1, { review = r })
  end
  if r and f.files then
    review_draw.side(P, r, 1, f.files + 2, assert(s.touches), whole - f.files - 3, pl.pane and pl.pane(r))
  end
  -- The item under the cursor lit across its column, two either side.
  s.span = pl.measure and { from = math.max(0, f.indent - 2), to = f.indent + f.width + 2 } or nil
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

--- Put the cursor on where a place starts: on a page, the first message
--- you have not read, but on a contract's, its head, from the top; on a
--- tab, its first item; at Home, the review you are on.
local function land()
  local s = assert(S)
  local o = M.at()
  local pl = places.get(s.place)
  local c = about(o)
  local read = o.review and c and conversation.read(o.review, c) or 0
  local pick ---@type thread.Part|nil
  -- The first message you have not read, else where the place lands.
  for _, p in ipairs(not pl.from_top and s.parts or {}) do
    local m = c and p.kind == 'message' and p.conversation and p.conversation.name == c.name and p.message and c.messages[p.message]
    if m and m.from == 'agent' and assert(p.message) > read then
      pick = p
      break
    end
  end
  for _, p in ipairs(pl.lands and not pick and s.parts or {}) do
    if pl.lands(p, s) then
      pick = p
      break
    end
  end
  local first = M.items()[1]
  vim.api.nvim_win_set_cursor(s.win, { (pick and pick.first or first and first.first or 0) + 1, 0 })
  if pl.from_top then
    vim.api.nvim_win_call(s.win, function()
      vim.fn.winrestview { topline = 1 }
    end)
  end
  -- Landing, what opens is drawn where it is, not scrolled to.
  s.landing = true
  M.light()
  s.landing = nil
  if pl.kind == 'home' and pick and pick.review then
    s.focus = pick.review.id
  end
end

--- Go to a place, leaving what you were reading read.
---@param at thread.ScreenAt
function M.move(at)
  local s = assert(S)
  leave()
  local pl = places.get(at.place)
  s.last_tab = pl.kind == 'tab' and at.place or (at.review == s.review and s.last_tab) or 'overview'
  s.place, s.review, s.note, s.contract, s.step, s.tour = at.place, at.review, at.note, at.contract, at.step, at.tour
  s.open, s.opened, s.free, s.here = {}, nil, false, nil
  -- Marks are for the list they were made in: elsewhere r, a and c would
  -- act on them, not on what you look at.
  s.marked = {}
  if pl.kind == 'home' then
    s.focus = at.review or s.focus
  end
  if s.note or s.step or s.contract then
    s.reading = { place = s.place, review = s.review, note = s.note, step = s.step, contract = s.contract }
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
  last_view = s.view
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
    place = 'home',
    last_tab = 'overview',
    show = 'open',
    fold = 'some',
    marked = {},
    parts = {},
    drawing = false,
    open = {},
    free = false,
    lit = false,
    view = last_view,
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
      if places.get(s.place).kind ~= 'home' then
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
      if s and (places.get(s.place).kind == 'home' or not ev.data or ev.data.id == s.review) then
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
  -- The cursor hidden in it while an item is lit, and shown anywhere
  -- else, a float over it too.
  vim.api.nvim_create_autocmd('WinEnter', {
    group = group,
    buffer = buf,
    callback = function()
      local s = S
      if s and s.win == win then
        frame.cursor(s.frame, s.lit)
      end
    end,
  })
  vim.api.nvim_create_autocmd('WinLeave', {
    group = group,
    buffer = buf,
    callback = function()
      if S and S.win == win then
        frame.cursor(S.frame, false)
      end
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

--- Open the screen at a place: full, or in a float over the code.
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

--- A review, on the tab it was last on, else its Overview.
---@param id string
---@return thread.ScreenAt
local function on_review(id)
  return { place = S and S.review == id and S.last_tab or 'overview', review = id }
end

go.register('screen', {
  open = {
    home = function(target)
      local id = target.review and target.review.id
      local one = not id and only()
      M.open(one and on_review(one) or { place = 'home', review = id })
    end,
    review = function(target)
      M.open(on_review(assert(target.review).id))
    end,
    note = function(target)
      M.open { place = 'note', review = assert(target.review).id, note = assert(target.note).id }
    end,
    -- A contract's page; on its page already, the code its new side is
    -- read from, else its old: the first that is a chunk.
    contract = function(target)
      local r, c = assert(target.review), assert(target.contract)
      local s = M.state()
      if s and s.review == r.id and s.contract == c.id then
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
      M.open { place = 'contract', review = r.id, contract = c.id }
    end,
    focus = function(target)
      M.open({ place = 'note', review = assert(target.review).id, note = assert(target.note).id }, true)
    end,
    page = function(target)
      M.open({ place = 'step', review = assert(target.review).id, step = assert(target.step).id }, true)
    end,
    briefing = function(target)
      local r, x = assert(target.review), assert(target.tour)
      M.open({ place = 'briefing', review = r.id, tour = review.tour_place(r, x) or 0 }, true)
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
  return s and s.over and (s.step or s.tour) and s.buf or nil
end)

return M
