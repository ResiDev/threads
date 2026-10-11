--- Batches on disk: one JSON file each under `<repo>/.threads/`, the current
--- one named in `.threads/active`. The file is the interface to the agent, so
--- it is re-read whenever it changes on disk and a reload never loses what is
--- in it. Whoever listens hears of every change, ours and the agent's.

local config = require 'thread.config'
local json = require 'thread.json'

local M = {}

local function store()
  return require 'thread.store'
end

local roots = {} -- cwd -> repo root
local cache = {} -- id -> thread.Batch, for the current root
local cache_root
local listeners = {} -- called whenever a batch changes

--- The repository the editor is in: git's top level, or the cwd outside git.
---@return string
function M.root()
  local cwd = vim.fn.getcwd()
  if not roots[cwd] then
    local out = vim.system({ 'git', '-C', cwd, 'rev-parse', '--show-toplevel' }, { text = true }):wait()
    roots[cwd] = out.code == 0 and vim.trim(out.stdout) or cwd
  end
  if cache_root ~= roots[cwd] then
    cache, cache_root = {}, roots[cwd]
  end
  return roots[cwd]
end

---@return string
function M.dir()
  return M.root() .. '/' .. config.options.dir
end

local function mtime(path)
  local st = vim.uv.fs_stat(path)
  return st and (st.mtime.sec * 1e9 + st.mtime.nsec) or nil
end

function M.read(path)
  local fd = io.open(path, 'r')
  if not fd then
    return nil
  end
  local s = fd:read '*a'
  fd:close()
  return s
end

function M.write(path, s)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
  -- Write beside it and rename, so a reader never sees half a file.
  local tmp = path .. '.tmp'
  local fd = assert(io.open(tmp, 'w'))
  fd:write(s)
  fd:close()
  assert(vim.uv.fs_rename(tmp, path))
end

local excluded = {} -- root -> true once checked

--- Keep the batches out of git without touching the repo's .gitignore.
local function exclude()
  if not config.options.exclude or excluded[M.root()] then
    return
  end
  excluded[M.root()] = true
  local out = require('thread.git').run { 'rev-parse', '--git-common-dir' }
  if not out then
    return
  end
  local gitdir = vim.trim(out)
  if not gitdir:match '^/' then
    gitdir = M.root() .. '/' .. gitdir
  end
  local path = gitdir .. '/info/exclude'
  local pattern = '/' .. config.options.dir .. '/'
  local current = M.read(path) or ''
  for line in current:gmatch '[^\n]+' do
    if line == pattern then
      return
    end
  end
  M.write(path, current .. (current == '' or current:sub(-1) == '\n' and '' or '\n') .. pattern .. '\n')
end

local function normalise(data)
  data.title = data.title or 'Untitled'
  data.reply = data.reply or config.options.reply
  data.rounds = data.rounds or {}
  data.threads = data.threads or {}
  for _, c in ipairs(data.threads) do
    c.messages = c.messages or {}
    c.status = c.status or 'open'
  end
  return data
end

--- The agent's messages in each thread of a batch, to tell what is new.
local function agent_counts(batch)
  local out = {}
  for _, c in ipairs(batch and batch.data.threads or {}) do
    local n = 0
    for _, m in ipairs(c.messages) do
      n = n + (m.from ~= 'you' and 1 or 0)
    end
    out[c.id] = n
  end
  return out
end

