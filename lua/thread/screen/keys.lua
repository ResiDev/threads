--- The screen's keys. Each acts on the part under the cursor: `⏎` opens
--- what it means, `r` replies in the conversation it is in, `a` accepts
--- its chunk, `c` closes its thread or its review. With threads marked
--- (space), `r`, `a` and `c` act on each of them instead.

local actions = require 'thread.actions'
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
  local p = api.here()
  local r = p and (p.review or api.at())
  if p and r and actions.accept_part(r, p) == nil then
    say 'nothing here to accept'
  end
end

--- Close a thread, asking how; open a closed one again.
---@param list { review: thread.Review, thread: thread.Thread }[]
---@param done fun()|nil
local function close_threads(list, done)
  if #list == 1 and thread.closed(list[1].thread) then
    actions.set_status(list[1].review, list[1].thread, 'open')
    if done then
      done()
    end
    return
  end
  local what = #list == 1 and ('#' .. list[1].thread.id) or (#list .. ' threads')
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
  for i, other in ipairs(r.threads) do
    if other == t and r.threads[i + d] then
      api.move { depth = 'thread', review = r.id, thread = r.threads[i + d].id }
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
  elseif S.depth == 'thread' and r and #r.threads > 1 then
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

local LISTS = { home = true, review = true }
local READING = { thread = true, step = true }
local BELOW = { review = true, thread = true, step = true }
local ALL = { home = true, review = true, thread = true, step = true }

---@type thread.ScreenKey[]
local KEYS = {
  { '<CR>', 'open', open, shown = ALL },
  { 'r', 'reply', reply, shown = BELOW },
  { 'a', 'accept', accept, shown = BELOW },
  { 'c', 'close', close, shown = { review = true, thread = true } },
  { '<Space>', 'mark', mark, at = LISTS },
  { 'n', 'new thread', new_thread, at = BELOW },
  { 'o', 'step', page, at = { thread = true } },
  { 'J', 'walk', walk, at = { review = true, thread = true, home = true }, shown = { thread = true } },
  {
    'L',
    'next',
    function(api)
      side(api, 1)
    end,
    at = READING,
    shown = READING,
  },
  {
    'H',
    'prev',
    function(api)
      side(api, -1)
    end,
    at = READING,
  },
  { 'K', 'back', up, at = BELOW, shown = BELOW },
  { '/', 'search', search, at = { home = true }, shown = { home = true } },
  {
    'C',
    'closed too',
    function(api)
      local S = assert(api.state())
      S.show = ({ open = 'all', all = 'closed', closed = 'open' })[S.show]
      api.draw()
    end,
    at = { home = true },
  },
  { 'N', 'new review', new_review, at = { home = true } },
  {
    '?',
    'help',
    function(api)
      help.open(assert(api.state()), function() end)
    end,
    shown = ALL,
  },
  { 'q', 'quit', quit, shown = { home = true } },
  { '<Esc>', 'back', quit },
}

--- The footer's keys at the depth the screen is at.
---@param S thread.ScreenState
---@return { [1]: string, [2]: string }[]
function M.footer(S)
  local out = {}
  for _, k in ipairs(KEYS) do
    if k.shown and k.shown[S.depth] then
      local key = k[1] == '<CR>' and '⏎' or k[1] == 'L' and 'L/H' or k[1]
      out[#out + 1] = { key, k[2] }
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
