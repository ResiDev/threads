--- The screen's keys, in KEYS.md's words. `j` and `k` go from item to
--- item, `}` and `{` from section to section; `J` (or `⏎`) goes down a
--- level into what is under the cursor, `K` (or `-`) back up; on a
--- topic `H` and `L` go from tab to tab, on a page to the page beside;
--- Tab folds and unfolds; `o` opens an item and lets the cursor in, `o` or Esc again
--- goes back to items. The rest act on the part under the cursor: `r`
--- replies in the conversation it is in, `a` accepts its chunk, `s`
--- settles its thread or closes its topic. On a page, `t` and `c` go to the tours and contracts its
--- prose places. With threads marked (space), `r`, `a` and `s` act on each
--- of them instead.

local actions = require 'thread.actions'
local contract_draw = require 'thread.draw.contract'
local conversation = require 'thread.model.conversation'
local draw = require 'thread.draw'
local fold_state = require 'thread.prose.fold'
local go = require 'thread.go'
local help = require 'thread.screen.help'
local thread = require 'thread.model.thread'
local topic = require 'thread.model.topic'
local places = require 'thread.screen.places'
local touch = require 'thread.model.touch'
local tour = require 'thread.model.tour'

local M = {}

--- What the keys need of the screen (thread.screen), passed in, since it
--- requires this.
---@class thread.ScreenApi
---@field state fun(): thread.ScreenState|nil
---@field here fun(): thread.Part|nil, integer, integer
---@field at fun(): thread.ScreenObjects
---@field move fun(at: thread.ScreenAt)
---@field draw fun()
---@field close fun()
---@field items fun(): thread.ScreenItem[]
---@field item fun(): thread.ScreenItem|nil, integer
---@field light fun()
---@field keep fun()
---@field lend fun()
---@field home fun()

---@param msg string
local function say(msg)
  vim.notify('thread: ' .. msg)
end

