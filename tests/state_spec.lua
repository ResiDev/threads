-- thread.model: the state each primitive has, worked out from the
-- messages or kept in the .seen file.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local message = require 'thread.model.message'
local review = require 'thread.model.review'
local step = require 'thread.model.step'
local thread = require 'thread.model.thread'
local tour = require 'thread.model.tour'

--- A review held in memory, its threads as given, as if read from its file.
---@param threads table[]
---@param id string|nil
---@return thread.Review
local function made(threads, id)
  local r, p = review.parse({ format = 2, title = 'T', threads = threads }, id or 'made')
  assert(r, table.concat(p.errors, '\n'))
  return r
end

---@param from 'you'|'agent'
---@return table
local function says(from, text)
  return { from = from, text = text or from }
end

--- A thread whose one message carries a tour of two steps.
---@param id integer
local function toured(id)
  return {
    id = id,
    title = 'Toured',
    messages = {
      { from = 'agent', text = 'intro', tours = { { title = 'T', steps = { { title = 'one', text = '1' }, { title = 'two', text = '2' } } } } },
    },
  }
end

R.test("thread.move: your message last is the agent's move; the agent's last, yours once you have spoken", function()
  local r = made {
    { id = 1, messages = { says 'you' } },
    { id = 2, messages = { says 'you', says 'agent' } },
    { id = 3, title = 'An explanation', messages = { says 'agent' } },
    { id = 4, status = 'fixed', messages = { says 'you' } },
  }
  R.eq(
    vim.tbl_map(function(t)
      return thread.move(thread.conversations(t)[1]) or 'nobody'
    end, r.threads),
    { 'agent', 'you', 'nobody', 'nobody' },
    'whose move'
  )
end)

