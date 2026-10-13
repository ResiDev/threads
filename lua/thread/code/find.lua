--- Finding threads in the code: the next one that wants you, in file and
--- line order; and after a save, a thread that moved quoted as its line
--- reads now.

local chunk = require 'thread.model.chunk'
local place = require 'thread.code.place'
local review = require 'thread.model.review'
local thread = require 'thread.model.thread'

local M = {}

---@class thread.Stop
---@field review thread.Review
---@field conversation thread.Conversation
---@field chunk thread.Chunk
---@field file string
---@field line integer

--- Every conversation with a line, in file and line order: those that
--- want you, or with `all` every open one.
---@param all boolean
---@return thread.Stop[]
function M.stops(all)
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
            out[#out + 1] = { review = r, conversation = c, chunk = ch, file = ch.file, line = at.line }
          end
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.file ~= b.file then
      return a.file < b.file
    end
    return a.line < b.line
  end)
  return out
end

--- The next (or previous) after a place, round the ends: one that wants
--- you, or with `all` any open one.
---@param d 1|-1
---@param all boolean
---@param where { file: string }|nil  the buffer's file
---@param line integer
---@return thread.Stop|nil
function M.next(d, all, where, line)
  local list = M.stops(all)
  if #list == 0 then
    return nil
  end
  local file = where and where.file or ''
  for i = d > 0 and 1 or #list, d > 0 and #list or 1, d do
    local s = list[i]
    local after = s.file > file or (s.file == file and s.line > line)
    local before = s.file < file or (s.file == file and s.line < line)
    if (d > 0 and after) or (d < 0 and before) then
      return s
    end
  end
  return d > 0 and list[1] or list[#list]
end

--- After a save, a thread found only by likeness, or moved, is quoted as
--- its line reads now. A step is the agent's to quote, and a removed line
--- stays as it was.
---@param buf integer
function M.requote(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local changed = {} ---@type table<thread.Review, true>
  for _, p in ipairs(place.locate(buf)) do
    local c = p.thread.chunk
    if not p.step and not p.gone and c and not c.rev and c.side ~= 'old' then
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
