--- Finding steps and threads in the code: the next conversation that
--- wants you, in file, line and key order; and after a save, a thread of
--- yours that moved quoted as its lines read now.

local chunk = require 'thread.model.chunk'
local conversation = require 'thread.model.conversation'
local thread = require 'thread.model.thread'
local place = require 'thread.code.place'
local topic = require 'thread.model.topic'

local M = {}

--- A conversation found on a line.
---@class thread.Found
---@field topic thread.Topic
---@field conversation thread.Conversation
---@field chunk thread.Chunk
---@field file string
---@field line integer
---@field key string  its step's or thread's, as thread.code.place keys it

--- Where a key goes among those on one line: a thread before a step, as
--- thread.code.place has them, then by key.
---@param key string
---@return string
local function order(key)
  return (key:find('#step:', 1, true) and '1' or '0') .. key
end

--- Every conversation on a line, in file, line and key order: those that
--- want you, or with `all` every one with something said in it, of a
--- thread not settled.
---@param all boolean
---@return thread.Found[]
function M.list(all)
  local out = {}
  for _, r in ipairs((topic.list())) do
    if r.status == 'open' then
      local spec = chunk.spec(r.diff)
      ---@param c thread.Conversation
      ---@param id string|nil
      ---@param key string
      local function put(c, id, key)
        local ch = topic.chunk(r, id)
        local wanted = all and #c.messages > 0 and not conversation.closed(c) or (not all and conversation.for_you(r, c))
        local at = ch and wanted and chunk.now(ch, spec)
        if ch and at then
          out[#out + 1] = { topic = r, conversation = c, chunk = ch, file = ch.file, line = at.line, key = key }
        end
      end
      for _, x in ipairs(r.tours) do
        for _, s in ipairs(x.steps) do
          put(conversation.of_step(s, x), s.chunk, place.key(r, s, 'step'))
        end
      end
      for _, n in ipairs(r.threads) do
        put(conversation.of_thread(n), n.chunk, place.key(r, n, 'thread'))
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
    return order(a.key) < order(b.key)
  end)
  return out
end

--- The thread after (or before) `n` in its topic, as the topic lists
--- them, that is in the code: not settled, and on lines found there.
--- Nil past the last, or before the first.
---@param r thread.Topic
---@param n thread.Thread
---@param d 1|-1
---@return { thread: thread.Thread, chunk: thread.Chunk }|nil
function M.beside(r, n, d)
  local spec = chunk.spec(r.diff)
  local at = 0
  for i, other in ipairs(r.threads) do
    at = other == n and i or at
  end
  for i = at + d, d > 0 and #r.threads or 1, d do
    local other = r.threads[i]
    local c = topic.chunk(r, other.chunk)
    if c and not thread.closed(other) and chunk.now(c, spec) then
      return { thread = other, chunk = c }
    end
  end
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
    local after = s.file > file or (s.file == file and s.line > line) or (here and order(s.key) > order(key or ''))
    local before = s.file < file or (s.file == file and s.line < line) or (here and order(s.key) < order(key or ''))
    if (d > 0 and after) or (d < 0 and before) then
      return s
    end
  end
  return d > 0 and list[1] or list[#list]
end

--- After a save, a thread of yours on lines as they are now (the chunk
--- starting it made, read at `now`), found only by likeness or moved, is
--- quoted as its lines read now. Anything else is the agent's to quote, and a blank
--- first line stays: it is found by its number alone, so the line at that
--- number now may be any other.
---@param buf integer
function M.requote(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local changed = {} ---@type table<thread.Topic, true>
  for _, p in ipairs(place.locate(buf)) do
    local c = p.chunk
    -- Its own chunk, as starting it made: one the agent wrote may be
    -- pointed at by a step or a contract too, and is the agent's to quote.
    local mine = p.thread
      and p.thread.messages[1]
      and p.thread.messages[1].from == 'you'
      and not thread.closed(p.thread)
      and c.id:match('^thread%-' .. p.thread.id .. '%f[^%d]') ~= nil
    if mine and not p.gone and c.rev == 'now' and not c.from:match '^%s*$' then
      local first, last = lines[p.line], p.to > p.line and lines[p.to] or nil
      if first and (c.line ~= p.line or c.from ~= first or (c.to and c.to ~= last)) then
        c.line, c.from = p.line, first
        c.to = c.to and last or nil
        changed[p.topic] = true
      end
    end
  end
  for r in pairs(changed) do
    topic.save(r)
  end
end

return M
