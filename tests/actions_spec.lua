-- thread.actions: the verbs change the review and save it, for every
-- surface to draw again.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local actions = require 'thread.actions'
local chunk = require 'thread.model.chunk'
local review = require 'thread.model.review'
local thread = require 'thread.model.thread'

local CODE = { 'local M = {}', '', 'function M.get(t, k)', '  return t[k]', 'end', '', 'return M' }

--- A review on a.lua: thread 1 on line 3 with a tour of two steps, on
--- line 4 and on no line; thread 2 on no line.
---@return thread.Review
local function written()
  H.reset()
  H.repo { ['a.lua'] = CODE }
  return H.review('r', {
    threads = {
      {
        id = 1,
        title = 'get',
        chunk = { file = 'a.lua', line = 3, text = 'function M.get(t, k)' },
        messages = {
          {
            from = 'agent',
            text = 'It reads.',
            tours = {
              {
                title = 'How',
                steps = {
                  { id = 1, title = 'the read', chunk = { file = 'a.lua', line = 4, text = '  return t[k]' } },
                  { id = 2, title = 'a page', text = 'No line.' },
                },
              },
            },
          },
        },
      },
      { id = 2, title = 'Why', messages = { { from = 'agent', text = 'Because.' } } },
    },
  })
end

--- The review as its file has it now.
---@return thread.Review
local function on_disk()
  return assert(review.parse(assert(vim.json.decode(table.concat(vim.fn.readfile '.threads/r.json', '\n'))), 'r'))
end

R.test('actions.reply: saved in its conversation, a step its own; a closed thread opens again', function()
  local r = written()
  local t = r.threads[1]
  local s = thread.step(t, 1)
  actions.reply(r, thread.conversation(t, s, thread.tours(t)[1]), 'And the step?')
  R.eq(on_disk().threads[1].messages[1].tours[1].steps[1].messages[1].text, 'And the step?', 'in the step')
  actions.set_status(r, r.threads[2], 'fixed')
  R.eq(on_disk().threads[2].status, 'fixed', 'closed')
  actions.reply(r, thread.conversation(r.threads[2]), 'Not yet.')
  R.eq({ on_disk().threads[2].status, #on_disk().threads[2].messages }, { 'open', 2 }, 'open again, the reply in it')
end)

R.test('actions.start: a thread of yours, on a line or on none, the next id; a new review by its title', function()
  local r = written()
  local t = actions.start(r, { file = 'a.lua', line = 1, text = 'local M = {}' }, 'Why a table?')
  R.eq({ t.id, on_disk().threads[3].chunk.line, on_disk().threads[3].messages[1].text }, { 3, 1, 'Why a table?' }, 'on line 1')
  R.eq(actions.start(r, nil, 'In general?').chunk, nil, 'on no line')
  local n = actions.new_review 'Caching'
  R.eq({ n.id, review.read 'caching' ~= nil }, { 'caching', true }, 'written')
end)

R.test('actions.set_review_status: a review closed and opened again', function()
  local r = written()
  actions.set_review_status(r, 'closed')
  R.eq(on_disk().status, 'closed', 'closed')
  actions.set_review_status(r, 'open')
  R.eq(on_disk().status, 'open', 'open')
end)

R.test('actions.accept_thread: every chunk in it, its steps too; again takes them all back', function()
  local r = written()
  local t = r.threads[1]
  local function states()
    return { chunk.accepted(r, t, t.chunk), chunk.accepted(r, t, thread.step(t, 1).chunk) }
  end
  chunk.accept(r, t, t.chunk, true)
  R.eq(actions.accept_thread(r, t), true, 'one was not: all accepted')
  R.eq(states(), { true, true }, 'both')
  R.eq(actions.accept_thread(r, t), false, 'all were: all taken back')
  R.eq(states(), { false, false }, 'neither')
  R.eq(actions.accept_thread(r, r.threads[2]), nil, 'a thread on no line has none')
end)

R.test("actions.accept_part: a thread's line, every chunk; in a step, its chunk; else the thread's own", function()
  local r = written()
  local t = r.threads[1]
  local x = thread.tours(t)[1]
  local s = thread.step(t, 1)
  R.eq(actions.accept_part(r, { kind = 'line', first = 0, last = 0, thread = t, tour = x, step = s }), true, 'in the step')
  R.eq({ chunk.accepted(r, t, s.chunk), chunk.accepted(r, t, t.chunk) }, { true, false }, "the step's only")
  R.eq(actions.accept_part(r, { kind = 'message', first = 0, last = 0, thread = t, message = 1 }), true, 'in the thread')
  R.eq(chunk.accepted(r, t, t.chunk), true, "the thread's own")
  R.eq(actions.accept_part(r, { kind = 'step', first = 0, last = 0, thread = t, tour = x, step = thread.step(t, 2) }), nil, 'a step on no line: nothing')
  R.eq(actions.accept_part(r, { kind = 'thread', first = 0, last = 0, thread = t }), false, 'the thread: all were, all back')
end)

R.test("actions.run: a terminal at the repository's root, the check's line typed in and not run", function()
  local root = (function()
    written()
    return vim.fn.getcwd()
  end)()
  actions.run { text = 'Says hello.', run = 'echo checked-$((40+2))' }
  R.eq(vim.bo.buftype, 'terminal', 'a terminal')
  local function said()
    return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  end
  vim.wait(2000, function()
    return said():find('checked-$((40+2))', 1, true) ~= nil
  end)
  R.ok(said():find('checked-$((40+2))', 1, true), 'typed in: ' .. said())
  R.ok(not said():find('checked-42', 1, true), 'not run')
  R.eq(vim.fn.getcwd(), root, "the editor's directory is left alone")
  vim.cmd 'stopinsert'
  vim.cmd 'bwipe!'
end)
