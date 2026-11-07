-- thread.actions: the verbs change the topic and save it, for every
-- surface to draw again, reading it afresh and finding what they are
-- given by id.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local actions = require 'thread.actions'
local chunk = require 'thread.model.chunk'
local conversation = require 'thread.model.conversation'
local topic = require 'thread.model.topic'

--- H.world's topic, read.
---@return thread.Topic
local function world()
  H.reset()
  H.mute()
  H.world()
  return assert(topic.read 'screens')
end

--- The topic as its file has it now, parsed from the disk and not from
--- what the plugin holds.
---@return table
local function on_disk()
  return assert(vim.json.decode(table.concat(vim.fn.readfile '.threads/screens.json', '\n')))
end

---@param raw table
---@param id integer
---@return table|nil
local function raw_thread(raw, id)
  for _, n in ipairs(raw.threads or {}) do
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

R.test("actions.reply: in a step's, a thread's and a contract's conversation, found again by id", function()
  local r = world()
  local m = actions.reply(r, assert(topic.conversation(r, 'step', 1)), 'And the step?')
  R.eq({ m and m.from, said(m), m and m.at ~= nil }, { 'you', 'And the step?', true }, 'yours, timed')
  actions.reply(r, assert(topic.conversation(r, 'thread', 2)), 'And the thread?')
  actions.reply(r, assert(topic.conversation(r, 'contract', 1)), 'And the contract?')
  local d = on_disk()
  R.eq(said(d.tours[1].steps[1].messages[1]), 'And the step?', 'in step 1')
  local q = assert(raw_thread(d, 2))
  R.eq({ #q.messages, said(q.messages[3]) }, { 3, 'And the thread?' }, 'after the answer in thread 2')
  R.eq(said(d.contracts[1].messages[1]), 'And the contract?', 'in contract 1')
end)

R.test('actions.reply: one held from an earlier read lands in the topic as it is now', function()
  local r = world()
  local c = assert(topic.conversation(r, 'thread', 1))
  -- The agent writes while the surface holds what it read.
  local raw = on_disk()
  table.insert(assert(raw_thread(raw, 1)).messages, { from = 'agent', prose = { text = 'Meanwhile.' } })
  H.agent_writes('screens', raw)
  actions.reply(r, c, 'Mine.')
  local n = assert(raw_thread(on_disk(), 1))
  R.eq(vim.tbl_map(said, n.messages), { '`cache` is a new table on every call, and nothing reads it.', 'Meanwhile.', 'Mine.' }, "the agent's kept, yours after")
end)

R.test('actions.reply: a settled thread opens again, and a closed topic', function()
  local r = world()
  actions.set_topic_status(r, 'closed')
  R.eq({ on_disk().status, raw_thread(on_disk(), 3).status }, { 'closed', 'agreed' }, 'closed, and the decision agreed')
  actions.reply(r, assert(topic.conversation(r, 'thread', 3)), 'Agreed too soon.')
  R.eq({ on_disk().status, raw_thread(on_disk(), 3).status }, { 'open', 'open' }, 'both open again')
end)

R.test('actions.reply: nothing when what it was in has gone, or the topic cannot be read; the file is left alone', function()
  local r = world()
  local raw = on_disk()
  local c = assert(topic.conversation(r, 'thread', 4))
  table.remove(raw.threads, 4)
  H.agent_writes('screens', raw)
  R.eq(actions.reply(r, c, 'Gone?'), nil, 'the thread has gone')
  R.eq(#on_disk().threads, 3, 'nothing added')
  vim.fn.writefile({ '{' }, '.threads/screens.json')
  R.eq(actions.reply(r, assert(topic.conversation(r, 'step', 1)), 'Lost?'), nil, 'a topic that cannot be read')
  R.eq(table.concat(vim.fn.readfile '.threads/screens.json'), '{', 'not written over')
end)

R.test('actions.start: on lines, a comment with a chunk of its own, `thread-<id>` at `now`; on no line, a question', function()
  local r = world()
  local n = assert(actions.start(r, { file = 'store.lua', line = 8, from = 'function M.set(store, key, value)', to = 'end' }, 'Why no guard?\nMore.'))
  R.eq({ n.id, n.kind, n.status, n.title, n.chunk }, { 5, 'comment', nil, 'Why no guard?', 'thread-5' }, 'the next id, titled by its first line')
  local d = on_disk()
  R.eq(d.chunks[#d.chunks], { id = 'thread-5', file = 'store.lua', line = 8, from = 'function M.set(store, key, value)', to = 'end', rev = 'now' }, 'its chunk')
  R.eq(said(raw_thread(d, 5).messages[1]), 'Why no guard?\nMore.', 'what you wrote, its first message')
  local q = assert(actions.start(r, nil, 'In general?'))
  R.eq({ q.id, q.kind, q.status, q.chunk }, { 6, 'question', 'open', nil }, 'a question, open, on no line')
  local again = assert(topic.read 'screens')
  R.eq({ again.threads[5].chunk, topic.chunk(again, 'thread-5') ~= nil }, { 'thread-5', true }, 'read back, its chunk found')
  local t = assert(actions.start(again, nil, 'Why\tno  guard?\r\nMore.'))
  R.eq(t.title, 'Why no guard?', 'a title is one line: its tabs and the like a space')
  R.ok(topic.read 'screens', 'and what it wrote reads')
end)

R.test('actions.start: a kind when told; a closed topic opens again', function()
  local r = world()
  actions.set_topic_status(r, 'closed')
  local n = assert(actions.start(r, { file = 'store.lua', line = 4, from = '  local cache = {}' }, 'Move it?', 'suggestion'))
  R.eq({ n.kind, n.status, raw_thread(on_disk(), n.id).kind, on_disk().status }, { 'suggestion', 'open', 'suggestion', 'open' }, 'a suggestion, open')
end)

R.test('actions.edit: a message of yours the agent has not answered, rewritten; one it answered, or its, refused', function()
  local r = world()
  local c = assert(topic.conversation(r, 'thread', 2))
  actions.reply(r, c, 'Typo hree.')
  c = assert(topic.conversation(assert(topic.read 'screens'), 'thread', 2))
  R.eq({ actions.edit(r, c, 3, 'Typo here.') }, { true }, 'yours, unanswered')
  R.eq(said(raw_thread(on_disk(), 2).messages[3]), 'Typo here.', 'rewritten')
  R.eq({ actions.edit(r, c, 1, 'Changed?') }, { false, 'the agent has answered it since' }, 'what the agent answered stays')
  R.eq({ actions.edit(r, c, 2, 'Mine now?') }, { false, 'the agent has answered it since' }, "the agent's stays")
  R.eq(said(raw_thread(on_disk(), 2).messages[2]), '`main.lua` does, once.', 'untouched')
end)

R.test('actions.edit: a thread of yours titled by its first line keeps to it', function()
  local r = world()
  local n = assert(actions.start(r, nil, 'Why no guard?'))
  local c = assert(topic.conversation(assert(topic.read 'screens'), 'thread', n.id))
  actions.edit(r, c, 1, 'Why no check?\nMore.')
  R.eq(raw_thread(on_disk(), n.id).title, 'Why no check?', 'its title follows')
end)

R.test("actions.unsay: your new replies taken back, the agent's move with them; a thread only you wrote goes, with its chunk", function()
  local r = world()
  local c = assert(topic.conversation(r, 'thread', 2))
  actions.reply(r, c, 'One.')
  actions.reply(r, c, 'Two.')
  local fresh = assert(topic.read 'screens')
  R.eq(conversation.move(assert(topic.conversation(fresh, 'thread', 2))), 'agent', "the agent's move")
  R.eq({ actions.unsay(r, c, 4) }, { true }, 'the second')
  R.eq({ actions.unsay(r, c, 3) }, { true }, 'the first')
  fresh = assert(topic.read 'screens')
  local after = assert(topic.conversation(fresh, 'thread', 2))
  R.eq({ #after.messages, conversation.move(after) }, { 2, 'you' }, 'nothing for the agent to answer')
  R.eq({ actions.unsay(r, c, 1) }, { false, 'the agent has answered it since' }, 'what it answered stays')
  local n = assert(actions.start(r, { file = 'store.lua', line = 8, from = 'function M.set(store, key, value)' }, 'Mine.'))
  R.eq({ actions.unsay(r, assert(topic.conversation(assert(topic.read 'screens'), 'thread', n.id)), 1) }, { true }, 'a thread only you wrote')
  local d = on_disk()
  R.eq({ raw_thread(d, n.id), vim.iter(d.chunks):any(function(x)
    return x.id == 'thread-' .. n.id
  end) }, { nil, false }, 'gone, and its chunk')
end)

R.test('actions.new_topic: a topic by its title, its id made from it, saved', function()
  world()
  local n = actions.new_topic 'Caching'
  R.eq({ n.id, n.status, (topic.read 'caching' or {}).title }, { 'caching', 'open', 'Caching' }, 'written')
end)

R.test('actions.settles: the ways each kind is settled; a comment has none', function()
  local r = world()
  R.eq(actions.settles(assert(topic.thread(r, 1))), { 'fixed', "won't fix", 'not a problem' }, 'an issue')
  R.eq(actions.settles(assert(topic.thread(r, 2))), { 'answered' }, 'a question')
  R.eq(actions.settles(assert(topic.thread(r, 4))), {}, 'a comment')
end)

R.test("actions.set_status: settled by one of its kind's statuses, and opened again; another kind's refused; a comment left as it is", function()
  local r = world()
  actions.set_status(r, assert(topic.thread(r, 1)), 'fixed')
  R.eq(raw_thread(on_disk(), 1).status, 'fixed', 'the issue fixed')
  actions.set_status(r, assert(topic.thread(r, 1)), 'open')
  R.eq(raw_thread(on_disk(), 1).status, 'open', 'open again')
  actions.set_status(r, assert(topic.thread(r, 2)), 'fixed')
  R.eq(raw_thread(on_disk(), 2).status, 'open', 'a question is never fixed')
  actions.set_status(r, assert(topic.thread(r, 4)), 'answered')
  R.eq(raw_thread(on_disk(), 4).status, nil, 'a comment has no status')
end)

R.test('actions.set_topic_status: a topic closed and opened again', function()
  local r = world()
  actions.set_topic_status(r, 'closed')
  R.eq(on_disk().status, 'closed', 'closed')
  actions.set_topic_status(r, 'open')
  R.eq(on_disk().status, 'open', 'open')
end)

R.test('actions.accept: a chunk accepted, and taken back; one whose lines went, nothing', function()
  local r = world()
  local get = assert(topic.chunk(r, 'get'))
  R.eq({ actions.accept(r, get), chunk.accepted(r, get) }, { true, true }, 'accepted')
  R.eq({ actions.accept(r, get), chunk.accepted(r, get) }, { false, false }, 'taken back')
  R.eq(actions.accept(r, assert(topic.chunk(r, 'gone'))), nil, 'gone: nothing')
end)

R.test("actions.accept_part: a thread's own chunk; nothing for a tour, a step, a page or a thread on no line", function()
  local r = world()
  R.eq(actions.accept_part(r, { kind = 'thread', first = 0, last = 0, thread = assert(topic.thread(r, 3)) }), true, "thread 3's chunk")
  R.eq(chunk.accepted(r, assert(topic.chunk(r, 'main-set'))), true, 'main-set')
  local n1 = assert(topic.thread(r, 1))
  R.eq(
    actions.accept_part(r, { kind = 'chunk', first = 0, last = 0, chunk = assert(topic.chunk(r, n1.chunk)), thread = n1 }),
    true,
    "the code on thread 1's page"
  )
  R.eq(actions.accept_part(r, { kind = 'tour', first = 0, last = 0, tour = r.tours[2] }), nil, 'a tour')
  R.eq(actions.accept_part(r, { kind = 'line', first = 0, last = 0, step = assert(topic.step(r, 1)) }), nil, 'a line in step 1')
  R.eq(actions.accept_part(r, { kind = 'step', first = 0, last = 0, step = assert(topic.step(r, 5)) }), nil, 'a page')
  R.eq(actions.accept_part(r, { kind = 'thread', first = 0, last = 0, thread = assert(topic.thread(r, 2)) }), nil, 'a thread on no line')
end)
