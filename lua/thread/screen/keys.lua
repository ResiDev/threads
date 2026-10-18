--- The screen's keys, in KEYS.md's words. `j` and `k` go from item to
--- item, `}` and `{` from section to section; `J` (or `⏎`) goes down a
--- level into what is under the cursor, `K` (or `-`) back up; Tab folds
--- and unfolds; `o` opens an item and lets the cursor in, `o` or Esc again
--- goes back to items. The rest act on the part under the cursor: `r`
--- replies in the conversation it is in, `a` accepts its chunk, `c`
--- settles its note or closes its review, `f` lays the chunks out by file
--- or by tour. With notes marked (space), `r`, `a` and `c` act on each of
--- them instead.

local actions = require 'thread.actions'
local conversation = require 'thread.model.conversation'
local draw = require 'thread.draw'
local go = require 'thread.go'
local help = require 'thread.screen.help'
local note = require 'thread.model.note'
local review = require 'thread.model.review'
local review_draw = require 'thread.draw.review'

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

---@param msg string
local function say(msg)
  vim.notify('thread: ' .. msg)
end

--- The notes marked, read afresh: each with its review.
---@param S thread.ScreenState
---@return { review: thread.Review, note: thread.Note }[]
local function marked(S)
  local out = {}
  for _, m in pairs(S.marked) do
    local r = review.read(m.review)
    local n = r and review.note(r, m.note)
    if r and n then
      out[#out + 1] = { review = r, note = n }
    end
  end
  table.sort(out, function(a, b)
    return a.review.id .. '#' .. a.note.id < b.review.id .. '#' .. b.note.id
  end)
  return out
end

--- The review a part is in: its own, else the screen's.
---@param api thread.ScreenApi
---@param p thread.Part|nil
---@return thread.Review|nil
local function review_of(api, p)
  return (p and p.review) or api.at().review
end

---@param api thread.ScreenApi
local function open(api)
  local p, row, col = api.here()
  local r = review_of(api, p)
  if not (p and r) then
    return
  end
  -- A kind's heading opens to its settled notes, as Tab does.
  if p.kind == 'kind' then
    local S = assert(api.state())
    local key = review_draw.kind_key(assert(p.name))
    S.open[key] = not S.open[key] or nil
    api.draw()
    return
  end
  local ok, why = go.press(r, p, row, col, 'screen')
  if not ok and why then
    say(why)
  end
end

--- The conversation a key on the screen acts in: on a page, the page's;
--- else the one the part under the cursor is in.
---@param api thread.ScreenApi
---@return thread.Review|nil, thread.Conversation|nil
local function here_conversation(api)
  local S = assert(api.state())
  local o = api.at()
  local p = api.here()
  local r = review_of(api, p)
  if not r then
    return nil
  end
  if S.depth == 'note' and o.note then
    return r, conversation.of_note(o.note)
  elseif S.depth == 'contract' and o.contract then
    return r, conversation.of_contract(o.contract)
  elseif S.depth == 'step' and o.step and not (p and p.kind == 'note') then
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
---@return thread.Review|nil, thread.Conversation|nil, integer|nil
local function mine(api)
  local p = api.here()
  local r = review_of(api, p)
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
    go.open('compose', { replies = { { review = r, conversation = c } }, edit = i }, 'screen')
  end
end

--- Delete the message of yours under the cursor, what it said kept in
--- the unnamed register. A note's first, the note is only what you
--- wrote: asked first, since the note goes with it.
---@param api thread.ScreenApi
local function delete(api)
  local r, c, i = mine(api)
  if not (r and c and i) then
    return
  end
  local said = c.messages[i].prose.text
  local function now()
    local ok, why = actions.unsay(r, c, i)
    if ok then
      vim.fn.setreg('"', said)
      say 'deleted; what it said is in the unnamed register'
    else
      say('not deleted: ' .. why)
    end
  end
  if not (c.note and i == 1) then
    now()
    return
  end
  vim.ui.select({ 'Delete the note', 'Keep it' }, { prompt = 'Note ' .. c.note.id .. ' is only what you wrote. Delete it?' }, function(_, k)
    if k == 1 then
      now()
    end
  end)
end

---@param api thread.ScreenApi
local function reply(api)
  local S = assert(api.state())
  local many = marked(S)
  if #many > 0 then
    local replies = vim.tbl_map(function(m)
      return { review = m.review, conversation = conversation.of_note(m.note) }
    end, many)
    S.marked = {}
    go.open('compose', { replies = replies }, 'screen')
    return
  end
  local r, c = here_conversation(api)
  if not (r and c) then
    local p = api.here()
    say((p and p.kind == 'tour') and 'a tour has no conversation: reply in one of its steps, or start a note with n' or 'nothing here to reply in')
    return
  end
  go.open('compose', { replies = { { review = r, conversation = c } } }, 'screen')
end

---@param api thread.ScreenApi
local function accept(api)
  local S = assert(api.state())
  local many = marked(S)
  if #many > 0 then
    for _, m in ipairs(many) do
      local c = review.chunk(m.review, m.note.chunk)
      if c then
        actions.accept(m.review, c)
      end
    end
    S.marked = {}
    api.draw()
    return
  end
  local p = api.here()
  local r = review_of(api, p)
  if p and r and actions.accept_part(r, p) == nil then
    say 'nothing here to accept'
  end
end

--- Settle notes, asking how, by their kind; open a settled one again.
---@param list { review: thread.Review, note: thread.Note }[]
---@param done fun()|nil
local function settle(list, done)
  local one = list[1].note
  if #list == 1 and note.closed(one) then
    actions.set_status(list[1].review, one, 'open')
    say('note ' .. one.id .. ' is open again')
    if done then
      done()
    end
    return
  end
  for _, m in ipairs(list) do
    if m.note.kind ~= one.kind then
      say 'the notes marked are of different kinds: settle them a kind at a time'
      return
    end
  end
  local ways = actions.settles(one)
  if #ways == 0 then
    say 'a comment has nothing to settle'
    return
  end
  local what = #list == 1 and ('note ' .. one.id .. ' “' .. one.title .. '”') or note.noun(one.kind, #list)
  vim.ui.select(ways, { prompt = 'Settle ' .. what .. ' as' }, function(status)
    if not status then
      return
    end
    for _, m in ipairs(list) do
      actions.set_status(m.review, m.note, status)
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
  local r = review_of(api, p)
  if not (p and r) then
    return
  end
  local n = p.note or (S.depth == 'note' and api.at().note) or nil
  if p.kind == 'review' then
    actions.set_review_status(r, r.status == 'open' and 'closed' or 'open')
  elseif n then
    settle { { review = r, note = n } }
  elseif p.tour or p.step or p.contract then
    say 'a tour, a step or a contract has no status: settle a note about it, or close the review'
  end
end

---@param api thread.ScreenApi
local function mark(api)
  local S = assert(api.state())
  local p = api.here()
  if not (p and p.kind == 'note' and p.item and p.review and p.note) then
    return
  end
  local key = p.review.id .. '#note:' .. p.note.id
  S.marked[key] = not S.marked[key] and { review = p.review.id, note = p.note.id } or nil
  api.draw()
  -- On to the next note, past a kind's heading, so space after space
  -- marks note after note.
  for _, it in ipairs(api.items()) do
    if it.first > p.first and it.part.kind == 'note' then
      vim.api.nvim_win_set_cursor(S.win, { it.first + 1, 0 })
      break
    end
  end
  api.light()
end

--- A new note here: on the line of code under the cursor, else on no
--- line, in the review you are in.
---@param api thread.ScreenApi
local function new_note(api)
  local p = api.here()
  local r = review_of(api, p)
  local c = p and p.kind == 'line' and p.chunk or nil
  ---@type thread.Anchor|nil
  local a = c and { file = c.file, line = c.line, from = c.from, rev = c.rev ~= 'now' and c.rev or nil } or nil
  go.open('compose', { review = r, anchor = a }, 'screen')
end

---@param api thread.ScreenApi
local function walk(api)
  local p = api.here()
  local r = review_of(api, p)
  if not r then
    return
  end
  local o = api.at()
  local x, s = (p and p.tour) or o.tour, (p and p.step) or o.step
  if not (x or s) and #r.tours == 0 then
    say(r.title .. ' has no tour')
    return
  end
  go.open('walk', { review = r, tour = x, step = s }, 'screen')
end

--- The next or previous of what the page is: a note, a contract, a step
--- of the walk, or from a briefing its first step.
---@param api thread.ScreenApi
---@param d 1|-1
local function side(api, d)
  local S = assert(api.state())
  local o = api.at()
  local r = o.review
  if not r then
    return
  end
  ---@generic T
  ---@param list T[]
  ---@param x T
  ---@return T|nil
  local function next_of(list, x)
    for i, other in ipairs(list) do
      if other == x then
        return list[i + d]
      end
    end
  end
  if S.depth == 'contract' and o.contract then
    local to = next_of(r.contracts, o.contract)
    if to then
      api.move { depth = 'contract', review = S.review, contract = to.id }
    end
  elseif S.depth == 'note' and o.note then
    local to = next_of(r.notes, o.note)
    if to then
      api.move { depth = 'note', review = S.review, note = to.id }
    end
  elseif S.depth == 'step' and o.tour and o.step then
    local to = next_of(o.tour.steps, o.step)
    if to or d < 0 then
      go.open('walk', { review = r, tour = o.tour, step = to, briefing = not to or nil }, 'screen')
    end
  elseif S.depth == 'tour' and o.tour and d > 0 and o.tour.steps[1] then
    go.open('walk', { review = r, tour = o.tour, step = o.tour.steps[1] }, 'screen')
  end
end

--- A step's page from a step's line.
---@param api thread.ScreenApi
local function page(api)
  local p = api.here()
  local r = review_of(api, p)
  if p and r and p.step then
    go.open('page', { review = r, tour = p.tour, step = p.step }, 'screen')
  end
end

---@param api thread.ScreenApi
local function up(api)
  local S = assert(api.state())
  local r = api.at().review
  if S.depth == 'review' then
    api.move { depth = 'home', review = S.review }
  elseif S.depth ~= 'home' and r then
    if S.over then
      go.open('review', { review = r }, 'screen')
    else
      api.move { depth = 'review', review = S.review }
    end
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

-- What } and { go between, at each depth.
local SECTIONS = {
  home = { review = true },
  review = { review = true, tour = true, kind = true, file = true, heading = true },
  note = { note = true, message = true },
  contract = { contract = true, block = true, tour = true, note = true, message = true },
  step = { step = true, note = true, message = true },
  tour = { tour = true, step = true },
}

--- The next or previous section: a review at Home, a tour or a kind of
--- note in a review, a file laid out by file.
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
--- close it and go back to items. A review at Home, or a note in a
--- review, opens.
---@param api thread.ScreenApi
local function toggle(api)
  local S = assert(api.state())
  local it = api.item()
  if not it then
    return
  end
  local p = it.part
  if not S.free and p.kind == 'note' and S.depth == 'review' then
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

-- Tab at Home: each review shows the first few of what wants you, then
-- all of it, then none.
local FOLDS = { none = 'some', some = 'all', all = 'none' }

-- What Tab folds in a review, by the kind of item the cursor is on: a
-- tour, that one; the tours' rule, every tour; a contract, the rest of the list; a kind of note,
-- its settled notes; a step, a file or code, every chunk's code;
-- anything else, the introduction.
local CODE = { step = true, file = true, chunk = true, line = true }

--- Fold or unfold: at Home, how much each review shows; in a review, as
--- CODE says. Reading an item line by line, back to items.
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
    -- The cursor on the review it was in: from all, what is under it goes.
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
  elseif p and p.kind == 'tour' then
    -- On a tour, that one alone: it folds with the tours' rule until
    -- told apart.
    local key = draw.key(p)
    local now = S.groups[key]
    if now == nil then
      now = not S.tours
    end
    S.groups[key] = not now
  elseif p and p.kind == 'kind' then
    local key = review_draw.kind_key(assert(p.name))
    S.open[key] = not S.open[key] or nil
  elseif p and CODE[p.kind] then
    S.code = not S.code
  else
    S.folded = not S.folded
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

--- A review's chunks by file, or by tour and note again.
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
      and (q.note and q.note.id) == (p.note and p.note.id)
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
---@field here (fun(p: thread.Part|nil): boolean)|nil  the footer lists it only while the cursor is on such a part

local LISTS = { review = true }
local READING = { note = true, contract = true, step = true, tour = true }
local BELOW = { review = true, note = true, contract = true, step = true, tour = true }
local ALL = { home = true, review = true, note = true, contract = true, step = true, tour = true }
local FOLDING = { home = true, review = true }
local PAGES = { note = true, contract = true, step = true }

local VIEWS = { review = true }

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
  { '<Tab>', 'fold', fold, at = FOLDING, shown = FOLDING, group = 2, hint = '⇥' },
  { 'o', 'read', toggle, at = BELOW, shown = BELOW, group = 2 },
  { 'f', 'by file', files, at = VIEWS, shown = VIEWS, group = 2 },
  { 'r', 'reply', reply, shown = PAGES, group = 3 },
  { 'e', 'edit', edit, at = PAGES, shown = PAGES, group = 3, here = yours_here },
  { 'd', 'delete', delete, at = PAGES, shown = PAGES, group = 3, here = yours_here },
  { 'a', 'accept', accept, shown = BELOW, group = 3 },
  { 'c', 'settle', close, shown = { home = true, review = true, note = true }, group = 3 },
  { '<Space>', 'mark', mark, at = LISTS },
  { 'n', 'new note', new_note, at = BELOW },
  { 'p', 'step page', page, at = { review = true, tour = true } },
  { 't', 'walk', walk, at = { review = true, step = true, tour = true }, shown = { review = true, tour = true }, group = 3 },
  { 'L', 'next', by(side, 1), at = READING },
  { 'H', 'prev', by(side, -1), at = READING },
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
    return S.files and 'by tour' or nil
  end,
  C = function(S)
    return S.show == 'closed' and 'view open' or nil
  end,
  c = function(S)
    return S.depth == 'home' and 'close' or nil
  end,
  ['<Tab>'] = function(S)
    return S.depth == 'home' and ({ none = 'three each', some = 'all of each', all = 'reviews only' })[S.fold] or nil
  end,
}

--- The footer's keys at the depth the screen is at, and for what the
--- cursor is on, in their groups: moving, seeing, acting, the screen.
---@param S thread.ScreenState
---@param p thread.Part|nil  under the cursor
---@return { [1]: string, [2]: string }[][]
function M.footer(S, p)
  if S.free then
    local out = { { { 'o/⇥', 'back to items' }, { 'j/k', 'lines' } }, { { 'r', 'reply' }, { 'a', 'accept' } } }
    if yours_here(p) then
      vim.list_extend(out[2], { { 'e', 'edit' }, { 'd', 'delete' } })
    end
    return out
  end
  local groups = {} ---@type { [1]: string, [2]: string }[][]
  for _, k in ipairs(KEYS) do
    if k.shown and k.shown[S.depth] and (not k.here or k.here(p)) then
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
