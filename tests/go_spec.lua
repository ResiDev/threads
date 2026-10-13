-- thread.go: surfaces open each other by name, and a part of a drawing
-- opens where it belongs.

local R = require 'tests.runner'
local H = require 'tests.helpers'

-- Its own go, so the surfaces registered here are gone after it.
local real = package.loaded['thread.go']
package.loaded['thread.go'] = nil
local go = require 'thread.go'
package.loaded['thread.go'] = real
local thread = require 'thread.model.thread'

local CODE = { 'local M = {}', '', 'function M.get(t, k)', '  return t[k]', 'end', '', 'return M' }

--- Surfaces that only note what they were asked: `screen` opens the
--- screen's names, `code` the code, `walk` a walk, `compose` a float.
---@return { name: string, target: thread.Target }[] opened, string[] closed
local function surfaces()
  local opened, closed = {}, {}
  local function note(n)
    return function(target)
      opened[#opened + 1] = { name = n, target = target }
    end
  end
  for surface, names in pairs { screen = { 'home', 'review', 'thread' }, code = { 'code' }, walk = { 'walk' }, compose = { 'compose' } } do
    local open = {}
    for _, n in ipairs(names) do
      open[n] = note(n)
    end
    go.register(surface, {
      open = open,
      close = function()
        closed[#closed + 1] = surface
      end,
    })
  end
  return opened, closed
end

---@return thread.Review
local function written()
  H.reset()
  H.repo { ['a.lua'] = CODE }
  H.review('other', { threads = { { id = 4, title = 'Elsewhere', messages = { { from = 'agent', text = 'x' } } } } })
  return H.review('r', {
    threads = {
      {
        id = 1,
        title = 'get',
        chunk = { file = 'a.lua', line = 3, text = 'function M.get(t, k)' },
        messages = {
          {
            from = 'agent',
            text = 'See #1.2 and other#4.',
            tours = { { title = 'How', steps = { { id = 2, title = 'the read', chunk = { file = 'a.lua', line = 4, text = '  return t[k]' } } } } },
          },
        },
      },
    },
  })
end

R.test('go.open: the surface that registered the name opens it; the one asking makes way, not for a float over it', function()
  local opened, closed = surfaces()
  go.open('code', { chunk = { file = 'a.lua', line = 1, text = '' } }, 'screen')
  R.eq({ opened[1].name, closed }, { 'code', { 'screen' } }, 'the screen made way for the code')
  go.open('thread', {}, 'screen')
  R.eq(#closed, 1, 'the screen opening its own: nothing closed')
  go.open('compose', {}, 'screen')
  R.eq(#closed, 1, 'compose opens over the screen')
end)

R.test('go.press: a link to a step walks to it; to a thread in another review, the screen there', function()
  local opened = surfaces()
  local r = written()
  local t = r.threads[1]
  R.eq(go.press(r, { kind = 'link', first = 0, last = 0, link = { thread = 1, step = 2 } }, 0, 0), true, 'followed')
  R.eq({ opened[1].name, opened[1].target.step.id, opened[1].target.thread.id }, { 'walk', 2, 1 }, 'walked to #1.2')
  go.press(r, { kind = 'link', first = 0, last = 0, link = { review = 'other', thread = 4 } }, 0, 0)
  R.eq({ opened[2].name, opened[2].target.review.id, opened[2].target.thread.id }, { 'thread', 'other', 4 }, 'other#4')
  local ok, why = go.press(r, { kind = 'link', first = 0, last = 0, link = { thread = 9 } }, 0, 0)
  R.eq({ ok, why ~= nil, #opened }, { false, true, 2 }, 'a link to no thread: why, nothing opened')
  R.eq(thread.step(t, 2).id, 2, 'the step is there')
end)

R.test('go.press: code goes to the code, a gone line says so; a step walks; a thread and a review open in the screen', function()
  local opened = surfaces()
  local r = written()
  local t = r.threads[1]
  local x = thread.tours(t)[1]
  go.press(r, { kind = 'line', first = 0, last = 0, thread = t, chunk = { file = 'a.lua', line = 4, text = '  return t[k]' } }, 0, 0)
  R.eq({ opened[1].name, opened[1].target.chunk.line }, { 'code', 4 }, 'a line of code')
  local ok, why = go.press(r, { kind = 'note', first = 0, last = 0, thread = t, chunk = { file = 'a.lua', line = 2, text = 'gone()' } }, 0, 0)
  R.eq({ ok, why }, { false, 'a.lua no longer has that line' }, 'a note on a line gone')
  go.press(r, { kind = 'step', first = 0, last = 0, thread = t, tour = x, step = x.steps[1] }, 0, 0)
  go.press(r, { kind = 'tour', first = 0, last = 0, thread = t, tour = x }, 0, 0)
  go.press(r, { kind = 'thread', first = 0, last = 0, thread = t }, 0, 0)
  go.press(r, { kind = 'review', first = 0, last = 0, review = r }, 0, 0)
  R.eq(
    vim.tbl_map(function(o)
      return o.name
    end, opened),
    { 'code', 'walk', 'walk', 'thread', 'review' },
    'where each went'
  )
  R.eq(go.press(r, { kind = 'message', first = 0, last = 0, thread = t, message = 1 }, 0, 0), false, 'a message goes nowhere')
end)

R.test('go.press: a name in backticks goes to where the code defines it', function()
  local opened = surfaces()
  local r = written()
  H.git(vim.fn.getcwd(), { 'add', '.' })
  go.press(r, { kind = 'name', first = 0, last = 0, s = 0, e = 5, name = 'M.get', thread = r.threads[1] }, 0, 0)
  R.eq(
    { opened[1] and opened[1].name, opened[1] and opened[1].target.chunk.line, opened[1] and opened[1].target.chunk.text },
    { 'code', 3, 'function M.get(t, k)' },
    'M.get'
  )
end)

R.test('go.ask: what a surface answers, nil when none does', function()
  R.eq(go.ask 'nobody-answers', nil, 'none')
  go.answer('walking', function(x)
    return 'on ' .. x
  end)
  R.eq(go.ask('walking', 3), 'on 3', 'answered')
end)