--- The threads marked, read afresh: each with its topic.
---@param S thread.ScreenState
---@return { topic: thread.Topic, thread: thread.Thread }[]
local function marked(S)
  local out = {}
  for _, m in pairs(S.marked) do
    local r = topic.read(m.topic)
    local n = r and topic.thread(r, m.thread)
    if r and n then
      out[#out + 1] = { topic = r, thread = n }
    end
  end
  table.sort(out, function(a, b)
    return a.topic.id .. '#' .. a.thread.id < b.topic.id .. '#' .. b.thread.id
  end)
  return out
end

--- The topic a part is in: its own, else the screen's.
---@param api thread.ScreenApi
---@param p thread.Part|nil
---@return thread.Topic|nil
local function topic_of(api, p)
  return (p and p.topic) or api.at().topic
end

---@param api thread.ScreenApi
local function open(api)
  local p, row, col = api.here()
  local r = topic_of(api, p)
  if not (p and r) then
    return
  end
  local enters = places.get(assert(api.state()).place).enters
  local to = enters and enters(r, p)
  if to then
    api.move(to)
    return
  end
  local seam = p.kind == 'link' and p.link and p.link.kind == 'seam'
  if not seam then
    api.home()
  end
  local ok, why = go.press(r, p, row, col, 'screen')
  if ok and seam then
    api.lend()
  elseif not ok and why then
    say(why)
  end
end

--- The conversation a key on the screen acts in: on a page, the page's;
--- else the one the part under the cursor is in.
---@param api thread.ScreenApi
---@return thread.Topic|nil, thread.Conversation|nil
local function here_conversation(api)
  local o = api.at()
  local p = api.here()
  local r = topic_of(api, p)
  if not r then
    return nil
  end
  if o.thread then
    return r, conversation.of_thread(o.thread)
  elseif o.contract then
    return r, conversation.of_contract(o.contract)
  elseif o.step and not (p and p.kind == 'thread') then
    return r, conversation.of_step(o.step, o.tour)
  end
  return r, p and draw.conversation(p) or nil
end

--- Whether a part is in a message of yours you can still edit or delete.
---@param p thread.Part|nil
---@return boolean
local function yours_here(p)
  local c, i = p and p.conversation, p and p.message
  return c ~= nil and i ~= nil and conversation.editable(c, i)
end

--- The message of yours under the cursor, to edit or delete: yours, and
--- not answered yet. Else nil, and why not said.
---@param api thread.ScreenApi
---@return thread.Topic|nil, thread.Conversation|nil, integer|nil
local function mine(api)
  local p = api.here()
  local r = topic_of(api, p)
  local c, i = p and p.conversation, p and p.message
  if not (r and c and i and c.messages[i]) then
    say 'put the cursor on a message of yours'
    return nil
  end
  if not conversation.editable(c, i) then
    say(c.messages[i].from == 'agent' and 'that is the agent’s' or 'the agent has answered it: reply instead')
    return nil
  end
  return r, c, i
end

--- Edit the message of yours under the cursor, where it is.
---@param api thread.ScreenApi
local function edit(api)
  local r, c, i = mine(api)
  if r and c then
    go.open('compose', { replies = { { topic = r, conversation = c } }, edit = i }, 'screen')
  end
end

--- Delete the message of yours under the cursor.
---@param api thread.ScreenApi
local function delete(api)
  local r, c, i = mine(api)
  if r and c then
    go.open('compose', { replies = { { topic = r, conversation = c } }, unsay = i }, 'screen')
  end
end

---@param api thread.ScreenApi
local function reply(api)
  local S = assert(api.state())
  local many = marked(S)
  if #many > 0 then
    local replies = vim.tbl_map(function(m)
      return { topic = m.topic, conversation = conversation.of_thread(m.thread) }
    end, many)
    S.marked = {}
    go.open('compose', { replies = replies }, 'screen')
    return
  end
  local r, c = here_conversation(api)
  if not (r and c) then
    local p = api.here()
    say((p and p.kind == 'tour') and 'a tour has no conversation: reply in one of its steps, or start a thread with n' or 'nothing here to reply in')
    return
  end
  -- What you answer from its row you have read; a page reads what it
  -- shows once you leave it, and drawn again now would move the rows
  -- you write in.
  if places.get(S.place).kind == 'tab' then
    conversation.mark_read(r, c)
  end
  go.open('compose', { replies = { { topic = r, conversation = c } } }, 'screen')
end

--- On a thread, or its page: what `a` accepts.
---@param p thread.Part|nil
---@param S thread.ScreenState
---@return boolean
local function on_thread(p, S)
  return S.thread ~= nil or (p ~= nil and p.thread ~= nil)
end

---@param api thread.ScreenApi
local function accept(api)
  local S = assert(api.state())
  local many = marked(S)
  if #many > 0 then
    for _, m in ipairs(many) do
      local c = topic.chunk(m.topic, m.thread.chunk)
      if c then
        actions.accept(m.topic, c)
      end
    end
    S.marked = {}
    api.draw()
    return
  end
  local p = api.here()
  local r = topic_of(api, p)
  if p and r and actions.accept_part(r, p) == nil then
    say 'only a thread is accepted; a step is walked'
  end
end

--- Settle threads, asking how, by their kind; open a settled one again.
---@param list { topic: thread.Topic, thread: thread.Thread }[]
---@param done fun()|nil
local function settle(list, done)
  local one = list[1].thread
  if #list == 1 and thread.closed(one) then
    actions.set_status(list[1].topic, one, 'open')
    say('thread ' .. one.id .. ' is open again')
    if done then
      done()
    end
    return
  end
  for _, m in ipairs(list) do
    if m.thread.kind ~= one.kind then
      say 'the threads marked are of different kinds: settle them a kind at a time'
      return
    end
  end
  local ways = actions.settles(one)
  if #ways == 0 then
    say 'a comment has nothing to settle'
    return
  end
  local what = #list == 1 and ('thread ' .. one.id .. ' “' .. one.title .. '”') or thread.noun(one.kind, #list)
  vim.ui.select(ways, { prompt = 'Settle ' .. what .. ' as' }, function(status)
    if not status then
      return
    end
    for _, m in ipairs(list) do
      actions.set_status(m.topic, m.thread, status)
    end
    if done then
      done()
    end
  end)
end

---@param api thread.ScreenApi
local function close(api)
  local S = assert(api.state())
  local many = marked(S)
  if #many > 0 then
    settle(many, function()
      S.marked = {}
      api.draw()
    end)
    return
  end
  local p = api.here()
  local r = topic_of(api, p)
  if not (p and r) then
    return
  end
  local n = p.thread or api.at().thread
  if p.kind == 'topic' then
    actions.set_topic_status(r, r.status == 'open' and 'closed' or 'open')
  elseif n then
    settle { { topic = r, thread = n } }
  elseif p.tour or p.step or p.contract then
    say 'a tour, a step or a contract has no status: settle a thread about it, or close the topic'
  end
end

---@param api thread.ScreenApi
local function mark(api)
  local S = assert(api.state())
  local p = api.here()
  if not (p and p.kind == 'thread' and p.item and p.topic and p.thread) then
    return
  end
  local key = p.topic.id .. '#thread:' .. p.thread.id
  S.marked[key] = not S.marked[key] and { topic = p.topic.id, thread = p.thread.id } or nil
  api.draw()
  -- On to the next thread, past a kind's heading, so space after space
  -- marks thread after thread.
  for _, it in ipairs(api.items()) do
    if it.first > p.first and it.part.kind == 'thread' then
      vim.api.nvim_win_set_cursor(S.win, { it.first + 1, 0 })
      break
    end
  end
  api.light()
end

--- A new thread here: on the line of code under the cursor, else on no
--- line, in the topic you are in.
---@param api thread.ScreenApi
local function new_thread(api)
  local p = api.here()
  local r = topic_of(api, p)
  local c = p and p.kind == 'line' and p.chunk or nil
  ---@type thread.Anchor|nil
  local a = c and { file = c.file, line = c.line, from = c.from, rev = c.rev ~= 'now' and c.rev or nil } or nil
  go.open('compose', { topic = r, anchor = a }, 'screen')
end

--- The tour or contract placed in prose that the part under the cursor
--- is in.
---@param S thread.ScreenState
---@param p thread.Part|nil
---@return thread.Part|nil
local function inline_here(S, p)
  return p and draw.inline_at(S.parts, p.first) or nil
end

--- The tours or contracts placed in prose on a page, by their head
--- rows, in order.
---@param S thread.ScreenState
---@param kind thread.FoldKind
---@return thread.Part[]
local function placed(S, kind)
  local out = {} ---@type thread.Part[]
  for _, q in ipairs(S.parts) do
    local head = kind == 'tour' and q.kind == 'tour' and q.tour ~= nil
      or kind == 'contract' and q.kind == 'link' and q.link ~= nil and q.link.kind == 'contract'
    if head and q.first == q.last and draw.inline_at(S.parts, q.first) then
      out[#out + 1] = q
    end
  end
  table.sort(out, function(a, b)
    return a.first < b.first
  end)
  return out
end

--- Go to a tour or contract placed on the page: from off one, the first
--- in the message the cursor is in; from one, the next, on down the page
--- and round.
---@param api thread.ScreenApi
---@param kind thread.FoldKind
local function to_placed(api, kind)
  local S = assert(api.state())
  local list = placed(S, kind)
  if #list == 0 then
    say('this page has no ' .. kind .. ' in it')
    return
  end
  local row = vim.api.nvim_win_get_cursor(S.win)[1] - 1
  local from = row
  local on = vim.iter(list):any(function(q)
    return q.first == row
  end)
  if not on then
    for _, q in ipairs(S.parts) do
      if q.kind == 'message' and row >= q.first and row <= q.last then
        from = q.first - 1
      end
    end
  end
  local to = list[1]
  for _, q in ipairs(list) do
    if q.first > from then
      to = q
      break
    end
  end
  vim.api.nvim_win_set_cursor(S.win, { to.first + 1, 0 })
  api.light()
end

---@param api thread.ScreenApi
local function to_contract(api)
  to_placed(api, 'contract')
end

---@param api thread.ScreenApi
local function walk(api)
  local p = api.here()
  local r = topic_of(api, p)
  if not r then
    return
  end
  local o = api.at()
  -- On a page, t goes to a tour placed on it; ⏎ there walks it.
  if o.thread or o.contract then
    to_placed(api, 'tour')
    return
  end
  local x, s = (p and p.tour) or o.tour, (p and p.step) or o.step
  -- On a contract, the tour that walks it, from its first step on it.
  local S = assert(api.state())
  if not (x or s) and p and p.contract then
    x, s = touch.tour_of(r, S.touches or touch.index(r), p.contract)
    if not x then
      say('no tour walks ' .. p.contract.name)
      return
    end
  end
  if not (x or s) and #tour.list(r) == 0 then
    say(r.title .. ' has no tour')
    return
  end
  api.home()
  go.open('walk', { topic = r, tour = x, step = s }, 'screen')
end

--- The next or previous tab, or of what the page is: a thread, a
--- contract, a step of the walk, or from a briefing its first step.
---@param api thread.ScreenApi
---@param d 1|-1
local function side(api, d)
  local turn = places.get(assert(api.state()).place).turn
  if turn and api.at().topic then
    turn(api, d)
  end
end

--- A step's page from a step's line.
---@param api thread.ScreenApi
local function page(api)
  local p = api.here()
  local r = topic_of(api, p)
  if p and r and p.step then
    api.home()
    go.open('page', { topic = r, tour = p.tour, step = p.step }, 'screen')
  end
end

--- Back up: to the place's parent, else the tab it was opened from;
--- over the code, to the topic, full.
---@param api thread.ScreenApi
local function up(api)
  local S = assert(api.state())
  local r = api.at().topic
  if not r then
    return
  elseif S.over then
    api.home()
    go.open('topic', { topic = r }, 'screen')
  else
    api.move { place = places.get(S.place).parent or S.last_tab, topic = S.topic }
  end
end

---@param api thread.ScreenApi
local function search(api)
  local S = assert(api.state())
  local before = S.query
  local group = vim.api.nvim_create_augroup('thread.screen.search', { clear = true })
  vim.api.nvim_create_autocmd('CmdlineChanged', {
    group = group,
    callback = function()
      local q = vim.fn.getcmdline()
      S.query = q ~= '' and q or nil
      api.draw()
      vim.cmd.redraw()
    end,
  })
  local ok, q = pcall(vim.fn.input, { prompt = '/', default = before or '', cancelreturn = '\0' })
  vim.api.nvim_del_augroup_by_id(group)
  if not api.state() then
    return
  end
  if not ok or q == '\0' then
    S.query = before
  else
    S.query = q ~= '' and q or nil
  end
  api.draw()
end

--- Put the cursor on an item's first row.
---@param api thread.ScreenApi
---@param it thread.ScreenItem
local function go_to(api, it)
  local S = assert(api.state())
  vim.api.nvim_win_set_cursor(S.win, { it.first + 1, 0 })
  api.light()
end

--- The next or previous item, `count` times; reading an item line by
--- line, the next or previous line.
---@param api thread.ScreenApi
---@param d 1|-1
local function step_item(api, d)
  local S = assert(api.state())
  local n = vim.v.count1
  if S.free then
    vim.cmd('normal! ' .. n .. (d > 0 and 'j' or 'k'))
    return
  end
  local list = api.items()
  local it, at = api.item()
  -- Nothing to go between, as on a topic's Overview: the lines.
  if #list == 0 then
    vim.cmd('normal! ' .. n .. (d > 0 and 'j' or 'k'))
    return
  end
  local row = vim.api.nvim_win_get_cursor(S.win)[1] - 1
  -- Below an item's first row, k goes to its first.
  if d < 0 and it and row > it.first then
    at = at + 1
  end
  local to = math.max(1, math.min(#list, at + d * n))
  go_to(api, list[to])
end

--- The next or previous link, or name in backticks, from the cursor,
--- `count` times, as `w` and `b` go between words; reading an item line
--- by line, the editor's.
---@param api thread.ScreenApi
---@param d 1|-1
local function link(api, d)
  local S = assert(api.state())
  if S.free then
    vim.cmd('normal! ' .. vim.v.count1 .. (d > 0 and 'w' or 'b'))
    return
  end
  local cur = vim.api.nvim_win_get_cursor(S.win)
  local to = draw.link(S.parts, cur[1] - 1, cur[2], d, vim.v.count1)
  if to then
    vim.api.nvim_win_set_cursor(S.win, { to.first + 1, to.s })
    api.light()
  end
end

--- The next or previous section: a topic at Home; in a topic, the
--- first item under the next or previous of its tab's headings.
---@param api thread.ScreenApi
---@param d 1|-1
local function section(api, d)
  local S = assert(api.state())
  local kinds = places.get(S.place).sections
  local row = vim.api.nvim_win_get_cursor(S.win)[1] - 1
  local list = api.items()
  if not kinds then
    local heads = {} ---@type integer[]
    for _, p in ipairs(S.parts) do
      if p.kind == 'heading' then
        heads[#heads + 1] = p.first
      end
    end
    table.sort(heads)
    -- The heading the cursor is under.
    local under = 0
    for i, h in ipairs(heads) do
      under = h <= row and i or under
    end
    ---@param h integer|nil
    ---@return thread.ScreenItem|nil
    local function under_it(h)
      for _, other in ipairs(list) do
        if h and other.first > h then
          return other
        end
      end
    end
    local to = under_it(heads[under + 1])
    if d < 0 then
      -- Below a section's first item, back to it; else to the one before.
      to = under_it(heads[under])
      if not (to and to.first < row) then
        to = under_it(heads[under - 1])
      end
    end
    if to then
      go_to(api, to)
    end
    return
  end
  local from, to, by = d > 0 and 1 or #list, d > 0 and #list or 1, d
  for i = from, to, by do
    local it = list[i]
    local one = kinds[it.part.kind] or (it.part.name and kinds[it.part.name])
    if one and (d > 0 and it.first > row or d < 0 and it.first < row) then
      go_to(api, it)
      return
    end
  end
end

--- Open the item the cursor is in and let the cursor in to read it, or
--- close it and go back to items. A topic at Home, or a thread in a
--- topic, opens.
---@param api thread.ScreenApi
local function toggle(api)
  local S = assert(api.state())
  local it = api.item()
  if not it then
    return
  end
  local p = it.part
  if not S.free and p.kind == 'thread' and places.get(S.place).kind == 'tab' then
    open(api)
    return
  end
  -- Reading line by line, o closes what it opened, wherever you are.
  local key = (S.free and S.opened) or draw.key(p)
  if S.open[key] then
    S.open[key], S.opened, S.free = nil, nil, false
  else
    S.open[key], S.opened, S.free = true, key, true
  end
  api.draw()
  for _, other in ipairs(api.items()) do
    if draw.key(other.part) == key then
      go_to(api, other)
      return
    end
  end
  api.light()
end

-- Tab at Home: each topic shows the first few of what wants you, then
-- all of it, then none.
local FOLDS = { none = 'some', some = 'all', all = 'none' }

-- What Tab shows next of a tour or a contract placed in prose, by its
-- folds and how it shows now.
local TURNS = {
  tour = { row = 'steps', titles = 'text', where = 'code', code = 'one row' },
  contract = { source = 'show as it was', against = 'one row', row = 'source' },
  side = { source = 'one row', row = 'source' },
}

--- What Tab shows next of a block placed in prose.
---@param block thread.Part
---@return string
local function turns(block)
  local kind = assert(block.inline)
  return TURNS[kind][fold_state.get(kind, assert(block.fold))]
end

--- Fold or unfold: on a tour or a contract placed in prose, it, to how
--- it shows next; on a contract's page, the next view of its change; at
--- Home, how much each topic shows. Reading an item line by line, back
--- to items.
---@param api thread.ScreenApi
local function fold(api)
  local S = assert(api.state())
  local block = inline_here(S, (api.here()))
  if block then
    local key = assert(block.fold)
    fold_state.turn(assert(block.inline), key)
    api.draw()
    -- The cursor on its head row: a tour's first, a contract's under its
    -- label.
    for _, p in ipairs(S.parts) do
      if p.kind == 'inline' and p.fold == key then
        pcall(vim.api.nvim_win_set_cursor, S.win, { p.first + (p.inline == 'tour' and 1 or 2), 0 })
        break
      end
    end
    api.light()
    return
  end
  -- On a contract's page, its change and its callers' in the next view.
  if S.place == 'contract' and not S.free then
    S.view = contract_draw.next(S.view)
    api.draw()
    api.keep()
    return
  end
  local kind = places.get(S.place).kind
  if kind == 'page' then
    return
  end
  if S.free then
    toggle(api)
    return
  end
  local it = api.item()
  if kind == 'home' then
    local r = it and it.part.topic
    S.fold = FOLDS[S.fold]
    S.focus = r and r.id or S.focus
    api.draw()
    -- The cursor on the topic it was in: from all, what is under it goes.
    for _, other in ipairs(api.items()) do
      if other.part.kind == 'topic' and r and other.part.topic and other.part.topic.id == r.id then
        go_to(api, other)
        break
      end
    end
    return
  end
  api.light()
end

---@param api thread.ScreenApi
local function new_topic(api)
  vim.ui.input({ prompt = 'A new topic, its title: ' }, function(title)
    if title and vim.trim(title) ~= '' then
      local r = actions.new_topic(title)
      api.move { place = 'home', topic = r.id }
    end
  end)
end

---@param api thread.ScreenApi
local function quit(api)
  local S = assert(api.state())
  if S.free then
    toggle(api)
    return
  end
  if S.query then
    S.query = nil
    api.draw()
    return
  end
  api.close()
end

---@class thread.ScreenKey
---@field [1] string  the key
---@field [2] string  what it does, in the footer
---@field [3] fun(api: thread.ScreenApi)
---@field at table<thread.PlaceId, true>|nil  where it acts; nil: everywhere
---@field shown table<thread.PlaceId, true>|nil  where the footer lists it, at a place with no keys of its own; nil: nowhere
---@field group integer|nil  the footer's group it is in: 1 moving, 2 seeing, 3 acting, 5 the screen
---@field hint string|nil  how the footer says the key, when not as typed
---@field here (fun(p: thread.Part|nil, S: thread.ScreenState): boolean)|nil  the footer lists it only while the cursor is on such a part

-- Every place; every place a topic is on, all but Home; a topic's tabs.
local ALL, BELOW, TABS = {}, {}, {} ---@type table<thread.PlaceId, true>, table<thread.PlaceId, true>, table<thread.PlaceId, true>
for _, pl in ipairs(places.LIST) do
  ALL[pl.id] = true
  BELOW[pl.id] = pl.shows and true or nil
  TABS[pl.id] = pl.kind == 'tab' or nil
end
local HOME = { home = true }
-- The pages with a conversation of their own.
local PAGES = { thread = true, contract = true, step = true }

--- A key's action: `fn` one way or the other.
---@param fn fun(api: thread.ScreenApi, d: 1|-1)
---@param d 1|-1
---@return fun(api: thread.ScreenApi)
local function by(fn, d)
  return function(api)
    fn(api, d)
  end
end

---@type thread.ScreenKey[]
local KEYS = {
  { 'j', 'next', by(step_item, 1) },
  { 'k', 'prev', by(step_item, -1) },
  { '}', 'next section', by(section, 1) },
  { '{', 'prev section', by(section, -1) },
  { 'w', 'next link', by(link, 1) },
  { 'b', 'prev link', by(link, -1) },
  { '<CR>', 'open', open, shown = ALL, group = 1, hint = '⏎/J' },
  { 'J', 'into', open },
  {
    '<Tab>',
    'fold',
    fold,
    shown = ALL,
    group = 2,
    hint = '⇥',
    -- With nothing placed under the cursor, Tab folds at Home alone; a
    -- topic's tabs have nothing to fold.
    here = function(p, S)
      return HOME[S.place] or S.place == 'contract' or inline_here(S, p) ~= nil
    end,
  },
  { 'o', 'read', toggle, at = BELOW, shown = BELOW, group = 2 },
  { 'r', 'reply', reply, shown = PAGES, group = 3 },
  { 'e', 'edit', edit, at = PAGES, shown = PAGES, group = 3, here = yours_here },
  { 'd', 'delete', delete, at = PAGES, shown = PAGES, group = 3, here = yours_here },
  { 'a', 'accept', accept, shown = { thread = true }, group = 3, here = on_thread },
  { 's', 'settle', close, shown = { home = true, thread = true }, group = 3 },
  {
    'c',
    'to the contract',
    to_contract,
    at = { thread = true, contract = true },
    shown = { thread = true, contract = true },
    group = 3,
    here = function(_, S)
      return #placed(S, 'contract') > 0
    end,
  },
  { '<Space>', 'mark', mark, at = TABS },
  { 'n', 'new thread', new_thread, at = BELOW },
  { 'p', 'step page', page, at = vim.tbl_extend('force', TABS, { briefing = true }) },
  {
    't',
    'walk',
    walk,
    at = BELOW,
    shown = { briefing = true, thread = true, contract = true },
    group = 3,
    here = function(_, S)
      return not (S.thread or S.contract) or #placed(S, 'tour') > 0
    end,
  },
  { 'L', 'next', by(side, 1), at = BELOW },
  { 'H', 'prev', by(side, -1), at = BELOW },
  { 'K', 'back', up, at = BELOW, shown = BELOW, group = 1 },
  { '-', 'back', up, at = BELOW },
  { '<BS>', 'back', up, at = BELOW },
  { '/', 'search', search, at = HOME, shown = HOME, group = 2 },
  {
    'C',
    'view closed',
    function(api)
      local S = assert(api.state())
      S.show = S.show == 'closed' and 'open' or 'closed'
      api.draw()
      local first = api.items()[1]
      if first then
        go_to(api, first)
      end
    end,
    at = HOME,
    shown = HOME,
    group = 3,
  },
  { 'N', 'new topic', new_topic, at = HOME },
  {
    '?',
    'help',
    help.open,
    shown = ALL,
    group = 5,
  },
  { 'q', 'quit', quit, shown = HOME, group = 5 },
  { '<Esc>', 'back', quit },
}

-- Footer labels that say what the key does here.
---@type table<string, fun(S: thread.ScreenState, p: thread.Part|nil): string|nil>
local LABELS = {
  C = function(S)
    return S.show == 'closed' and 'view open' or nil
  end,
  s = function(S)
    return HOME[S.place] and 'close' or nil
  end,
  t = function(S)
    return (S.thread or S.contract) and 'to the tour' or nil
  end,
  ['<Tab>'] = function(S, p)
    local block = inline_here(S, p)
    if block then
      return turns(block)
    end
    if S.place == 'contract' then
      return contract_draw.NAMES[contract_draw.next(S.view)]
    end
    return HOME[S.place] and ({ none = 'three each', some = 'all of each', all = 'topics only' })[S.fold] or nil
  end,
}

--- The footer's keys at the place the screen is at, and for what the
--- cursor is on, in their groups: moving, seeing, acting, the screen.
---@param S thread.ScreenState
---@param p thread.Part|nil  under the cursor
---@return { [1]: string, [2]: string }[][]
function M.footer(S, p)
  if S.free then
    local out = { { { 'o/⇥', 'back to items' }, { 'j/k', 'lines' } }, { { 'r', 'reply' } } }
    local block = inline_here(S, p)
    if block then
      out[1][1] = { 'o', 'back to items' }
      table.insert(out[1], { '⇥', turns(block) })
    end
    if on_thread(p, S) then
      table.insert(out[2], { 'a', 'accept' })
    end
    if yours_here(p) then
      vim.list_extend(out[2], { { 'e', 'edit' }, { 'd', 'delete' } })
    end
    return out
  end
  -- A place's own, full screen: where H and L go, what its keys do,
  -- and help.
  local pl = places.get(S.place)
  if pl.keys and S.topic and not S.over then
    local r = topic.read(S.topic)
    local own = {} ---@type { [1]: string, [2]: string }[]
    for _, k in ipairs(pl.keys) do
      local said = k[2]
      local label ---@type string|nil
      if type(said) == 'function' then
        label = r and said(r, p, S.touches or touch.index(r), S) or nil
      else
        label = said
      end
      if label then
        own[#own + 1] = { k[1], label }
      end
    end
    -- On an excerpt, a tour or a contract placed in its prose, what
    -- opens it, and what Tab shows of a block next.
    local block = inline_here(S, p)
    if block then
      table.insert(own, 1, { '⇥', turns(block) })
      table.insert(own, 1, { '⏎', block.inline == 'tour' and 'walk' or 'open' })
    elseif p and p.kind == 'excerpt' then
      table.insert(own, 1, { '⏎', 'to the code' })
    end
    return { { { 'H/L', assert(pl.turns) } }, own, { { '?', 'help' } } }
  end
  local groups = {} ---@type { [1]: string, [2]: string }[][]
  for _, k in ipairs(KEYS) do
    if k.shown and k.shown[S.place] and (not k.here or k.here(p, S)) then
      local g = k.group or 5
      groups[g] = groups[g] or {}
      local label = LABELS[k[1]] and LABELS[k[1]](S, p) or k[2]
      table.insert(groups[g], { k.hint or k[1], label })
    end
  end
  local out = {}
  for g = 1, 5 do
    if groups[g] then
      out[#out + 1] = groups[g]
    end
  end
  return out
end

--- Give the screen's buffer its keys.
---@param buf integer
---@param api thread.ScreenApi
function M.map(buf, api)
  for _, k in ipairs(KEYS) do
    vim.keymap.set('n', k[1], function()
      local S = api.state()
      if S and S.buf == buf and (not k.at or k.at[S.place]) then
        k[3](api)
      end
    end, { buffer = buf, nowait = true, desc = 'Thread: ' .. k[2] })
  end
end

return M
