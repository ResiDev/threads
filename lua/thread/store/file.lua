--- Reviews on disk: one JSON file each in `<repo>/.threads/`, named by
--- the review's id, and beside it `<id>.seen`, what you have seen of it,
--- which only the plugin writes. A review is a decoded table here; what
--- it means is thread.model's. A change to a review, ours or the agent's,
--- fires `User ThreadChanged` with its id.

local config = require 'thread.config'
local git = require 'thread.base.git'
local json = require 'thread.base.json'
local repo = require 'thread.base.repo'

local M = {}

-- What each review file's time was when we last wrote it, or last told
-- everyone it changed; a file whose time differs changed under us.
local known = {} ---@type table<string, number>

--- Where the reviews are.
---@return string
function M.dir()
  return repo.root() .. '/' .. config.options.dir
end

---@param id string
---@param ext 'json'|'seen'
---@return string
local function path_of(id, ext)
  return M.dir() .. '/' .. id .. '.' .. ext
end

---@param path string
---@return number|nil
local function mtime(path)
  local st = vim.uv.fs_stat(path)
  return st and (st.mtime.sec * 1e9 + st.mtime.nsec) or nil
end

---@param path string
---@return string|nil
local function slurp(path)
  local fd = io.open(path, 'r')
  if not fd then
    return nil
  end
  local s = fd:read '*a'
  fd:close()
  return s
end

--- Written beside it and renamed, so a reader never sees half a file.
---@param path string
---@param s string
local function put(path, s)
  vim.fn.mkdir(vim.fs.dirname(path), 'p')
  local tmp = path .. '.tmp'
  local fd = assert(io.open(tmp, 'w'))
  fd:write(s)
  fd:close()
  assert(vim.uv.fs_rename(tmp, path))
end

local excluded = {} ---@type table<string, true>

--- Keep the reviews out of git, without touching the repository's
--- .gitignore: through .git/info/exclude.
local function exclude()
  local root = repo.root()
  if not config.options.exclude or excluded[root] then
    return
  end
  excluded[root] = true
  local out = git.run { 'rev-parse', '--git-common-dir' }
  if not out then
    return
  end
  local gitdir = vim.trim(out)
  if not gitdir:match '^/' then
    gitdir = repo.path(gitdir)
  end
  local path = gitdir .. '/info/exclude'
  local pattern = '/' .. config.options.dir .. '/'
  local current = slurp(path) or ''
  for line in current:gmatch '[^\n]+' do
    if line == pattern then
      return
    end
  end
  put(path, current .. ((current == '' or current:sub(-1) == '\n') and '' or '\n') .. pattern .. '\n')
end

--- Tell whoever listens that a review changed.
---@param id string
function M.fire(id)
  vim.api.nvim_exec_autocmds('User', { pattern = 'ThreadChanged', modeline = false, data = { id = id } })
end

--- The id of every review on disk.
---@return string[]
function M.ids()
  local out = {}
  local dir = M.dir()
  if not vim.uv.fs_stat(dir) then
    return out
  end
  for name, kind in vim.fs.dir(dir) do
    local id = kind == 'file' and name:match '^(.+)%.json$'
    if id then
      out[#out + 1] = id
    end
  end
  table.sort(out)
  return out
end

--- When a review's file last changed: a number that moves on with every
--- write, nil when there is no such review.
---@param id string
---@return number|nil
function M.mtime(id)
  return mtime(path_of(id, 'json'))
end

--- A review's file, decoded afresh.
---@param id string
---@return table|nil review, string|nil err
function M.read(id)
  local path = path_of(id, 'json')
  local s = slurp(path)
  if not s then
    return nil, 'no review ' .. id
  end
  local value, err = json.decode(s)
  if type(value) ~= 'table' then
    return nil, string.format('%s is not valid JSON: %s', path, err or 'not an object')
  end
  return value
end

--- Write a review, its keys in the order `schema` gives, and say so.
---@param id string
---@param value table
---@param schema thread.JsonSchema
---@return number mtime  its file's, now
function M.write(id, value, schema)
  exclude()
  local path = path_of(id, 'json')
  put(path, json.encode(value, schema))
  local t = assert(mtime(path))
  known[path] = t
  M.fire(id)
  M.watch()
  return t
end

--- Delete a review and what you have seen of it, and say so.
---@param id string
function M.remove(id)
  local path = path_of(id, 'json')
  os.remove(path)
  os.remove(path_of(id, 'seen'))
  known[path] = nil
  M.fire(id)
end

--- An id for a new review, from its title: not one on disk already.
---@param title string
---@return string
function M.new_id(title)
  local slug = title:lower():gsub('[^%w]+', '-'):sub(1, 40):gsub('^%-', ''):gsub('%-$', '')
  slug = slug ~= '' and slug or 'review'
  local id, n = slug, 1
  while M.mtime(id) do
    n = n + 1
    id = slug .. '-' .. n
  end
  return id
end

--- What you have seen of a review, as last written; nil before anything.
---@param id string
---@return table|nil
function M.read_seen(id)
  local value = json.decode(slurp(path_of(id, 'seen')) or '')
  return type(value) == 'table' and value or nil
end

--- Keep what you have seen of a review. It says nothing: whoever changed
--- it fires, when the change is one to draw.
---@param id string
---@param value table
function M.write_seen(id, value)
  put(path_of(id, 'seen'), json.encode(value))
end

local watcher, watched ---@type uv.uv_fs_event_t|nil, string|nil
local timer ---@type uv.uv_timer_t|nil

--- Every review whose file changed under us, or went: fire for each.
---@param dir string
local function rescan(dir)
  -- A wait begun before the editor moved to another repository.
  if dir ~= M.dir() then
    return
  end
  local here = {} ---@type table<string, true>
  for _, id in ipairs(M.ids()) do
    local path = path_of(id, 'json')
    here[path] = true
    local t = mtime(path)
    if t and known[path] ~= t then
      known[path] = t
      M.fire(id)
    end
  end
  for path in pairs(known) do
    if vim.startswith(path, dir .. '/') and not here[path] then
      known[path] = nil
      M.fire((vim.fs.basename(path):gsub('%.json$', '')))
    end
  end
end

--- Watch the reviews, so the agent's writes show as they land. Again
--- after the editor moves to another repository.
function M.watch()
  local dir = M.dir()
  if watched == dir then
    return
  end
  if watcher then
    watcher:stop()
    watcher, watched = nil, nil
  end
  if timer then
    timer:stop()
  end
  if not vim.uv.fs_stat(dir) then
    return
  end
  for _, id in ipairs(M.ids()) do
    local path = path_of(id, 'json')
    known[path] = known[path] or mtime(path)
  end
  local w = assert(vim.uv.new_fs_event())
  local t = timer or assert(vim.uv.new_timer())
  timer = t
  w:start(dir, {}, function(_, name)
    if not (name and name:match '%.json$') then
      return
    end
    -- An agent's write is often several: wait for it to settle.
    t:stop()
    t:start(
      80,
      0,
      vim.schedule_wrap(function()
        rescan(dir)
      end)
    )
  end)
  watcher, watched = w, dir
end

return M
