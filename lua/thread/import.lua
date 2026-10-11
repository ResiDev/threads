--- A tour.nvim `.tour` file, read in as threads: a standalone tour in the
--- current batch.
---
--- - the tour itself becomes a thread about no line, its overview the
---   agent's message, leading to the stages;
--- - each stage becomes a page (a thread about no line) whose message is the
---   briefing: the point, then the description, with its verdict and
---   diagram, leading to the stage's steps;
--- - each step on a line becomes a thread there, its description the agent's
---   message and its comments and notes the message's notes;
--- - a step on no line inside a stage (a page) becomes a page under it.
---
--- Anchors by `symbol`, `pattern` or `line` are turned into quoted lines as
--- they are read, so the threads follow the code the way every thread does.

local config = require 'thread.config'
local store = require 'thread.store'

local M = {}

local function notify(msg, level)
  vim.notify('thread: ' .. msg, level or vim.log.levels.INFO)
end

local function tours_dir()
  return store.root() .. '/' .. config.options.tours
end

--- Every tour name in the tours directory.
---@return string[]
function M.names()
  local out = {}
  for name, kind in vim.fs.dir(tours_dir()) do
    local n = name:match '^(.+)%.tour$'
    if kind == 'file' and n then
      out[#out + 1] = n
    end
  end
  table.sort(out)
  return out
end

local lines_cache = {}
local function lines_of(file)
  if lines_cache[file] == nil then
    local ok, lines = pcall(vim.fn.readfile, store.root() .. '/' .. file)
    lines_cache[file] = ok and lines or false
  end
  return lines_cache[file] or nil
end

--- A definition of `symbol` in `lines`: `function M.start`, `local x =`,
--- `def start`, `class Start`, `start(...) {` and the like.
local function find_symbol(lines, symbol)
  local name = symbol:gsub('^.*[.:]', '')
  local esc = vim.pesc(name)
  local qual = vim.pesc(symbol)
  local patterns = {
    'function%s+' .. qual .. '%s*%(',
    'function%s+[%w_.:]*' .. esc .. '%s*%(',
    '[%w_.]*' .. esc .. '%s*=%s*function',
    'local%s+' .. esc .. '%s*=',
    'def%s+' .. esc .. '%f[^%w_]',
    'class%s+' .. esc .. '%f[^%w_]',
    'fn%s+' .. esc .. '%f[^%w_]',
    'func%s+[%w_()%s*]*' .. esc .. '%s*%(',
    'const%s+' .. esc .. '%f[^%w_]',
    'let%s+' .. esc .. '%f[^%w_]',
    'interface%s+' .. esc .. '%f[^%w_]',
    'type%s+' .. esc .. '%f[^%w_]',
    '^%s*' .. esc .. '%s*%(.*%)%s*{',
  }
  for _, p in ipairs(patterns) do
    for i, l in ipairs(lines) do
      if l:find(p) then
        return i
      end
    end
  end
end

--- A step's anchor, as a quoted line: { file, text, line, lines }.
local function anchor_of(raw)
  local file = raw.file
  if type(file) ~= 'string' or file == '' then
    return nil
  end
  local out = { file = file, line = tonumber(raw.line), lines = tonumber(raw.lines) }
  if type(raw.text) == 'string' and raw.text ~= '' then
    out.text = raw.text
    return out
  end
  local lines = lines_of(file)
  local at
  if lines and type(raw.symbol) == 'string' then
    at = find_symbol(lines, raw.symbol)
  end
  if lines and not at and type(raw.pattern) == 'string' then
    local ok, re = pcall(vim.regex, '\\v' .. raw.pattern)
    if ok then
      for i, l in ipairs(lines) do
        if re:match_str(l) then
          at = i
          break
        end
      end
    end
  end
  if lines and not at and type(raw.selection) == 'table' and type(raw.selection.start) == 'table' then
    at = tonumber(raw.selection.start.line)
  end
  at = at or out.line
  if lines and at and lines[at] then
    out.line, out.text = at, lines[at]
    return out
  end
  out.text = ''
  return out
end

--- A step's evidence and asides, as notes on the message.
local function notes_of(step)
  local out = {}
  for _, c in ipairs(type(step.comments) == 'table' and step.comments or {}) do
    local a = anchor_of(vim.tbl_extend('keep', c, { file = step.file }))
    if a then
      a.note = c.comment
      a.mark = c.mark
      if a.file == step.file then
        a.file = nil
      end
      out[#out + 1] = a
    end
  end
  for _, n in ipairs(type(step.notes) == 'table' and step.notes or {}) do
    local a = anchor_of(vim.tbl_extend('keep', n, { file = step.file }))
    if a then
      a.note = n.note
      if a.file == step.file then
        a.file = nil
      end
      out[#out + 1] = a
    end
  end
  return #out > 0 and out or nil
end

local function first_sentence(text)
  local s = vim.trim((text or ''):gsub('```.-```', ''))
  s = s:match '^(.-[.!?])%s' or s:match '^([^\n]*)' or s
  s = s:gsub('`', '')
  if vim.fn.strchars(s) > 60 then
    s = vim.fn.strcharpart(s, 0, 59) .. '…'
  end
  return s
end

--- Read a tour into the current batch as threads.
---@param name string|nil  without `.tour`; none asks
function M.run(name)
  if not name or name == '' then
    local names = M.names()
    if #names == 0 then
      return notify('no tours in ' .. config.options.tours .. '/')
    end
    vim.ui.select(names, { prompt = 'Import which tour?' }, function(pick)
      if pick then
        M.run(pick)
      end
    end)
    return
  end
  local path = tours_dir() .. '/' .. name:gsub('%.tour$', '') .. '.tour'
  local ok, text = pcall(vim.fn.readfile, path)
  if not ok then
    return notify('no tour at ' .. path, vim.log.levels.ERROR)
  end
  local dok, tour = pcall(vim.json.decode, table.concat(text, '\n'), { luanil = { object = true, array = true } })
  if not dok or type(tour) ~= 'table' or type(tour.steps) ~= 'table' then
    return notify(name .. ' does not parse as a tour', vim.log.levels.ERROR)
  end
  lines_cache = {}
  local batch = store.active(true)
  local id = store.next_id(batch)
  local function new(fields)
    fields.id = id
    fields.status = 'open'
    id = id + 1
    batch.data.threads[#batch.data.threads + 1] = fields
    return fields
  end

  -- The tour itself: its overview, leading to the stages.
  local overview = tour.overview
  local over_text = type(overview) == 'table' and overview.description or overview
  local intro = {}
  if type(tour.description) == 'string' and tour.description ~= '' then
    intro[#intro + 1] = tour.description
  end
  if type(over_text) == 'string' and over_text ~= '' then
    intro[#intro + 1] = over_text
  end
  local root_msg = { from = 'agent', text = table.concat(intro, '\n\n'), children = {} }
  if type(overview) == 'table' and type(overview.diagram) == 'table' then
    root_msg.diagram = overview.diagram
  end
  local root = new { title = tour.title or name, messages = { root_msg } }
  if type(tour.diff) == 'table' and not batch.data.diff then
    batch.data.diff = { base = tour.diff.base, head = tour.diff.head }
  end

  local stage_msg -- the current stage's message, which leads to its steps
  local steps, stages = 0, 0
  for _, step in ipairs(tour.steps) do
    if type(step.stage) == 'string' and step.stage ~= '' then
      stages = stages + 1
      local body = {}
      if type(step.point) == 'string' and step.point ~= '' then
        body[#body + 1] = '**' .. step.point .. '**'
      end
      if type(step.description) == 'string' and step.description ~= '' then
        body[#body + 1] = step.description
      end
      stage_msg = {
        from = 'agent',
        text = table.concat(body, '\n\n'),
        verdict = step.verdict,
        severity = step.severity,
        diagram = type(step.diagram) == 'table' and step.diagram or nil,
        children = {},
      }
      local stage = new { title = step.stage, messages = { stage_msg } }
      table.insert(root_msg.children, stage.id)
      -- A stage that is also on a line: its first step.
      if type(step.file) == 'string' and step.file ~= '' then
        local a = anchor_of(step)
        if a then
          steps = steps + 1
          local c = new(vim.tbl_extend('force', a, {
            title = step.title or first_sentence(step.description),
            messages = { { from = 'agent', text = step.description or '', notes = notes_of(step) } },
          }))
          table.insert(stage_msg.children, c.id)
        end
      end
    else
      local parent = stage_msg or root_msg
      local a = anchor_of(step)
      local msg = { from = 'agent', text = step.description or '', diagram = type(step.diagram) == 'table' and step.diagram or nil }
      local c
      if a then
        steps = steps + 1
        msg.notes = notes_of(step)
        c = new(vim.tbl_extend('force', a, {
          title = step.title or first_sentence(step.description),
          rev = step.side == 'old' and tour.diff and tour.diff.base or nil,
          messages = { msg },
        }))
      else
        c = new { title = step.title or first_sentence(step.description), messages = { msg } }
      end
      table.insert(parent.children, c.id)
    end
  end
  store.save(batch)
  store.notify()
  store.watch()
  notify(string.format('imported "%s": %d stage%s, %d step%s, as thread %d · %s walks it', root.title, stages, stages == 1 and '' or 's', steps, steps == 1 and '' or 's', root.id, require('thread.render').key 'walk' or ':Thread walk'))
  return root
end

return M
