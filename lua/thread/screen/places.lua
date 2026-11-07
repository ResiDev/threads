--- Where the screen is: a place. Home, the list of topics; a topic's
--- tabs, Overview, Contracts, Tours and Threads (those it has), which H
--- and L go between; and the pages under them, a contract's, a thread's, a step's
--- and a tour's briefing. Each is a spec here: the tab it lights, where K
--- goes back to, its column, what its items are, its top and bottom rows,
--- what H, L and ⏎ do there, and how it draws. The screen keeps the id
--- of the one it is at, and the ids of what that place shows, and asks
--- this for the rest.

local contracts = require 'thread.draw.contracts'
local conversation = require 'thread.model.conversation'
local go = require 'thread.go'
local inbox = require 'thread.draw.inbox'
local topic = require 'thread.model.topic'
local topic_draw = require 'thread.draw.topic'
local touch = require 'thread.model.touch'
local tour = require 'thread.model.tour'
local tour_draw = require 'thread.draw.tour'
local view = require 'thread.screen.view'

local M = {}

---@alias thread.PlaceId 'home'|'overview'|'contracts'|'tours'|'threads'|'briefing'|'contract'|'thread'|'step'

--- A key the bottom row lists, and what it does there, said from the
--- item under the cursor and what touches what; a label of nil leaves
--- the key out.
---@alias thread.PlaceKey { [1]: string, [2]: string|fun(r: thread.Topic, p: thread.Part|nil, T: thread.Touches, s: thread.ScreenState): string|nil }

