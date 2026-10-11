--- thread.nvim: threads on code, answered by an agent. A thread is a
--- conversation, on lines or on none; an answer can lead to more threads,
--- and those are a tour you walk. See DESIGN.md.

local config = require 'thread.config'

local M = {}

M.config = config.options

local did_setup = false
-- lhs -> the mapping a zone key had before ours, kept across setup calls.
local zone_before = {}

local function actions()
  return require 'thread.actions'
end

--- The `:Thread` subcommands.
M.commands = {
  batches = function()
    require('thread.menu').open()
  end,
  home = function()
    require('thread.home').open()
  end,
  add = function(cmd)
    local from = cmd and cmd.range > 0 and cmd.line1 or vim.api.nvim_win_get_cursor(0)[1]
    local to = cmd and cmd.range > 0 and cmd.line2 or from
    actions().add(from, to)
  end,
  ask = function()
    actions().ask()
  end,
  open = function()
    actions().focus()
  end,
  walk = function(cmd)
    local id = cmd and tonumber((cmd.args or ''):match '%s(%d+)')
    local n = cmd and tonumber((cmd.args or ''):match '%s%d+%s+(%d+)')
    require('thread.walk').start(id, n)
  end,
  stop = function()
    require('thread.walk').stop()
  end,
  dim = function()
    local on = require('thread.render').dim()
    vim.notify('thread: ' .. (on and 'dimming all but the thread you are on' or 'not dimming'))
  end,
  diff = function()
    actions().diff_here()
  end,
  reply = function()
    actions().focus { reply = true }
  end,
  close = function()
    actions().close_here()
  end,
  map = function()
    require('thread.map').pin()
  end,
  toggle = function()
    local mode = require('thread.render').toggle()
    vim.notify('thread: ' .. (mode == 'full' and 'bubbles' or 'one line each'))
  end,
  hide = function()
    local shown = require('thread.render').hide()
    vim.notify('thread: ' .. (shown and 'shown' or 'hidden'))
  end,
  next = function()
    actions().step(1)
  end,
  prev = function()
    actions().step(-1)
  end,
  next_all = function()
    actions().step(1, true)
  end,
  prev_all = function()
    actions().step(-1, true)
  end,
  new = function(cmd)
    require('thread.store').new(cmd and (cmd.args:gsub('^%S+%s*', '')) or nil)
    require('thread.store').watch()
  end,
  changes = function()
    local store = require 'thread.store'
    local batch = store.active()
    if batch then
      actions().all_changes(batch)
    end
  end,
}

local function map_keys()
  local maps = config.options.mappings
  local function set(mode, lhs, fn, desc)
    if lhs then
      vim.keymap.set(mode, lhs, fn, { desc = 'Thread: ' .. desc })
    end
  end
  set('n', maps.add, M.commands.add, 'start a thread on this line')
  set('x', maps.add, function()
    local a, b = vim.fn.line 'v', vim.fn.line '.'
    vim.api.nvim_feedkeys(vim.keycode '<Esc>', 'nx', false)
    actions().add(math.min(a, b), math.max(a, b))
  end, 'start a thread on these lines')
  set('n', maps.ask, M.commands.ask, 'ask about no line in particular')
  set('n', maps.open, M.commands.open, 'focus the thread here')
  set('n', maps.reply, M.commands.reply, 'reply to the thread here')
  set('n', maps.close, M.commands.close, 'close the thread here')
  set('n', maps.map, M.commands.map, 'the map: the batch, or the walk')
  set('n', maps.walk, M.commands.walk, 'walk the tour here')
  set('n', maps.stop, M.commands.stop, 'stop walking')
  set('n', maps.dim, M.commands.dim, 'dim all but the thread here')
  set('n', maps.diff, M.commands.diff, 'draw its changes in the code')
  set('n', maps.home, M.commands.home, 'home: every thread')
  set('n', maps.menu, M.commands.batches, 'every batch')
  set('n', maps.toggle, M.commands.toggle, 'bubbles or one line each')
  set('n', maps.hide, M.commands.hide, 'hide or show the bubbles')
  set('n', maps.next, M.commands.next, 'next thread that is your move')
  set('n', maps.prev, M.commands.prev, 'previous thread that is your move')
  set('n', maps.next_all, M.commands.next_all, 'next open thread')
  set('n', maps.prev_all, M.commands.prev_all, 'previous open thread')

  -- On a comment's lines these act on it; anywhere else they do what they
  -- always do.
  local zone = config.options.zone or {}
  local function on_comment(lhs, fn, desc)
    if not lhs then
      return
    end
    -- Off a thread the key does what it did before: what another plugin
    -- mapped it to, else its own meaning.
    local old = vim.fn.maparg(lhs, 'n', false, true)
    if old and (old.desc or ''):find '^Thread: ' then
      old = zone_before[lhs]
    end
    zone_before[lhs] = old
    local function before()
      if old and old.callback then
        if old.expr == 1 then
          return old.callback()
        end
        vim.schedule(old.callback)
        return ''
      elseif old and old.rhs and old.rhs ~= '' then
        return vim.keycode(old.rhs)
      end
      return vim.keycode(lhs)
    end
    vim.keymap.set('n', lhs, function()
      local render = require 'thread.render'
      if vim.bo.buftype ~= '' or not render.visible() or not render.at_cursor() then
        return before()
      end
      vim.schedule(fn)
      return ''
    end, { expr = true, desc = 'Thread: ' .. desc })
  end
  on_comment(zone.focus, function()
    actions().focus()
  end, 'focus the thread here')
  on_comment(zone.fold, function()
    actions().fold_here()
  end, 'fold or unfold the thread here')
  on_comment(zone.next, function()
    local render = require 'thread.render'
    render.cycle(1)
  end, 'the next card on this line')
  on_comment(zone.more, function()
    actions().resize_here(1)
  end, 'more of the thread here')
  on_comment(zone.less, function()
    actions().resize_here(-1)
  end, 'less of the thread here')
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
    require('thread.review_page').refresh()
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