--- Say what the agent just answered, and when nothing is left waiting.
local function announce(before, batch)
  local after = agent_counts(batch)
  local answered = {}
  for _, c in ipairs(batch.data.threads) do
    if (after[c.id] or 0) > (before[c.id] or 0) then
      answered[#answered + 1] = c
    end
  end
  if #answered == 0 then
    return
  end
  local names = {}
  for i, c in ipairs(answered) do
    if i > 3 then
      break
    end
    local title = store().title(c)
    names[#names + 1] = c.id .. ' ' .. (#title > 30 and (title:sub(1, 29) .. '…') or title)
  end
  local msg = #answered > 3 and string.format('the agent answered %d threads', #answered) or ('the agent answered ' .. table.concat(names, ', '))
  local waiting = 0
  for _, c in ipairs(batch.data.threads) do
    waiting = waiting + (store().status(c) == 'waiting' and 1 or 0)
  end
  local key = require('thread.config').options.mappings.next
  local led = false
  for _, c in ipairs(answered) do
    led = led or require('thread.tour').leads(c)
  end
  if led then
    msg = msg .. ' (with a walkthrough)'
  end
  msg = msg .. (waiting == 0 and '; nothing is waiting now' or string.format('; %d still waiting', waiting))
  vim.notify('thread: ' .. msg .. (key and (' · ' .. key) or ''))
end

--- A batch by id, re-read when its file has changed since. When the agent
--- has answered in the meantime, says so.
---@param id string
---@return thread.Batch|nil, string|nil err
function M.load(id)
  local path = M.dir() .. '/' .. id .. '.json'
  local t = mtime(path)
  if not t then
    cache[id] = nil
    return nil, 'no batch ' .. id
  end
  local hit = cache[id]
  if hit and hit.mtime == t then
    return hit
  end
  local data, err = json.decode(M.read(path) or '')
  if type(data) ~= 'table' then
    return nil, string.format('%s is not valid JSON: %s', path, err or 'not an object')
  end
  local before = hit and agent_counts(hit)
  local batch = hit or { id = id, path = path }
  batch.data, batch.mtime = normalise(data), t
  batch.derived = nil
  cache[id] = batch
  require('thread.store.seen').hear(batch)
  if before and id == M.active_id() then
    vim.schedule(function()
      announce(before, batch)
    end)
  end
  return batch
end

---@param batch thread.Batch
function M.save(batch)
  batch.derived = nil
  exclude()
  M.write(batch.path, json.encode(batch.data))
  batch.mtime = mtime(batch.path)
end

--- Every batch, most recently changed first.
---@return thread.Batch[]
function M.list()
  local out = {}
  for name, kind in vim.fs.dir(M.dir()) do
    local id = name:match '^(.+)%.json$'
    if kind == 'file' and id then
      out[#out + 1] = M.load(id)
    end
  end
  table.sort(out, function(a, b)
    return a.mtime > b.mtime
  end)
  return out
end

local function slug(title)
  local s = title:lower():gsub('[^%w]+', '-'):gsub('^%-+', ''):gsub('%-+$', '')
  return s ~= '' and s:sub(1, 40) or 'batch'
end

---@param title string|nil
---@return thread.Batch
function M.new(title)
  title = (title and vim.trim(title) ~= '') and vim.trim(title) or os.date '%Y-%m-%d %H:%M'
  local id, n = slug(title), 1
  while mtime(M.dir() .. '/' .. id .. '.json') do
    n = n + 1
    id = slug(title) .. '-' .. n
  end
  exclude()
  local batch = { id = id, path = M.dir() .. '/' .. id .. '.json', data = normalise { title = title } }
  M.save(batch)
  cache[id] = batch
  M.set_active(id)
  return batch
end

---@param id string
function M.delete(id)
  os.remove(M.dir() .. '/' .. id .. '.json')
  os.remove(M.dir() .. '/' .. id .. '.seen')
  require('thread.git').drop(id)
  cache[id] = nil
  if M.active_id() == id then
    os.remove(M.dir() .. '/active')
  end
end

---@return string|nil
function M.active_id()
  local s = M.read(M.dir() .. '/active')
  s = s and vim.trim(s)
  return s ~= '' and s or nil
end

---@param id string
function M.set_active(id)
  M.write(M.dir() .. '/active', id .. '\n')
  M.notify()
end

--- The current batch; with `create`, a new one when there is none.
---@param create boolean|nil
---@return thread.Batch|nil
function M.active(create)
  local id = M.active_id()
  local batch = id and M.load(id)
  if not batch and create then
    batch = M.new()
  end
  return batch
end

--- Call `fn` whenever a batch changes: our own edits and the agent's
--- writes alike.
---@param fn fun()
function M.on_change(fn)
  listeners[#listeners + 1] = fn
end

function M.notify()
  for _, fn in ipairs(listeners) do
    pcall(fn)
  end
end

local watcher, watched, timer

--- Watch the batches directory, so an agent's reply shows as it lands.
function M.watch()
  local dir = M.dir()
  if watched == dir then
    return
  end
  if watcher then
    watcher:stop()
  end
  if not vim.uv.fs_stat(dir) then
    watched = nil
    return
  end
  watcher, watched = vim.uv.new_fs_event(), dir
  timer = timer or vim.uv.new_timer()
  watcher:start(dir, {}, function(_, name)
    if not (name and name:match '%.json$' or name == 'active') then
      return
    end
    timer:stop()
    timer:start(
      80,
      0,
      vim.schedule_wrap(function()
        local changed = false
        for id, batch in pairs(cache) do
          if mtime(batch.path) ~= batch.mtime then
            M.load(id)
            changed = true
          end
        end
        if changed or name == 'active' then
          M.notify()
        end
      end)
    )
  end)
end

return M
