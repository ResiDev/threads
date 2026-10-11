-- Every screen thread.nvim draws, as text: each window (a float's size,
-- title and footer; the buffer's lines; its extmarks), then the screen
-- itself. Compared with tests/screens/<name>.txt, so a change to what you
-- see fails. `make screens` checks; `UPDATE=1 make screens` writes them.

local H = require 'tests.helpers'

local dir = H.root .. '/tests/screens'
local update = vim.env.UPDATE == '1'
local failures = {}
local diff = vim.text and vim.text.diff or vim.diff

vim.o.columns, vim.o.lines = 120, 40
vim.o.signcolumn = 'yes:2'
vim.notify = function() end
H.freeze_time '2026-10-11T12:00:00'

----------------------------------------------------------------------
-- The fixture: a repository, work in progress, and a batch written out
----------------------------------------------------------------------

local root = H.repo(H.fixture)
vim.fn.writefile({ '/.threads/' }, root .. '/.git/info/exclude')
local head = vim.trim(H.git(root, { 'rev-parse', 'HEAD' }))
-- What the review and thread 4's change read: a changed line, and a file
-- git does not track.
vim.fn.writefile({ 'local store = require "store"', 'store.set({}, "a", 2)' }, root .. '/main.lua')
vim.fn.writefile({ 'return 1' }, root .. '/extra.lua')

local data = {
  title = 'Screens',
  reply = 'inline',
  rounds = { { sent = '2026-10-11T11:00:00', snapshot = head } },
  threads = {
    {
      id = 1,
      title = 'How get works',
      file = 'store.lua',
      line = 3,
      text = 'function M.get(store, key)',
      status = 'open',
      messages = {
        { from = 'you', round = 1, text = 'How does get work?' },
        {
          from = 'agent',
          at = '2026-10-11T11:30:00',
          text = 'It reads the store. **One stage**, three steps. See #3.',
          verdict = 'how it works',
          diagram = {
            kind = 'flow',
            nodes = { { id = 'a', label = 'M.get', file = 'store.lua', text = 'function M.get(store, key)' }, { id = 'b', label = 'store' } },
            edges = { { from = 'a', to = 'b', label = 'reads' } },
          },
          walk = {
            { stage = 'Reading is a lookup', point = 'get never writes.', body = '```code\n{ "file": "store.lua", "text": "  return store[key]", "lines": 2 }\n```' },
            {
              file = 'store.lua',
              line = 4,
              text = '  local cache = {}',
              title = 'the cache is thrown away',
              body = 'A new table each call.',
              notes = { { line = 4, text = '  local cache = {}', note = 'new every call', mark = 'cache' } },
            },
            { file = 'store.lua', line = 9, text = '  store[key] = value', title = 'set writes straight through', body = 'No cache to update.' },
            { file = 'store.lua', line = 30, text = '  gone()', title = 'a step whose line went', body = 'It moved.' },
          },
        },
      },
    },
    {
      id = 2,
      on = { thread = 1, step = 2 },
      file = 'store.lua',
      line = 4,
      text = '  local cache = {}',
      status = 'open',
      messages = { { from = 'you', round = 1, text = 'Should the cache move to the module?' } },
    },
    {
      id = 3,
      title = 'Who else reads it · 誰が読む',
      status = 'open',
      messages = {
        { from = 'you', round = 1, text = 'What else reads the store?' },
        { from = 'agent', at = '2026-10-11T11:45:00', text = '`main.lua` does, once.' },
      },
    },
    {
      id = 4,
      file = 'main.lua',
      line = 1,
      text = 'local store = require "store"',
      status = 'closed',
      messages = { { from = 'you', round = 1, text = 'Rename it?' }, { from = 'agent', at = '2026-10-11T11:10:00', text = 'Done.', changes = { { file = 'main.lua', line = 2, text = 'store.set({}, "a", 2)' } } } },
    },
    {
      id = 5,
      title = 'Writing to the store',
      status = 'open',
      messages = { {
        from = 'agent',
        at = '2026-10-11T11:50:00',
        text = 'Where writes go.',
        walk = {
          { stage = 'Writes go straight in', point = 'set has no cache.', verdict = 'fine', body = 'Nothing to keep in step.' },
          { file = 'store.lua', line = 8, text = 'function M.set(store, key, value)', body = 'The whole of set.' },
        },
      } },
    },
    {
      id = 6,
      title = 'Review: the value',
      status = 'open',
      messages = { {
        from = 'agent',
        at = '2026-10-11T11:55:00',
        text = 'One change, and a new file.',
        review = {
          diff = { of = 'uncommitted' },
          groups = { {
            title = 'the value is 2 now',
            kind = 'fix',
            risk = 'high',
            risk_why = 'callers read it',
            body = 'It was 1.',
            hunks = { { file = 'main.lua', text = 'store.set({}, "a", 2)', line = 2, note = 'the new value' } },
            affected = { { file = 'store.lua', text = 'function M.set(store, key, value)', line = 8, note = 'what it calls' } },
          } },
        },
      } },
    },
  },
}
vim.fn.mkdir(root .. '/.threads', 'p')
vim.fn.writefile(vim.split(require('thread.json').encode(data), '\n'), root .. '/.threads/screens.json')
vim.fn.writefile({ 'screens' }, root .. '/.threads/active')
-- The batches menu says how long ago each file changed.
vim.uv.fs_utime(root .. '/.threads/screens.json', os.time() - 600, os.time() - 600)

----------------------------------------------------------------------
-- Writing a screen out
----------------------------------------------------------------------

local function hl_name(h)
  if type(h) == 'table' then
    return table.concat(vim.tbl_map(tostring, h), '+')
  end
  return h == nil and '' or tostring(h)
end

local function chunks(list)
  if type(list) ~= 'table' then
    return tostring(list)
  end
  local out = {}
  for _, c in ipairs(list) do
    out[#out + 1] = '[' .. tostring(c[1]) .. '|' .. hl_name(c[2]) .. ']'
  end
  return table.concat(out)
end

local function ns_name(id)
  for name, n in pairs(vim.api.nvim_get_namespaces()) do
    if n == id then
      return name
    end
  end
  return tostring(id)
end

local FIELDS = { 'hl_group', 'line_hl_group', 'number_hl_group', 'sign_text', 'sign_hl_group', 'virt_text_pos', 'virt_text_win_col', 'priority', 'hl_eol', 'virt_lines_above' }

local function mark_lines(m)
  local d = m[4]
  local parts = { ns_name(d.ns_id), m[2] .. ':' .. m[3] }
  if d.end_row then
    parts[#parts + 1] = 'to ' .. d.end_row .. ':' .. tostring(d.end_col)
  end
  for _, k in ipairs(FIELDS) do
    if d[k] ~= nil then
      parts[#parts + 1] = k .. '=' .. hl_name(d[k])
    end
  end
  if d.virt_text then
    parts[#parts + 1] = 'vt=' .. chunks(d.virt_text)
  end
  local out = { table.concat(parts, ' ') }
  for _, vl in ipairs(d.virt_lines or {}) do
    out[#out + 1] = '    vl ' .. chunks(vl)
  end
  return out
end

local function window(win)
  local c = vim.api.nvim_win_get_config(win)
  local buf = vim.api.nvim_win_get_buf(win)
  local out = {}
  if c.relative ~= '' then
    out[#out + 1] = string.format('== float %dx%d at %s,%s z%s', c.width, c.height, tostring(c.row), tostring(c.col), tostring(c.zindex))
    if c.title then
      out[#out + 1] = 'title ' .. chunks(c.title)
    end
    if c.footer then
      out[#out + 1] = 'footer ' .. chunks(c.footer)
    end
  else
    out[#out + 1] = string.format('== window %dx%d', vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win))
  end
  out[#out + 1] = 'buffer ' .. (vim.bo[buf].filetype ~= '' and vim.bo[buf].filetype or '-') .. ' ' .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':t')
  local bar = vim.wo[win].winbar
  if bar ~= '' then
    out[#out + 1] = 'winbar ' .. (bar:find('thread.walk', 1, true) and require('thread.walk').bar() or bar)
  end
  out[#out + 1] = 'cursor ' .. table.concat(vim.api.nvim_win_get_cursor(win), ':')
  for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    out[#out + 1] = string.format('%3d|%s', i, l)
  end
  -- Highlights sorted, so the order they were made in does not matter;
  -- marks that draw something in the order Neovim keeps them.
  local hls, drawn = {}, {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
    local d = m[4]
    if d.virt_text or d.virt_lines or d.sign_text then
      vim.list_extend(drawn, mark_lines(m))
    else
      hls[#hls + 1] = mark_lines(m)[1]
    end
  end
  table.sort(hls)
  vim.list_extend(out, hls)
  vim.list_extend(out, drawn)
  return out
end

local function order(a, b)
  local ca, cb = vim.api.nvim_win_get_config(a), vim.api.nvim_win_get_config(b)
  local fa, fb = ca.relative ~= '', cb.relative ~= ''
  if fa ~= fb then
    return not fa
  end
  if (ca.zindex or 0) ~= (cb.zindex or 0) then
    return (ca.zindex or 0) < (cb.zindex or 0)
  end
  local pa, pb = vim.api.nvim_win_get_position(a), vim.api.nvim_win_get_position(b)
  if pa[1] ~= pb[1] then
    return pa[1] < pb[1]
  end
  return pa[2] < pb[2]
end

local function capture(name)
  H.settle()
  local wins = vim.api.nvim_tabpage_list_wins(0)
  table.sort(wins, order)
  local out = {}
  for _, w in ipairs(wins) do
    vim.list_extend(out, window(w))
  end
  out[#out + 1] = '== screen'
  for _, row in ipairs(H.screen()) do
    out[#out + 1] = (row:gsub('%s+$', ''))
  end
  for i, l in ipairs(out) do
    out[i] = (l:gsub(vim.pesc(root), '<root>'))
  end
  local path = dir .. '/' .. name .. '.txt'
  if update then
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile(out, path)
    return
  end
  local want = vim.fn.filereadable(path) == 1 and vim.fn.readfile(path) or {}
  if vim.deep_equal(want, out) then
    os.remove(path .. '.actual')
  else
    vim.fn.writefile(out, path .. '.actual')
    failures[#failures + 1] = '--- ' .. name .. '\n' .. diff(table.concat(want, '\n') .. '\n', table.concat(out, '\n') .. '\n')
  end
end

----------------------------------------------------------------------
-- The screens
----------------------------------------------------------------------

require('thread').setup {}
local store = require 'thread.store'
local render = require 'thread.render'
local home = require 'thread.home'
local page = require 'thread.page'
local walk = require 'thread.walk'
local rpage = require 'thread.review.screen'

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
H.press '4'
capture 'home-closed'
H.press '1'
H.press '?'
capture 'home-help'
H.press 'q'
home.close()

home.focus { comment = store.find(store.active(), 1) }
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

require('thread.map').pin()
capture 'map-batch'
require('thread.map').close()

require('thread.menu').open()
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

if #failures > 0 then
  io.stderr:write('screens changed; the new ones are in tests/screens/*.actual\n' .. table.concat(failures, '\n') .. '\n')
  vim.cmd 'cquit 1'
end
io.stdout:write(update and 'screens: written\n' or 'screens: ok\n')
vim.cmd 'qa!'
