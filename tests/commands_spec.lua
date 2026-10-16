-- Commands and keys come from one list: every key the config names runs a
-- command, and :Thread completes every command. And what a few of them
-- open: the float to write in, and the map.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local thread = require 'thread'

local COMMANDS = { 'home', 'ask', 'add', 'open', 'reply', 'close', 'walk', 'stop', 'map', 'toggle', 'hide', 'diff', 'next', 'prev', 'next_all', 'prev_all' }

--- H.world, set up as a person has it, in a window wide enough for the
--- map.
---@return thread.Review
local function world()
  H.reset()
  H.mute()
  vim.o.columns, vim.o.lines = 100, 50
  thread.setup {}
  H.world()
  return assert(require('thread.model.review').read 'screens')
end

--- The current buffer's text.
---@return string
local function shown()
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
end

R.test('every mapping in the config runs the command named the same, and is set', function()
  thread.setup {}
  local config = require 'thread.config'
  for name, lhs in pairs(config.defaults.mappings) do
    R.ok(thread.commands[name], name .. ' is a command')
    local m = vim.fn.maparg(lhs, 'n', false, true)
    R.ok(m.desc and m.desc:find '^Thread: ', string.format('%s (%s) is mapped: %s', name, lhs, vim.inspect(m.desc)))
  end
  R.ok(vim.fn.maparg(config.defaults.mappings.add, 'x', false, true).desc, 'add on a selection too')
end)

R.test(':Thread completes every command, and only those', function()
  thread.setup {}
  local done = vim.fn.getcompletion('Thread ', 'cmdline')
  table.sort(done)
  local want = vim.deepcopy(COMMANDS)
  table.sort(want)
  R.eq(done, want, 'completed')
  R.eq(vim.fn.getcompletion('Thread wa', 'cmdline'), { 'walk' }, 'by what is typed')
end)

R.test(':Thread with no such command says so, and does nothing', function()
  local said
  H.mute(function(msg, level)
    said = { msg, level }
  end)
  vim.cmd 'Thread batches'
  R.eq(said, { 'thread: no subcommand batches', vim.log.levels.ERROR }, 'said')
end)

R.test(':Thread ask opens the float for a question; :Thread add on lines, for a note on them', function()
  world()
  vim.cmd 'Thread ask'
  local t = vim.api.nvim_win_get_config(0).title
  R.eq(t and t[1] and vim.trim(t[1][1]), 'A question, on no line', 'a question')
  H.press '<Esc><Esc>'
  vim.cmd 'edit store.lua'
  vim.cmd '8,10Thread add'
  t = vim.api.nvim_win_get_config(0).title
  R.eq(t and t[1] and vim.trim(t[1][1]), 'A note on store.lua:8', 'a note on lines 8 to 10')
  H.press '<Esc><Esc>'
end)

R.test(':Thread map: every open note on a line, by file, in the open reviews; a letter goes to its line', function()
  world()
  H.review(
    'closed',
    H.draft {
      status = 'closed',
      notes = {
        {
          id = 1,
          kind = 'issue',
          issue = 'bug',
          severity = 'low',
          status = 'open',
          title = 'in a closed review',
          chunk = 'get',
          messages = { { from = 'agent', prose = { text = 'x' } } },
        },
      },
    }
  )
  vim.cmd 'Thread map'
  R.eq(vim.bo.filetype, 'thread-map', 'the map')
  local lines = shown()
  R.ok(lines:find('store.lua', 1, true) and lines:find('note 1', 1, true) and lines:find('set has no guard', 1, true), 'listed:\n' .. lines)
  R.ok(not lines:find('a is 2', 1, true), 'a settled note is not:\n' .. lines)
  R.ok(not lines:find('Who else reads', 1, true), 'nor one on no line:\n' .. lines)
  R.ok(not lines:find('in a closed review', 1, true), "nor a closed review's:\n" .. lines)
  H.press 'b'
  R.eq({ vim.fn.expand '%:t', vim.api.nvim_win_get_cursor(0)[1] }, { 'store.lua', 8 }, "b: the second, note 4's on line 8")
end)

R.test(":Thread map: walking, the tour's outline, the cursor on the step you are on; a letter walks to that step", function()
  local r = world()
  require('thread.go').open('walk', { review = r, tour = r.tours[1], step = r.tours[1].steps[2] })
  vim.cmd 'Thread map'
  local lines = shown()
  R.ok(lines:find('get reads the store', 1, true) and lines:find('a step whose lines went', 1, true), 'its steps:\n' .. lines)
  R.ok(not lines:find('set has no guard', 1, true) and not lines:find('set writes straight through', 1, true), 'no notes, no other tour:\n' .. lines)
  R.ok(vim.api.nvim_get_current_line():find('the cache is thrown away', 1, true), 'on step 2: ' .. vim.api.nvim_get_current_line())
  H.press 'a'
  R.eq(assert(require('thread.walk').state()).step, 1, 'a: step 1')
  require('thread.walk').stop()
end)
