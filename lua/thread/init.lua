--- thread.nvim: threads on code, answered by an agent. A thread is a
--- conversation, on lines or on none; an answer can lead to more threads,
--- and those are a tour you walk. See DESIGN.md.

local config = require 'thread.config'

local M = {}

M.config = config.options

local did_setup = false

local function actions()
  return require 'thread.actions'
end

local function say(msg)
  vim.notify('thread: ' .. msg)
end

--- Every command, as `:Thread <name>`, and as the global key named the
--- same in `mappings` (`menu` runs `batches`), with what it does.
---@type { [1]: string, [2]: string|false, [3]: fun(cmd: table|nil), key: string|nil }[]
local COMMANDS = {
  { 'home', 'home: every thread', function()
    require('thread.home').open()
  end },
  { 'batches', 'every batch', function()
    require('thread.menu').open()
  end, key = 'menu' },
  { 'add', 'start a thread on this line', function(cmd)
    local from = cmd and cmd.range > 0 and cmd.line1 or vim.api.nvim_win_get_cursor(0)[1]
    actions().add(from, cmd and cmd.range > 0 and cmd.line2 or from)
  end },
  { 'ask', 'ask about no line in particular', function()
    actions().ask()
  end },
  { 'open', 'focus the thread here', function()
    actions().focus()
  end },
  { 'reply', 'reply to the thread here', function()
    actions().focus { reply = true }
  end },
  { 'close', 'close the thread here', function()
    actions().close_here()
  end },
  { 'map', 'the map: the batch, or the walk', function()
    require('thread.map').pin()
  end },
  { 'walk', 'walk the tour here', function(cmd)
    local args = cmd and cmd.args or ''
    require('thread.walk').start(tonumber(args:match '%s(%d+)'), tonumber(args:match '%s%d+%s+(%d+)'))
  end },
  { 'stop', 'stop walking', function()
    require('thread.walk').stop()
  end },
  { 'dim', 'dim all but the thread here', function()
    say(require('thread.render').dim() and 'dimming all but the thread you are on' or 'not dimming')
  end },
  { 'diff', 'draw its changes in the code', function()
    actions().diff_here()
  end },
  { 'toggle', 'bubbles or one line each', function()
    say(require('thread.render').toggle() == 'full' and 'bubbles' or 'one line each')
  end },
  { 'hide', 'hide or show the bubbles', function()
    say(require('thread.render').hide() and 'shown' or 'hidden')
  end },
  { 'next', 'next thread that is your move', function()
    actions().step(1)
  end },
  { 'prev', 'previous thread that is your move', function()
    actions().step(-1)
  end },
  { 'next_all', 'next open thread', function()
    actions().step(1, true)
  end },
  { 'prev_all', 'previous open thread', function()
    actions().step(-1, true)
  end },
  { 'new', false, function(cmd)
    local store = require 'thread.store'
    store.new(cmd and (cmd.args:gsub('^%S+%s*', '')) or nil)
    store.watch()
  end },
  { 'changes', false, function()
    local batch = require('thread.store').active()
    if batch then
      actions().all_changes(batch)
    end
  end },
}

--- Keys that act on the thread the cursor is on, by their name in `zone`.
local ZONE = {
  { 'focus', 'focus the thread here', function()
    actions().focus()
  end },
  { 'fold', 'fold or unfold the thread here', function()
    actions().fold_here()
  end },
  { 'next', 'the next card on this line', function()
    require('thread.render').cycle(1)
  end },
  { 'more', 'more of the thread here', function()
    actions().resize_here(1)
  end },
  { 'less', 'less of the thread here', function()
    actions().resize_here(-1)
  end },
}

--- The `:Thread` subcommands, by name.
M.commands = {}
for _, c in ipairs(COMMANDS) do
  M.commands[c[1]] = c[3]
end

local function map_keys()
  local maps = config.options.mappings
  for _, c in ipairs(COMMANDS) do
    local lhs = c[2] and maps[c.key or c[1]]
    if lhs then
      vim.keymap.set('n', lhs, c[3], { desc = 'Thread: ' .. c[2] })
    end
  end
  if maps.add then
    vim.keymap.set('x', maps.add, function()
      local a, b = vim.fn.line 'v', vim.fn.line '.'
      vim.api.nvim_feedkeys(vim.keycode '<Esc>', 'nx', false)
      actions().add(math.min(a, b), math.max(a, b))
    end, { desc = 'Thread: start a thread on these lines' })
  end

  -- On a thread's lines these act on it; anywhere else they do what they
  -- always do.
  local zone = config.options.zone or {}
  local function on_thread()
    return vim.bo.buftype == '' and require('thread.render').visible() and require('thread.render.place').at_cursor() ~= nil
  end
  for _, z in ipairs(ZONE) do
    if zone[z[1]] then
      require('thread.keys').zone(zone[z[1]], z[3], 'Thread: ' .. z[2], on_thread)
    end
  end
end

local function autocmds()
  local render = require 'thread.render'
  local store = require 'thread.store'
  local group = vim.api.nvim_create_augroup('thread', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufWinEnter', 'WinResized', 'TextChanged', 'InsertLeave' }, {
    group = group,
    callback = render.schedule,
  })
  vim.api.nvim_create_autocmd('CursorMoved', {
    group = group,
    callback = render.cursor_moved,
  })
  -- The window scrolls after the cursor moves: a card above the first line
  -- is shown once the top comes into view.
  vim.api.nvim_create_autocmd('WinScrolled', {
    group = group,
    callback = function()
      render.show_top()
    end,
  })
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = group,
    callback = function(ev)
      render.follow(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = function()
      require('thread.theme').apply()
    end,
  })
  vim.api.nvim_create_autocmd('DirChanged', {
    group = group,
    callback = function()
      store.watch()
      render.schedule()
    end,
  })
  store.on_change(function()
    render.schedule()
    require('thread.home').refresh()
    require('thread.menu').refresh()
    require('thread.map').refresh()
    require('thread.page').refresh()
    require('thread.review.screen').refresh()
  end)
end

--- Set up with the defaults if nothing has yet: the command works without
--- a setup() call.
function M.ensure()
  if not did_setup then
    M.setup()
  end
end

---@param opts table|nil
function M.setup(opts)
  config.setup(opts)
  M.config = config.options
  require('thread.theme').apply()
  if not did_setup then
    autocmds()
    did_setup = true
  end
  map_keys()
  require('thread.store').watch()
  require('thread.render').schedule()
end

return M