---@class thread.Place
---@field id thread.PlaceId
---@field kind 'home'|'tab'|'page'
---@field shows 'topic'|'thread'|'contract'|'tour'|'step'|nil  what of a topic it shows, as thread.ScreenObjects names it: once that has gone from the file, the screen goes up
---@field parent thread.PlaceId|nil  where K goes back to; none, the tab it was opened from
---@field tab thread.PlaceId|nil  full screen, the tab the top row lights: a tab its own; none, the row says what is here and beside
---@field title string|nil  a tab's, along the top
---@field mark (fun(s: thread.ScreenState): string)|nil  what the tab it lights adds to its title here: ` › 1`
---@field top (fun(s: thread.ScreenState): thread.Chunks)|nil  the top row, said whole
---@field beside (fun(r: thread.Topic, o: thread.ScreenObjects, s: thread.ScreenState): string|nil, string|nil, string|nil)|nil  a page's top row: what is here, then what H and L go to
---@field measure integer|nil  its column's width, centred, when no files are beside it; none, the window's
---@field files boolean|nil  the files down the right, in a window wide enough
---@field pane (fun(r: thread.Topic, width: integer): thread.SidePane)|nil  how it draws them, `width` wide, else as the topic's
---@field noun string|nil  the kind of part its items are, which the bottom row counts: `2 of 8`, and which open under the cursor
---@field position (fun(r: thread.Topic, o: thread.ScreenObjects, s: thread.ScreenState): string|nil)|nil  what the bottom row says of where you are, else counted by its noun
---@field opens boolean|nil  the item under the cursor opens under its row
---@field shuts boolean|nil  what opened shuts as the cursor leaves items of its noun
---@field keys thread.PlaceKey[]|nil  full screen, its bottom row's own, after H/L and before ?; none, the screen's keys shown there
---@field turns string|nil  what its bottom row says H/L do
---@field line (fun(r: thread.Topic, p: thread.Part|nil, T: thread.Touches, width: integer): thread.Chunks|nil)|nil  the row over the keys: what is under the cursor, said, in `width`
---@field sections table<string, true>|nil  the kinds of part } and { go between, or their names; none, its headings
---@field lands (fun(p: thread.Part, s: thread.ScreenState): boolean)|nil  the part the cursor lands on as you arrive; none, the first message you have not read
---@field from_top boolean|nil  arrived at, shown from its top with the cursor where it lands, a message unread or not
---@field keep string|nil  the block of that name scrolled into view as its items open, whole when it fits
---@field enters (fun(r: thread.Topic, p: thread.Part): thread.ScreenAt|nil)|nil  where ⏎ on a part goes here, before what the part means anywhere
---@field turn (fun(api: thread.ScreenApi, d: 1|-1))|nil  H and L: the place beside
---@field draw fun(P: thread.Sheet, o: thread.ScreenObjects, f: thread.Frame, s: thread.ScreenState): thread.Part[]

-- A list reads well this wide, prose a little narrower.
local LIST, PROSE = 100, 88

--- What `t` walks, said: the tour under the cursor, else the topic's
--- first; with `from`, the step it picks up at once some is walked.
---@param r thread.Topic
---@param p thread.Part|nil
---@param from boolean
---@return string|nil
function M.walks(r, p, from)
  if from and p and p.kind == 'step' and p.step then
    return 'walk from step ' .. p.step.id
  end
  local x = (p and p.tour) or tour.list(r)[1]
  if not x then
    return nil
  end
  local i = from and tour.walked(r, x) > 0 and tour.next(r, x)
  if i then
    return 'walk from step ' .. x.steps[i].id
  end
  return 'walk tour ' .. (topic.tour_place(r, x) or x.title)
end

--- Where `x` is in `list`.
---@generic T
---@param list T[]
---@param x T
---@return integer
local function index(list, x)
  for i, other in ipairs(list) do
    if other == x then
      return i
    end
  end
  return 0
end

--- The one `d` from `x` in `list`.
---@generic T
---@param list T[]
---@param x T
---@param d 1|-1
---@return T|nil
local function beside_of(list, x, d)
  local i = index(list, x)
  return i > 0 and list[i + d] or nil
end

---@param p thread.Part
---@return boolean
local function an_item(p)
  return p.item == true
end

--- H and L on a tab: the tab beside, round from the last to the first.
---@param api thread.ScreenApi
---@param d 1|-1
local function next_tab(api, d)
  local S = assert(api.state())
  api.move { place = M.step(S.place, d, assert(api.at().topic)), topic = S.topic }
end

---@type thread.Place[]
M.LIST = {
  {
    id = 'home',
    kind = 'home',
    top = function(s)
      return { { ' Home' .. (s.show == 'open' and '' or (' · ' .. s.show)) .. (s.query and (' · /' .. s.query) or '') .. ' ', 'ThreadCrumbHere' } }
    end,
    sections = { topic = true },
    -- The topic you are on.
    lands = function(p, s)
      return p.kind == 'topic' and p.topic ~= nil and (p.topic.id == s.focus or not s.focus)
    end,
    draw = function(P, _, f, s)
      return view.home(P, { width = f.width, query = s.query, show = s.show, fold = s.fold })
    end,
  },
  {
    id = 'overview',
    kind = 'tab',
    shows = 'topic',
    parent = 'home',
    tab = 'overview',
    title = 'Overview',
    measure = PROSE,
    keys = {
      { 'w/b', 'link to link' },
      { '⏎', 'follow it' },
      {
        't',
        function(r, p)
          return M.walks(r, p, false)
        end,
      },
    },
    turns = 'tab',
    line = topic_draw.named,
    lands = an_item,
    turn = next_tab,
    draw = function(P, o, f)
      return topic_draw.head(P, assert(o.topic), { width = f.width, indent = f.indent })
    end,
  },
  {
    id = 'contracts',
    kind = 'tab',
    shows = 'topic',
    parent = 'home',
    tab = 'contracts',
    title = 'Contracts',
    measure = LIST,
    files = true,
    noun = 'contract',
    opens = true,
    keys = {
      { 'j/k', 'contract' },
      { '⏎', 'its page' },
      {
        't',
        function(r, p, T)
          return p and p.contract and touch.tour_of(r, T, p.contract) and 'its tour' or nil
        end,
      },
      { 'r', 'reply' },
    },
    turns = 'tab',
    pane = contracts.pane,
    lands = an_item,
    turn = next_tab,
    draw = function(P, o, f, s)
      return contracts.tab(P, assert(o.topic), { width = f.width, indent = f.indent, here = s.here })
    end,
  },
  {
    id = 'tours',
    kind = 'tab',
    shows = 'topic',
    parent = 'home',
    tab = 'tours',
    title = 'Tours',
    measure = LIST,
    files = true,
    noun = 'tour',
    opens = true,
    keys = {
      { 'j/k', 'tour' },
      { '⏎', 'briefing' },
      {
        't',
        function(r, p)
          return M.walks(r, p, true)
        end,
      },
    },
    turns = 'tab',
    pane = tour_draw.pane,
    lands = an_item,
    -- A tour's row opens its briefing; its steps walk.
    enters = function(r, p)
      if p.kind == 'tour' and p.tour then
        return { place = 'briefing', topic = r.id, tour = topic.tour_place(r, p.tour) or 0 }
      end
    end,
    turn = next_tab,
    draw = function(P, o, f, s)
      return tour_draw.tab(P, assert(o.topic), { width = f.width, indent = f.indent, here = s.here, open = s.open })
    end,
  },
  {
    id = 'threads',
    kind = 'tab',
    shows = 'topic',
    parent = 'home',
    tab = 'threads',
    title = 'Threads',
    measure = LIST,
    noun = 'thread',
    opens = true,
    keys = { { 'j/k', 'thread' }, { '⏎', 'its page' }, { 'r', 'reply' }, { 's', 'settle' } },
    turns = 'tab',
    lands = an_item,
    turn = next_tab,
    draw = function(P, o, f, s)
      return inbox.draw(P, assert(o.topic), { width = f.width, indent = f.indent, here = s.here })
    end,
  },
  {
    -- A page of Tours, full: down the left with the files beside it as
    -- Tours has them, its tab saying which, `Tours › 1`.
    id = 'briefing',
    kind = 'page',
    shows = 'tour',
    parent = 'tours',
    tab = 'tours',
    mark = function(s)
      return ' › ' .. s.tour
    end,
    -- Full, the tours either side, as a contract's page has the contracts;
    -- over the code, walking, its first step after it.
    beside = function(r, o, s)
      if not o.tour then
        return nil
      elseif s.over then
        local n = o.tour.steps[1]
        return r.title, nil, n and (n.id .. ' ' .. n.title)
      end
      local list = tour.list(r)
      local i = index(list, o.tour)
      return r.title, list[i - 1] and list[i - 1].title, list[i + 1] and list[i + 1].title
    end,
    measure = LIST,
    files = true,
    pane = tour_draw.pane,
    -- Back to Tours or on to step 1, walking it, and the page of the step
    -- under the cursor.
    keys = {
      {
        't',
        function(r, p, _, s)
          local x = p and p.tour or tour.list(r)[s.tour]
          return x and M.walks(r, p and p.step and p or { kind = 'tour', first = 0, last = 0, tour = x }, true)
        end,
      },
      {
        'p',
        function(_, p)
          return p and p.kind == 'step' and 'step page' or nil
        end,
      },
    },
    turns = 'tour',
    -- Which of the topic's tours, as a contract's page says which contract.
    position = function(r, o)
      local i = o.tour and index(tour.list(r), o.tour) or 0
      return i > 0 and (i .. ' of ' .. #tour.list(r)) or nil
    end,
    sections = { tour = true, step = true },
    -- Full, the tour beside's briefing; t walks. Over the code, walking,
    -- L its first step.
    turn = function(api, d)
      local S, o = assert(api.state()), api.at()
      if S.over then
        if d > 0 and o.tour and o.tour.steps[1] then
          go.open('walk', { topic = assert(o.topic), tour = o.tour, step = o.tour.steps[1] }, 'screen')
        end
        return
      end
      local r = assert(o.topic)
      local to = o.tour and beside_of(tour.list(r), o.tour, d)
      if to then
        api.move { place = 'briefing', topic = S.topic, tour = topic.tour_place(r, to) or 0 }
      end
    end,
    draw = view.briefing,
  },
  {
    -- A page of Contracts, full: its tab says which, `Contracts › 3`. Its
    -- callers open their code beside or under them, as a tab's items do.
    id = 'contract',
    kind = 'page',
    shows = 'contract',
    tab = 'contracts',
    mark = function(s)
      return ' › ' .. s.contract
    end,
    beside = function(r, o)
      if not o.contract then
        return nil
      end
      local i = index(r.contracts, o.contract)
      return r.title, r.contracts[i - 1] and r.contracts[i - 1].name, r.contracts[i + 1] and r.contracts[i + 1].name
    end,
    -- As wide as Contracts, the files beside it where Contracts has them;
    -- its callers across both.
    measure = LIST,
    files = true,
    pane = contracts.pane,
    noun = 'chunk',
    opens = true,
    keys = {
      {
        'j/k',
        function(r, _, _, s)
          local c = s.contract and topic.contract(r, s.contract)
          return c and #(c.dependents or {}) > 0 and 'caller' or 'part'
        end,
      },
      { '⇥', 'view' },
      {
        '⏎',
        function(_, p)
          return p and (p.kind == 'chunk' or p.kind == 'contract') and 'its code' or nil
        end,
      },
      {
        'o',
        function(_, p)
          return p and p.kind == 'block' and p.name == 'source' and 'read it whole' or nil
        end,
      },
      { '{/}', 'part' },
      { 'r', 'reply' },
      {
        'e/d',
        function(_, p)
          local c, i = p and p.conversation, p and p.message
          return c and i and conversation.editable(c, i) and 'edit / delete' or nil
        end,
      },
    },
    turns = 'contract',
    -- Which of the topic's contracts, as a tab says which of its items.
    position = function(r, o)
      local i = o.contract and index(r.contracts, o.contract) or 0
      return i > 0 and (i .. ' of ' .. #r.contracts) or nil
    end,
    sections = { contract = true, block = true, callers = true, message = true },
    -- Arrived at, its head, from the top: the contract is what it is
    -- about. Moving to a caller, all of them and its code in view.
    keep = 'callers',
    from_top = true,
    lands = function(p)
      return p.kind == 'contract'
    end,
    turn = function(api, d)
      local S, o = assert(api.state()), api.at()
      local to = o.contract and beside_of(assert(o.topic).contracts, o.contract, d)
      if to then
        api.move { place = 'contract', topic = S.topic, contract = to.id }
      end
    end,
    draw = function(P, o, f, s)
      return view.contract(P, o, f, s, f.window >= M.WIDE)
    end,
  },
  {
    -- A page of Threads, full: its tab says which, `Threads › 8`, and H and
    -- L go through the topic's threads in its order, which reading them
    -- does not change, as Threads' does. Over the code, the row is the
    -- threads beside alone.
    id = 'thread',
    kind = 'page',
    shows = 'thread',
    tab = 'threads',
    mark = function(s)
      return ' › ' .. s.thread
    end,
    beside = function(r, o, s)
      if not o.thread then
        return nil
      end
      local i = index(r.threads, o.thread)
      local p, n = r.threads[i - 1], r.threads[i + 1]
      return s.over and '' or r.title, p and ('thread ' .. p.id .. ' ' .. p.title), n and ('thread ' .. n.id .. ' ' .. n.title)
    end,
    measure = 120,
    -- The contract under the cursor opens, as on Contracts; off them, none.
    noun = 'contract',
    opens = true,
    shuts = true,
    keep = 'opened',
    keys = {
      { 'j/k', 'part' },
      {
        '⏎',
        function(_, p)
          return p and (p.kind == 'chunk' or p.kind == 'change') and 'its code' or nil
        end,
      },
      { 'r', 'reply' },
      {
        's',
        function(_, _, _, s)
          return s.thread and 'settle' or nil
        end,
      },
      {
        'a',
        function(_, p)
          return p and p.thread and p.thread.chunk and 'accept' or nil
        end,
      },
      {
        'e/d',
        function(_, p)
          local c, i = p and p.conversation, p and p.message
          return c and i and conversation.editable(c, i) and 'edit / delete' or nil
        end,
      },
    },
    turns = 'thread',
    position = function(r, o)
      local i = o.thread and index(r.threads, o.thread) or 0
      return i > 0 and (i .. ' of ' .. #r.threads) or nil
    end,
    sections = { thread = true, chunk = true, contract = true, message = true },
    -- Arrived at, the agent's first message you have not read, else its head.
    lands = function(p)
      return p.kind == 'thread'
    end,
    turn = function(api, d)
      local S, o = assert(api.state()), api.at()
      local to = o.thread and beside_of(assert(o.topic).threads, o.thread, d)
      if to then
        api.move { place = 'thread', topic = S.topic, thread = to.id }
      end
    end,
    draw = view.thread,
  },
  {
    -- Over the code, as the walk shows a step on no line.
    id = 'step',
    kind = 'page',
    shows = 'step',
    beside = function(_, o)
      if not (o.tour and o.step) then
        return nil
      end
      local i = index(o.tour.steps, o.step)
      local p, n = o.tour.steps[i - 1], o.tour.steps[i + 1]
      return o.tour.title, p and (p.id .. ' ' .. p.title) or 'briefing', n and (n.id .. ' ' .. n.title)
    end,
    sections = { step = true, thread = true, message = true },
    -- The step beside, walked; from the first, back to the briefing.
    turn = function(api, d)
      local o = api.at()
      local to = o.tour and o.step and beside_of(o.tour.steps, o.step, d)
      if o.tour and o.step and (to or d < 0) then
        go.open('walk', { topic = assert(o.topic), tour = o.tour, step = to, briefing = not to or nil }, 'screen')
      end
    end,
    draw = view.step,
  },
}

local by = {} ---@type table<thread.PlaceId, thread.Place>
--- The tabs, in the order H and L go through them.
---@type thread.Place[]
M.TABS = {}
for _, pl in ipairs(M.LIST) do
  by[pl.id] = pl
  if pl.kind == 'tab' then
    M.TABS[#M.TABS + 1] = pl
  end
end

--- The place of an id.
---@param id thread.PlaceId
---@return thread.Place
function M.get(id)
  return assert(by[id], id)
end

--- A topic's tabs: Contracts and Tours only when it has some, so a
--- topic of threads is its Overview and its Threads.
---@param r thread.Topic
---@return thread.Place[]
function M.tabs(r)
  return vim.tbl_filter(function(t)
    return t.id == 'contracts' and #r.contracts > 0 or t.id == 'tours' and #tour.list(r) > 0 or (t.id ~= 'contracts' and t.id ~= 'tours')
  end, M.TABS)
end

--- The tab `d` from one, of those `r` has, round from the last to the
--- first.
---@param id thread.PlaceId
---@param d 1|-1
---@param r thread.Topic
---@return thread.PlaceId
function M.step(id, d, r)
  local tabs = M.tabs(r)
  local i = index(tabs, by[id])
  return tabs[(i - 1 + d) % #tabs + 1].id
end

--- The tabs along the top, at a place that lights one: their titles, as
--- they read there, and which is lit.
---@param pl thread.Place
---@param s thread.ScreenState
---@param r thread.Topic
---@return string[], integer
function M.titles(pl, s, r)
  local titles, lit = {}, 1 ---@type string[], integer
  for i, t in ipairs(M.tabs(r)) do
    local here = t.id == pl.tab
    titles[i] = t.title .. (here and pl.mark and pl.mark(s) or '')
    lit = here and i or lit
  end
  return titles, lit
end

-- The window narrower than this, the files beside are left out.
M.WIDE = 120

-- Columns the files take, the line between them and the page included:
-- this many at fewest, and with room to spare, up to the most.
M.FILES, M.FILES_MOST = 37, 50

--- Where a place's column goes in a window `width` wide: with the files
--- beside it from column `files`, when it has them and there is room, as
--- wide as it reads well and the pair centred; centred, as wide as it
--- reads well, when it has a measure; else across the window.
---@class thread.Frame
---@field indent integer
---@field width integer
---@field files integer|nil  the column of the line between the page and the files
---@field side integer|nil  the columns from `files` the files take
---@field window integer  the window's width

---@param pl thread.Place
---@param width integer  the window's
---@return thread.Frame
function M.frame(pl, width)
  if pl.files and width >= M.WIDE then
    -- The line two clear of the item lit across the page.
    local w = math.min(pl.measure or width, width - M.FILES - 7)
    local side = math.min(M.FILES_MOST, width - w - 7)
    local indent = 3 + math.floor((width - w - 7 - side) / 2)
    return { indent = indent, width = w, files = indent + w + 4, side = side, window = width }
  end
  if not pl.measure then
    return { indent = view.INDENT, width = width - 2 * view.INDENT, window = width }
  end
  local w = math.max(20, math.min(pl.measure, width - 8))
  return { indent = math.max(0, math.floor((width - w) / 2)), width = w, window = width }
end

return M
