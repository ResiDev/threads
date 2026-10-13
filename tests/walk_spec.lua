-- thread.walk and thread.map: a tour walked step by step with the keys a
-- person presses, and the map jumped from.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local code = require 'thread.code'
local config = require 'thread.config'
local go = require 'thread.go'
local map = require 'thread.map'
local review = require 'thread.model.review'
local screen = require 'thread.screen'
local step = require 'thread.model.step'
local thread = require 'thread.model.thread'
local walk = require 'thread.walk'
require 'thread.compose'

local CODE = { 'local M = {}', '', 'function M.get(t, k)', '  return t[k]', 'end', '', 'function M.set(t, k, v)', '  t[k] = v', 'end', '', 'return M' }

--- `alpha`, thread 1: a tour of three steps, on line 4, on no line, on
--- line 8; and a second tour of one step. `beta`: a thread on line 7.
local function written()
  H.reset()
  H.mute()
  vim.o.columns, vim.o.lines = 100, 50
  config.setup { rebuild = true }
  H.repo { ['a.lua'] = CODE }
  H.review('beta', {
    title = 'Beta',
    threads = {
      {
        id = 1,
        title = 'Other review',
        chunk = { file = 'a.lua', line = 7, text = 'function M.set(t, k, v)' },
        messages = { { from = 'agent', text = 'b' } },
      },
    },
  })
  H.review('alpha', {
    title = 'Alpha',
    threads = {
      {
        id = 1,
        title = 'How it reads',
        chunk = { file = 'a.lua', line = 3, text = 'function M.get(t, k)' },
        messages = {
          {
            from = 'agent',
            text = 'A tour.',
            tours = {
              {
                title = 'The read',
                steps = {
                  { id = 1, title = 'the index', text = 'One index.', chunk = { file = 'a.lua', line = 4, text = '  return t[k]' } },
                  { id = 2, title = 'no cache', text = 'Nothing is kept anywhere.' },
                  { id = 3, title = 'the write', text = 'Straight through.', chunk = { file = 'a.lua', line = 8, text = '  t[k] = v' } },
                },
              },
              {
                title = 'Elsewhere',
                steps = { { id = 4, title = 'the module', text = 'Returned.', chunk = { file = 'a.lua', line = 11, text = 'return M' } } },
              },
            },
          },
        },
      },
    },
  })
  code.reset()
  code.setup()
  vim.cmd.edit 'a.lua'
  code.refresh()
end

---@return string
local function drawn()
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, code.ns, 0, -1, { details = true })) do
    for _, vl in ipairs(m[4].virt_lines or {}) do
      out[#out + 1] = table.concat(vim.tbl_map(function(c)
        return c[1]
      end, vl))
    end
  end
  return table.concat(out, '\n')
end

---@return thread.Review, thread.Thread
local function alpha()
  local r = assert(review.read 'alpha')
  return r, r.threads[1]
end

R.test('walk: from the first step, its card whole above its line, the winbar saying where; L and H go on and back', function()
  written()
  local r, t = alpha()
  go.open('walk', { review = r, thread = t })
  R.eq(vim.api.nvim_win_get_cursor(0)[1], 4, 'on step 1’s line')
  R.ok(drawn():find('One index.', 1, true), 'its card:\n' .. drawn())
  R.ok(walk.bar():find('step 1/3', 1, true) and walk.bar():find('the index', 1, true), 'the winbar: ' .. walk.bar())
  R.eq(step.walked(r, t, assert(thread.step(t, 1))), true, 'walked')
  H.press 'L'
  R.eq(assert(screen.state()).step, 2, 'step 2 is on no line: its page')
  R.ok(vim.bo.filetype == 'thread-screen', 'in the page')
  H.press 'L'
  R.eq({ screen.state(), vim.api.nvim_win_get_cursor(0)[1] }, { nil, 8 }, 'step 3: back in the code, on line 8')
  H.press 'H'
  H.press 'H'
  R.eq(vim.api.nvim_win_get_cursor(0)[1], 4, 'back to step 1')
  H.press 'q'
  R.eq({ walk.state(), vim.wo.winbar }, { nil, '' }, 'ended: the winbar as it was')
end)

R.test('walk: again, it picks up at the first step not walked', function()
  written()
  local r, t = alpha()
  step.walk(r, t, assert(thread.step(t, 1)))
  step.walk(r, t, assert(thread.step(t, 2)))
  go.open('walk', { review = r, thread = t })
  R.eq({ assert(walk.state()).step, vim.api.nvim_win_get_cursor(0)[1] }, { 3, 8 }, 'step 3')
  walk.stop()
end)

R.test('walk: its keys lie over yours and go back as they were; outside the walk, r is your own', function()
  written()
  vim.keymap.set('n', 'L', '<Cmd>let g:mine = 1<CR>')
  local r, t = alpha()
  go.open('walk', { review = r, thread = t })
  R.ok((vim.fn.maparg('L', 'n', false, true).desc or ''):find('Thread walk', 1, true), 'L is the walk’s')
  walk.stop()
  R.eq(vim.fn.maparg('L', 'n'), '<Cmd>let g:mine = 1<CR>', 'L is yours again')
  vim.keymap.del('n', 'L')
end)

R.test('walk: r replies in the step; K goes to its thread on the screen, and the walk ends', function()
  written()
  local r, t = alpha()
  go.open('walk', { review = r, thread = t })
  H.press 'r'
  H.type_in 'Why one index?'
  H.press '<C-s>'
  R.eq(assert(thread.step(alpha().threads[1], 1)).messages[1].text, 'Why one index?', 'in step 1')
  H.press 'K'
  R.eq({ walk.state(), assert(screen.state()).depth, assert(screen.state()).thread }, { nil, 'thread', 1 }, 'the thread')
  screen.close()
end)

