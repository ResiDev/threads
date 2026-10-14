--- The screen's keys, in KEYS.md's words. `j` and `k` go from item to
--- item, `}` and `{` from section to section; `J` (or `⏎`) goes down a
--- level into what is under the cursor, `K` (or `-`) back up; Tab folds
--- and unfolds; `o` opens an item and lets the cursor in, `o` or Esc again
--- goes back to items. The rest act on the part under the cursor: `r`
--- replies in the conversation it is in, `a` accepts its chunk, `c` closes
--- its thread or its review, `f` lays the chunks out by file or by thread.
--- With threads marked (space), `r`, `a` and `c` act on each of them
--- instead.

local actions = require 'thread.actions'
local draw = require 'thread.draw'
local go = require 'thread.go'
local help = require 'thread.screen.help'
local review = require 'thread.model.review'
local thread = require 'thread.model.thread'

local M = {}

--- What the keys need of the screen (thread.screen), passed in, since it
--- requires this.
---@class thread.ScreenApi
---@field state fun(): thread.ScreenState|nil
---@field here fun(): thread.Part|nil, integer, integer
---@field at fun(): thread.Review|nil, thread.Thread|nil, thread.Tour|nil, thread.Step|nil
---@field move fun(at: thread.ScreenAt)
---@field draw fun()
---@field close fun()
---@field items fun(): thread.ScreenItem[]
---@field item fun(): thread.ScreenItem|nil, integer
---@field light fun()

---@param msg string
local function say(msg)
  vim.notify('thread: ' .. msg)
end

