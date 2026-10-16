-- thread.store: reviews on disk, and what you have seen of them.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local file = require 'thread.store.file'

--- Every `User ThreadChanged` fired while `fn` runs, by the id it names.
---@param fn fun()
---@return string[]
local function fired(fn)
  local ids = {}
  local id = vim.api.nvim_create_autocmd('User', {
    pattern = 'ThreadChanged',
    callback = function(ev)
      ids[#ids + 1] = ev.data.id
    end,
  })
  fn()
  vim.api.nvim_del_autocmd(id)
  return ids
end

R.test('store.file: a review is written in the order its schema gives, and read back', function()
  H.reset()
  H.repo { ['a.lua'] = { 'x' } }
  local schema = { order = { 'title', 'threads' }, lists = { threads = true } }
  local ids = fired(function()
    file.write('one', { threads = {}, title = 'One', extra = 1 }, schema)
  end)
  R.eq(ids, { 'one' }, 'its write is told')
  R.eq(vim.fn.readfile(file.dir() .. '/one.json'), { '{', '  "title": "One",', '  "threads": [],', '  "extra": 1', '}' }, 'on disk')
  R.eq(file.read 'one', { title = 'One', threads = {}, extra = 1 }, 'read back')
  R.eq(file.ids(), { 'one' }, 'listed')
end)

R.test('store.file: the reviews stay out of git', function()
  H.reset()
  local root = H.repo { ['a.lua'] = { 'x' } }
  file.write('one', { title = 'One' }, { order = {}, lists = {} })
  R.eq(H.git(root, { 'status', '--porcelain' }), '', 'nothing untracked')
end)

R.test("store.file: the agent's write is told once it lands, and ours only once", function()
  H.reset()
  H.repo { ['a.lua'] = { 'x' } }
  -- The first write makes the folder, and watches it.
  file.write('ours', { title = 'Ours' }, { order = {}, lists = {} })
  local ids = {}
  local au = vim.api.nvim_create_autocmd('User', {
    pattern = 'ThreadChanged',
    callback = function(ev)
      ids[#ids + 1] = ev.data.id
    end,
  })
  file.write('ours', { title = 'Ours again' }, { order = {}, lists = {} })
  vim.fn.writefile({ '{"title": "Theirs"}' }, file.dir() .. '/theirs.json')
  vim.wait(2000, function()
    return #ids > 1
  end)
  H.settle(200)
  vim.api.nvim_del_autocmd(au)
  R.eq(ids, { 'ours', 'theirs' }, 'ours as it is written, theirs as it lands, each once')
end)

R.test('store.file: removing a review takes what you have seen of it too', function()
  H.reset()
  H.repo { ['a.lua'] = { 'x' } }
  file.write('gone', { title = 'Gone' }, { order = {}, lists = {} })
  file.write_seen('gone', { read = { ['1'] = 2 } })
  R.eq(
    fired(function()
      file.remove 'gone'
    end),
    { 'gone' },
    'told'
  )
  R.eq({ file.read 'gone', file.read_seen 'gone', file.ids() }, { nil, nil, {} }, 'both files gone')
end)

R.test('store.file: a new id comes from the title, and is no id there is', function()
  H.reset()
  H.repo { ['a.lua'] = { 'x' } }
  R.eq(file.new_id 'How auth works!', 'how-auth-works', 'a slug')
  file.write('how-auth-works', { title = 'x' }, { order = {}, lists = {} })
  R.eq(file.new_id 'How auth works', 'how-auth-works-2', 'not taken')
  R.eq(file.new_id '!!!', 'review', 'something, when the title has no letters')
  R.eq(file.new_id(string.rep('a', 39) .. ' b'), string.rep('a', 39), 'no - where it is cut')
end)

R.test('store.seen: what you have read, walked and accepted is kept for the next start, each review its own', function()
  H.reset()
  H.repo { ['a.lua'] = { 'x' } }
  local seen = require 'thread.store.seen'
  R.eq(
    fired(function()
      R.eq(seen.mark_read('r', 'note:12', 3), true, 'read')
      R.eq(seen.mark_read('r', 'note:12', 2), false, 'never back down')
      R.eq(seen.walk('r', 'step:7'), true, 'walked')
      R.eq(seen.walk('r', 'step:7'), false, 'once')
      R.eq(seen.accept('r', 'c1234', true), true, 'accepted')
      R.eq(seen.accept('r', 'c1234', true), false, 'once')
    end),
    { 'r', 'r', 'r' },
    'each change told'
  )
  R.eq(file.read_seen 'r', { read = { ['note:12'] = 3 }, walked = { ['step:7'] = true }, accepted = { c1234 = true } }, 'on disk, by name')
  package.loaded['thread.store.seen'] = nil
  local again = require 'thread.store.seen'
  package.loaded['thread.store.seen'] = seen
  R.eq({ again.read('r', 'note:12'), again.read('r', 'note:13') }, { 3, 0 }, 'read')
  R.eq({ again.walked('r', 'step:7'), again.walked('r', 'step:8') }, { true, false }, 'walked, by its name')
  R.eq({ again.accepted('r', 'c1234'), again.accepted('other', 'c1234') }, { true, false }, 'accepted, in its review')
  again.accept('r', 'c1234', false)
  R.eq(again.accepted('r', 'c1234'), false, 'taken back')
  local v = again.version()
  again.walk('r', 'step:8')
  R.ok(again.version() > v, 'what is drawn from it moves on')
end)

R.test('store.seen: a file that is not what it should be is read as nothing seen', function()
  H.reset()
  H.repo { ['a.lua'] = { 'x' } }
  file.write_seen('odd', { read = { 'not', 'a', 'map' }, walked = 'yes', accepted = { c1 = true } })
  local seen = require 'thread.store.seen'
  R.eq({ seen.read('odd', '1'), seen.walked('odd', 'step:1'), seen.accepted('odd', 'c1') }, { 0, false, true }, 'what is a map is kept')
end)

R.test('store.seen: the first time a review is heard, what is there is from before; then from now; told to no one', function()
  H.reset()
  H.repo { ['a.lua'] = { 'x' } }
  local seen = require 'thread.store.seen'
  R.eq(seen.heard('r', 'note:1:1'), nil, 'not heard')
  R.eq(
    fired(function()
      R.eq(seen.hear('r', {}, 'now', 'before'), true, 'heard once, with nothing in it')
      R.eq(seen.hear('r', { 'note:1:1' }, 'now', 'before'), true, 'a message')
      R.eq(seen.hear('r', { 'note:1:1', 'note:1:2' }, 'later', 'before'), true, 'and another')
      R.eq(seen.hear('r', { 'note:1:2' }, 'later still', 'before'), false, 'nothing new')
    end),
    {},
    'nothing to draw'
  )
  R.eq({ seen.heard('r', 'note:1:1'), seen.heard('r', 'note:1:2') }, { 'now', 'later' }, 'each when it showed up')
  seen.hear('s', { 'step:1:1' }, 'now', 'before')
  R.eq(seen.heard('s', 'step:1:1'), 'before', 'the first time: as its file was written')
  seen.forget 's'
  R.eq(seen.heard('s', 'step:1:1'), 'before', 'forgotten in memory, read again from its file')
end)

R.test('store.file: a wait begun before the editor moved to another repository tells nothing', function()
  H.reset()
  local a = H.repo { ['a.lua'] = { 'x' } }
  H.agent_writes('one', H.draft())
  file.watch()
  local ids = fired(function()
    -- The agent writes in a: the watcher waits for the write to settle.
    vim.fn.writefile(vim.fn.readfile(a .. '/.threads/one.json'), a .. '/.threads/one.json')
    vim.wait(20, function()
      return false
    end)
    -- The editor moves to b before the wait ends.
    H.repo { ['b.lua'] = { 'y' } }
    file.watch()
    vim.wait(300, function()
      return false
    end)
  end)
  R.eq(ids, {}, "nothing: not a's review gone from b")
end)
