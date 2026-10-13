-- thread.code: every open review's threads and steps in the code, drawn
-- as virtual lines; what the keys on their lines do.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local code = require 'thread.code'
local config = require 'thread.config'
local review = require 'thread.model.review'
local screen = require 'thread.screen'
local thread = require 'thread.model.thread'
require 'thread.compose'

local CODE = { 'local M = {}', '', 'function M.get(t, k)', '  return t[k]', 'end', '', 'function M.set(t, k, v)', '  t[k] = v', 'end', '', 'return M' }

--- `alpha`: thread 1 on line 3, its tour's step on line 8; thread 2 on
--- line 4, closed. `beta`: thread 1 on line 7, where it is your move.
--- `gamma`, closed: thread 1 on line 1.
local function written()
  H.reset()
  H.mute()
  vim.o.columns, vim.o.lines = 100, 50
  config.setup { rebuild = true }
  H.repo { ['a.lua'] = CODE }
  H.review('gamma', {
    title = 'Gamma',
    status = 'closed',
    threads = {
      { id = 1, title = 'Closed review', chunk = { file = 'a.lua', line = 1, text = 'local M = {}' }, messages = { { from = 'agent', text = 'x' } } },
    },
  })
  H.review('beta', {
    title = 'Beta',
    threads = {
      {
        id = 1,
        title = 'Set writes through',
        chunk = { file = 'a.lua', line = 7, text = 'function M.set(t, k, v)' },
        messages = { { from = 'you', text = 'Does set cache?' }, { from = 'agent', text = 'No: it writes straight to the table.' } },
      },
    },
  })
  H.review('alpha', {
    title = 'Alpha',
    threads = {
      {
        id = 1,
        title = 'Get reads',
        chunk = { file = 'a.lua', line = 3, text = 'function M.get(t, k)' },
        messages = {
          {
            from = 'agent',
            text = 'It indexes the table.',
            notes = { { file = 'a.lua', line = 4, text = '  return t[k]', mark = 't[k]', note = 'one index' } },
            tours = {
              {
                title = 'Both',
                steps = { { id = 1, title = 'set is the other half', text = 'It writes.', chunk = { file = 'a.lua', line = 8, text = '  t[k] = v' } } },
              },
            },
          },
        },
      },
      {
        id = 2,
        title = 'Closed thread',
        status = 'fixed',
        chunk = { file = 'a.lua', line = 4, text = '  return t[k]' },
        messages = { { from = 'agent', text = 'y' } },
      },
    },
  })
  code.reset()
  code.setup()
  vim.cmd.edit 'a.lua'
  code.refresh()
end

--- Every virtual line drawn into the buffer, as text, with the line it
--- hangs above.
---@return string
local function drawn()
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, code.ns, 0, -1, { details = true })) do
    for _, vl in ipairs(m[4].virt_lines or {}) do
      out[#out + 1] = (m[2] + 1) .. ': ' .. table.concat(vim.tbl_map(function(c)
        return c[1]
      end, vl))
    end
  end
  return table.concat(out, '\n')
end

--- The sign on a line, and its colour.
---@param line integer
---@return string|nil, string|nil
local function sign(line)
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, code.ns, { line - 1, 0 }, { line - 1, -1 }, { details = true })) do
    if m[4].sign_text then
      return vim.trim(m[4].sign_text), m[4].sign_hl_group
    end
  end
end

---@param line integer
local function cursor(line)
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  code.cursor_moved()
end

R.test("code: every open review's threads, a bubble each with its review's name; a closed thread or review is not there", function()
  written()
  local d = drawn()
  R.ok(d:find('Alpha', 1, true) and d:find('Get reads', 1, true), 'alpha’s thread:\n' .. d)
  R.ok(d:find('Beta', 1, true) and d:find('Set writes through', 1, true), 'beta’s')
  R.ok(not d:find('Closed', 1, true), 'no closed thread, no closed review')
  R.eq({ (sign(3)), (sign(7)), (sign(1)) }, { '▎', '▎', nil }, 'a sign on each thread’s line')
  R.ok(d:find('3: ', 1, true) and d:find('7: ', 1, true), 'above lines 3 and 7')
end)

R.test('code: a step is its sign until the cursor is on it, then its line; tab its card', function()
  written()
  R.eq((sign(8)), '▸', 'its sign')
  R.ok(not drawn():find('set is the other half', 1, true), 'nothing else')
  cursor(8)
  local d = drawn()
  R.ok(d:find('set is the other half', 1, true) and not d:find('It writes.', 1, true), 'its line:\n' .. d)
  code.fold()
  R.ok(drawn():find('It writes.', 1, true), 'its card:\n' .. drawn())
end)

R.test('code: tab folds a bubble to its line; toggle every one, hide all but the signs', function()
  written()
  cursor(3)
  R.ok(drawn():find('It indexes the table.', 1, true), 'whole')
  code.fold()
  R.ok(not drawn():find('It indexes the table.', 1, true) and drawn():find('Get reads', 1, true), 'a line:\n' .. drawn())
  code.fold()
  R.ok(drawn():find('It indexes the table.', 1, true), 'whole again')
  code.toggle()
  R.ok(not drawn():find('No: it writes', 1, true), 'every one a line')
  code.toggle()
  code.hide()
  R.eq({ drawn(), (sign(3)) }, { '', '▎' }, 'only signs')
  code.hide()
end)

