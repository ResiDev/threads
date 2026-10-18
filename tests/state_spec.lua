-- thread.model: the state each primitive has, worked out from the
-- messages or kept in the .seen file, and what you write into a review.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local conversation = require 'thread.model.conversation'
local file = require 'thread.store.file'
local message = require 'thread.model.message'
local review = require 'thread.model.review'
local step = require 'thread.model.step'
local tour = require 'thread.model.tour'

---@param from 'you'|'agent'
---@param text string|nil
---@return table
local function says(from, text)
  return { from = from, at = from == 'you' and '2026-10-11T10:00:00' or nil, prose = { text = text or from } }
end

---@param id integer
---@param kind string
---@param messages table[]
---@param status string|nil
---@return table
local function note(id, kind, messages, status)
  local n = { id = id, kind = kind, title = 'note ' .. id, messages = messages }
  if kind ~= 'comment' then
    n.status = status or 'open'
  end
  if kind == 'issue' then
    n.issue, n.severity = 'bug', 'low'
  end
  return n
end

--- A review held in memory, as if read from its file: H.draft with
--- `over`'s fields.
---@param over table|nil
---@param id string|nil
---@return thread.Review
local function made(over, id)
  local r, p = review.parse(H.draft(over), id or 'made')
  return assert(r, table.concat(p.errors, '\n'))
end

-- Tours made, so each has an id of its own.
local tours = 0

--- A tour of steps on no chunk, each with its id and messages.
---@param ids integer[]
---@param messages table[][]|nil  each step's
---@return table
local function pages(ids, messages)
  tours = tours + 1
  local steps = {}
  for i, id in ipairs(ids) do
    steps[i] = { id = id, title = 'step ' .. id, text = { text = 't' }, messages = (messages or {})[i] or {} }
  end
  return { id = tours, title = 'Pages', colour = 'sky', introduction = { text = 'i' }, steps = steps }
end

---@param list thread.Conversation[]
---@return string[]
local function names(list)
  return vim.tbl_map(function(c)
    return c.name
  end, list)
end

R.test("conversation.move: your message last is the agent's move; the agent's last, yours once you have spoken", function()
  local r = made {
    notes = {
      note(1, 'question', { says 'you' }),
      note(2, 'question', { says 'you', says 'agent' }),
      note(3, 'decision', { says 'agent' }),
      note(4, 'issue', { says 'you' }, 'fixed'),
      note(5, 'comment', { says 'you' }),
    },
  }
  R.eq(
    vim.tbl_map(function(n)
      return conversation.move(conversation.of_note(n)) or 'nobody'
    end, r.notes),
    { 'agent', 'you', 'nobody', 'nobody', 'agent' },
    "whose move: an explanation is nobody's, a settled note nobody's"
  )
  R.eq(conversation.move(conversation.of_step(r.tours[1].steps[1])), nil, 'a step with no messages: nobody')
end)

R.test("conversation.all and waiting: every step's, note's and contract's; what waits is the agent's move; none in a closed review", function()
  local contract = {
    id = 1,
    name = 'M.get',
    kind = 'function',
    source = { change = 'added', after = 'get' },
    prose = { text = 'p' },
    messages = { says 'you' },
  }
  local r = made {
    contracts = { contract },
    tours = { pages({ 7, 8 }, { {}, { says 'you' } }) },
    notes = { note(12, 'question', { says 'you', says 'agent' }), note(13, 'suggestion', { says 'you' }) },
  }
  R.eq(names(conversation.all(r)), { 'contract:1', 'step:7', 'step:8', 'note:12', 'note:13' }, "contracts', steps', notes'")
  R.eq(names(conversation.waiting(r)), { 'contract:1', 'step:8', 'note:13' }, 'waiting on the agent')
  r.status = 'closed'
  R.eq(conversation.waiting(r), {}, 'closed')
  R.eq(conversation.link(conversation.all(r)[2]), '#step:7', 'linked as prose links it')
end)

R.test('review.conversation: by its kind and id, whichever tour a step is in; nil when it has gone', function()
  local r = made { tours = { pages { 1, 2 }, pages { 5 } }, notes = { note(3, 'comment', { says 'agent' }) } }
  local c = assert(review.conversation(r, 'step', 5))
  R.eq({ c.name, c.step.title, c.tour == r.tours[2] }, { 'step:5', 'step 5', true }, 'a step, with its tour')
  R.eq(assert(review.conversation(r, 'note', 3)).note, r.notes[1], 'a note')
  R.eq({ review.conversation(r, 'step', 4), review.conversation(r, 'note', 1), review.conversation(r, 'contract', 1) }, {}, 'none of these')
end)

