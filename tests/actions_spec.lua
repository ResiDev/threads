-- thread.actions: the verbs change the review and save it, for every
-- surface to draw again, reading it afresh and finding what they are
-- given by id.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local actions = require 'thread.actions'
local chunk = require 'thread.model.chunk'
local review = require 'thread.model.review'

--- H.world's review, read.
---@return thread.Review
local function world()
  H.reset()
  H.mute()
  H.world()
  return assert(review.read 'screens')
end

--- The review as its file has it now, parsed from the disk and not from
--- what the plugin holds.
---@return table
local function on_disk()
  return assert(vim.json.decode(table.concat(vim.fn.readfile '.threads/screens.json', '\n')))
end

---@param raw table
---@param id integer
---@return table|nil
local function raw_note(raw, id)
  for _, n in ipairs(raw.notes or {}) do
    if n.id == id then
      return n
    end
  end
end

---@param m table|nil
---@return string|nil
local function said(m)
  return m and m.prose and m.prose.text
end

R.test("actions.reply: in a step's, a note's and a contract's conversation, found again by id", function()
  local r = world()
  local m = actions.reply(r, assert(review.conversation(r, 'step', 1)), 'And the step?')
  R.eq({ m and m.from, said(m), m and m.at ~= nil }, { 'you', 'And the step?', true }, 'yours, timed')
  actions.reply(r, assert(review.conversation(r, 'note', 2)), 'And the note?')
  actions.reply(r, assert(review.conversation(r, 'contract', 1)), 'And the contract?')
  local d = on_disk()
  R.eq(said(d.tours[1].steps[1].messages[1]), 'And the step?', 'in step 1')
  local q = assert(raw_note(d, 2))
  R.eq({ #q.messages, said(q.messages[3]) }, { 3, 'And the note?' }, 'after the answer in note 2')
  R.eq(said(d.contracts[1].messages[1]), 'And the contract?', 'in contract 1')
end)

R.test('actions.reply: one held from an earlier read lands in the review as it is now', function()
  local r = world()
  local c = assert(review.conversation(r, 'note', 1))
  -- The agent writes while the surface holds what it read.
  local raw = on_disk()
  table.insert(assert(raw_note(raw, 1)).messages, { from = 'agent', prose = { text = 'Meanwhile.' } })
  H.agent_writes('screens', raw)
  actions.reply(r, c, 'Mine.')
  local n = assert(raw_note(on_disk(), 1))
  R.eq(vim.tbl_map(said, n.messages), { '`cache` is a new table on every call, and nothing reads it.', 'Meanwhile.', 'Mine.' }, "the agent's kept, yours after")
end)

R.test('actions.reply: a settled note opens again, and a closed review', function()
  local r = world()
  actions.set_review_status(r, 'closed')
  R.eq({ on_disk().status, raw_note(on_disk(), 3).status }, { 'closed', 'agreed' }, 'closed, and the decision agreed')
  actions.reply(r, assert(review.conversation(r, 'note', 3)), 'Agreed too soon.')
  R.eq({ on_disk().status, raw_note(on_disk(), 3).status }, { 'open', 'open' }, 'both open again')
end)

R.test('actions.reply: nothing when what it was in has gone, or the review cannot be read; the file is left alone', function()
  local r = world()
  local raw = on_disk()
  local c = assert(review.conversation(r, 'note', 4))
  table.remove(raw.notes, 4)
  H.agent_writes('screens', raw)
  R.eq(actions.reply(r, c, 'Gone?'), nil, 'the note has gone')
  R.eq(#on_disk().notes, 3, 'nothing added')
  vim.fn.writefile({ '{' }, '.threads/screens.json')
  R.eq(actions.reply(r, assert(review.conversation(r, 'step', 1)), 'Lost?'), nil, 'a review that cannot be read')
  R.eq(table.concat(vim.fn.readfile '.threads/screens.json'), '{', 'not written over')
end)

R.test('actions.start: on lines, a comment with a chunk of its own, `note-<id>` at `now`; on no line, a question', function()
  local r = world()
  local n = assert(actions.start(r, { file = 'store.lua', line = 8, from = 'function M.set(store, key, value)', to = 'end' }, 'Why no guard?\nMore.'))
  R.eq({ n.id, n.kind, n.status, n.title, n.chunk }, { 5, 'comment', nil, 'Why no guard?', 'note-5' }, 'the next id, titled by its first line')
  local d = on_disk()
  R.eq(d.chunks[#d.chunks], { id = 'note-5', file = 'store.lua', line = 8, from = 'function M.set(store, key, value)', to = 'end', rev = 'now' }, 'its chunk')
  R.eq(said(raw_note(d, 5).messages[1]), 'Why no guard?\nMore.', 'what you wrote, its first message')
  local q = assert(actions.start(r, nil, 'In general?'))
  R.eq({ q.id, q.kind, q.status, q.chunk }, { 6, 'question', 'open', nil }, 'a question, open, on no line')
  local again = assert(review.read 'screens')
  R.eq({ again.notes[5].chunk, review.chunk(again, 'note-5') ~= nil }, { 'note-5', true }, 'read back, its chunk found')
end)

R.test('actions.start: a kind when told; a closed review opens again', function()
  local r = world()
  actions.set_review_status(r, 'closed')
  local n = assert(actions.start(r, { file = 'store.lua', line = 4, from = '  local cache = {}' }, 'Move it?', 'suggestion'))
  R.eq({ n.kind, n.status, raw_note(on_disk(), n.id).kind, on_disk().status }, { 'suggestion', 'open', 'suggestion', 'open' }, 'a suggestion, open')
end)

R.test('actions.new_review: a review by its title, its id made from it, saved', function()
  world()
  local n = actions.new_review 'Caching'
  R.eq({ n.id, n.status, (review.read 'caching' or {}).title }, { 'caching', 'open', 'Caching' }, 'written')
end)

R.test('actions.settles: the ways each kind is settled; a comment has none', function()
  local r = world()
  R.eq(actions.settles(assert(review.note(r, 1))), { 'fixed', "won't fix", 'not a problem' }, 'an issue')
  R.eq(actions.settles(assert(review.note(r, 2))), { 'answered' }, 'a question')
  R.eq(actions.settles(assert(review.note(r, 4))), {}, 'a comment')
end)

R.test("actions.set_status: settled by one of its kind's statuses, and opened again; another kind's refused; a comment left as it is", function()
  local r = world()
  actions.set_status(r, assert(review.note(r, 1)), 'fixed')
  R.eq(raw_note(on_disk(), 1).status, 'fixed', 'the issue fixed')
  actions.set_status(r, assert(review.note(r, 1)), 'open')
  R.eq(raw_note(on_disk(), 1).status, 'open', 'open again')
  actions.set_status(r, assert(review.note(r, 2)), 'fixed')
  R.eq(raw_note(on_disk(), 2).status, 'open', 'a question is never fixed')
  actions.set_status(r, assert(review.note(r, 4)), 'answered')
  R.eq(raw_note(on_disk(), 4).status, nil, 'a comment has no status')
end)

R.test('actions.set_review_status: a review closed and opened again', function()
  local r = world()
  actions.set_review_status(r, 'closed')
  R.eq(on_disk().status, 'closed', 'closed')
  actions.set_review_status(r, 'open')
  R.eq(on_disk().status, 'open', 'open')
end)

R.test('actions.accept: a chunk accepted, and taken back; one whose lines went, nothing', function()
  local r = world()
  local get = assert(review.chunk(r, 'get'))
  R.eq({ actions.accept(r, get), chunk.accepted(r, get) }, { true, true }, 'accepted')
  R.eq({ actions.accept(r, get), chunk.accepted(r, get) }, { false, false }, 'taken back')
  R.eq(actions.accept(r, assert(review.chunk(r, 'gone'))), nil, 'gone: nothing')
end)

R.test("actions.accept_tour: every chunk of its steps; again takes them back; a step whose lines went doesn't count", function()
  local r = world()
  local reading = r.tours[1]
  local function states()
    return { chunk.accepted(r, assert(review.chunk(r, 'get'))), chunk.accepted(r, assert(review.chunk(r, 'cache'))) }
  end
  chunk.accept(r, assert(review.chunk(r, 'get')), true)
  R.eq(actions.accept_tour(r, reading), true, 'one was not: all accepted')
  R.eq(states(), { true, true }, 'both')
  R.eq(actions.accept_tour(r, reading), false, 'all were: all taken back')
  R.eq(states(), { false, false }, 'neither')
  local x = { title = 'Pages', colour = 'lime', introduction = { text = 'x' }, steps = { r.tours[2].steps[2] } }
  R.eq(actions.accept_tour(r, x), nil, 'a tour of pages has none')
end)

R.test("actions.accept_part: a tour, all its chunks; a chunk; a step's or a note's own; nothing for a page or a note on no line", function()
  local r = world()
  local set = assert(review.chunk(r, 'set'))
  R.eq(actions.accept_part(r, { kind = 'tour', first = 0, last = 0, tour = r.tours[2] }), true, 'the Writing tour')
  R.eq(chunk.accepted(r, set), true, 'its step on set')
  R.eq(actions.accept_part(r, { kind = 'chunk', first = 0, last = 0, chunk = set }), false, 'the chunk: taken back')
  local s = assert(review.step(r, 1))
  R.eq(actions.accept_part(r, { kind = 'line', first = 0, last = 0, step = s }), true, "a line in step 1: the step's chunk")
  R.eq(chunk.accepted(r, assert(review.chunk(r, 'get'))), true, 'get')
  R.eq(actions.accept_part(r, { kind = 'note', first = 0, last = 0, note = assert(review.note(r, 3)) }), true, "note 3's chunk")
  R.eq(chunk.accepted(r, assert(review.chunk(r, 'main-set'))), true, 'main-set')
  R.eq(actions.accept_part(r, { kind = 'step', first = 0, last = 0, step = assert(review.step(r, 5)) }), nil, 'a page')
  R.eq(actions.accept_part(r, { kind = 'note', first = 0, last = 0, note = assert(review.note(r, 2)) }), nil, 'a note on no line')
end)

R.test('actions.accept: a chunk shared by a step and a note is accepted once, for both', function()
  local r = world()
  actions.accept_part(r, { kind = 'note', first = 0, last = 0, note = assert(review.note(r, 1)) })
  R.eq(actions.accept_part(r, { kind = 'step', first = 0, last = 0, step = assert(review.step(r, 2)) }), false, "step 2's is note 1's: taken back")
end)