R.test("thread.waiting: every conversation that is the agent's move, steps too; none in a closed review", function()
  local r = made { { id = 1, messages = { says 'you', says 'agent' } }, toured(2) }
  R.eq(#thread.waiting(r), 0, 'nothing yet')
  local convs = thread.conversations(r.threads[2])
  table.insert(convs[3].messages, says 'you')
  table.insert(r.threads[1].messages, says 'you')
  R.eq(
    vim.tbl_map(function(c)
      return c.step and (c.thread.id .. ' ' .. c.step.title) or tostring(c.thread.id)
    end, thread.waiting(r)),
    { '1', '2 two' },
    'the thread, and the step'
  )
  r.status = 'closed'
  R.eq(#thread.waiting(r), 0, 'closed')
end)

R.test('review.reply: joins the round still waiting, or starts one with a snapshot; it opens the thread', function()
  H.reset()
  local root = H.repo { ['a.lua'] = { 'x' } }
  local r = review.create 'Rounds'
  local t = review.add(r, nil, 'first')
  R.eq({ #r.rounds, t.messages[1].round }, { 1, 1 }, 'a new thread starts round 1')
  R.ok(r.rounds[1].snapshot, 'with a snapshot')
  local u = review.add(r, nil, 'second')
  R.eq(u.messages[1].round, 1, 'joins it: the first still waits')
  table.insert(t.messages, says 'agent')
  table.insert(u.messages, says 'agent')
  t.status = 'fixed'
  review.reply(r, thread.conversations(t)[1], 'not quite')
  R.eq({ #r.rounds, t.messages[3].round, t.status }, { 2, 2, 'open' }, 'nothing waited: round 2, the thread open again')
  R.ok(vim.trim(H.git(root, { 'for-each-ref', 'refs/threads/rounds/' })):find 'refs/threads/rounds/2', 'kept under the review')
  R.eq(review.base_for(r, thread.conversations(t)[1], 2), r.rounds[1].snapshot, 'the answer is to round 1')
  R.eq(u.id, 2, 'ids go up one')
  table.insert(t.messages, says 'agent')
  r.status = 'closed'
  review.reply(r, thread.conversations(u)[1], 'one more')
  review.reply(r, thread.conversations(t)[1], 'and here')
  R.eq({ r.status, #r.rounds }, { 'open', 3 }, 'a reply opens a closed review, and the next joins its round')
  table.insert(u.messages, says 'agent')
  table.insert(t.messages, says 'agent')
  r.status = 'closed'
  review.add(r, nil, 'a new thread')
  R.eq({ r.status, #r.rounds }, { 'open', 4 }, 'so does a new thread')
end)

R.test('thread.link: #12 a thread, #12.3 a step of its one tour, #12.2.3 of its second', function()
  local r = made { toured(1), toured(2) }
  local two = r.threads[2]
  table.insert(two.messages, { from = 'agent', text = 'more', tours = { { title = 'U', steps = { { title = 'three', text = '3' } } } } })
  local function links(t)
    return vim.tbl_map(thread.link, thread.conversations(t))
  end
  R.eq(links(r.threads[1]), { '#1', '#1.1', '#1.2' }, 'one tour')
  R.eq(links(two), { '#2', '#2.1.1', '#2.1.2', '#2.2.1' }, 'two')
end)

R.test("thread.unread: the agent's messages past what you have read", function()
  H.reset()
  H.repo { ['a.lua'] = { 'x' } }
  local r = made { { id = 1, messages = { says 'agent', says 'you', says 'agent' } } }
  local c = thread.conversations(r.threads[1])[1]
  R.eq(thread.unread(r, c), 2, 'both of the agent’s')
  R.eq(thread.mark_read(r, c), true, 'read')
  table.insert(c.messages, says 'agent')
  R.eq(thread.unread(r, c), 1, 'the new one')
end)

R.test('step.walked: kept by what the step is, so reordering keeps it', function()
  H.reset()
  H.repo { ['a.lua'] = { 'x' } }
  local r = made { toured(1) }
  local t = r.threads[1]
  local x = thread.tours(t)[1]
  R.eq(tour.next(r, t, x), 1, 'from the start')
  step.walk(r, t, x.steps[1])
  R.eq({ tour.walked(r, t, x), tour.next(r, t, x) }, { 1, 2 }, 'one walked, on to the next')
  x.steps[1], x.steps[2] = x.steps[2], x.steps[1]
  R.eq({ step.walked(r, t, x.steps[2]), tour.next(r, t, x) }, { true, 1 }, 'the walked one, wherever it is')
  local other = made({ toured(1) }, 'other')
  R.eq(tour.walked(other, other.threads[1], thread.tours(other.threads[1])[1]), 0, 'in its review only')
end)

R.test('step.names: a step stays walked and read when the agent requotes it or retitles it, not both', function()
  H.reset()
  H.repo { ['a.lua'] = { 'local x = 1', 'local y = 2', 'return x' } }
  local steps = {
    { title = 'one', text = '1', chunk = { file = 'a.lua', line = 1, text = 'local x = 1' }, messages = { says 'you', says 'agent' } },
    { title = 'two', text = '2', chunk = { file = 'a.lua', line = 2, text = 'local y = 2' } },
    { title = 'a page', text = 'on no line' },
  }
  local r = made { { id = 1, title = 'T', messages = { { from = 'agent', text = 'intro', tours = { { title = 'T', steps = steps } } } } } }
  local t = r.threads[1]
  local x = thread.tours(t)[1]
  for _, s in ipairs(x.steps) do
    step.walk(r, t, s)
  end
  thread.mark_read(r, thread.conversations(t)[2])
  local function kept(s, n)
    return { step.walked(r, t, s), thread.unread(r, thread.conversations(t)[n]) }
  end
  x.steps[1].title = 'one, retitled'
  R.eq(kept(x.steps[1], 2), { true, 0 }, 'retitled: still walked, still read')
  x.steps[1].title, x.steps[1].chunk.text, x.steps[1].chunk.line = 'one', 'return x', 3
  R.eq(kept(x.steps[1], 2), { true, 0 }, 'requoted')
  x.steps[1].title = 'one, retitled'
  R.eq(kept(x.steps[1], 2), { false, 1 }, 'both at once: over')
  x.steps[3].title = 'a page, retitled'
  R.eq(step.walked(r, t, x.steps[3]), true, 'a page, retitled')
  x.steps[3].text = 'rewritten'
  R.eq(step.walked(r, t, x.steps[3]), false, 'and rewritten')
end)

R.test('step.names: steps on one chunk keep their own marks when the agent reorders them or adds one before', function()
  H.reset()
  H.repo { ['a.lua'] = { 'local x = 1' } }
  local function on_x(title)
    return { title = title, text = title, chunk = { file = 'a.lua', line = 1, text = 'local x = 1' } }
  end
  local r = made { { id = 1, title = 'T', messages = { { from = 'agent', text = 'i', tours = { { title = 'T', steps = { on_x 'a', on_x 'b' } } } } } } }
  local t = r.threads[1]
  local steps = thread.tours(t)[1].steps
  R.eq({ #step.names(t, steps[1]), #step.names(t, steps[2]) }, { 1, 1 }, 'each by its title only: the quote is not its own')
  step.walk(r, t, steps[1])
  steps[1], steps[2] = steps[2], steps[1]
  R.eq({ step.walked(r, t, steps[1]), step.walked(r, t, steps[2]) }, { false, true }, 'swapped: b not walked, a walked')
  table.insert(steps, 1, on_x 'new')
  R.eq(step.walked(r, t, steps[1]), false, 'a step added before them is new')
end)

R.test('step.names: the agent requoting a step, then retitling it, keeps it, as each is read', function()
  H.reset()
  H.repo { ['a.lua'] = { 'local x = 1', 'return x' } }
  local r = review.create 'Moves'
  local raw = {
    format = 2,
    title = 'Moves',
    threads = {
      {
        id = 1,
        title = 'T',
        messages = {
          {
            from = 'agent',
            text = 'intro',
            tours = { { title = 'T', steps = { { title = 'one', text = '1', chunk = { file = 'a.lua', line = 1, text = 'local x = 1' }, messages = {} } } } },
          },
        },
      },
    },
  }
  local path = require('thread.store.file').dir() .. '/moves.json'
  local n = 0
  local function agent_writes(edit)
    edit(raw.threads[1].messages[1].tours[1].steps[1])
    vim.fn.writefile({ vim.json.encode(raw) }, path)
    n = n + 1
    vim.uv.fs_utime(path, os.time() + n, os.time() + n)
    r = assert(review.read 'moves')
    local t = r.threads[1]
    return step.walked(r, t, thread.tours(t)[1].steps[1])
  end
  agent_writes(function() end)
  local t = r.threads[1]
  step.walk(r, t, thread.tours(t)[1].steps[1])
  R.eq(
    agent_writes(function(s)
      s.chunk.text, s.chunk.line = 'return x', 2
    end),
    true,
    'requoted'
  )
  R.eq(
    agent_writes(function(s)
      s.title = 'one, retitled'
    end),
    true,
    'then retitled'
  )
end)

R.test('message.when: yours as you saved it; the agent’s as it first showed up', function()
  H.reset()
  H.repo { ['a.lua'] = { 'x' } }
  local restore = H.freeze_time '2026-10-13T10:00:00'
  local r = review.create 'When'
  review.add(r, nil, 'q')
  review.save(r)
  local raw = vim.json.decode(table.concat(vim.fn.readfile(require('thread.store.file').dir() .. '/when.json'), '\n'))
  table.insert(raw.threads[1].messages, says 'agent')
  restore()
  restore = H.freeze_time '2026-10-13T11:00:00'
  vim.fn.writefile({ vim.json.encode(raw) }, require('thread.store.file').dir() .. '/when.json')
  vim.uv.fs_utime(require('thread.store.file').dir() .. '/when.json', os.time() + 5, os.time() + 5)
  r = assert(review.read 'when')
  restore()
  local c = thread.conversations(r.threads[1])[1]
  R.eq({ message.when(r, c, 1), message.when(r, c, 2) }, { '2026-10-13T10:00:00', '2026-10-13T11:00:00' }, 'each')
  R.eq(review.latest(r), '2026-10-13T11:00:00', 'the newest')
end)
