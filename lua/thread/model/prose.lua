--- Prose as the review holds it: markdown text, and diagrams beside it by
--- name, each placed in the text with `{{diagram:name}}`. A review's and a
--- tour's introduction, a step's text, a contract's page and every message
--- are prose. Reading the text into what is drawn is thread.prose.

local diagram = require 'thread.model.diagram'
local fields = require 'thread.model.fields'

local M = {}

---@class (exact) thread.Prose
---@field text string
---@field diagrams table<string, table>|nil  as written, by name

local FIELDS = { 'text', 'diagrams' }

-- Each diagram checked, by the table written: a copy with each node's
-- chunk's file beside it, which is never written back.
local checked = setmetatable({}, { __mode = 'k' }) ---@type table<table, table>

--- A name a diagram can have: what `{{diagram:name}}` finds.
M.NAME = '^[%w_.-]+$'

--- Prose, checked: text, and diagrams that each check (thread.model.diagram)
--- with its nodes on chunks `file` finds. `need`: it must be there.
---@param p thread.Problems
---@param where string
---@param raw table  what holds it
---@param name string  its field there
---@param file fun(id: string): string|nil  a chunk's file, by its id
---@param need boolean|nil
---@return thread.Prose|nil
function M.parse(p, where, raw, name, file, need)
  local v = raw[name]
  local at = where .. ', ' .. name
  if v == nil then
    if need then
      fields.bad(p, where, string.format('no `%s`', name))
    end
    return nil
  end
  if type(v) == 'string' then
    fields.bad(p, at, 'prose is an object, `{ "text": "..." }`, with its `diagrams` beside the text')
    raw[name] = nil
    return nil
  end
  if not fields.object(p, at, v, FIELDS) then
    raw[name] = nil
    return nil
  end
  if not fields.text(p, at, v, 'text', true) then
    v.text = v.text or ''
  end
  local diagrams = v.diagrams
  if diagrams ~= nil and (type(diagrams) ~= 'table' or vim.islist(diagrams) and next(diagrams) ~= nil) then
    fields.bad(p, at, '`diagrams` is an object: each diagram by its name')
    v.diagrams = nil
    return v
  end
  local names = vim.tbl_keys(diagrams or {})
  table.sort(names)
  for _, n in ipairs(names) do
    if not n:match(M.NAME) then
      fields.bad(p, at, string.format('the diagram "%s": a name is letters, digits, `-`, `_` and `.`, so `{{diagram:%s}}` finds it', n, n))
    end
    local d, err = diagram.validate(diagrams[n], file)
    if d then
      checked[diagrams[n]] = d
    else
      fields.bad(p, at .. ', diagram ' .. n, err or 'not a diagram')
    end
  end
  return v
end

--- A diagram of prose, by name, checked; nil when it has none by that
--- name, or it did not check.
---@param x thread.Prose|nil
---@param name string
---@return table|nil
function M.diagram(x, name)
  local raw = x and x.diagrams and x.diagrams[name]
  return raw and checked[raw] or nil
end

--- Prose of one paragraph: what a message of yours is.
---@param text string
---@return thread.Prose
function M.of(text)
  return { text = text }
end

--- Its text, or nothing.
---@param x thread.Prose|nil
---@return string
function M.text(x)
  return x and x.text or ''
end

--- What a line of prose places, alone on it: `{{chunk:id}}` or
--- `{{diagram:name}}`.
---@param line string
---@return 'chunk'|'diagram'|nil kind, string|nil name
function M.place(line)
  local kind, name = line:match '^%s*{{(%a+):([^}]*)}}%s*$'
  if kind == 'chunk' or kind == 'diagram' then
    return kind, vim.trim(name)
  end
  return nil, nil
end

--- The places it puts something, in order, outside code fences.
---@param x thread.Prose|nil
---@return { kind: 'chunk'|'diagram', name: string, line: integer }[]
function M.placed(x)
  local out = {}
  local n, ticks = 0, nil ---@type integer, integer|nil
  for line in (M.text(x) .. '\n'):gmatch '(.-)\r?\n' do
    n = n + 1
    -- As thread.prose reads fences: one opens on backticks and a word or
    -- none, and closes on as many or more alone on a line.
    if ticks then
      local close = line:match '^%s*(```+)%s*$'
      if close and #close >= ticks then
        ticks = nil
      end
    elseif line:match '^%s*```+%s*[^`]-%s*$' then
      ticks = #line:match '^%s*(```+)'
    else
      local kind, name = M.place(line)
      if kind and name then
        out[#out + 1] = { kind = kind, name = name, line = n }
      end
    end
  end
  return out
end

return M
