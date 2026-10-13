-- Every screen thread.nvim draws, as text: each window (a float's size,
-- title and footer; the buffer's lines; its extmarks), then the screen
-- itself. Compared with tests/screens/<name>.txt, so a change to what you
-- see fails. `make screens` checks; `UPDATE=1 make screens` writes them.

local H = require 'tests.helpers'

vim.o.columns, vim.o.lines = 120, 40
vim.o.signcolumn = 'yes:2'
H.mute()
H.freeze_time '2026-10-11T12:00:00'

----------------------------------------------------------------------
-- The fixture: a repository, work in progress, and a batch written out
----------------------------------------------------------------------

local root = H.world()
local screens = require('tests.capture').new(H.root .. '/tests/screens', root, function(bar)
  return bar:find('thread.legacy.walk', 1, true) and require('thread.legacy.walk').bar() or bar
end)
local capture = screens.shot

----------------------------------------------------------------------
-- The screens
----------------------------------------------------------------------

require('thread').setup {}
local store = require 'thread.legacy.store'
local render = require 'thread.legacy.render'
local home = require 'thread.legacy.home'
local page = require 'thread.legacy.page'
local walk = require 'thread.legacy.walk'
local rpage = require 'thread.legacy.review.screen'

vim.cmd.edit 'store.lua'
local code_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(code_win, { 3, 0 })
render.refresh()
capture 'code-bubbles'
render.toggle()
capture 'code-one-line'
render.toggle()

home.open()
capture 'home-threads'
H.press 'o'
capture 'home-threads-open'
H.press '2'
capture 'home-tours'
H.press '3'
capture 'home-review'
H.press 'o'
capture 'home-review-group'
H.press 'o'
H.press '4'
capture 'home-closed'
H.press '1'
H.press '?'
capture 'home-help'
H.press 'q'
home.close()

home.focus { thread = store.find(store.active(), 1) }
capture 'focus-float'
home.close()

page.open(5, 0)
capture 'page-overview'
page.close()
page.open(1, 1)
capture 'page-stage'
H.press 'M'
capture 'page-stage-outline'
H.press 'M'
page.close()
page.open(1, 4)
capture 'page-step-gone'
page.close()

vim.api.nvim_set_current_win(code_win)
walk.start(1, 2)
capture 'walk-step'
walk.stop()

require('thread.legacy.map').pin()
capture 'map-batch'
require('thread.legacy.map').close()

require('thread.legacy.menu').open()
capture 'menu'
H.press 'q'

rpage.open { owner = 6 }
capture 'review-groups'
H.press 'j'
H.press '<CR>'
capture 'review-group'
-- The cursor starts on the affected line: up to the hunk.
H.press 'k'
H.press 'o'
capture 'review-hunk-open'
H.press 'o'
H.press '<CR>'
capture 'review-walk-hunk'
walk.stop()
rpage.close()

vim.cmd.edit(root .. '/main.lua')
render.toggle_drawn(4)
capture 'code-changes-drawn'
render.toggle_drawn(4)

vim.o.columns = 70
home.open()
capture 'home-narrow'
home.close()
vim.o.columns = 120

-- Last, as they add threads: one on a removed line of the review's hunk,
-- and on the hunk, a change the agent made in answer.
local review = require 'thread.legacy.review'
local batch = store.active()
local hn = review.work(review.of(store.find(batch, 6))).index['h1:1']
vim.list_extend(batch.data.threads, {
  {
    id = 7,
    file = 'main.lua',
    line = 2,
    text = 'store.set({}, "a", 1)',
    side = 'old',
    review = 6,
    status = 'open',
    messages = { { from = 'you', round = 1, text = 'Why not keep 1? Callers read it.' } },
  },
  {
    id = 8,
    on = { thread = 6, step = hn, at = 'h1:1' },
    file = 'main.lua',
    line = 2,
    text = 'store.set({}, "a", 2)',
    status = 'open',
    messages = {
      { from = 'you', round = 1, text = 'Make it 2 here too.' },
      { from = 'agent', at = '2026-10-11T11:58:00', text = 'Done: it is 2.', changes = { { file = 'main.lua', line = 2, text = 'store.set({}, "a", 2)' } } },
    },
  },
})
store.save(batch)
rpage.open { owner = 6, n = hn }
capture 'review-hunk-talk'
rpage.close()
vim.cmd.edit(root .. '/main.lua')
review.show(6)
render.refresh()
vim.api.nvim_win_set_cursor(0, { 2, 0 })
render.cursor_moved()
capture 'code-removed-line-thread'
review.show(nil)

screens.finish 'screens'
