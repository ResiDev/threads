--- Walking: moving through a tour, a thread at a time. A step (a thread on
--- a line) is its bubble in the code, with its notes; a stage (a thread on
--- no line) is a page in the centred float. The map (`<leader>hm`) shows
--- where the walk started and every thread in it, and follows along.
---
--- While a walk is on, `L`/`H` go to the next and previous thread in it,
--- `K` up to the parent and `J` into the first thread this one leads to.
--- They are set globally when it starts and put back when it ends, as
--- tour.nvim does.

local config = require 'thread.config'
local store = require 'thread.store'
local tree = require 'thread.tree'

local M = {}

---@class thread.WalkState
---@field id integer     the thread you are on
---@field head integer   the thread the walk is under
---@field saved table<string, table|false>  lhs -> the mapping it had
---@type thread.WalkState|nil
local W

local function notify(msg, level)
  vim.notify('thread: ' .. msg, level or vim.log.levels.INFO)
end

---@return { id: integer, head: integer }|nil
function M.state()
  return W and { id = W.id, head = W.head } or nil
end

local function set_keys()
  if W.saved then
    return
  end
  W.saved = {}
  local keys = config.options.walk or {}
  local acts = { next = M.next, prev = M.prev, up = M.up, into = M.into }
  for action, fn in pairs(acts) do
    local lhs = keys[action]
    if lhs then
      local old = vim.fn.maparg(lhs, 'n', false, true)
      W.saved[lhs] = (old and old.lhs) and old or false
      vim.keymap.set('n', lhs, fn, { desc = 'Thread walk: ' .. action })
    end
  end
end

local function restore_keys()
  for lhs, old in pairs(W and W.saved or {}) do
    pcall(vim.keymap.del, 'n', lhs)
    if old then
      pcall(vim.fn.mapset, 'n', false, old)
    end
  end
end

--- Show one thread of the walk: a step in the code, a stage as a page.
---@param batch thread.Batch
---@param c thread.Comment
local function show(batch, c)
  local home = require 'thread.home'
  local render = require 'thread.render'
  if store.anchored(c) then
    -- Back in the code: the page, if one is open, goes.
    if home.is_open() then
      home.close()
    end
    require('thread.actions').jump(c)
    store.mark_seen(batch, c)
    render.refresh()
    require('thread.map').refresh()
  else
    store.mark_seen(batch, c)
    require('thread.map').refresh()
    home.focus { comment = c, walk = true }
  end
end

--- Walk to a thread: start a walk there, or move the one going.
---@param id integer
function M.go(id)
  local batch = store.active()
  local c = batch and store.find(batch, id)
  if not c then
    return
  end
  local head = tree.head(batch, id)
  if not head then
    return notify(string.format('thread %d is not in a walk', id))
  end
  W = W or {}
  W.id, W.head = id, head.id
  set_keys()
  show(batch, c)
end

--- Start walking: from the thread the cursor is on (or `id`): the walk it
--- leads to, or the one it is in.
---@param id integer|nil
function M.start(id)
  local batch = store.active()
  if not batch then
    return notify 'no batch yet'
  end
  if not id then
    local c = require('thread.render').at_cursor()
    id = c and c.id
  end
  local c = id and store.find(batch, id)
  if not c then
    return notify 'no thread here to walk'
  end
  local led = tree.led(batch, c)
  if #led > 0 then
    return M.go(led[1].c.id)
  end
  if tree.in_tour(batch, c.id) then
    return M.go(c.id)
  end
  notify 'this thread leads nowhere and is in no walk'
end

local function move(n)
  if not W then
    return
  end
  local batch = store.active()
  local head = batch and store.find(batch, W.head)
  if not head then
    return M.stop()
  end
  local list = tree.walk(batch, head)
  local at
  for i, item in ipairs(list) do
    if item.c.id == W.id then
      at = i
    end
  end
  local to = list[(at or 0) + n]
  if not to then
    local render = require 'thread.render'
    return notify(n > 0 and string.format('the end of the walk: %s goes up, %s ends it', render.show_key(config.options.walk.up) or ':Thread', render.key 'stop' or ':Thread stop') or 'the start of the walk')
  end
  M.go(to.c.id)
end

function M.next()
  move(1)
end

function M.prev()
  move(-1)
end

--- Up: to the thread this one is under. Above the walk's own threads that
--- is where it started, a step or your question, which ends the walk there.
function M.up()
  if not W then
    return
  end
  local batch = store.active()
  local parent = batch and tree.parent(batch, W.id)
  if not parent then
    return notify 'already at the top'
  end
  if parent.id == W.head then
    local id = parent.id
    M.stop()
    local home = require 'thread.home'
    if store.anchored(parent) then
      if home.is_open() then
        home.close()
      end
      require('thread.actions').jump(parent)
    else
      home.focus { comment = parent }
    end
    return id
  end
  M.go(parent.id)
end

--- Into: the first thread the one you are on leads to: a new walk under it.
function M.into()
  local id = W and W.id
  if not id then
    local c = require('thread.render').at_cursor()
    id = c and c.id
  end
  local batch = store.active()
  local c = batch and id and store.find(batch, id)
  local led = c and tree.led(batch, c) or {}
  if #led == 0 then
    return notify 'this thread leads nowhere'
  end
  M.go(led[1].c.id)
end

--- The float moved to another thread: a walk going on follows it.
---@param id integer
function M.follow(id)
  if not W then
    return
  end
  local batch = store.active()
  local head = batch and tree.head(batch, id)
  if head then
    W.id, W.head = id, head.id
    store.mark_seen(batch, store.find(batch, id))
    require('thread.map').refresh()
  end
end

--- End the walk: the keys go back to what they were, the map closes.
function M.stop()
  if not W then
    return
  end
  restore_keys()
  W = nil
  require('thread.map').close()
  require('thread.render').refresh()
end

return M
