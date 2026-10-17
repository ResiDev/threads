-- Drive thread.nvim as a person does and see what it shows: a Neovim in a
-- tmux of its own, given keys, and after each step the screen as text, a
-- picture of it, and what `:Thread debug` says. For looking, not for
-- comparing: nothing here fails. `make view`; the variables:
--
--   STEPS   what to do, `;` between: keys in Vim's notation (`L`, `<CR>`,
--           `<leader>ht`), `:` an Ex command, `=` a Lua expression whose
--           value is written down, `wait 500` milliseconds
--   REPO    `fixture` (the default): H.world, a store module and a review
--           of every kind, store.lua open; or the path of a repository
--   CONFIG  `clean` (the default): thread.nvim alone; `mine`: your config
--   OUT     where it writes (default $TMPDIR/thread-view): NN.txt, NN.png
--   SIZE    columns x rows (default 140x45)
--   KEEP=1  leave it running: `tmux -L thread-view attach`
--
-- Each step waits for the screen to stop changing, so what is written is
-- what it settled on.

local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')

-- Asked to make the fixture: H.world, copied to the directory given, since
-- its own goes with the Neovim that made it.
if arg[1] == '--world' then
  local H = require 'tests.helpers'
  H.mute()
  local made = H.world()
  vim.system({ 'cp', '-a', made .. '/.', arg[2] }):wait()
  vim.cmd 'qa!'
end

local env = vim.env
local OUT = env.OUT or ((env.TMPDIR or '/tmp') .. '/thread-view')
local cols, rows = (env.SIZE or '140x45'):match '^(%d+)x(%d+)$'
cols, rows = tonumber(cols) or 140, tonumber(rows) or 45
local SOCK = OUT .. '/nvim.sock'
local TMUX = { 'tmux', '-L', 'thread-view', '-f', '/dev/null' }

---@param cmd string[]
---@return string out
local function run(cmd)
  local r = vim.system(cmd, { text = true }):wait()
  if r.code ~= 0 then
    error(table.concat(cmd, ' ') .. ': ' .. (r.stderr or ''))
  end
  return r.stdout or ''
end

---@param ... string
local function tmux(...)
  return run(vim.list_extend(vim.deepcopy(TMUX), { ... }))
end

local BUSY = '(no answer: Neovim is waiting for the rest of a key, or busy)'

--- An expression evaluated in the Neovim driven. Not while it waits for
--- the rest of a key, which holds every request back: then, after `ms`
--- (three seconds), BUSY.
---@param expr string
---@param ms integer|nil
---@return string
local function remote(expr, ms)
  local r = vim.system({ 'nvim', '--server', SOCK, '--remote-expr', expr }, { text = true }):wait(ms or 3000)
  if r.code ~= 0 then
    return BUSY
  end
  return r.stdout or ''
end

---@param expr string  in Lua
---@return string
local function lua(expr)
  return remote(string.format('luaeval(%q)', expr))
end

-- A fresh start: the last run's tmux and files gone.
vim.system(vim.list_extend(vim.deepcopy(TMUX), { 'kill-server' })):wait()
vim.fn.delete(OUT, 'rf')
vim.fn.mkdir(OUT, 'p')

local repo = env.REPO or 'fixture'
local open = nil ---@type string|nil
if repo == 'fixture' then
  repo = OUT .. '/repo'
  vim.fn.mkdir(repo, 'p')
  run { 'nvim', '--headless', '--clean', '-u', root .. '/tests/minimal_init.lua', '-l', root .. '/tests/view.lua', '--world', repo }
  open = 'store.lua'
end
repo = vim.fn.fnamemodify(repo, ':p')

local nvim = { 'nvim', '--listen', SOCK }
if (env.CONFIG or 'clean') == 'clean' then
  nvim = { 'nvim', '--clean', '-u', root .. '/tests/view_init.lua', '--listen', SOCK }
