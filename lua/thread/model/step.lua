--- A step: one place in a tour, on a chunk or on no line (drawn as a
--- page), with what it says, and the messages you and the agent write
--- about it. Walked or not is its state, kept under two names, so the
--- agent moving it, requoting it or retitling it keeps it.

local check = require 'thread.model.check'
local chunk = require 'thread.model.chunk'
local fields = require 'thread.model.fields'
local labels = require 'thread.model.labels'
local message = require 'thread.model.message'
local seen = require 'thread.store.seen'

local M = {}

---@class (exact) thread.Step: thread.Labels
---@field title string  its claim
---@field chunk thread.Chunk|nil  none: on no line, a page
---@field text string|nil
---@field notes thread.Note[]|nil
---@field diagram table|nil
---@field messages thread.Message[]  about this step
---@field checks thread.Check[]|nil

local FIELDS = vim.list_extend({ 'title', 'chunk', 'text', 'notes', 'diagram', 'messages', 'checks' }, labels.FIELDS)

---@param p thread.Problems
---@param where string
---@param raw any
---@return thread.Step|nil
function M.parse(p, where, raw)
  if not fields.object(p, where, raw, FIELDS) then
    return nil
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

--- How many of the thread's steps, up to `s`, are known by each thing.
---@param t thread.Thread
---@param s thread.Step
---@return table<string, integer>
local function counts(t, s)
  local n = {} ---@type table<string, integer>
  for _, m in ipairs(t.messages) do
    for _, x in ipairs(m.tours or {}) do
      for _, other in ipairs(x.steps) do
        for _, k in ipairs(known_by(other)) do
          n[k] = (n[k] or 0) + 1
        end
        if other == s then
          return n
        end
      end
    end
  end
  return n
end

--- A step's names in the .seen file, its conversation's too: `12/<quote>`
--- and `12/<title>`, or a page's `12/<title>` and `12/<text>`. What you
--- have walked and read of it is found by either, so the agent can
--- requote it after a change or retitle it; changing both at once starts
--- it over. A later step of the thread known by the same is told apart
--- by its place among them.
---@param t thread.Thread  the step's
---@param s thread.Step
---@return string[]
function M.names(t, s)
  local n = counts(t, s)
  return vim.tbl_map(function(k)
    return string.format('%d/%s%s', t.id, vim.fn.sha256(k):sub(1, 16), (n[k] or 1) > 1 and ('.' .. n[k]) or '')
  end, known_by(s))
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
