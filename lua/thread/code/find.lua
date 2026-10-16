--- Finding steps and notes in the code: the next conversation that
--- wants you, in file, line and key order; and after a save, a note of
--- yours that moved quoted as its lines read now.

local chunk = require 'thread.model.chunk'
local conversation = require 'thread.model.conversation'
local note = require 'thread.model.note'
local place = require 'thread.code.place'
local review = require 'thread.model.review'

local M = {}

--- A conversation found on a line.
---@class thread.Found
---@field review thread.Review
---@field conversation thread.Conversation
---@field chunk thread.Chunk
---@field file string
---@field line integer
---@field key string  its step's or note's, as thread.code.place keys it

--- Every conversation on a line, in file, line and key order: those that
--- want you, or with `all` every one with something said in it, of a
--- note not settled.
---@param all boolean
---@return thread.Found[]
function M.list(all)
  local out = {}
  for _, r in ipairs((review.list())) do
    if r.status == 'open' then
      local spec = chunk.spec(r.diff)
      ---@param c thread.Conversation
      ---@param id string|nil
      ---@param key string
      local function put(c, id, key)
        local ch = review.chunk(r, id)
        local wanted = all and #c.messages > 0 and not conversation.closed(c) or (not all and conversation.for_you(r, c))
        local at = ch and wanted and chunk.now(ch, spec)
        if ch and at then
          out[#out + 1] = { review = r, conversation = c, chunk = ch, file = ch.file, line = at.line, key = key }
        end
      end
      for _, x in ipairs(r.tours) do
        for _, s in ipairs(x.steps) do
          put(conversation.of_step(s, x), s.chunk, place.key(r, s, 'step'))
        end
      end
      for _, n in ipairs(r.notes) do
        put(conversation.of_note(n), n.chunk, place.key(r, n, 'note'))
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

--- After a save, a note of yours on lines as they are now (the chunk
--- starting it made, read at `now`), found only by likeness or moved, is
--- quoted as its lines read now. Anything else is the agent's to quote, and a blank
--- first line stays: it is found by its number alone, so the line at that
--- number now may be any other.
---@param buf integer
function M.requote(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local changed = {} ---@type table<thread.Review, true>
  for _, p in ipairs(place.locate(buf)) do
    local c = p.chunk
    -- Its own chunk, as starting it made: one the agent wrote may be
    -- pointed at by a step or a contract too, and is the agent's to quote.
    local mine = p.note
      and p.note.messages[1]
      and p.note.messages[1].from == 'you'
      and not note.closed(p.note)
      and c.id:match('^note%-' .. p.note.id .. '%f[^%d]') ~= nil
    if mine and not p.gone and c.rev == 'now' and not c.from:match '^%s*$' then
      local first, last = lines[p.line], p.to > p.line and lines[p.to] or nil
      if first and (c.line ~= p.line or c.from ~= first or (c.to and c.to ~= last)) then
        c.line, c.from = p.line, first
        c.to = c.to and last or nil
        changed[p.review] = true
      end
    end
  end
  for r in pairs(changed) do
    review.save(r)
  end
end

return M
