--- Where a `name` in prose points: the code it is talking about, found
--- without the agent writing anything more than it already does, so a
--- name in backticks is a link to a chunk.
---
--- In order: a location written right after it (`sorted_keys (json.lua:37)`),
--- a path, where the name is defined, and last where its exact text appears.
--- Several places can match; they come ranked, best first: definitions
--- before uses, the thread's own file, then files the thread mentions, then
--- the rest, and nearest the thread's line within a file.

local git = require 'thread.base.git'
local repo = require 'thread.base.repo'

local M = {}

--- A place a name points to.
---@class thread.NamePlace
---@field file string  repo-relative
---@field line integer
---@field def boolean|nil

-- More places than this, with no definition among them, and a name is too
-- common to point anywhere.
local FEW = 6

local files_cache = {} ---@type table<string, string[]>  root -> repo-relative paths
local cache = {} ---@type table<string, thread.NamePlace[]>  root .. name .. context -> places

---@return string[]
local function tracked()
  local root = repo.root()
  if not files_cache[root] then
    local out = git.run { 'ls-files' }
    files_cache[root] = out and vim.split(vim.trim(out), '\n', { plain = true }) or {}
  end
  return files_cache[root]
end

--- The tracked file a written path means: exact, else the one ending in it.
---@param path string
---@return string|nil
local function find_file(path)
  path = path:gsub('^%./', '')
  local tail
  for _, f in ipairs(tracked()) do
    if f == path then
      return f
    end
    if not tail and (f:sub(-#path - 1) == '/' .. path) then
      tail = f
    end
  end
  return tail
end

---@class thread.NameHit
---@field file string
---@field line integer
---@field text string
---@field def boolean|nil

--- `git grep` over tracked files: a hit per line.
---@param args string[]
---@return thread.NameHit[]
local function grep(args)
  local out = git.run(vim.list_extend({ 'grep', '-n', '-I', '--no-color' }, args)) or ''
  local hits = {}
  for l in out:gmatch '[^\n]+' do
    local file, line, text = l:match '^(.-):(%d+):(.*)$'
    if file then
      hits[#hits + 1] = { file = file, line = tonumber(line), text = text }
    end
    if #hits >= 200 then
      break
    end
  end
  return hits
end

---@param s string
---@return string
local function esc(s)
  return (s:gsub('[%^%$%(%)%%%.%[%]%*%+%-%?]', '%%%0'))
end

--- Whether a line defines `name`, in the shapes most languages use: a
--- function or type anywhere, or a variable at the top level of its file.
--- An assignment inside a function, `c.status = 'open'`, is not one.
---@param text string
---@param name string
---@return boolean
local function defines(text, name)
  -- A comment can spell a definition out without being one.
  if text:match '^%s*%-%-' or text:match '^%s*//' or text:match '^%s*#' or text:match '^%s*%*' then
    return false
  end
  local n = esc(name)
  for _, p in ipairs {
    'function%s+' .. n .. '%s*%(',
    'function%s+[%w_.:]+[.:]' .. n .. '%s*%(',
    '[%w_]%.' .. n .. '%s*=%s*function',
    '^%s*' .. n .. '%s*=%s*function',
    'def%s+' .. n .. '%f[^%w_]',
    'fn%s+' .. n .. '%f[^%w_]',
    'func%s+' .. n .. '%f[^%w_]',
    'class%s+' .. n .. '%f[^%w_]',
    'struct%s+' .. n .. '%f[^%w_]',
    'interface%s+' .. n .. '%f[^%w_]',
    'type%s+' .. n .. '%f[^%w_]',
  } do
    if text:find(p) then
      return true
    end
  end
  for _, p in ipairs {
    '^local%s+' .. n .. '%s*[=,]',
    '^local%s+[%w_,%s]+,%s*' .. n .. '%s*=',
    '^[%w_]+%.' .. n .. '%s*=[^=]',
    '^export%s+',
    '^const%s+' .. n .. '%s*[=:]',
    '^let%s+' .. n .. '%s*[=:]',
    '^var%s+' .. n .. '%s*[=:]',
  } do
    if text:find(p) and text:find('%f[%w_]' .. n .. '%f[^%w_]') then
      return true
    end
  end
  return false
end

---@param file string
---@return string
local function stem(file)
  return vim.fn.fnamemodify(file, ':t:r')
end

--- Where the name is written, to rank the places it may mean.
---@class thread.NameContext
---@field file string|nil     the thread's file
---@field line integer|nil    the thread's line
---@field mentioned table<string, boolean>|nil  files the thread names
---@field near table<string, boolean>|nil  modules the message names, `store` for `store.status`

--- Rank hits, best first, keeping each place once.
---@param hits thread.NameHit[]
---@param ctx thread.NameContext
---@param qualifier string|nil
---@return thread.NamePlace[]
local function rank(hits, ctx, qualifier)
  local function score(h)
    local s = h.def and 0 or 100
    if qualifier and stem(h.file) == qualifier then
      s = s - 40
    end
    if ctx.near and ctx.near[stem(h.file)] then
      s = s - 15
    end
    if ctx.file == h.file then
      s = s - 30
    elseif ctx.mentioned and ctx.mentioned[h.file] then
      s = s - 20
    end
    -- Tests and docs talk about everything; the code is usually what is meant.
    if h.file:match '^tests?/' or h.file:match '%.md$' then
      s = s + 10
    end
    return s
  end
  table.sort(hits, function(a, b)
    local sa, sb = score(a), score(b)
    if sa ~= sb then
      return sa < sb
    end
    if a.file ~= b.file then
      return a.file < b.file
    end
    if a.file == ctx.file and ctx.line then
      return math.abs(a.line - ctx.line) < math.abs(b.line - ctx.line)
    end
    return a.line < b.line
  end)
  local seen, out = {}, {}
  for _, h in ipairs(hits) do
    local key = h.file .. ':' .. h.line
    if not seen[key] then
      seen[key] = true
      out[#out + 1] = { file = h.file, line = h.line, def = h.def }
    end
    if #out >= 20 then
      break
    end
  end
  return out
end

--- The places `name` (the text between backticks) points to, best first;
--- empty when it is not a reference, such as `[]`.
---@param name string
---@param ctx thread.NameContext
---@param after string|nil  the text right after it, for a written `(file:line)`
---@return thread.NamePlace[]
function M.resolve(name, ctx, after)
  name = vim.trim(name)
  -- Written right after it: `sorted_keys (json.lua:37)`.
  local wf, wl = (after or ''):match '^%s*%(([%w_%./%-]+):(%d+)%)'
  if wf then
    local f = find_file(wf)
    if f then
      return { { file = f, line = tonumber(wl), def = true } }
    end
  end
  -- A path, with or without a line: `tests/spec.lua`, `plugins/ui.lua:62`.
  -- One with a slash that is not in this repo points nowhere; without one,
  -- `store.status` reads like a file but is a name.
  local pf, pl = name:match '^([%w_%./%-]+%.%w+):(%d+)$'
  pf = pf or name:match '^[%w_%./%-]+%.%w+$' and name
  if pf then
    local f = find_file(pf)
    if f then
      return { { file = f, line = tonumber(pl) or 1, def = true } }
    elseif pf:find '/' or pl then
      return {}
    end
  end
  -- Nothing worth finding: no letters, or barely any.
  if not name:find '%a%a' then
    return {}
  end
  local near = table.concat(vim.tbl_keys(ctx.near or {}), ',')
  local key = repo.root() .. '\0' .. name .. '\0' .. (ctx.file or '') .. '\0' .. (ctx.line or '') .. '\0' .. near
  if cache[key] then
    return cache[key]
  end

  local result = {}
  -- An identifier, maybe qualified and maybe called: `store.save`, `encode()`.
  local ident = name:match '^([%a_][%w_.:]*)%s*%(?.-%)?$'
  if ident then
    local qualifier, last = ident:match '^(.*)[.:]([%a_][%w_]*)$'
    last = last or ident
    local hits = grep { '-w', '-F', '-e', last }
    local defs = {}
    for _, h in ipairs(hits) do
      h.def = defines(h.text, last)
      -- A qualified name is defined where the qualifier says: `store.save`
      -- in store.lua, or a line spelling it out, `function M.status(`.
      if h.def and (not qualifier or stem(h.file) == qualifier:match '([%w_]+)$' or h.text:find(ident, 1, true)) then
        defs[#defs + 1] = h
      end
    end
    if #defs > 0 then
      result = rank(defs, ctx, qualifier and qualifier:match '([%w_]+)$')
    elseif not qualifier and #hits <= FEW then
      result = rank(hits, ctx)
    elseif not qualifier then
      -- A word used all over and defined nowhere, `status` or `nil`, is a
      -- word, not a reference.
      cache[key] = {}
      return {}
    end
  end
  -- Its exact text: a test's name, a qualified name with no definition here;
  -- unless it is everywhere, which says nothing about where it means.
  if #result == 0 then
    local hits = grep { '-F', '-e', name }
    result = #hits <= FEW and rank(hits, ctx) or {}
  end
  cache[key] = result
  return result
end

--- The modules a message names: `store` for `store.status`.
---@param text string
---@return table<string, boolean>
function M.near(text)
  local out = {}
  for name in (text or ''):gmatch '`([%a_][%w_]*)[.:][%a_][%w_]*' do
    out[name] = true
  end
  return out
end

--- Forget what was found, for when the code has changed.
function M.reset()
  cache, files_cache = {}, {}
end

return M
