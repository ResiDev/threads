-- thread.compose: the float you write in. A reply goes in each
-- conversation it was opened on; a note you start goes in the review you
-- pick as you save it.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local go = require 'thread.go'
local review = require 'thread.model.review'
require 'thread.compose'

--- H.world, and beside it a closed review, which is never offered.
local function world()
  H.reset()
  H.mute()
  H.world()
  H.review('closed', { title = 'Closed', status = 'closed' })
end

--- vim.ui.select and vim.ui.input answering as given, for `fn`.
---@param pick integer|nil  the item picked; nil: none
---@param title string|nil  what is typed for a title
---@param fn fun()
---@return string[] offered
local function answering(pick, title, fn)
  local select, input = vim.ui.select, vim.ui.input
  local offered = {}
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.ui.select = function(items, _, cb)
    offered = items
    cb(pick and items[pick], pick)
  end
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.ui.input = function(_, cb)
    cb(title)
  end
  local ok, err = pcall(fn)
  vim.ui.select, vim.ui.input = select, input
  assert(ok, err)
  return offered
end

--- The float's title, as it is drawn.
---@return string
local function title()
  local t = vim.api.nvim_win_get_config(0).title
  return vim.trim(type(t) == 'table' and table.concat(vim.tbl_map(function(c)
    return c[1]
  end, t)) or tostring(t))
end

---@param kind 'step'|'note'|'contract'
---@param id integer
---@return { review: thread.Review, conversation: thread.Conversation }
local function reply_in(kind, id)
  local r = assert(review.read 'screens')
  return { review = r, conversation = assert(review.conversation(r, kind, id)) }
end

---@param kind 'step'|'note'|'contract'
---@param id integer
---@return string[]
local function said(kind, id)
  local c = assert(review.conversation(assert(review.read 'screens'), kind, id))
  return vim.tbl_map(function(m)
    return m.prose.text
  end, c.messages)
end

R.test('compose: a reply is titled by its conversation, its kind, id and title', function()
  world()
  go.open('compose', { replies = { reply_in('step', 2) } })
  R.eq(title(), 'Reply in step 2 the cache is thrown away', 'a step')
  H.press '<Esc><Esc>'
  go.open('compose', { replies = { reply_in('contract', 1) } })
  R.eq(title(), 'Reply in contract 1 the value of a', 'a contract, by its name')
  H.press '<Esc><Esc>'
  go.open('compose', { replies = { reply_in('note', 4), reply_in('step', 1) } })
  R.eq(title(), 'A reply to 2 conversations', 'several')
  H.press '<Esc><Esc>'
end)

R.test('compose: one reply saved into each conversation it was opened on', function()
  world()
  go.open('compose', { replies = { reply_in('note', 4), reply_in('step', 1), reply_in('contract', 1) } })
  H.type_in 'All of them.'
  H.press '<C-s>'
  R.eq(said('note', 4), { 'set has no guard', 'All of them.' }, 'note 4')
  R.eq(said('step', 1), { 'All of them.' }, 'step 1')
  R.eq(said('contract', 1), { 'All of them.' }, 'contract 1')
end)

R.test('compose: a reply into what has gone is kept in the unnamed register', function()
  world()
  local gone = reply_in('note', 4)
  local raw = assert(vim.json.decode(table.concat(vim.fn.readfile '.threads/screens.json', '\n')))
  table.remove(raw.notes, 4)
  H.agent_writes('screens', raw)
  go.open('compose', { replies = { gone } })
  H.type_in 'Into nothing.'
  H.press '<C-s>'
  R.eq(vim.fn.getreg '"', 'Into nothing.', 'kept')
end)

R.test('compose: a question goes in the open review you pick; a note on lines in a new one you name', function()
  world()
  local offered = answering(1, nil, function()
    go.open('compose', {})
    R.eq(title(), 'A question, on no line', 'titled')
    H.type_in 'In general?'
    H.press '<C-s>'
  end)
  R.eq(offered, { 'Screens', 'A new review…' }, 'the open reviews, then a new one')
  local n = assert(review.read 'screens').notes[5]
  R.eq({ n and n.kind, n and n.chunk, n and n.messages[1].prose.text }, { 'question', nil, 'In general?' }, 'in Screens, on no line')
  answering(2, 'Fresh one', function()
    go.open('compose', { anchor = { file = 'store.lua', line = 8, from = 'function M.set(store, key, value)', to = 'end' } })
    R.eq(title(), 'A note on store.lua:8', 'titled by where')
    H.type_in 'Why no guard?'
    H.press '<C-s>'
  end)
  local f = assert(review.read 'fresh-one')
  local c = review.chunk(f, f.notes[1].chunk)
  R.eq(
    { f.title, f.notes[1].kind, c and c.file, c and c.line, f.notes[1].messages[1].prose.text },
    { 'Fresh one', 'comment', 'store.lua', 8, 'Why no guard?' },
    'a new review, the note a comment on its lines'
  )
end)

R.test('compose: a note started in a review goes there, nothing asked', function()
  world()
  local r = assert(review.read 'screens')
  local offered = answering(nil, nil, function()
    go.open('compose', { review = r })
    H.type_in 'Straight in.'
    H.press '<C-s>'
  end)
  R.eq(offered, {}, 'nothing offered')
  R.eq(said('note', 5), { 'Straight in.' }, 'note 5')
end)

R.test('compose: nothing picked saves nothing, and what you wrote is in the unnamed register', function()
  world()
  answering(nil, nil, function()
    go.open('compose', {})
    H.type_in 'Lost?'
    H.press '<C-s>'
  end)
  R.eq(#assert(review.read 'screens').notes, 4, 'nothing saved')
  R.eq(vim.fn.getreg '"', 'Lost?', 'kept')
end)

R.test('compose: q throws it away; going to another window saves it', function()
  world()
  go.open('compose', { replies = { reply_in('note', 4) } })
  H.type_in 'Never mind.'
  H.press 'q'
  R.eq(#said('note', 4), 1, 'thrown away')
  go.open('compose', { replies = { reply_in('note', 4) } })
  H.type_in 'Kept.'
  vim.cmd 'wincmd p'
  H.settle()
  R.eq(said('note', 4)[2], 'Kept.', 'saved on leaving')
end)

R.test('compose: :q saves it, as leaving does', function()
  world()
  go.open('compose', { replies = { reply_in('note', 4) } })
  H.type_in 'Typed then :q'
  vim.cmd 'stopinsert'
  local ok, err = pcall(vim.cmd, 'q')
  H.settle()
  R.ok(ok, tostring(err))
  R.eq(said('note', 4)[2], 'Typed then :q', 'saved')
end)
