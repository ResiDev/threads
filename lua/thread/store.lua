--- Batches on disk: one JSON file each under `<repo>/.threads/`, the current
--- one named in `.threads/active`. The file is the interface to the agent, so
--- it is re-read whenever it changes on disk and a reload never loses what is
--- in it.

local config = require 'thread.config'
local json = require 'thread.json'

local M = {}

---@class thread.Message
---@field from 'you'|'agent'
---@field text string
---@field round integer|nil   the round it went to the agent in
---@field changes thread.Anchor[]|nil
---@field notes thread.Note[]|nil
---@field diagram table|nil
---@field verdict string|nil
---@field severity string|nil
---@field walk thread.Stop[]|nil  the tour it leads to, in order

---@class thread.Note: thread.Anchor
---@field note string|nil  what it says; none is a highlight only
---@field mark string|nil  a word on the line to pick out

---@class thread.Anchor
---@field file string   repo-relative
---@field rev string|nil
---@field line integer
---@field lines integer|nil
---@field text string

---@class thread.Comment: thread.Anchor
---@field id integer
---@field file string|nil   none: a thread about no line, shown as a page
---@field status 'open'|'closed'|nil
---@field title string|nil   the agent names a thread in its first reply
---@field messages thread.Message[]
---@field on { thread: integer, step: integer }|nil  a reply in a tour's stop

---@class thread.Batch
---@field id string
---@field path string
---@field mtime integer
---@field data { title: string, reply: string, diff: table|nil, rounds: table[], threads: thread.Comment[] }
---@field derived table|nil  what thread.tour works out once per load

local roots = {} -- cwd -> repo root
local cache = {} -- id -> thread.Batch, for the current root
local cache_root
local listeners = {}

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

local function read(path)
  local fd = io.open(path, 'r')
  if not fd then
    return nil
  end
  local s = fd:read '*a'
  fd:close()
  return s
end

