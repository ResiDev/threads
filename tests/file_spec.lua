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

R.test('store.seen: what you have read, walked and accepted is kept for the next start', function()
  H.reset()
  H.repo { ['a.lua'] = { 'x' } }
  local seen = require 'thread.store.seen'
  R.eq(
    fired(function()
      R.eq(seen.mark_read('r', { '12' }, 3), true, 'read')
      R.eq(seen.mark_read('r', { '12' }, 2), false, 'never back down')
      R.eq(seen.walk('r', { '12/abc' }), true, 'walked')
      R.eq(seen.accept('r', '12', 'h1', true), true, 'accepted')
      R.eq(seen.accept('r', '12', 'h1', true), false, 'once')
    end),
    { 'r', 'r', 'r' },
    'each change told'
  )
  package.loaded['thread.store.seen'] = nil
  local again = require 'thread.store.seen'
  package.loaded['thread.store.seen'] = seen
  R.eq(again.read('r', { '12' }), 3, 'read')
  R.eq({ again.walked('r', { '12/abc' }), again.walked('r', { '13/abc' }) }, { true, false }, 'walked, by its name')
  R.eq({ again.accepted('r', '12', 'h1'), again.accepted('r', '13', 'h1') }, { true, false }, 'accepted, in its thread')
  again.accept('r', '12', 'h1', false)
  R.eq(again.accepted('r', '12', 'h1'), false, 'taken back')
end)

R.test('store.seen: a thing known by two names has the marks of either; join copies them to both', function()
  H.reset()
  H.repo { ['a.lua'] = { 'x' } }
  local seen = require 'thread.store.seen'
  seen.mark_read('r', { 'q', 't' }, 2)
  seen.walk('r', { 'q', 't' })
  R.eq({ seen.read('r', { 'q2', 't' }), seen.walked('r', { 'q2', 't' }) }, { 2, true }, 'by the name that holds')
  R.eq({ seen.read('r', { 'q2', 't2' }), seen.walked('r', { 'q2', 't2' }) }, { 0, false }, 'not when both went')
  R.eq(
    fired(function()
      R.eq(seen.join('r', { { 'q2', 't' } }), true, 'joined')
      R.eq(seen.join('r', { { 'q2', 't' } }), false, 'once')
    end),
    {},
    'nothing you see changed, so nothing told'
  )
  R.eq({ seen.read('r', { 'q2', 't2' }), seen.walked('r', { 'q2', 't2' }) }, { 2, true }, 'so the second change keeps them too')
  seen.hear('r', { { 'q:1', 't:1' } }, 'now', 'before')
  R.eq(seen.heard('r', { 'q2:1', 't:1' }), 'before', 'heard by either')
  seen.hear('r', { { 'q2:1', 't:1' } }, 'later', 'before')
  R.eq(seen.heard('r', { 'q2:1', 't2:1' }), 'before', 'and copied, not heard again')
end)

R.test('store.seen: the first time a review is heard, what is there is from before; then from now', function()
  H.reset()
  H.repo { ['a.lua'] = { 'x' } }
  local seen = require 'thread.store.seen'
  R.eq(seen.heard('r', { '1:1' }), nil, 'not heard')
  seen.hear('r', { { '1:1' } }, 'now', 'before')
  seen.hear('r', { { '1:1' }, { '1:2' } }, 'later', 'before')
  R.eq({ seen.heard('r', { '1:1' }), seen.heard('r', { '1:2' }) }, { 'before', 'later' }, 'each when it showed up')
end)
