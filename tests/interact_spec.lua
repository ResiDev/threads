-- Keys, pressed the way a person presses them, on the world the screens are
-- taken of: Home's history and tabs, its review tab, the focus float, a
-- change undone, the page's outline, the map, a bubble folded.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local function world()
  H.reset()
  local root = H.world()
  require('thread').ensure()
  require('thread.base.diff').invalidate()
  H.mute()
  return root
end

local function home()
  return require 'thread.legacy.home'
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
  local w = require('thread.legacy.walk').state()
  R.eq(w and w.owner, 1, 'walking its tour')
  require('thread.legacy.walk').stop()
end)

R.test('home: in the review tab, ⏎ opens the group on its screen, r asks about it', function()
  world()
  home().open { view = 'review' }
  H.settle()
  press 'o'
  press '<CR>'
  local rs = require('thread.legacy.review.screen').state()
  R.eq(rs and rs.k, 1, 'the group, on the review screen')
  require('thread.legacy.review.screen').close()
  home().open { view = 'review' }
  H.settle()
  press 'o'
  press 'r'
  R.eq(vim.bo.filetype, 'markdown', 'writing a thread on the group')
  press '<Esc>'
end)

R.test('home: in the review tab, j and k go from review to review, o into one and j and k through its groups', function()
  world()
  local store = require 'thread.legacy.store'
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
  require('thread.base.diff').invalidate()
  H.mute()
  local rs = require 'thread.legacy.review.screen'
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

R.test('home: c closes a review, in the review tab or on its screen; the closed tab has it', function()
  world()
  local store = require 'thread.legacy.store'
  home().open { view = 'review' }
  H.settle()
  R.eq(state().focus, 'v:6', 'on the review')
  press 'c'
  R.eq(store.status(store.find(store.active(), 6)), 'closed', 'c closes it')
  H.must_see('No review yet', 'and it leaves the review tab')
  press '4'
  R.ok(vim.tbl_contains(state().order, 6), 'the closed tab has it')
  state().focus = 6
  home().draw()
  press 'c'
  R.ok(store.status(store.find(store.active(), 6)) ~= 'closed', 'c there opens it again')
  home().close()
  require('thread.legacy.review.screen').open { owner = 6 }
  H.settle()
  press 'c'
  R.eq(store.status(store.find(store.active(), 6)), 'closed', 'c on its screen closes it too')
  R.ok(not require('thread.legacy.review.screen').is_open(), 'and goes back to Home')
  home().close()
end)

--- The review screen's lines, past its bottom too.
local function screen_lines()
  return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

local function row_of(t)
  for i, l in ipairs(screen_lines()) do
    if l:find(t, 1, true) then
      return i
    end
  end
end

R.test('review screen: o on a hunk lets you onto its lines; r on a removed one starts a thread there', function()
  world()
  local store, review = require 'thread.legacy.store', require 'thread.legacy.review'
  local rs = require 'thread.legacy.review.screen'
  local w = review.work(review.of(store.find(store.active(), 6)))
  rs.open { owner = 6, n = w.index['h1:1'] }
  H.settle()
  press 'o'
  local removed = row_of '- store.set({}, "a", 1)'
  vim.api.nvim_win_set_cursor(0, { removed, 12 })
  press 'r'
  H.type_in 'why 2? callers read 1'
  press '<C-s>'
  local batch = store.active()
  local c = batch.data.threads[#batch.data.threads]
  R.eq(
    { c.file, c.line, c.text, c.side, c.review },
    { 'main.lua', 2, 'store.set({}, "a", 1)', 'old', 6 },
    'on the removed line: quoted as it was, its number in the old side'
  )
  R.ok(screen_lines()[removed + 1]:find('#' .. c.id .. ' · waiting', 1, true), 'drawn under its line')
  R.ok(row_of 'why 2? callers read 1', 'what you said')
  -- On the thread: r replies in it.
  vim.api.nvim_win_set_cursor(0, { removed + 1, 14 })
  press 'r'
  H.type_in 'and the docs?'
  press '<C-s>'
  R.eq(#store.find(store.active(), c.id).messages, 2, 'r on it replies in it')
  rs.close()
end)

R.test('review screen: under a reply, the places its agent changed, ⏎ goes there; c closes the thread', function()
  world()
  local store, review = require 'thread.legacy.store', require 'thread.legacy.review'
  local batch = store.active()
  local n = review.work(review.of(store.find(batch, 6))).index['h1:1']
  table.insert(batch.data.threads, {
    id = 7,
    on = { thread = 6, step = n, at = 'h1:1' },
    file = 'main.lua',
    line = 2,
    text = 'store.set({}, "a", 2)',
    status = 'open',
    messages = {
      { from = 'you', round = 1, text = 'make it 2' },
      { from = 'agent', text = 'Done: it is 2.', changes = { { file = 'main.lua', line = 2, text = 'store.set({}, "a", 2)' } } },
    },
  })
  store.save(batch)
  local rs = require 'thread.legacy.review.screen'
  rs.open { owner = 6, n = n }
  H.settle()
  R.ok(row_of '◆ changed in answer to you · look again', 'the hunk says the agent changed it')
  local at = row_of 'changed  main.lua:2'
  R.ok(at and at > row_of 'Done: it is 2.', 'under the reply, the place it changed')
  R.ok(not screen_lines()[at + 1]:find('store.set', 1, true), 'a place, not a diff')
  press 'c'
  R.eq(store.status(store.find(store.active(), 7)), 'closed', 'c closes the thread on the hunk')
  local rule = row_of 'your thread here'
  R.ok(screen_lines()[rule + 1]:find('2 messages · Done: it is 2.', 1, true), 'folded to a line')
  R.ok(not row_of 'changed  main.lua:2', 'what was said, folded away')
  R.ok(not row_of '◆ changed in answer', 'nothing left to look at')
  press 'o'
  R.ok(row_of 'changed  main.lua:2', 'o: all of it again')
  press 'o'
  press 'c'
  R.ok(store.status(store.find(store.active(), 7)) ~= 'closed', 'c again opens it')
  -- Let in, ⏎ on the place: there, in the code.
  press 'o'
  vim.api.nvim_win_set_cursor(0, { row_of 'changed  main.lua:2', 20 })
  press '<CR>'
  R.ok(not rs.is_open(), 'out of the review')
  R.eq({ vim.fn.expand '%:t', vim.fn.line '.' }, { 'main.lua', 2 }, 'on the line it changed')
end)

R.test('review: in the code, a thread on a removed line hangs where it was, the line marked', function()
  local root = world()
  local store = require 'thread.legacy.store'
  local batch = store.active()
  table.insert(batch.data.threads, {
    id = 7,
    file = 'main.lua',
    line = 2,
    text = 'store.set({}, "a", 1)',
    side = 'old',
    review = 6,
    status = 'open',
    messages = { { from = 'you', round = 1, text = 'why 2?' } },
  })
  store.save(batch)
  vim.cmd.edit(root .. '/main.lua')
  local buf = vim.api.nvim_get_current_buf()
  require('thread.legacy.review').show(6)
  local render = require 'thread.legacy.render'
  render.refresh()
  local placed
  for _, p in ipairs(require('thread.legacy.render.place').placed[buf]) do
    if p.thread.id == 7 then
      placed = p
    end
  end
  R.eq(placed and placed.line, 2, 'above the line that replaced it')
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  render.cursor_moved()
  H.must_see('on the removed line − store.set({}, "a", 1)', 'its bubble quotes the line')
  local marked = false
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, render.ns, 0, -1, { details = true })) do
    for _, l in ipairs(m[4].virt_lines or {}) do
      if l[1][1] == 'store.set({}, "a", 1)' and l[2] and l[2][1]:match ' 7$' then
        marked = true
      end
    end
  end
  R.ok(marked, 'the removed line, drawn above, says which thread is on it')
  render.follow(buf)
  local c = store.find(store.active(), 7)
  R.eq({ c.line, c.text }, { 2, 'store.set({}, "a", 1)' }, 'a save leaves its quote alone')
  require('thread.legacy.review').show(nil)
end)

R.test('home: a closed tour leaves the tours tab for the closed one', function()
  world()
  local store = require 'thread.legacy.store'
  home().open { view = 'tours' }
  H.settle()
  local focus = state().focus
  local title = store.title(store.find(store.active(), focus))
  press 'c'
  R.eq(store.status(store.find(store.active(), focus)), 'closed', 'c closes the tour')
  R.ok(not vim.tbl_contains(state().order, focus), 'it is not in the tours tab')
  press '4'
  R.ok(vim.tbl_contains(state().order, focus), 'the closed tab has it: ' .. title)
  home().close()
end)

R.test('review: one the code has left behind says it is out of date', function()
  local root = world()
  local store, review = require 'thread.legacy.store', require 'thread.legacy.review'
  local w = review.work(review.of(store.find(store.active(), 6)))
  R.eq(review.health(w).stale, false, 'as written, it holds')
  -- Its change committed: the uncommitted diff it reviews no longer has it.
  H.git(root, { 'add', '-A' })
  H.git(root, { 'commit', '-qm', 'the value' })
  require('thread.base.diff').invalidate()
  w = review.work(review.of(store.find(store.active(), 6)))
  local h = review.health(w)
  R.eq({ h.gone, h.named, h.stale }, { 1, 1, true }, 'its one hunk is gone')
  R.eq(review.moved(h), '1/1 hunks gone', 'said short')
  home().open { view = 'review' }
  H.settle()
  H.must_see('OUT OF DATE', 'Home says so on its row')
  H.must_see('The code has moved on since it was written', 'and why, when it is focused')
  home().close()
end)

R.test('home: d picks the diff the batch asks to review', function()
  world()
  local select = vim.ui.select
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.ui.select = function(items, _, on)
    on(items[2])
  end
  home().open { view = 'review' }
  H.settle()
  press 'd'
  vim.ui.select = select
  R.eq(require('thread.legacy.store').active().data.diff, { of = 'staged' }, 'staged')
  home().close()
end)

R.test('focused from the code: l and h go to the threads either side, tab to the next one on the line', function()
  world()
  local store = require 'thread.legacy.store'
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
  -- The old line, as often as Home shows it: the thread's code has it once.
  local function olds()
    local n = 0
    for _, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
      n = n + (l:find('store.set({}, "a", 1)', 1, true) and 1 or 0)
    end
    return n
  end
  local before = olds()
  press 'u'
  R.eq(vim.fn.readfile(root .. '/main.lua')[2], 'store.set({}, "a", 2)', 'once only says what it will do')
  R.eq(olds(), before + 1, 'and shows under the place what it would put back')
  press 'u'
  R.eq(vim.fn.readfile(root .. '/main.lua')[2], 'store.set({}, "a", 1)', 'twice undoes it')
  home().close()
end)

R.test('page: ⏎ on a stop in the outline walks to it', function()
  world()
  local page = require 'thread.legacy.page'
  page.open(1, 0)
  for i, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if l:find('the cache is thrown away', 1, true) then
      vim.api.nvim_win_set_cursor(0, { i, 0 })
    end
  end
  press '<CR>'
  local w = require('thread.legacy.walk').state()
  R.eq(w and { w.owner, w.n }, { 1, 2 }, 'walking, on that stop')
  require('thread.legacy.walk').stop()
end)

R.test('map: a letter jumps to its thread', function()
  world()
  vim.cmd.edit 'store.lua'
  require('thread.legacy.map').pin()
  H.settle()
  press 'a'
  R.eq(vim.fs.basename(vim.api.nvim_buf_get_name(0)), 'main.lua', 'the first thread on a line: main.lua')
  require('thread.legacy.map').close()
end)

R.test('code: Tab on a thread folds its bubble to a line and back', function()
  world()
  vim.cmd.edit 'store.lua'
  local render = require 'thread.legacy.render'
  render.refresh()
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  require('thread.legacy.render').cursor_moved()
  local store = require 'thread.legacy.store'
  local c = store.find(store.active(), 1)
  R.ok(render.level(store.active(), c) > 0, 'open')
  press '<Tab>'
  R.eq(render.level(store.active(), c), 0, 'one line')
  press '<Tab>'
  R.ok(render.level(store.active(), c) > 0, 'whole again')
end)
