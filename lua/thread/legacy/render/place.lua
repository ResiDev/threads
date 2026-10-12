--- Where the threads sit in a buffer, and which one the cursor is on: the
--- one that lights up, lists its keys and shows its notes.

local source = require 'thread.base.source'
local on_lines = require 'thread.legacy.review.lines'
local store = require 'thread.legacy.store'
local tour = require 'thread.legacy.tour'

local M = {}

---@type table<integer, { thread: thread.Thread, line: integer, to: integer, confidence: number, stale: boolean|nil }[]>
M.placed = {} -- bufnr -> where its threads sat when last located
-- bufnr -> the thread the cursor is on: its id, how many cover the line,
-- whether it was picked by hand, whether all of it has been on screen.
local active = {}

--- Where the active batch's threads sit in a buffer. An open thread whose
--- line is gone sits where its line was, marked stale.
---@param bufnr integer
---@return { thread: thread.Thread, line: integer, to: integer, confidence: number, stale: boolean|nil }[]
function M.locate(bufnr)
  local where = source.of_buf(bufnr)
  local batch = where and store.active()
  if not batch then
    return {}
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local out = {}
  -- Every thread, but a reply in a tour's step is drawn as that step's card
  -- with the conversation in it, and every step no one replied in too.
  local all = {}
  for _, c in ipairs(batch.data.threads) do
    if not (type(c.on) == 'table' and store.anchored(c)) then
      all[#all + 1] = c
    end
  end
  -- While walking, the other tours' stops no one replied in are hidden.
  local walk = require('thread.legacy.walk').state()
  for _, c in ipairs(tour.cards(batch)) do
    if not (walk and c.virtual and c.stop.owner ~= walk.owner) then
      all[#all + 1] = c
    end
  end
  for _, c in ipairs(all) do
    if source.belongs(c, where) then
      local loc = on_lines.locate(c, lines)
      if loc then
        out[#out + 1] = {
          thread = c,
          line = loc.line,
          to = math.min(#lines, loc.line + (c.lines or 1) - 1),
          confidence = loc.confidence,
        }
      elseif store.status(c) ~= 'closed' and not c.virtual and #lines > 0 then
        local line = math.max(1, math.min(#lines, c.line or 1))
        out[#out + 1] = { thread = c, line = line, to = line, confidence = 0, stale = true }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.line ~= b.line then
      return a.line < b.line
    end
    return tostring(a.thread.id) < tostring(b.thread.id)
  end)
  return out
end

--- The threads covering `lnum`, innermost first: the smallest range, then
--- the one starting latest.
---@param placed table[]
---@param lnum integer
---@return table[]
function M.covering(placed, lnum)
  local out = {}
  for _, p in ipairs(placed) do
    if lnum >= p.line and lnum <= p.to then
      out[#out + 1] = p
    end
  end
  table.sort(out, function(a, b)
    local sa, sb = a.to - a.line, b.to - b.line
    if sa ~= sb then
      return sa < sb
    end
    if a.line ~= b.line then
      return a.line > b.line
    end
    -- A conversation before a card no one has replied in.
    if (a.thread.virtual or false) ~= (b.thread.virtual or false) then
      return not a.thread.virtual
    end
    return tostring(a.thread.id) < tostring(b.thread.id)
  end)
  return out
end

--- Mark a thread read once its bubble has shown you all of it: when the
--- cursor leaves it, so what was new stays marked while you read.
local function leave_active(bufnr)
  local a = active[bufnr]
  if not (a and a.full) then
    return
  end
  local batch = store.active()
  local c = batch and store.find(batch, a.id)
  if c then
    store.mark_seen(batch, c)
  end
end

--- Work out which thread the cursor is on in `bufnr`; true if it changed.
---@param bufnr integer
---@return boolean
function M.track(bufnr)
  local placed = M.placed[bufnr]
  local win = vim.api.nvim_get_current_win()
  local now
  if placed and require('thread.legacy.render').visible() and vim.api.nvim_win_get_buf(win) == bufnr then
    local here = M.covering(placed, vim.api.nvim_win_get_cursor(win)[1])
    if #here > 0 then
      local keep = active[bufnr]
      -- Stay on the one picked (by focusing it, say) while it still covers
      -- the line; else the innermost.
      local pick = here[1]
      for _, p in ipairs(here) do
        if keep and p.thread.id == keep.id and keep.pinned then
          pick = p
        end
      end
      now = { id = pick.thread.id, here = #here, pinned = keep and keep.pinned and keep.id == pick.thread.id }
    end
  end
  local before = active[bufnr]
  if (before and before.id) == (now and now.id) and (before and before.here) == (now and now.here) then
    return false
  end
  if before and (not now or now.id ~= before.id) then
    leave_active(bufnr)
  end
  active[bufnr] = now
  return true
end

--- The thread the cursor is on in the current buffer, and how many cover
--- the line.
---@return thread.Thread|nil, integer
function M.at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  if not M.placed[buf] then
    M.placed[buf] = M.locate(buf)
  end
  M.track(buf)
  local a = active[buf]
  if not a then
    -- Hidden bubbles still have threads under them.
    local here = M.covering(M.placed[buf], vim.api.nvim_win_get_cursor(0)[1])
    return here[1] and here[1].thread, #here
  end
  for _, p in ipairs(M.placed[buf]) do
    if p.thread.id == a.id then
      return p.thread, a.here
    end
  end
  return nil, 0
end

--- Make another of the threads on the cursor's line the current one.
---@param n integer
---@return thread.Thread|nil
function M.cycle(n)
  local buf = vim.api.nvim_get_current_buf()
  local placed = M.placed[buf] or {}
  local here = M.covering(placed, vim.api.nvim_win_get_cursor(0)[1])
  if #here == 0 then
    return nil
  end
  local at = 1
  for i, p in ipairs(here) do
    if active[buf] and p.thread.id == active[buf].id then
      at = i
    end
  end
  local pick = here[(at - 1 + n) % #here + 1]
  leave_active(buf)
  active[buf] = { id = pick.thread.id, here = #here, pinned = true }
  return pick.thread
end

--- The thread the cursor is on in a buffer, as last tracked.
---@param bufnr integer
---@return { id: any, here: integer, pinned: boolean|nil, full: boolean|nil }|nil
function M.current(bufnr)
  return active[bufnr]
end

return M