R.test("conversation.unread, read and mark_read: the agent's messages past what you have read, kept per review", function()
  H.reset()
  H.repo(H.fixture)
  local r = made { notes = { note(1, 'question', { says 'agent', says 'you', says 'agent' }) } }
  local c = conversation.of_note(r.notes[1])
  R.eq({ conversation.read(r, c), conversation.unread(r, c) }, { 0, 2 }, "both of the agent's")
  R.eq(conversation.for_you(r, c), true, 'yours to read')
  R.eq(conversation.mark_read(r, c, 1), true, 'the first read')
  R.eq({ conversation.read(r, c), conversation.unread(r, c) }, { 1, 1 }, 'one left')
  R.eq(conversation.mark_read(r, c), true, 'all of it')
  R.eq({ conversation.mark_read(r, c), conversation.mark_read(r, c, 1) }, { false, false }, 'never again, never back')
  table.insert(c.messages, says 'agent')
  R.eq(conversation.unread(r, c), 1, 'the new one')
  local other = made({ notes = { note(1, 'question', { says 'agent' }) } }, 'other')
  R.eq(conversation.unread(other, conversation.of_note(other.notes[1])), 1, 'in its review only')
  local mine = made({ notes = { note(1, 'question', { says 'you' }) } }, 'mine')
  R.eq(conversation.for_you(mine, conversation.of_note(mine.notes[1])), false, 'waiting on the agent is not for you')
end)

R.test('step.walked and tour.next: kept by its id, so the agent moving it keeps it; in its review only', function()
  H.reset()
  H.repo(H.fixture)
  local r = made { tours = { pages { 1, 2 } } }
  local x = r.tours[1]
  R.eq({ tour.walked(r, x), tour.next(r, x) }, { 0, 1 }, 'from the start')
  R.eq(step.walk(r, x.steps[1]), true, 'walked')
  R.eq(step.walk(r, x.steps[1]), false, 'once')
  R.eq({ tour.walked(r, x), tour.next(r, x) }, { 1, 2 }, 'on to the next')
  x.steps[1], x.steps[2] = x.steps[2], x.steps[1]
  x.steps[2].title = 'retitled'
  R.eq({ step.walked(r, x.steps[2]), tour.next(r, x) }, { true, 1 }, 'the walked one, wherever it is, whatever it says')
  step.walk(r, x.steps[1])
  R.eq(tour.next(r, x), nil, 'all walked')
  local other = made({ tours = { pages { 1, 2 } } }, 'other')
  R.eq(tour.walked(other, other.tours[1]), 0, 'in its review only')
end)

R.test('review.next_id: one past the highest of its kind, each kind its own', function()
  local r = made { tours = { pages { 2, 9 }, pages { 4 } }, notes = { note(3, 'comment', { says 'you' }) } }
  R.eq({ review.next_id(r, 'step'), review.next_id(r, 'note'), review.next_id(r, 'contract') }, { 10, 4, 1 }, 'each')
end)