end
if open then
  nvim[#nvim + 1] = open
end
local cmd = table.concat(vim.tbl_map(vim.fn.shellescape, nvim), ' ')
tmux(
  'start-server',
  ';',
  'set',
  '-g',
  'default-terminal',
  'tmux-256color',
  ';',
  'set',
  '-sa',
  'terminal-features',
  ',*:RGB',
  ';',
  'new-session',
  '-d',
  '-s',
  'view',
  '-x',
  tostring(cols),
  '-y',
  tostring(rows),
  '-c',
  repo,
  '-e',
  'COLORTERM=truecolor',
  cmd
)

-- Up when it answers.
local up = vim.wait(10000, function()
  return vim.uv.fs_stat(SOCK) ~= nil and vim.trim(remote '1') == '1'
end, 100)
if not up then
  error('thread view: Neovim did not start; ' .. tmux('capture-pane', '-p', '-t', 'view'))
end

--- The screen, once it has stopped changing: the same three looks running
--- 100ms apart, or what it is after five seconds.
---@return string plain, string ansi
local function settled()
  local last, same = nil, 0
  vim.wait(5000, function()
    local now = tmux('capture-pane', '-p', '-e', '-t', 'view')
    same = now == last and same + 1 or 0
    last = now
    return same >= 2
  end, 100)
  return tmux('capture-pane', '-p', '-t', 'view'), assert(last)
end

-- 256 colours and the basic 16, as xterm has them.
local BASIC = {
  '000000',
  'cd0000',
  '00cd00',
  'cdcd00',
  '0000ee',
  'cd00cd',
  '00cdcd',
  'e5e5e5',
  '7f7f7f',
  'ff0000',
  '00ff00',
  'ffff00',
  '5c5cff',
  'ff00ff',
  '00ffff',
  'ffffff',
}
---@param n integer
---@return string
local function c256(n)
  if n < 16 then
    return '#' .. BASIC[n + 1]
  elseif n < 232 then
    local i = n - 16
    local function v(x)
      return x == 0 and 0 or 55 + x * 40
    end
    return string.format('#%02x%02x%02x', v(math.floor(i / 36)), v(math.floor(i / 6) % 6), v(i % 6))
  end
  local g = 8 + (n - 232) * 10
  return string.format('#%02x%02x%02x', g, g, g)
end

---@param s string
---@return string
local function esc(s)
  return (s:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;'))
end

--- The screen as a page to take a picture of: each run of text in the
--- colours its escape codes set.
---@param ansi string
---@return string
local function html(ansi)
  local out = {}
  local st = {} ---@type { fg: string|nil, bg: string|nil, bold: boolean|nil, italic: boolean|nil, under: boolean|nil, rev: boolean|nil }
  local function span(t)
    if t == '' then
      return
    end
    local fg, bg = st.fg, st.bg
    if st.rev then
      fg, bg = bg or '#1e1e2e', fg or '#cdd6f4'
    end
    local css = {}
    css[#css + 1] = fg and ('color:' .. fg) or nil
    css[#css + 1] = bg and ('background:' .. bg) or nil
    css[#css + 1] = st.bold and 'font-weight:bold' or nil
    css[#css + 1] = st.italic and 'font-style:italic' or nil
    css[#css + 1] = st.under and 'text-decoration:underline' or nil
    out[#out + 1] = #css > 0 and ('<span style="' .. table.concat(css, ';') .. '">' .. esc(t) .. '</span>') or esc(t)
  end
  local i = 1
  while i <= #ansi do
    local s, e, codes = ansi:find('\27%[([%d;:]*)m', i)
    span(ansi:sub(i, (s or #ansi + 1) - 1))
    if not s then
      break
    end
    local list = vim.split(codes == '' and '0' or codes:gsub(':', ';'), ';')
    local k = 1
    while k <= #list do
      local n = tonumber(list[k]) or 0
      if n == 0 then
        st = {}
      elseif n == 1 then
        st.bold = true
      elseif n == 3 then
        st.italic = true
      elseif n == 4 then
        st.under = true
      elseif n == 7 then
        st.rev = true
      elseif n == 22 then
        st.bold = nil
      elseif n == 23 then
        st.italic = nil
      elseif n == 24 then
        st.under = nil
      elseif n == 27 then
        st.rev = nil
      elseif n == 39 then
        st.fg = nil
      elseif n == 49 then
        st.bg = nil
      elseif (n == 38 or n == 48) and list[k + 1] == '2' then
        local c = string.format('#%02x%02x%02x', tonumber(list[k + 2]) or 0, tonumber(list[k + 3]) or 0, tonumber(list[k + 4]) or 0)
        st[n == 38 and 'fg' or 'bg'] = c
        k = k + 4
      elseif (n == 38 or n == 48) and list[k + 1] == '5' then
        st[n == 38 and 'fg' or 'bg'] = c256(tonumber(list[k + 2]) or 0)
        k = k + 2
      elseif n >= 30 and n <= 37 then
        st.fg = c256(n - 30)
      elseif n >= 40 and n <= 47 then
        st.bg = c256(n - 40)
      elseif n >= 90 and n <= 97 then
        st.fg = c256(n - 90 + 8)
      elseif n >= 100 and n <= 107 then
        st.bg = c256(n - 100 + 8)
      end
      k = k + 1
    end
    i = e + 1
  end
  return table.concat {
    '<!doctype html><meta charset="utf-8"><body style="margin:0;background:#1e1e2e;color:#cdd6f4">',
    "<pre style=\"margin:0;padding:6px;font:14px/17px 'CaskaydiaMono Nerd Font Mono','DejaVu Sans Mono',monospace\">",
    table.concat(out),
    '</pre>',
  }
end

--- A picture of the screen, by a headless chromium.
---@param ansi string
---@param png string
local function picture(ansi, png)
  local page = png:gsub('%.png$', '.html')
  vim.fn.writefile(vim.split(html(ansi), '\n'), page)
  local w, h = math.ceil(cols * 8.6) + 12, rows * 17 + 12
  vim
    .system({
      'chromium',
      '--headless',
      '--disable-gpu',
      '--no-sandbox',
      '--hide-scrollbars',
      '--screenshot=' .. png,
      '--window-size=' .. w .. ',' .. h,
      'file://' .. page,
    }, { text = true })
    :wait()
  vim.fn.delete(page)
end

local leader = remote([[get(g:, 'mapleader', '\')]]):gsub('\n$', '')
leader = leader == ' ' and '<Space>' or leader

local said = {} ---@type string[]
---@param n integer
---@param step string
---@param value string|nil  what an `=` step came to
local function look(n, step, value)
  -- Its keys taken first: an answer comes only once Neovim waits for no
  -- more of a mapping, 'timeoutlen' after an ambiguous one.
  if remote('1', 5000) == BUSY then
    value = (value and (value .. '\n') or '') .. BUSY
  end
  local plain, ansi = settled()
  local base = string.format('%s/%02d', OUT, n)
  local debug = lua [[(function()
    local ok, report = pcall(require, 'thread.code.report')
    return ok and table.concat(report.lines(), '\n') or 'thread.nvim not loaded'
  end)()]]
  local text = { 'step ' .. n .. ': ' .. step }
  if value then
    vim.list_extend(text, { '', '= ' .. value })
  end
  vim.list_extend(text, { '', '--- screen', plain, '--- :Thread debug', debug })
  vim.fn.writefile(vim.split(table.concat(text, '\n'), '\n'), base .. '.txt')
  picture(ansi, base .. '.png')
  said[#said + 1] = string.format('%02d  %-30s %s.txt  %s.png', n, step, base, base)
end

look(0, 'start')
local n = 0
for step in vim.gsplit(env.STEPS or '', ';', { trimempty = true }) do
  step = vim.trim(step)
  if step ~= '' then
    n = n + 1
    local value = nil ---@type string|nil
    local ms = step:match '^wait%s+(%d+)$'
    if ms then
      vim.wait(tonumber(ms))
    elseif step:sub(1, 1) == '=' then
      value = vim.trim(lua(string.format('vim.inspect(%s)', step:sub(2))))
    else
      local keys = step:sub(1, 1) == ':' and (step .. '<CR>') or step:gsub('<[Ll]eader>', leader)
      run { 'nvim', '--server', SOCK, '--remote-send', keys }
    end
    look(n, step, value)
  end
end

if env.KEEP ~= '1' then
  vim.system(vim.list_extend(vim.deepcopy(TMUX), { 'kill-server' })):wait()
end
io.stdout:write(table.concat(said, '\n') .. '\n')
if env.KEEP == '1' then
  io.stdout:write 'still running: tmux -L thread-view attach\n'
end
vim.cmd 'qa!'