--- The threads marked, read afresh: each with its review.
---@param S thread.ScreenState
---@return { review: thread.Review, thread: thread.Thread }[]
local function marked(S)
  local out = {}
  for _, m in pairs(S.marked) do
    local r = review.read(m.review)
    local t = r and review.find(r, m.thread)
    if r and t then
      out[#out + 1] = { review = r, thread = t }
    end
  end
  table.sort(out, function(a, b)
    return a.review.id .. '#' .. a.thread.id < b.review.id .. '#' .. b.thread.id
  end)
  return out
end

---@param api thread.ScreenApi
local function open(api)
  local p, row, col = api.here()
  if not p then
    return
  end
  local r = p.review or api.at()
  if not r then
    return
  end
  -- A group's heading goes in to its first thread, as a review does.
  if p.kind == 'group' and p.group then
    go.open('thread', { review = r, thread = p.group.threads[1] }, 'screen')
    return
  end
  local ok, why = go.press(r, p, row, col, 'screen')
  if not ok and why then
    say(why)
  end
end

---@param api thread.ScreenApi
local function reply(api)
  local S = assert(api.state())
  local many = marked(S)
  if #many > 0 then
    local replies = vim.tbl_map(function(m)
      return { review = m.review, conversation = thread.conversation(m.thread) }
    end, many)
    S.marked = {}
    go.open('compose', { replies = replies }, 'screen')
    return
  end
  local p = api.here()
  local r = p and (p.review or api.at())
  if not (p and r and p.thread) then
    return
  end
  -- The tours' carrier has no conversation: its steps do.
  if p.thread.carrier and not p.step then
    say 'a tour has no conversation: reply in one of its steps, or start a note with n'
    return
  end
  go.open('compose', { replies = { { review = r, conversation = thread.conversation(p.thread, p.step, p.tour) } } }, 'screen')
end

---@param api thread.ScreenApi
local function accept(api)
  local S = assert(api.state())
  local many = marked(S)
  if #many > 0 then
    for _, m in ipairs(many) do
      actions.accept_thread(m.review, m.thread)
    end
    S.marked = {}
    api.draw()
    return
  end
  local p, row = api.here()
  local r = p and (p.review or api.at())
  if p and r and actions.accept_part(r, p, row) == nil then
    say 'nothing here to accept'
  end
end

--- Close a thread, asking how; open a closed one again.
---@param list { review: thread.Review, thread: thread.Thread }[]
---@param done fun()|nil
local function close_threads(list, done)
  if #list == 1 and thread.closed(list[1].thread) then
    actions.set_status(list[1].review, list[1].thread, 'open')
    say('thread #' .. list[1].thread.id .. ' is open again')
    if done then
      done()
    end
    return
  end
  -- The thread, said whole: in it, the cursor is on a step or a chunk.
  local one = list[1].thread
  local what = #list == 1 and ('thread #' .. one.id .. (one.title and (' “' .. one.title .. '”') or '')) or (#list .. ' threads')
  vim.ui.select(actions.CLOSED, { prompt = 'Close ' .. what .. ' as' }, function(status)
    if not status then
      return
    end
    for _, m in ipairs(list) do
      actions.set_status(m.review, m.thread, status)
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
    close_threads(many, function()
      S.marked = {}
      api.draw()
    end)
    return
  end
  local p = api.here()
  local r = p and (p.review or api.at())
  if not (p and r) then
    return
  end
  if p.kind == 'review' then
    actions.set_review_status(r, r.status == 'open' and 'closed' or 'open')
  elseif p.thread and p.thread.carrier then
    say 'a tour or a step has no status: close the note about it, or the review'
  elseif p.thread then
    close_threads { { review = r, thread = p.thread } }
  end
end

---@param api thread.ScreenApi
local function mark(api)
  local S = assert(api.state())
  local p = api.here()
  if not (p and p.kind == 'thread' and p.review and p.thread) then
    return
  end
  local key = p.review.id .. '#' .. p.thread.id
  S.marked[key] = not S.marked[key] and { review = p.review.id, thread = p.thread.id } or nil
  api.draw()
  vim.cmd 'normal! j'
end

--- A new thread here: on the line of code under the cursor, else on no
--- line, in the review you are in.
---@param api thread.ScreenApi
local function new_thread(api)
  local p = api.here()
  local r = (p and p.review) or api.at()
  local c = p and p.kind == 'line' and p.chunk or nil
  go.open('compose', { review = r, chunk = c }, 'screen')
end

---@param api thread.ScreenApi
local function walk(api)
  local p = api.here()
  local r = p and (p.review or api.at())
  local t = p and p.thread
  if not (p and r and t) then
    return
  end
  if #thread.tours(t) == 0 then
    say('#' .. t.id .. ' has no tour')
    return
  end
  go.open('walk', { review = r, thread = t, tour = p.tour }, 'screen')
end

--- The next or previous thread of the review; in a step's page, the
--- next or previous step of the walk.
---@param api thread.ScreenApi
---@param d 1|-1
local function side(api, d)
  local S = assert(api.state())
  local r, t, x, s = api.at()
  if not (r and t) then
    return
  end
  if S.depth == 'step' and x and s then
    for i, other in ipairs(x.steps) do
      if other == s and x.steps[i + d] then
        go.open('walk', { review = r, thread = t, tour = x, step = x.steps[i + d] }, 'screen')
        return
      end
    end
    return
  end
  local list = review.ordered(r)
  for i, other in ipairs(list) do
    if other.id == t.id and list[i + d] then
      api.move { depth = 'thread', review = r.id, thread = list[i + d].id }
      return
    end
  end
end

--- A step's page from a step's line.
---@param api thread.ScreenApi
local function page(api)
  local p = api.here()
  local r = p and (p.review or api.at())
  if p and r and p.step and p.thread then
    go.open('page', { review = r, thread = p.thread, tour = p.tour, step = p.step }, 'screen')
  end
end

---@param api thread.ScreenApi
local function up(api)
  local S = assert(api.state())
  local r, t = api.at()
  if S.depth == 'step' then
    go.open('thread', { review = r, thread = t }, 'screen')
  elseif S.depth == 'thread' and S.over then
    go.open('review', { review = r }, 'screen')
  elseif S.depth == 'thread' and r and (r.format == 3 or #r.threads > 1) then
    api.move { depth = 'review', review = S.review }
  elseif S.depth == 'thread' or S.depth == 'review' then
    -- A review of one thread opens as it, so up from that thread is Home.
    api.move { depth = 'home', review = S.review }
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
  if #list == 0 then
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

-- What } and { go between, at each depth.
local SECTIONS = {
  home = { review = true },
  review = { review = true, group = true, file = true, tour = true },
  thread = { thread = true, tour = true },
  step = { step = true },
}

--- The next or previous section: a review at Home, a tour in a thread, a
--- file laid out by file.
---@param api thread.ScreenApi
---@param d 1|-1
local function section(api, d)
  local S = assert(api.state())
  local kinds = SECTIONS[S.depth]
  local row = vim.api.nvim_win_get_cursor(S.win)[1] - 1
  local list = api.items()
  local from, to, by = d > 0 and 1 or #list, d > 0 and #list or 1, d
  for i = from, to, by do
    local it = list[i]
    if kinds[it.part.kind] and (d > 0 and it.first > row or d < 0 and it.first < row) then
      go_to(api, it)
      return
    end
  end
end

--- Open the item the cursor is in and let the cursor in to read it, or
--- close it and go back to items. A review or a thread in a list opens.
---@param api thread.ScreenApi
local function toggle(api)
  local S = assert(api.state())
  local it = api.item()
  if not it then
    return
  end
  local p = it.part
  if not S.free and (S.depth == 'home' or (p.kind == 'thread' and S.depth == 'review')) then
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

-- Tab at Home: each review shows the first few of its threads, then all
-- of them, then none.
local FOLDS = { none = 'some', some = 'all', all = 'none' }

-- What Tab folds below Home, by the kind of item the cursor is on: a
-- group's or a tour's heading, that one (a tour laid out by file, every
-- chunk's code); the tours' rule, every tour; a contract, the rest of
-- the list; a step, a file or code, every chunk's code; anything else,
-- the messages, and in a review every group.
local CODE = { step = true, tour = true, file = true, chunk = true, line = true }

--- Fold or unfold: at Home, how many threads each review shows; in a
--- review or a thread, on a message every message, on a chunk every
--- chunk's code. Reading an item line by line, back to items.
---@param api thread.ScreenApi
local function fold(api)
  local S = assert(api.state())
  if S.free then
    toggle(api)
    return
  end
  local it = api.item()
  if S.depth == 'home' then
    local r = it and it.part.review
    S.fold = FOLDS[S.fold]
    S.focus = r and r.id or S.focus
    api.draw()
    -- The cursor on the review it was in: from all, the threads go away.
    for _, other in ipairs(api.items()) do
      if other.part.kind == 'review' and r and other.part.review and other.part.review.id == r.id then
        go_to(api, other)
        break
      end
    end
    return
  end
  local p = it and it.part
  if p and p.kind == 'contract' then
    -- On a contract, every one of the list or only the first few.
    S.contracts = not S.contracts
  elseif p and p.kind == 'heading' and p.name == 'tours' then
    -- On the tours' rule, every tour opened, or every one a row; none
    -- told apart.
    S.tours, S.groups = not S.tours, {}
  elseif p and ((p.kind == 'group' and not S.side) or (p.kind == 'tour' and not S.files)) then
    -- On a group's heading or a tour's, that one alone: a group folds
    -- with the rest until told apart, a tour with the tours' rule. With
    -- the files beside them, groups are cards, never opened.
    local key = draw.key(p)
    local now = S.groups[key]
    if now == nil then
      now = p.kind == 'group' and S.folded or (p.kind == 'tour' and not S.tours)
    end
    S.groups[key] = not now
  elseif p and CODE[p.kind] then
    S.code = not S.code
  else
    S.folded = not S.folded
    -- In a review, every group with it.
    if S.depth == 'review' then
      S.groups = {}
    end
  end
  api.draw()
  local key = it and draw.key(it.part)
  for _, other in ipairs(api.items()) do
    if draw.key(other.part) == key then
      go_to(api, other)
      return
    end
  end
  api.light()
end

--- A review's or a thread's chunks by file, or by thread again.
---@param api thread.ScreenApi
local function files(api)
  local S = assert(api.state())
  local was = api.item()
  local p = was and was.part
  S.files = not S.files
  S.open, S.opened, S.free = {}, nil, false
  api.draw()
  -- The same step, tour or message in the other layout; else the top.
  local list = api.items()
  for _, it in ipairs(list) do
    local q = it.part
    if
      p
      and q.kind == p.kind
      and (q.step and q.step.id) == (p.step and p.step.id)
      and (q.tour and q.tour.title) == (p.tour and p.tour.title)
      and q.message == p.message
      and (q.thread and q.thread.id) == (p.thread and p.thread.id)
    then
      go_to(api, it)
      return
    end
  end
  if list[1] then
    go_to(api, list[1])
  end
end

---@param api thread.ScreenApi
local function new_review(api)
  vim.ui.input({ prompt = 'A new review, its title: ' }, function(title)
    if title and vim.trim(title) ~= '' then
      local r = actions.new_review(title)
      api.move { depth = 'home', review = r.id }
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
---@field at table<thread.Depth, true>|nil  where it acts; nil: everywhere
---@field shown table<thread.Depth, true>|nil  where the footer lists it; nil: nowhere
---@field group integer|nil  the footer's group it is in: 1 moving, 2 seeing, 3 acting, 5 the screen
---@field hint string|nil  how the footer says the key, when not as typed

local LISTS = { home = true, review = true }
local READING = { thread = true, step = true }
local BELOW = { review = true, thread = true, step = true }
local ALL = { home = true, review = true, thread = true, step = true }

local VIEWS = { review = true, thread = true }

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
  { '<CR>', 'open', open, shown = ALL, group = 1, hint = '⏎/J' },
  { 'J', 'into', open },
  { '<Tab>', 'fold', fold, at = { home = true, review = true, thread = true }, shown = { home = true, review = true, thread = true }, group = 2, hint = '⇥' },
  { 'o', 'read', toggle, at = BELOW, shown = BELOW, group = 2 },
  { 'f', 'by file', files, at = VIEWS, shown = VIEWS, group = 2 },
  { 'r', 'reply', reply, shown = BELOW, group = 3 },
  { 'a', 'accept', accept, shown = BELOW, group = 3 },
  { 'c', 'close', close, shown = { home = true, review = true, thread = true }, group = 3 },
  { '<Space>', 'mark', mark, at = LISTS },
  { 'n', 'new thread', new_thread, at = BELOW },
  { 'p', 'step page', page, at = { thread = true } },
  { 'w', 'walk', walk, at = { review = true, thread = true, home = true }, shown = { thread = true }, group = 3 },
  { 'L', 'next thread', by(side, 1), at = READING },
  { 'H', 'prev thread', by(side, -1), at = READING },
  { 'K', 'back', up, at = BELOW, shown = BELOW, group = 1 },
  { '-', 'back', up, at = BELOW },
  { '<BS>', 'back', up, at = BELOW },
  { '/', 'search', search, at = { home = true }, shown = { home = true }, group = 2 },
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
    at = { home = true },
    shown = { home = true },
    group = 3,
  },
  { 'N', 'new review', new_review, at = { home = true } },
  {
    '?',
    'help',
    function(api)
      help.open(assert(api.state()), function() end)
    end,
    shown = ALL,
    group = 5,
  },
  { 'q', 'quit', quit, shown = { home = true }, group = 5 },
  { '<Esc>', 'back', quit },
}

-- Footer labels that say what the key does here.
---@type table<string, fun(S: thread.ScreenState): string|nil>
local LABELS = {
  f = function(S)
    return S.files and 'by thread' or nil
  end,
  C = function(S)
    return S.show == 'closed' and 'view open' or nil
  end,
  c = function(S)
    return S.depth == 'thread' and 'close thread' or nil
  end,
  ['<Tab>'] = function(S)
    return S.depth == 'home' and ({ none = 'three each', some = 'all threads', all = 'reviews only' })[S.fold] or nil
  end,
}

--- The footer's keys at the depth the screen is at, in their groups:
--- moving, seeing, acting, the screen.
---@param S thread.ScreenState
---@return { [1]: string, [2]: string }[][]
function M.footer(S)
  if S.free then
    return { { { 'o/⇥', 'back to items' }, { 'j/k', 'lines' } }, { { 'r', 'reply' }, { 'a', 'accept' } } }
  end
  local groups = {} ---@type { [1]: string, [2]: string }[][]
  for _, k in ipairs(KEYS) do
    if k.shown and k.shown[S.depth] then
      local g = k.group or 5
      groups[g] = groups[g] or {}
      local label = LABELS[k[1]] and LABELS[k[1]](S) or k[2]
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

--- Every key, with what it does where, for the help.
---@return thread.ScreenKey[]
function M.list()
  return KEYS
end

--- Give the screen's buffer its keys.
---@param buf integer
---@param api thread.ScreenApi
function M.map(buf, api)
  for _, k in ipairs(KEYS) do
    vim.keymap.set('n', k[1], function()
      local S = api.state()
      if S and (not k.at or k.at[S.depth]) then
        k[3](api)
      end
    end, { buffer = buf, nowait = true, desc = 'Thread: ' .. k[2] })
  end
end

return M
