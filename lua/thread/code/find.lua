--- Finding threads in the code: the next conversation that wants you, in
--- file, line and key order; and after a save, a thread that moved quoted
--- as its line reads now.

local chunk = require 'thread.model.chunk'
local place = require 'thread.code.place'
local review = require 'thread.model.review'
local thread = require 'thread.model.thread'

local M = {}

--- A conversation found on a line.
---@class thread.Found
---@field review thread.Review
---@field conversation thread.Conversation
---@field chunk thread.Chunk
---@field file string
---@field line integer
---@field key string  its thread's or step's, as thread.code.place keys it

--- Every conversation on a line, in file, line and key order: those that
--- want you, or with `all` every open one.
---@param all boolean
---@return thread.Found[]
function M.list(all)
  local out = {}
  for _, r in ipairs((review.list())) do
    if r.status == 'open' then
      local spec = chunk.spec(r.diff)
      for _, t in ipairs(r.threads) do
        for _, c in ipairs(thread.conversations(t)) do
          local ch = c.step and c.step.chunk or (not c.step and t.chunk)
          local wanted = all and not thread.closed(t) and (not c.step or #c.messages > 0) or (not all and thread.for_you(r, c))
          local at = ch and wanted and chunk.locate(ch, spec)
          if ch and at then
            out[#out + 1] = { review = r, conversation = c, chunk = ch, file = ch.file, line = at.line, key = place.key(r, t, c.step) }
          end
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.file ~= b.file then
      return a.file < b.file
    end
    if a.line ~= b.line then
      return a.line < b.line
    end
    return a.key < b.key
  end)
  return out
end

--- The next (or previous) after a place, round the ends: one that wants
--- you, or with `all` any open one. On a line several are on, from the
--- one you are on to the next of them.
---@param d 1|-1
---@param all boolean
---@param where { file: string }|nil  the buffer's file
---@param line integer
---@param key string|nil  the one you are on, on that line
---@return thread.Found|nil
function M.next(d, all, where, line, key)
  local list = M.list(all)
  if #list == 0 then
    return nil
  end
  local file = where and where.file or ''
  for i = d > 0 and 1 or #list, d > 0 and #list or 1, d do
    local s = list[i]
    local here = s.file == file and s.line == line and key ~= nil
    local after = s.file > file or (s.file == file and s.line > line) or (here and s.key > key)
    local before = s.file < file or (s.file == file and s.line < line) or (here and s.key < key)
    if (d > 0 and after) or (d < 0 and before) then
      return s
    end
  end
  return d > 0 and list[1] or list[#list]
end

--- After a save, a thread found only by likeness, or moved, is quoted as
--- its line reads now. A step is the agent's to quote, a removed line
--- stays as it was, and so does a blank line: it is found by its number
--- alone, so the line at that number now may be any other.
---@param buf integer
function M.requote(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local changed = {} ---@type table<thread.Review, true>
  for _, p in ipairs(place.locate(buf)) do
    local c = p.thread.chunk
    if not p.step and not p.gone and c and not c.rev and c.side ~= 'old' and not c.text:match '^%s*$' then
      local now = lines[p.line]
      if now and (c.line ~= p.line or c.text ~= now) then
        c.line, c.text = p.line, now
        changed[p.review] = true
      end
    end
  end
  for r in pairs(changed) do
    review.save(r)
  end
end

return M
