-- Drawing in the code: bubbles, notes, changes.

local R = require 'tests.runner'
local H = require 'tests.helpers'

R.test('changes: a hunk two changes overlap is drawn once', function()
  H.reset()
  local root = H.repo { ['a.lua'] = { 'one', 'two', 'three', 'four' } }
  require('thread').ensure()
  local store, render = require 'thread.store', require 'thread.render'
  local batch = store.active(true)
  local t = store.add(batch, { file = 'a.lua', line = 2, text = 'two' }, 'change these')
  vim.fn.writefile({ 'one', 'TWO', 'THREE', 'four' }, root .. '/a.lua')
  batch = store.active()
  t = store.find(batch, t.id)
  t.messages[#t.messages + 1] = {
    from = 'agent',
    text = 'done',
    changes = { { file = 'a.lua', line = 2, text = 'TWO' }, { file = 'a.lua', line = 3, text = 'THREE' } },
  }
  store.save(batch)
  vim.cmd.edit(root .. '/a.lua')
  render.toggle_drawn(t.id)
  local drawn = 0
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, render.ns, 0, -1, { details = true })) do
    for _, vl in ipairs(m[4].virt_lines or {}) do
      if (vl[1] and vl[1][1] or ''):find '^two' then
        drawn = drawn + 1
      end
    end
  end
  render.toggle_drawn(t.id)
  R.eq(drawn, 1, 'the removed "two" drawn once')
end)
