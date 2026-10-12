-- Keys, pressed the way a person presses them, on the world the screens are
-- taken of: Home's history and tabs, its review tab, the focus float, a
-- change undone, the page's outline, the map, a bubble folded.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local function world()
  H.reset()
  local root = H.world()
  require('thread').ensure()
  require('thread.review.diff').invalidate()
  vim.notify = function() end
  return root
end

local function home()
  return require 'thread.home'
end

local function state()
  return home()._state()
end

local function press(keys)
  H.press(keys)
  H.settle()
end

R.test('home: h and l show less or more of the history', function()
  world()
  home().open()
  H.settle()
  R.eq(state().focus, 1, 'on the answered thread')
  H.must_see('1 earlier message', 'its last message only')
  press 'l'
  R.ok(not H.on_screen '1 earlier message', 'l: both messages')
  H.must_see('How does get work?', 'the question too')
  press 'h'
  H.must_see('1 earlier message', 'h: the last one again')
  home().close()
end)

R.test('home: H and L go to the tab on the left or right', function()
  world()
  home().open()
  H.settle()
  press 'L'
  R.eq(state().tab, 2, 'L: the tours')
  press 'L'
  R.eq(state().tab, 3, 'L: the review')
  press 'H'
  press 'H'
  press 'H'
  R.eq(state().tab, 4, 'H: round the start to the closed ones')
  home().close()
end)

R.test('home: tab and S-tab go through the tabs, g through the groupings', function()
  world()
  home().open()
  H.settle()
  local tab = function()
    local S = state()
    return S.tab or S.filter
  end
  press '<Tab>'
  R.eq(tab(), 2, 'the tours')
  H.must_see('answers that walk you through it', 'the tours tab')
  press '<S-Tab>'
  press '<S-Tab>'
  R.eq(tab(), 4, 'round the end to the closed ones')
  press '1'
  local group = state().group
  press 'g'
  R.eq(state().group, group % 3 + 1, 'the next grouping')
  home().close()
end)

R.test('home: J walks the tour the focused thread leads to', function()
  world()
  home().open()
  H.settle()
  press 'J'
  local w = require('thread.walk').state()
  R.eq(w and w.owner, 1, 'walking its tour')
  require('thread.walk').stop()
end)

R.test('home: in the review tab, ⏎ opens the group on its screen, r asks about it', function()
  world()
  home().open { view = 'review' }
  H.settle()
  press 'o'
  press '<CR>'
  local rs = require('thread.review.screen').state()
  R.eq(rs and rs.k, 1, 'the group, on the review screen')
  require('thread.review.screen').close()
  home().open { view = 'review' }
  H.settle()
  press 'o'
  press 'r'
  R.eq(vim.bo.filetype, 'markdown', 'writing a thread on the group')
  press '<Esc>'
end)

R.test('home: in the review tab, j and k go from review to review, o into one and j and k through its groups', function()
  world()
  local store = require 'thread.store'
  local batch = store.active()
  local second = vim.deepcopy(store.find(batch, 6))
  second.id, second.title = 7, 'Review: the value again'
  table.insert(batch.data.threads, second)
  store.save(batch)
  home().open { view = 'review' }
  H.settle()
  R.eq(state().focus, 'v:6', 'on the first review')
  H.must_see('the value is 2 now', 'its groups under it')
  press 'j'
  R.eq(state().focus, 'v:7', 'j: the next review, not a group')
  press 'k'
  R.eq(state().focus, 'v:6', 'k: back')
  press 'o'
  R.eq(state().focus, 'g:6:1', 'o: into its first group')
  press 'j'
  R.eq(state().focus, 'g:6:4', 'j: its next group, what nothing explains')
  press 'j'
  R.eq(state().focus, 'g:6:4', 'and no further: the next review is not one of them')
  press 'o'
  R.eq(state().focus, 'v:6', 'o again: back on the review')
  press 'o'
  press '<Esc>'
  R.eq(state().focus, 'v:6', 'Esc comes back out too')
  R.ok(home().is_open(), 'and leaves Home open')
  home().close()
end)

