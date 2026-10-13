--- Where the threads and steps of every open review sit in a buffer, and
--- which of them covers a line. A thread that is closed is not in the
--- code; one whose line is gone sits where its line was, saying so.

local chunk = require 'thread.model.chunk'
local review = require 'thread.model.review'
local source = require 'thread.base.source'
local thread = require 'thread.model.thread'

local M = {}

--- A thread or a step, where it sits in a buffer.
---@class thread.Placed
---@field review thread.Review
---@field thread thread.Thread
---@field tour thread.Tour|nil  a step's
---@field step thread.Step|nil
---@field line integer  its first line, 1-based
---@field to integer    its last
---@field gone boolean|nil  its line is not in the code: it sits where it was
---@field old integer|nil    on a line its review's diff removed: that line's number in the old side
---@field key string    the same thread or step, drawn again: `<review>#12`, `<review>#12.3`

--- Its key: the same thread or step, wherever it is drawn.
---@param r thread.Review
---@param t thread.Thread
---@param s thread.Step|nil
---@return string
function M.key(r, t, s)
  return r.id .. '#' .. t.id .. (s and ('.' .. s.id) or '')
end

--- Everything placed in a buffer, by its first line, threads before
--- steps on the same line.
---@param buf integer
---@return thread.Placed[]
function M.locate(buf)
  local where = source.of_buf(buf)
  if not where then
    return {}
  end
  local count = vim.api.nvim_buf_line_count(buf)
  local out = {} ---@type thread.Placed[]
  for _, r in ipairs((review.list())) do
    if r.status == 'open' then
      local spec = chunk.spec(r.diff)
      ---@param t thread.Thread
      ---@param c thread.Chunk
      ---@param x thread.Tour|nil
      ---@param s thread.Step|nil
      local function put(t, c, x, s)
        if not source.belongs(c, where) then
          return
        end
        local at = chunk.locate(c, spec)
        -- A step whose line is gone is not drawn; a thread says so.
        if not at and s then
          return
        end
        local line = at and at.line or math.max(1, math.min(count, c.line))
        local to = (not at or at.old) and line or math.min(count, line + (c.lines or 1) - 1)
        out[#out + 1] = { review = r, thread = t, tour = x, step = s, key = M.key(r, t, s), line = line, to = to, gone = not at or nil, old = at and at.old }
      end
      for _, t in ipairs(r.threads) do
        if not thread.closed(t) then
          if t.chunk then
            put(t, t.chunk)
          end
          for _, x in ipairs(thread.tours(t)) do
            for _, s in ipairs(x.steps) do
              if s.chunk then
                put(t, s.chunk, x, s)
              end
            end
          end
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.line ~= b.line then
      return a.line < b.line
    end
    if (a.step == nil) ~= (b.step == nil) then
      return a.step == nil
    end
    return a.key < b.key
  end)
  return out
end

--- What covers a line, innermost first: the fewest lines, then the one
--- starting latest, a thread before a step.
---@param placed thread.Placed[]
---@param line integer
---@return thread.Placed[]
function M.covering(placed, line)
  local out = {} ---@type thread.Placed[]
  for _, p in ipairs(placed) do
    if line >= p.line and line <= p.to then
      out[#out + 1] = p
    end
  end
  table.sort(out, function(a, b)
    if a.to - a.line ~= b.to - b.line then
      return a.to - a.line < b.to - b.line
    end
    if a.line ~= b.line then
      return a.line > b.line
    end
    if (a.step == nil) ~= (b.step == nil) then
      return a.step == nil
    end
    return a.key < b.key
  end)
  return out
end

return M
