--- A step: one place in a tour, on a chunk or on no line (drawn as a
--- page), with what it says, and the messages you and the agent write
--- about it. Walked or not is its state, kept by its content, so the agent
--- reordering steps keeps it.

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

--- A step's name in the .seen file: its title and where it is.
---@param s thread.Step
---@return string
function M.key(s)
  local c = s.chunk
  return vim.fn.sha256(s.title .. '\n' .. (c and (c.file .. '\n' .. c.text) or '')):sub(1, 16)
end

---@param r thread.Review
---@param t thread.Thread  the step's
---@param s thread.Step
---@return boolean
function M.walked(r, t, s)
  return seen.walked(r.id, tostring(t.id), M.key(s))
end

--- You have been to a step.
---@param r thread.Review
---@param t thread.Thread
---@param s thread.Step
---@return boolean changed
function M.walk(r, t, s)
  return seen.walk(r.id, tostring(t.id), M.key(s))
end

return M