R.test('review screen: affected code shows a few lines of its function, o all of it', function()
  H.reset()
  local long = { 'local M = {}', '', 'function M.long(x)' }
  for i = 1, 20 do
    long[#long + 1] = '  local v' .. i .. ' = x + ' .. i
  end
  vim.list_extend(long, { '  return x', 'end', '', 'return M' })
  local root = H.repo { ['long.lua'] = long, ['main.lua'] = { 'return 1' } }
  vim.fn.writefile({ 'return 2' }, root .. '/main.lua')
  H.batch {
    {
      id = 1,
      title = 'Review: two',
      status = 'open',
      messages = {
        {
          from = 'agent',
          text = 'One change.',
          review = {
            diff = { of = 'uncommitted' },
            groups = {
              {
                title = 'two now',
                kind = 'fix',
                risk = 'low',
                body = 'b',
                hunks = { { file = 'main.lua', text = 'return 2', line = 1 } },
                affected = { { file = 'long.lua', text = '  local v2 = x + 2', line = 5, note = 'reads it' } },
              },
            },
          },
        },
      },
    },
  }
  require('thread.review.diff').invalidate()
  vim.notify = function() end
  local rs = require 'thread.review.screen'
  rs.open { owner = 1, n = 1 }
  H.settle()
  -- What the screen holds, past its bottom too.
  local function shows(t)
    return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'):find(t, 1, true) ~= nil
  end
  local body = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local said
  for i, l in ipairs(body) do
    if l:find('reads it', 1, true) then
      said = i
    end
  end
  R.ok(said, 'its note')
  R.ok(body[said + 1]:find('long.lua:5 · in function M.long(x)', 1, true), 'under it, where it is and the function it is in')
  R.ok(shows 'local v2 = x + 2', 'its line')
  R.ok(not shows 'local v15 = x + 15', 'a few lines only')
  R.ok(shows '⋯ 17 more lines of its function', 'and how much more there is')
  for _ = 1, 5 do
    press 'j'
  end
  press 'o'
  R.ok(shows 'local v15 = x + 15', 'o: the whole function')
  R.ok(not shows 'more lines of its function', 'nothing more to show')
  press 'o'
  R.ok(not shows 'local v15 = x + 15', 'o again: a few lines again')
  rs.close()
end)

R.test('home: d picks the diff the batch asks to review', function()
  world()
  local select = vim.ui.select
  vim.ui.select = function(items, _, on)
    on(items[2])
  end
  home().open { view = 'review' }
  H.settle()
  press 'd'
  vim.ui.select = select
  R.eq(require('thread.store').active().data.diff, { of = 'staged' }, 'staged')
  home().close()
end)

R.test('focused from the code: l and h go to the threads either side, tab to the next one on the line', function()
  world()
  local store = require 'thread.store'
  local one = store.find(store.active(), 1)
  home().focus { thread = one, comment = one }
  H.settle()
  local was = state().single
  press 'l'
  R.ok(state().single ~= was, 'l: another thread')
  R.ok(state().strip and vim.api.nvim_win_is_valid(state().strip.win), 'the strip of threads under it')
  press 'h'
  R.eq(state().single, was, 'h: back')
  home().close()
  home().focus { thread = one, comment = one, others = { 1, 3 } }
  H.settle()
  press '<Tab>'
  R.eq(state().single, 3, 'tab: the next thread on that line')
  home().close()
end)

R.test('home: u twice on a change puts back what it replaced', function()
  local root = world()
  home().open()
  H.settle()
  press '4'
  press 'o'
  local S = state()
  for _ = 1, 10 do
    local it = S.items[S.inside.item]
    if it and it.kind == 'change' then
      break
    end
    press 'j'
  end
  R.eq(S.items[S.inside.item].kind, 'change', 'on the change')
  press 'u'
  R.eq(vim.fn.readfile(root .. '/main.lua')[2], 'store.set({}, "a", 2)', 'once only says what it will do')
  press 'u'
  R.eq(vim.fn.readfile(root .. '/main.lua')[2], 'store.set({}, "a", 1)', 'twice undoes it')
  home().close()
end)

R.test('page: ⏎ on a stop in the outline walks to it', function()
  world()
  local page = require 'thread.page'
  page.open(1, 0)
  for i, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if l:find('the cache is thrown away', 1, true) then
      vim.api.nvim_win_set_cursor(0, { i, 0 })
    end
  end
  press '<CR>'
  local w = require('thread.walk').state()
  R.eq(w and { w.owner, w.n }, { 1, 2 }, 'walking, on that stop')
  require('thread.walk').stop()
end)

R.test('map: a letter jumps to its thread', function()
  world()
  vim.cmd.edit 'store.lua'
  require('thread.map').pin()
  H.settle()
  press 'a'
  R.eq(vim.fs.basename(vim.api.nvim_buf_get_name(0)), 'main.lua', 'the first thread on a line: main.lua')
  require('thread.map').close()
end)

R.test('code: Tab on a thread folds its bubble to a line and back', function()
  world()
  vim.cmd.edit 'store.lua'
  local render = require 'thread.render'
  render.refresh()
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  require('thread.render').cursor_moved()
  local store = require 'thread.store'
  local c = store.find(store.active(), 1)
  R.ok(render.level(store.active(), c) > 0, 'open')
  press '<Tab>'
  R.eq(render.level(store.active(), c), 0, 'one line')
  press '<Tab>'
  R.ok(render.level(store.active(), c) > 0, 'whole again')
end)
