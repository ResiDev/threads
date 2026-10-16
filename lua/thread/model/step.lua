--- A step: one place in a tour, on a chunk or on no line (drawn as a
--- page), with what it says, and the messages you and the agent write
--- about it. Its id is its number, which links name: in its thread, or
--- in format 3 among the review's steps. Walked or not is its state,
--- kept under two names, so the agent moving it, requoting it or
--- retitling it keeps it; in format 3 under its id first, which never
--- changes.

local check = require 'thread.model.check'
local chunk = require 'thread.model.chunk'
local fields = require 'thread.model.fields'
local labels = require 'thread.model.labels'
local message = require 'thread.model.message'
local seen = require 'thread.store.seen'

local M = {}

---@class (exact) thread.Step: thread.Labels
---@field id integer    its number in its thread, across its tours, or in format 3 the review's: the highest there plus one, never changed
---@field title string  its claim
---@field chunk thread.Chunk|nil  none: on no line, a page
---@field text string|nil
---@field diagram table|nil
---@field messages thread.Message[]  about this step
---@field checks thread.Check[]|nil

-- `notes`, marks on lines from before they went, is read only to be
-- dropped (thread.model.message.parse_extras).
local FIELDS = vim.list_extend({ 'id', 'title', 'chunk', 'text', 'notes', 'diagram', 'messages', 'checks' }, labels.FIELDS)

---@param p thread.Problems
---@param where string
---@param raw any
---@return thread.Step|nil
function M.parse(p, where, raw)
  if not fields.object(p, where, raw, FIELDS) then
    return nil
  end
  if raw.id == nil then
    fields.bad(p, where, 'no `id`: number it the highest step id in its thread plus one')
  else
    fields.count(p, where, raw, 'id')
  end
  fields.text(p, where, raw, 'title', true)
  if raw.chunk ~= nil then
    chunk.parse(p, where .. ', chunk', raw.chunk)
  end
  if not fields.text(p, where, raw, 'text') then
    fields.warn(p, where, 'no `text`')
  end
  labels.parse(p, where, raw)
  message.parse_extras(p, where, raw)
  raw.messages = fields.list(p, where, raw, 'messages') or {}
  for i, m in ipairs(raw.messages) do
    local mwhere = where .. ', message ' .. i
    if message.parse(p, mwhere, m) and m.tours ~= nil then
      fields.bad(p, mwhere, "a step's messages carry no tours: the back and forth stops a level down")
    end
  end
  for i, c in ipairs(fields.list(p, where, raw, 'checks') or {}) do
    check.parse(p, where .. ', check ' .. i, c)
  end
  return raw
end

--- What a step is known by: on code, its quote and its title; on no
--- line, its title and its text.
---@param s thread.Step
---@return string[]
local function known_by(s)
  local c = s.chunk
  if c then
    return { 'quote\n' .. table.concat({ c.file, c.side or '', c.text }, '\n'), 'title\n' .. s.title }
  end
  local out = { 'title\n' .. s.title }
  if s.text then
    out[2] = 'text\n' .. s.text
  end
  return out
end

--- How many of the thread's steps are known by each thing: all of them,
--- and those up to `s`.
---@param t thread.Thread
---@param s thread.Step
---@return table<string, integer> all, table<string, integer> before
local function counts(t, s)
  local all, before, past = {}, {}, false ---@type table<string, integer>, table<string, integer>, boolean
  for _, m in ipairs(t.messages) do
    for _, x in ipairs(m.tours or {}) do
      for _, other in ipairs(x.steps) do
        for _, k in ipairs(known_by(other)) do
          all[k] = (all[k] or 0) + 1
          before[k] = (before[k] or 0) + (past and 0 or 1)
        end
        past = past or other == s
      end
    end
  end
  return all, before
end

--- A step's names in the .seen file, its conversation's too: `12/<quote>`
--- and `12/<title>`, or a page's `12/<title>` and `12/<text>`. What you
--- have walked and read of it is found by either, so the agent can
--- requote it after a change or retitle it; changing both at once starts
--- it over. A name another step of the thread goes by too tells neither
--- apart, so it is dropped: steps on one chunk go by their titles. Only a
--- step with no name of its own is told apart by its place among those
--- known by the same.
---
--- In format 3 a step goes by `step:7` first, its id, which never
--- changes; the names above follow, which it went by before, so what you
--- walked and read under them is found and copied to it
--- (thread.store.seen.join).
---@param t thread.Thread  the step's
---@param s thread.Step
---@return string[]
function M.names(t, s)
  local all, before = counts(t, s)
  local mine = known_by(s)
  local own = vim.tbl_filter(function(k)
    return all[k] == 1
  end, mine)
  local out = vim.tbl_map(function(k)
    local n = #own > 0 and 1 or before[k]
    return string.format('%d/%s%s', t.id, vim.fn.sha256(k):sub(1, 16), n > 1 and ('.' .. n) or '')
  end, #own > 0 and own or mine)
  if t.carrier then
    table.insert(out, 1, 'step:' .. s.id)
  end
  return out
end

---@param r thread.Review
---@param t thread.Thread  the step's
---@param s thread.Step
---@return boolean
function M.walked(r, t, s)
  return seen.walked(r.id, M.names(t, s))
end

--- You have been to a step.
---@param r thread.Review
---@param t thread.Thread
---@param s thread.Step
---@return boolean changed
function M.walk(r, t, s)
  return seen.walk(r.id, M.names(t, s))
end

return M