R.test('code: the thread you are on shows its notes; leaving it reads what its bubble showed', function()
  written()
  local r = assert(review.read 'beta')
  local c = thread.conversation(r.threads[1])
  R.eq(thread.unread(r, c), 1, 'new')
  cursor(3)
  local notes = vim.tbl_filter(function(m)
    return m[4].virt_text and m[4].virt_text_pos == 'eol'
  end, vim.api.nvim_buf_get_extmarks(0, code.ns, { 3, 0 }, { 3, -1 }, { details = true }))
  R.ok(#notes == 1 and notes[1][4].virt_text[2][1]:find('one index', 1, true), 'its note on line 4')
  cursor(7)
  R.eq(thread.unread(assert(review.read 'beta'), c), 1, 'not read while you are on it')
  cursor(1)
  R.eq(thread.unread(assert(review.read 'beta'), c), 0, 'read once you leave')
end)

R.test('code: ⏎ on a thread focuses it over the code, on a step opens its page', function()
  written()
  cursor(3)
  code.focus()
  local S = assert(screen.state())
  R.eq({ S.depth, S.review, S.thread, S.over ~= nil }, { 'thread', 'alpha', 1, true }, 'thread 1 in a float')
  screen.close()
  cursor(8)
  code.focus()
  R.eq({ assert(screen.state()).depth, assert(screen.state()).step }, { 'step', 1 }, 'its page')
  screen.close()
end)

R.test(']h goes to the next conversation that wants you, round the ends; ]H to any open one', function()
  written()
  cursor(1)
  code.next(1)
  R.eq(vim.api.nvim_win_get_cursor(0)[1], 3, 'alpha’s: the agent explaining, not read')
  code.next(1)
  R.eq(vim.api.nvim_win_get_cursor(0)[1], 7, 'beta’s: your move')
  code.next(1)
  R.eq(vim.api.nvim_win_get_cursor(0)[1], 7, 'alpha’s was read on the way: round to beta’s again')
  code.next(-1, true)
  R.eq(vim.api.nvim_win_get_cursor(0)[1], 3, 'any open one, back')
end)

R.test('code: a save quotes a moved thread as its line reads now; a step is left as the agent wrote it', function()
  written()
  vim.api.nvim_buf_set_lines(0, 0, 0, false, { '-- a header' })
  vim.api.nvim_buf_set_lines(0, 3, 4, false, { 'function M.get(tbl, k)' })
  vim.cmd 'silent write'
  H.settle()
  local t = assert(review.read 'alpha').threads[1]
  R.eq({ t.chunk.line, t.chunk.text }, { 4, 'function M.get(tbl, k)' }, 'requoted')
  R.eq(thread.step(t, 1).chunk.line, 8, 'the step as it was')
end)

R.test('code: a thread started on lines goes in the review picked', function()
  written()
  local select = vim.ui.select
  vim.ui.select = function(items, _, cb)
    cb(items[1], 1)
  end
  code.add(8, 9)
  H.type_in 'Why not rawset?'
  H.press '<C-s>'
  vim.ui.select = select
  local r = assert(review.read 'alpha')
  local t = r.threads[#r.threads]
  R.eq({ t.chunk.line, t.chunk.lines, t.chunk.text, t.messages[1].text }, { 8, 2, '  t[k] = v', 'Why not rawset?' }, 'on lines 8 and 9, in alpha, newest')
end)

R.test('code: a thread whose line is gone sits where it was, saying so', function()
  written()
  H.review('delta', {
    title = 'Delta',
    threads = { { id = 1, title = 'Gone', chunk = { file = 'a.lua', line = 10, text = 'xyzzy = plugh()' }, messages = { { from = 'agent', text = 'z' } } } },
  })
  code.refresh()
  R.eq((sign(10)), '!', 'marked')
  R.ok(drawn():find('its line is gone', 1, true) and drawn():find('xyzzy', 1, true), 'said, and what it read:\n' .. drawn())
end)

R.test("code: a review's diff drawn in on asking, its removed lines above where they went", function()
  written()
  vim.api.nvim_buf_set_lines(0, 3, 4, false, { '  return rawget(t, k)' })
  vim.cmd 'silent write'
  local raw = vim.json.decode(table.concat(vim.fn.readfile '.threads/alpha.json', '\n'))
  raw.diff = { of = 'uncommitted' }
  vim.fn.writefile({ vim.json.encode(raw) }, '.threads/alpha.json')
  require('thread.base.diff').invalidate()
  code.refresh()
  cursor(3)
  R.eq(code.diff_here(), true, 'drawn')
  R.ok(drawn():find('return t[k]', 1, true), 'the removed line:\n' .. drawn())
  R.eq(code.diff_here(), false, 'hidden again')
  R.ok(not drawn():find('return t[k]', 1, true), 'gone')
end)