R.test('review.add: a note of yours, on no line or on lines with a chunk of its own; it opens a closed review', function()
  H.reset()
  H.repo(H.fixture)
  local restore = H.freeze_time '2026-10-13T10:00:00'
  local r = made { notes = { note(4, 'comment', { says 'agent' }) } }
  r.status = 'closed'
  local n = review.add(r, nil, '## Why is the cache thrown away?\n\nIt is made each call.', 'question')
  R.eq(n, {
    id = 5,
    kind = 'question',
    title = 'Why is the cache thrown away?',
    status = 'open',
    messages = { { from = 'you', at = '2026-10-13T10:00:00', prose = { text = '## Why is the cache thrown away?\n\nIt is made each call.' } } },
  }, 'on no line, its title the first line')
  R.eq({ r.status, r.notes[2] }, { 'open', n }, 'the review open again, the note in it')
  local a = { file = 'store.lua', line = 4, from = '  local cache = {}', to = '  return store[key]' }
  r.chunks[#r.chunks + 1] = { id = 'note-6', file = 'x', line = 1, from = 'x', rev = 'now' }
  local m = review.add(r, a, string.rep('long ', 20), 'comment')
  R.eq({ m.chunk, m.status, vim.fn.strchars(m.title) }, { 'note-6-2', nil, 72 }, 'a chunk id no other has; a comment has no status; a long title cut')
  R.eq(
    review.chunk(r, 'note-6-2'),
    { id = 'note-6-2', file = 'store.lua', line = 4, from = '  local cache = {}', to = '  return store[key]', rev = 'now' },
    'its chunk, read now'
  )
  restore()
end)

R.test('review.reply: a message of yours, at the time; it opens a settled note and a closed review', function()
  H.reset()
  H.repo(H.fixture)
  local restore = H.freeze_time '2026-10-13T11:00:00'
  local r = made { notes = { note(1, 'issue', { says 'agent' }, 'not a problem') } }
  r.status = 'closed'
  local c = conversation.of_note(r.notes[1])
  R.eq(conversation.move(c), nil, 'settled: nobody')
  local m = review.reply(r, c, 'It is.')
  R.eq(m, { from = 'you', at = '2026-10-13T11:00:00', prose = { text = 'It is.' } }, 'yours')
  R.eq({ r.status, r.notes[1].status, conversation.move(c) }, { 'open', 'open', 'agent' }, 'open again, the agent to answer')
  review.reply(r, conversation.of_step(r.tours[1].steps[1]), 'And here?')
  R.eq(#r.tours[1].steps[1].messages, 1, 'in a step')
  restore()
end)

R.test('review.add then save: what the plugin writes is what the agent reads', function()
  H.reset()
  H.repo(H.fixture)
  local r = review.create 'Mine'
  review.add(r, { file = 'store.lua', line = 9, from = '  store[key] = value' }, 'Should this check the key?', 'question')
  review.add(r, nil, 'Looks good.', 'comment')
  review.save(r)
  local again, p = review.parse(assert(file.read(r.id)), r.id)
  R.eq({ again ~= nil, p.errors, p.warnings }, { true, {}, {} }, 'reads, with nothing to say')
  R.eq(names(conversation.waiting(assert(again))), { 'note:1', 'note:2' }, 'both wait on the agent')
end)

R.test('review.notes: by kind in the order a review lists them, the open first in each, how many are open', function()
  local r = made {
    notes = {
      note(1, 'question', { says 'you' }, 'answered'),
      note(2, 'comment', { says 'you' }),
      note(3, 'issue', { says 'agent' }, 'fixed'),
      note(4, 'question', { says 'you' }),
      note(5, 'issue', { says 'agent' }),
      note(6, 'issue', { says 'agent' }),
    },
  }
  R.eq(
    vim.tbl_map(function(g)
      return {
        g.kind,
        g.open,
        vim.tbl_map(function(n)
          return n.id
        end, g.notes),
      }
    end, review.notes(r)),
    { { 'issue', 2, { 5, 6, 3 } }, { 'question', 1, { 4, 1 } }, { 'comment', 0, { 2 } } },
    'issues first; a kind with none left out; a comment never open'
  )
end)

R.test("message.when and review.latest: yours as you saved it; the agent's as it first showed up", function()
  H.reset()
  H.repo(H.fixture)
  local restore = H.freeze_time '2026-10-13T10:00:00'
  local r = review.create 'When'
  review.add(r, nil, 'q', 'question')
  review.save(r)
  local raw = assert(file.read 'when')
  table.insert(raw.notes[1].messages, says 'agent')
  restore()
  restore = H.freeze_time '2026-10-13T11:00:00'
  r = assert(H.agent_writes('when', raw))
  restore()
  local c = conversation.of_note(r.notes[1])
  R.eq({ message.when(r, c, 1), message.when(r, c, 2), message.when(r, c, 3) }, { '2026-10-13T10:00:00', '2026-10-13T11:00:00', nil }, 'each')
  R.eq(review.latest(r), '2026-10-13T11:00:00', 'the newest')
end)

R.test('message.when: what is in a review the first time it is read is from when its file was written', function()
  H.reset()
  H.repo(H.fixture)
  local restore = H.freeze_time '2026-10-13T12:00:00'
  local path = file.dir() .. '/first.json'
  vim.fn.mkdir(file.dir(), 'p')
  vim.fn.writefile({ vim.json.encode(H.draft { notes = { note(1, 'decision', { says 'agent' }) } }) }, path)
  local written = os.time { year = 2026, month = 10, day = 12, hour = 9, min = 0, sec = 0 }
  vim.uv.fs_utime(path, written, written)
  local r = assert(review.read 'first')
  restore()
  R.eq(message.when(r, conversation.of_note(r.notes[1]), 1), '2026-10-12T09:00:00', 'as the file says')
end)
