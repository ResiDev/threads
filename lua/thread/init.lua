--- thread.nvim: reviews of code, written by an agent and answered in
--- the editor. A review has contracts, tours of steps you walk, and
--- notes, each a conversation. See README.md, and design/format.ts.

local config = require 'thread.config'

local M = {}

M.config = config.options

local did_setup = false

local function say(msg)
  vim.notify('thread: ' .. msg)
end

--- The surfaces, each registered with go as it loads.
---@return table go
local function surfaces()
  for _, s in ipairs { 'thread.screen', 'thread.compose', 'thread.code', 'thread.walk', 'thread.map' } do
    require(s)
  end
  return require 'thread.go'
end

local function code()
  surfaces()
  return require 'thread.code'
end

--- Every command, as `:Thread <name>`, and as the global key named the
--- same in `mappings`, with what it does.
---@type { [1]: string, [2]: string|false, [3]: fun(cmd: table|nil), key: string|nil }[]
local COMMANDS = {
  {
    'home',
    'home: every review',
    function()
      surfaces().open('home', {})
    end,
  },
  {
    'ask',
    'ask about no line in particular',
    function()
      surfaces().open('compose', {})
    end,
  },
  {
    'add',
    'start a note on this line',
    function(cmd)
      local from = cmd and cmd.range > 0 and cmd.line1 or vim.api.nvim_win_get_cursor(0)[1]
      code().add(from, cmd and cmd.range > 0 and cmd.line2 or from)
    end,
  },
  {
    'open',
    'open the note or step here',
    function()
      code().focus()
    end,
  },
  {
    'reply',
    'reply to the note or step here',
    function()
      code().reply()
    end,
  },
  {
    'close',
    'settle the note here',
    function()
      code().close_here()
    end,
  },
  {
    'walk',
    'walk from the step here',
    function()
      if not code().walk_here() then
        say 'no step here to walk'
      end
    end,
  },
  {
    'stop',
    'stop walking',
    function()
      surfaces()
      require('thread.walk').stop()
    end,
  },
  {
    'map',
    'the map: the notes on lines, or the tour you walk',
    function()
      surfaces().open('map', {})
    end,
  },
  {
    'toggle',
    "every note open, and the walk's tour; or only what you are on",
    function()
      say(code().toggle() == 'all' and "every note open, and the walk's tour" or 'only what you are on open')
    end,
  },
  {
    'hide',
    'hide or show the bubbles',
    function()
      say(code().hide() and 'shown' or 'hidden')
    end,
  },
  {
    'diff',
    "draw its review's diff in the code, or stop; while walking, the walk's, off or on",
    function()
      surfaces()
      local walk = require 'thread.walk'
      if walk.state() then
        local on = walk.toggle 'diff'
        -- Kept drawn on a removed step, the walk has said why.
        if on or not assert(walk.state()).removed then
          say(on and "the walk's diff drawn" or "the walk's diff hidden")
        end
        return
      end
      local on = code().diff_here()
      say(on == nil and 'no review with a diff here' or on and "its review's diff drawn" or 'diff hidden')
    end,
  },
  {
    'next',
    'next note or step that wants you',
    function()
      code().next(1)
    end,
  },
  {
    'prev',
    'previous note or step that wants you',
    function()
      code().next(-1)
    end,
  },
  {
    'debug',
    false,
    function()
      code()
      say('written to ' .. require('thread.code.report').write())
    end,
  },
  {
    'next_all',
    'next conversation on a line',
    function()
      code().next(1, true)
    end,
  },
  {
    'prev_all',
    'previous conversation on a line',
    function()
      code().next(-1, true)
    end,
  },
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
      code().add(math.min(a, b), math.max(a, b))
    end, { desc = 'Thread: start a note on these lines' })
  end
  code().setup()
  local group = vim.api.nvim_create_augroup('thread', { clear = true })
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = function()
      require('thread.ui.theme').apply()
    end,
  })
  vim.api.nvim_create_autocmd('DirChanged', {
    group = group,
    callback = function()
      require('thread.store.file').watch()
    end,
  })
  require('thread.base.diff').watch()
  require('thread.store.file').watch()
  code().schedule()
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
  require('thread.ui.theme').apply()
  did_setup = true
  map_keys()
end

return M
