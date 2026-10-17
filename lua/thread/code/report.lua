--- `:Thread debug`: what the code holds for the current buffer and what
--- the editor actually draws there, written to a file to send when
--- something shows that should not. What thread.nvim thinks: the copy
--- loaded, the walk, each note and step placed with the size it is drawn
--- at and why. What is drawn: every mark with virtual lines in the buffer,
--- whoever's namespace it is in, so a stale card or another plugin's
--- shows up as one.

local config = require 'thread.config'
local go = require 'thread.go'
local paint = require 'thread.code.paint'
local text = require 'thread.base.text'

local M = {}

local S = paint.S

--- Where thread.nvim is loaded from, and its commit and branch there.
---@return string
local function loaded()
  local src = debug.getinfo(1, 'S').source:gsub('^@', '')
  local root = vim.fn.fnamemodify(src, ':h:h:h:h')
  local git = vim.system({ 'git', '-C', root, 'log', '-1', '--format=%h %s' }, { text = true }):wait()
  local branch = vim.system({ 'git', '-C', root, 'branch', '--show-current' }, { text = true }):wait()
  local dirty = vim.system({ 'git', '-C', root, 'status', '--porcelain', '--untracked-files=no' }, { text = true }):wait()
  return string.format(
    '%s @ %s (%s)%s',
    root,
    vim.trim(git.stdout or '?'),
    vim.trim(branch.stdout or '?'),
    vim.trim(dirty.stdout or '') ~= '' and ' with uncommitted changes' or ''
  )
end

---@param p thread.Placed
---@return string
local function what(p)
  if p.step then
    return string.format('step %d of %q', p.step.id, p.tour and p.tour.title or '?')
  end
  return 'note ' .. tostring(p.note and p.note.id)
end

--- The text of a virtual line.
---@param vl thread.VirtChunk[]
---@return string
local function said(vl)
  local t = {}
  for _, c in ipairs(vl) do
    t[#t + 1] = c[1]
  end
  return vim.trim(table.concat(t))
end

--- Who a mapping is: its description, and where its function or script
--- was written.
---@param m table  as maparg() gives it
---@return string
local function whose(m)
  local at = ''
  if m.callback then
    local info = debug.getinfo(m.callback, 'S')
    at = vim.fn.fnamemodify(info.source:gsub('^@', ''), ':~') .. ':' .. info.linedefined
  elseif (m.sid or 0) > 0 then
    local script = vim.fn.getscriptinfo({ sid = m.sid })[1]
    at = script and vim.fn.fnamemodify(script.name, ':~') .. ':' .. (m.lnum or 0) or ''
  end
  return string.format('%q%s%s', m.desc or m.rhs or '', at ~= '' and ' at ' or '', at)
end

--- Thread's keys another mapping has taken in the current buffer: a later
--- global one, or the buffer's own, which wins over any global. Each
--- does what that one does, and thread's never runs.
---@return string[]
local function taken()
  local o = config.options
  local keys = {} ---@type table<string, string>  lhs -> its name in the config
  for group, list in pairs { mappings = o.mappings, zone = o.zone, walk = go.ask 'walking' and o.walk or {} } do
    for name, lhs in pairs(list or {}) do
      if type(lhs) == 'string' then
        keys[lhs] = group .. '.' .. name
      end
    end
  end
  local out = {} ---@type string[]
  for lhs, name in pairs(keys) do
    local m = vim.fn.maparg(lhs, 'n', false, true)
    if not (m.desc or ''):find '^Thread' then
      out[#out + 1] = string.format('  %-12s %-16s %s%s', lhs, name, m.lhs and whose(m) or 'not mapped', m.buffer == 1 and ', this buffer' or '')
    end
  end
  table.sort(out)
  return out
end

--- The report, as lines.
---@return string[]
function M.lines()
  local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
  local out = {} ---@type string[]
  local function add(fmt, ...)
    out[#out + 1] = select('#', ...) > 0 and string.format(fmt, ...) or fmt
  end
  local v = vim.version()
  add('thread debug, %s', os.date '%Y-%m-%d %H:%M:%S')
  add('loaded: %s', loaded())
  add('nvim %d.%d.%d, cwd %s', v.major, v.minor, v.patch, vim.fn.getcwd())
  add('walking: %s', vim.inspect(go.ask 'walking', { newline = ' ', indent = '' }))
  add('mode %s, hidden %s, diffs %s', S.mode, tostring(S.hidden), vim.inspect(vim.tbl_keys(S.diffs)))
  add('closed with Tab: %s', vim.inspect(vim.tbl_keys(S.closed), { newline = ' ', indent = '' }))
  local lost = taken()
  add('keys taken from thread here: %s', #lost == 0 and 'none' or #lost)
  vim.list_extend(out, lost)
  add ''
  add('buffer %d %s, window %d, cursor line %d', buf, vim.api.nvim_buf_get_name(buf), win, vim.api.nvim_win_get_cursor(win)[1])
  local cur = S.current[buf]
  add('the cursor is on: %s', cur and (cur.key .. (cur.pinned and (', picked by hand on line ' .. cur.pinned) or '')) or 'nothing')
  local list = S.placed[buf] or {}
  local size, why = paint.sizes(list, cur and cur.key, go.ask 'walking')
  add ''
  add('placed: %d', #list)
  for _, p in ipairs(list) do
    add(
      '  %-6s lines %d-%d  %-40s %-14s %-5s %s%s',
      p.review.id:sub(1, 6),
      p.line,
      p.to,
      what(p),
      p.key,
      size[p.key],
      why[p.key],
      p.old and ', on removed lines' or ''
    )
  end
  add ''
  add('hung by the code: %d', vim.tbl_count(S.hung[buf] or {}))
  for key, h in pairs(S.hung[buf] or {}) do
    add('  %-14s mark %d', key, h.id)
  end
  -- Every namespace's, not only ours: what is on screen, whoever drew it.
  local names = {} ---@type table<integer, string>
  for name, id in pairs(vim.api.nvim_get_namespaces()) do
    names[id] = name
  end
  local drawn = {} ---@type string[]
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
    local d = m[4] or {}
    local vls = d.virt_lines or {}
    if #vls > 0 then
      local first = ''
      for _, vl in ipairs(vls) do
        first = first ~= '' and first or said(vl)
      end
      local ns = d.ns_id or -1
      drawn[#drawn + 1] = string.format('  %-14s line %-5d mark %-5d %3d rows  %s', names[ns] or tostring(ns), m[2] + 1, m[1], #vls, text.fit(first, 70))
    end
  end
  add ''
  add('virtual lines in the buffer: %d', #drawn)
  vim.list_extend(out, drawn)
  return out
end

--- Write the report to a file and show it in a split.
---@return string path
function M.write()
  local lines = M.lines()
  local path = vim.fn.stdpath 'log' .. '/thread-debug.txt'
  vim.fn.writefile(lines, path)
  vim.cmd('split ' .. vim.fn.fnameescape(path))
  return path
end

return M
