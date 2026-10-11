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

local root = H.world()

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

local FIELDS = {
  'hl_group',
  'line_hl_group',
  'number_hl_group',
  'sign_text',
  'sign_hl_group',
  'virt_text_pos',
  'virt_text_win_col',
  'priority',
  'hl_eol',
  'virt_lines_above',
}

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
