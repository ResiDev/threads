--- A check: what the agent ran to confirm something works, said in some
--- text, and the bash line it ran, for you to run too.

local fields = require 'thread.model.fields'

local M = {}

---@class (exact) thread.Check
---@field text string  what it ran, and what it got
---@field run string   the line, as typed in a shell

local FIELDS = { 'text', 'run' }

---@param p thread.Problems
---@param where string
---@param raw any
---@return thread.Check|nil
function M.parse(p, where, raw)
  if not fields.object(p, where, raw, FIELDS) then
    return nil
  end
  fields.text(p, where, raw, 'text', true)
  fields.text(p, where, raw, 'run', true)
  return raw
end

return M