R.test("walk: the other tours' steps stay signs, other reviews' threads fold to a line", function()
  written()
  local r, t = alpha()
  vim.api.nvim_win_set_cursor(0, { 7, 0 })
  code.cursor_moved()
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  code.cursor_moved()
  R.ok(drawn():find('│ ', 1, true) and drawn():find('Beta', 1, true), 'beta’s bubble, framed')
  go.open('walk', { review = r, thread = t })
  local d = drawn()
  R.ok(not d:find('Returned.', 1, true) and not d:find('the module', 1, true), 'the other tour’s step: a sign')
  R.ok(d:find('Other review', 1, true) and not d:find('Beta', 1, true), 'beta’s a line, no frame:\n' .. d)
  walk.stop()
end)

R.test('map: every open thread on a line, by file; a letter goes there', function()
  written()
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  map.open()
  local lines = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  R.ok(lines:find('a.lua', 1, true) and lines:find('How it reads', 1, true) and lines:find('Other review', 1, true), 'listed:\n' .. lines)
  H.press 'b'
  R.eq({ vim.bo.filetype, vim.api.nvim_win_get_cursor(0)[1] }, { 'lua', 7 }, 'b: the second, beta’s on line 7')
end)

R.test("map: walking, the tour's outline; a letter walks to that step", function()
  written()
  local r, t = alpha()
  go.open('walk', { review = r, thread = t })
  H.press 'M'
  local lines = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  R.ok(lines:find('the write', 1, true) and not lines:find('Other review', 1, true), 'the outline:\n' .. lines)
  H.press 'c'
  R.eq({ assert(walk.state()).step, vim.api.nvim_win_get_cursor(0)[1] }, { 3, 8 }, 'step 3')
  walk.stop()
end)

R.test('walk: a step at a rev is on its line in the working tree while it is there, else in the file at that rev', function()
  written()
  local root = vim.fn.getcwd()
  local base = vim.trim(vim.fn.system { 'git', '-C', root, 'rev-parse', 'HEAD' })
  local at_head = vim.deepcopy(CODE)
  at_head[4] = '  return rawget(t, k)'
  vim.fn.writefile(at_head, 'a.lua')
  H.git(root, { 'commit', '-qam', 'rawget' })
  local head = vim.trim(vim.fn.system { 'git', '-C', root, 'rev-parse', '--short', 'HEAD' })
  local now = vim.deepcopy(at_head)
  now[4] = '  return t[k] or nil'
  vim.fn.writefile(now, 'a.lua')
  vim.cmd 'edit!'
  H.review('pinned', {
    title = 'Pinned',
    diff = { base = base, head = head },
    threads = {
      {
        id = 1,
        title = 'At the head',
        messages = {
          {
            from = 'agent',
            text = 'A tour.',
            tours = {
              {
                title = 'T',
                steps = {
                  {
                    id = 1,
                    title = 'rawget, since changed',
                    text = 'GONE-SINCE.',
                    chunk = { file = 'a.lua', line = 4, rev = head, text = '  return rawget(t, k)' },
                  },
                  { id = 2, title = 'the write, still there', text = 'STILL-THERE.', chunk = { file = 'a.lua', line = 8, rev = head, text = '  t[k] = v' } },
                },
              },
            },
          },
        },
      },
    },
  })
  local r = assert(review.read 'pinned')
  go.open('walk', { review = r, thread = r.threads[1] })
  R.ok(vim.api.nvim_buf_get_name(0):find('///' .. head .. '/a.lua', 1, true), 'the file at the head: ' .. vim.api.nvim_buf_get_name(0))
  R.eq(vim.api.nvim_get_current_line(), '  return rawget(t, k)', 'on its line there')
  R.ok(drawn():find('GONE-SINCE.', 1, true), 'its card:\n' .. drawn())
  H.press 'L'
  R.eq({ vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t'), vim.api.nvim_get_current_line() }, { 'a.lua', '  t[k] = v' }, 'the working tree, on its line')
  R.ok(drawn():find('STILL-THERE.', 1, true), 'its card:\n' .. drawn())
  H.press 'q'
end)

R.test('map: past the letters, ⏎ on a row goes there', function()
  written()
  local lines = {}
  for i = 1, 30 do
    lines[i] = 'local v' .. i .. ' = ' .. i
  end
  vim.fn.writefile(lines, 'b.lua')
  local threads = {}
  for i = 1, 30 do
    threads[i] = { id = i, title = 'line ' .. i, chunk = { file = 'b.lua', line = i, text = lines[i] }, messages = { { from = 'agent', text = 'x' } } }
  end
  H.review('many', { title = 'Many', threads = threads })
  map.open()
  local rows = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local at
  for i, l in ipairs(rows) do
    at = l:find('line 30', 1, true) and i or at
  end
  vim.api.nvim_win_set_cursor(0, { assert(at, table.concat(rows, '\n')), 0 })
  H.press '<CR>'
  R.eq({ vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':t'), vim.api.nvim_win_get_cursor(0)[1] }, { 'b.lua', 30 }, 'the 30th')
end)

R.test("walk: Home opened during a walk is not the walk's: its keys there are yours", function()
  written()
  local r, t = alpha()
  go.open('walk', { review = r, thread = t })
  go.open('home', {})
  R.eq(vim.bo.filetype, 'thread-screen', 'Home')
  H.press 'M'
  R.ok(vim.bo.filetype ~= 'thread-map', 'no map over Home')
  map.close()
  walk.stop()
end)