local function write(path, s)
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
  local out = vim.system({ 'git', '-C', M.root(), 'rev-parse', '--git-common-dir' }, { text = true }):wait()
  if out.code ~= 0 then
    return
  end
  local gitdir = vim.trim(out.stdout)
  if not gitdir:match '^/' then
    gitdir = M.root() .. '/' .. gitdir
  end
  local path = gitdir .. '/info/exclude'
  local pattern = '/' .. config.options.dir .. '/'
  local current = read(path) or ''
  for line in current:gmatch '[^\n]+' do
    if line == pattern then
      return
    end
  end
  write(path, current .. (current == '' or current:sub(-1) == '\n' and '' or '\n') .. pattern .. '\n')
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
    local title = M.title(c)
    names[#names + 1] = c.id .. ' ' .. (#title > 30 and (title:sub(1, 29) .. '…') or title)
  end
  local msg = #answered > 3 and string.format('the agent answered %d threads', #answered) or ('the agent answered ' .. table.concat(names, ', '))
  local waiting = 0
  for _, c in ipairs(batch.data.threads) do
    waiting = waiting + (M.status(c) == 'waiting' and 1 or 0)
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
  local data, err = json.decode(read(path) or '')
  if type(data) ~= 'table' then
    return nil, string.format('%s is not valid JSON: %s', path, err or 'not an object')
  end
  local before = hit and agent_counts(hit)
  local batch = hit or { id = id, path = path }
  batch.data, batch.mtime = normalise(data), t
  batch.derived = nil
  cache[id] = batch
  M.hear(batch)
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
  write(batch.path, json.encode(batch.data))
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
  cache[id] = nil
  if M.active_id() == id then
    os.remove(M.dir() .. '/active')
  end
end

---@return string|nil
function M.active_id()
  local s = read(M.dir() .. '/active')
  s = s and vim.trim(s)
  return s ~= '' and s or nil
end

---@param id string
function M.set_active(id)
  write(M.dir() .. '/active', id .. '\n')
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

--- Whose move it is, worked out from the messages: waiting on the agent,
--- answered (your move), info (only the agent has spoken: an explanation,
--- not a turn you owe), or closed. A message of yours is with the agent as
--- soon as it is saved: there are no drafts.
---@param comment thread.Comment
---@return 'waiting'|'answered'|'info'|'closed'
function M.status(comment)
  -- `resolved` and `dismissed` are what closing used to be called.
  local s = comment.status
  if s == 'closed' or s == 'resolved' or s == 'dismissed' then
    return 'closed'
  end
  local last = comment.messages[#comment.messages]
  if last and last.from ~= 'you' then
    return M.talked(comment) and 'answered' or 'info'
  end
  return 'waiting'
end

--- Whether you have said anything in the thread.
---@param comment thread.Comment
function M.talked(comment)
  for _, m in ipairs(comment.messages) do
    if m.from == 'you' then
      return true
    end
  end
  return false
end

--- A thread's name: its title, else the start of its first message.
---@param comment thread.Comment
---@return string
function M.title(comment)
  if comment.title and comment.title ~= '' then
    return comment.title
  end
  local first = comment.messages[1] and comment.messages[1].text or ''
  return ((first:match '^%s*([^\n]*)' or ''):gsub('`', ''))
end

--- Whether a thread is about lines of code, or about none (a page).
---@param comment thread.Comment
function M.anchored(comment)
  return type(comment.file) == 'string' and comment.file ~= ''
end

--- A message of yours goes to the agent as you save it. It joins the round
--- still waiting on an answer; when nothing is waiting, it starts a new
--- round, and the code is snapshotted so the agent's changes can be shown
--- against it.
---@param batch thread.Batch
---@param msg thread.Message
local function stamp(batch, msg)
  local rounds = batch.data.rounds
  local open = false
  if #rounds > 0 then
    for _, c in ipairs(batch.data.threads) do
      if M.status(c) == 'waiting' then
        open = true
        break
      end
    end
  end
  if not open then
    local n = #rounds + 1
    local ok, sha = pcall(require('thread.git').snapshot, batch, n)
    rounds[n] = { sent = os.date '%Y-%m-%dT%H:%M:%S', snapshot = ok and sha or nil }
  end
  msg.round = #rounds
  msg.at = os.date '%Y-%m-%dT%H:%M:%S'
end

--- A new thread of yours: on `anchor`, or with none a question about no line.
---@param batch thread.Batch
---@param anchor thread.Anchor|nil
---@param text string
---@param extra table|nil  more fields for the thread, such as `on`
---@return thread.Comment
function M.add(batch, anchor, text, extra)
  local id = 0
  for _, c in ipairs(batch.data.threads) do
    id = math.max(id, c.id or 0)
  end
  local msg = { from = 'you', text = text }
  stamp(batch, msg)
  local comment = vim.tbl_extend('force', anchor or {}, extra or {}, {
    id = id + 1,
    status = 'open',
    messages = { msg },
  })
  batch.data.threads[#batch.data.threads + 1] = comment
  M.save(batch)
  M.notify()
  return comment
end

---@param batch thread.Batch
---@param comment thread.Comment
---@param text string
function M.reply(batch, comment, text)
  local msg = { from = 'you', text = text }
  stamp(batch, msg)
  comment.messages[#comment.messages + 1] = msg
  comment.status = 'open'
  M.save(batch)
  M.notify()
end

---@param batch thread.Batch
---@param id integer
---@return thread.Comment|nil, integer|nil index
function M.find(batch, id)
  for i, c in ipairs(batch.data.threads) do
    if c.id == id then
      return c, i
    end
  end
end

---@param batch thread.Batch
---@param comment thread.Comment
function M.remove(batch, comment)
  local _, i = M.find(batch, comment.id)
  if i then
    table.remove(batch.data.threads, i)
    M.save(batch)
    M.notify()
  end
end

---@param batch thread.Batch
---@param comment thread.Comment
---@param status 'open'|'closed'
function M.set_status(batch, comment, status)
  comment.status = status
  M.save(batch)
  M.notify()
end

----------------------------------------------------------------------
-- Seen: which messages you have looked at. Kept beside the batch in its own
-- file, which only the plugin writes, so the agent never has to know.
----------------------------------------------------------------------

local function seen_path(batch)
  return M.dir() .. '/' .. batch.id .. '.seen'
end

---@param batch thread.Batch
---@return table<string, integer>  comment id -> messages seen
local function seen(batch)
  if not batch.seen then
    batch.seen = (json.decode(read(seen_path(batch)) or '') or {})
  end
  return batch.seen
end

--- The agent writes its messages into the file with no time, so when one
--- first shows up its time is noted beside what you have seen. The first
--- time a batch is read, what is already there has no time.
---@param batch thread.Batch
function M.hear(batch)
  local s = seen(batch)
  local first = type(s._heard) ~= 'table'
  if first then
    s._heard = {}
  end
  local now, changed = os.date '%Y-%m-%dT%H:%M:%S', first
  for _, c in ipairs(batch.data.threads) do
    for i, m in ipairs(c.messages) do
      local key = c.id .. ':' .. i
      if m.from ~= 'you' and not m.at and s._heard[key] == nil then
        s._heard[key] = not first and now or false
        changed = true
      end
    end
  end
  if changed then
    write(seen_path(batch), json.encode(s))
  end
end

--- When message `i` of a thread was written: yours as you saved it (or
--- when its round was sent), the agent's as it first showed up.
---@param batch thread.Batch
---@param comment thread.Comment
---@param i integer
---@return string|nil  `2026-10-11T04:23:58`
function M.when(batch, comment, i)
  local m = comment.messages[i]
  if not m then
    return nil
  end
  if m.at then
    return m.at
  end
  if m.from == 'you' then
    local r = m.round and batch.data.rounds[m.round]
    return r and r.sent
  end
  local h = seen(batch)._heard
  return type(h) == 'table' and h[comment.id .. ':' .. i] or nil
end

-- A stop drawn as a thread (thread.tour.display) carries the stop's words
-- as an extra first message: its real thread, and how many it adds. A stop
-- no one has replied in is read once you have walked it.
local function real_of(comment)
  if comment.real then
    return comment.real, #comment.messages - #comment.real.messages
  end
  return comment, 0
end

--- Whether the comment has a message from the agent you have not looked at.
---@param batch thread.Batch
---@param comment thread.Comment
function M.unseen(batch, comment)
  if comment.virtual then
    return not M.visited(batch, comment.stop.owner, comment.stop.n)
  end
  local real, extra = real_of(comment)
  local n = (seen(batch)[tostring(real.id)] or 0) + extra
  for i = #comment.messages, n + 1, -1 do
    if comment.messages[i].from ~= 'you' then
      return true
    end
  end
  return false
end

--- How many of the thread's messages you had seen.
---@param batch thread.Batch
---@param comment thread.Comment
---@return integer
function M.seen_count(batch, comment)
  if comment.virtual then
    return M.visited(batch, comment.stop.owner, comment.stop.n) and 1 or 0
  end
  local real, extra = real_of(comment)
  return (seen(batch)[tostring(real.id)] or 0) + extra
end

--- Mark every message in the thread seen.
---@param batch thread.Batch
---@param comment thread.Comment
---@return boolean changed
function M.mark_seen(batch, comment)
  if comment.virtual then
    return M.visit(batch, comment.stop.owner, comment.stop.n)
  end
  comment = real_of(comment)
  local s = seen(batch)
  local key = tostring(comment.id)
  if (s[key] or 0) >= #comment.messages then
    return false
  end
  s[key] = #comment.messages
  write(seen_path(batch), json.encode(s))
  return true
end

--- Whether you have been to stop `n` of a thread's tour.
---@param batch thread.Batch
---@param owner integer
---@param n integer
function M.visited(batch, owner, n)
  local w = seen(batch)._walked
  local t = type(w) == 'table' and w[tostring(owner)]
  return type(t) == 'table' and t[tostring(n)] == true
end

--- Mark stop `n` of a thread's tour as been to.
---@return boolean changed
function M.visit(batch, owner, n)
  if M.visited(batch, owner, n) then
    return false
  end
  local s = seen(batch)
  if type(s._walked) ~= 'table' then
    s._walked = {}
  end
  local key = tostring(owner)
  s._walked[key] = type(s._walked[key]) == 'table' and s._walked[key] or {}
  s._walked[key][tostring(n)] = true
  write(seen_path(batch), json.encode(s))
  return true
end

--- Whether you have marked a changed file viewed, in the review.
---@param batch thread.Batch
---@param file string
function M.viewed(batch, file)
  local v = seen(batch)._viewed
  return type(v) == 'table' and v[file] == true
end

---@param batch thread.Batch
---@param file string
function M.toggle_viewed(batch, file)
  local s = seen(batch)
  if type(s._viewed) ~= 'table' then
    s._viewed = {}
  end
  s._viewed[file] = not s._viewed[file] or nil
  write(seen_path(batch), json.encode(s))
end

--- The id the next new thread gets.
---@param batch thread.Batch
---@return integer
function M.next_id(batch)
  local id = 0
  for _, c in ipairs(batch.data.threads) do
    id = math.max(id, c.id or 0)
  end
  return id + 1
end

--- One reply, added to each of several threads.
---@param batch thread.Batch
---@param ids integer[]
---@param text string
function M.reply_all(batch, ids, text)
  local round = { from = 'you' }
  stamp(batch, round)
  for _, id in ipairs(ids) do
    local c = M.find(batch, id)
    if c then
      c.messages[#c.messages + 1] = { from = 'you', text = text, round = round.round }
      c.status = 'open'
    end
  end
  M.save(batch)
  M.notify()
end

---@param batch thread.Batch
---@param ids integer[]
---@param status 'open'|'closed'
function M.set_status_all(batch, ids, status)
  for _, id in ipairs(ids) do
    local c = M.find(batch, id)
    if c then
      c.status = status
    end
  end
  M.save(batch)
  M.notify()
end

----------------------------------------------------------------------
-- Change notification: our own edits and the agent's writes alike
----------------------------------------------------------------------

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
    timer:start(80, 0, vim.schedule_wrap(function()
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
    end))
  end)
end

return M
