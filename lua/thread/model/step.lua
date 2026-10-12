--- A step: one place in a tour, on a chunk or on no line (drawn as a
--- page), with what it says, and the messages you and the agent write
--- about it. Walked or not is its state, kept by its chunk, so the agent
--- moving or retitling it keeps it.

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

--- What a step is known by: its chunk, or its title when it is on no line.
---@param s thread.Step
---@return string
local function known_by(s)
  local c = s.chunk
  return c and table.concat({ c.file, c.side or '', c.text }, '\n') or s.title
end

--- A step's name in the .seen file. It is known by its chunk, or by its
--- title when it is on no line, so the agent moving it or retitling it
--- keeps it. A later step of the thread on the same chunk is told apart
--- by its place among them.
---@param t thread.Thread  the step's
---@param s thread.Step
---@return string
function M.key(t, s)
  local mine, n = known_by(s), 0
  for _, m in ipairs(t.messages) do
    for _, x in ipairs(m.tours or {}) do
      for _, other in ipairs(x.steps) do
        n = n + (known_by(other) == mine and 1 or 0)
        if other == s then
          return vim.fn.sha256(mine):sub(1, 16) .. (n > 1 and ('.' .. n) or '')
        end
      end
    end
  end
  return vim.fn.sha256(mine):sub(1, 16)
end

---@param r thread.Review
---@param t thread.Thread  the step's
---@param s thread.Step
---@return boolean
function M.walked(r, t, s)
  return seen.walked(r.id, tostring(t.id), M.key(t, s))
end

--- You have been to a step.
---@param r thread.Review
---@param t thread.Thread
---@param s thread.Step
---@return boolean changed
function M.walk(r, t, s)
  return seen.walk(r.id, tostring(t.id), M.key(t, s))
end

return M
