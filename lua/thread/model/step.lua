--- A step: a claim about the code at its chunk, or on no chunk a page,
--- for one idea in many places; with its prose and a conversation. Its
--- id never changes, so walked or not, its state, is kept under it.

local fields = require 'thread.model.fields'
local message = require 'thread.model.message'
local prose = require 'thread.model.prose'
local seen = require 'thread.store.seen'

local M = {}

---@class (exact) thread.Step
---@field id integer
---@field title string  its claim
---@field text thread.Prose|nil
---@field chunk string|nil  its chunk's id; none: a page
---@field messages thread.Message[]

--- What a review gives what it reads, to find its chunks by id.
---@class thread.ParseContext
---@field file fun(id: string): string|nil  a chunk's file, by its id; nil when there is none
---@field refer fun(where: string, field: string, id: any)  a chunk pointed at: said when it is not one

local FIELDS = { 'id', 'title', 'text', 'chunk', 'messages' }

local GONE = {
  kind = 'a step is a claim; what kind of change it is goes in its tour or its text',
  severity = 'an issue about a step\'s code is a note of `kind` "issue" on the same chunk',
}

---@param p thread.Problems
---@param where string
---@param raw any
---@param ctx thread.ParseContext
---@return thread.Step|nil
function M.parse(p, where, raw, ctx)
  if not fields.object(p, where, raw, FIELDS, GONE) then
    return nil
  end
  fields.count(p, where, raw, 'id', true)
  fields.text(p, where, raw, 'title', true)
  if not prose.parse(p, where, raw, 'text', ctx.file) and raw.chunk == nil then
    fields.warn(p, where, 'a page with no `text`: it says nothing but its title')
  end
  if raw.chunk ~= nil then
    ctx.refer(where, 'chunk', raw.chunk)
  end
  raw.messages = fields.list(p, where, raw, 'messages') or {}
  for i, m in ipairs(raw.messages) do
    message.parse(p, where .. ', message ' .. i, m, ctx)
  end
  return raw
end

--- Its name in the .seen file, its conversation's too: `step:7`.
---@param s thread.Step
---@return string
function M.name(s)
  return 'step:' .. s.id
end

---@param r thread.Review
---@param s thread.Step
---@return boolean
function M.walked(r, s)
  return seen.walked(r.id, M.name(s))
end

--- You have been to a step.
---@param r thread.Review
---@param s thread.Step
---@return boolean changed
function M.walk(r, s)
  return seen.walk(r.id, M.name(s))
end

return M
