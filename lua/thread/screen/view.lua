--- What the screen shows at each depth, drawn into a sheet: the reviews,
--- the one you are on opened under its line, two rows a thread; a
--- review's overview; a thread whole, its steps as blocks of code or its
--- chunks by file; a step whole, its tour's outline under it.

local draw = require 'thread.draw'
local review = require 'thread.model.review'
local review_draw = require 'thread.draw.review'
local step_draw = require 'thread.draw.step'
local text = require 'thread.base.text'
local thread = require 'thread.model.thread'
local thread_draw = require 'thread.draw.thread'
local tour_draw = require 'thread.draw.tour'

local M = {}

-- Columns either side of what is drawn.
M.INDENT = 2

---@class thread.HomeOpts
---@field width integer
---@field focus string|nil  the review you are on: its open threads show under it
---@field query string|nil  only what mentions it, every review's threads shown
---@field show 'open'|'closed'|'all'  which reviews

--- How the screen draws a review or a thread: what is opened, and
--- whether its chunks are laid out by file.
---@class thread.ViewOpts
---@field width integer
---@field open table<string, true>
---@field files boolean

--- Whether `s` says `q`, case aside.
---@param s string|nil
---@param q string
---@return boolean
local function says(s, q)
  return s ~= nil and s:lower():find(q:lower(), 1, true) ~= nil
end

--- Whether a thread says `q`: its title, or anything written in it.
---@param t thread.Thread
---@param q string
---@return boolean
local function mentions(t, q)
  if says(t.title, q) then
    return true
  end
  for _, c in ipairs(thread.conversations(t)) do
    if c.step and (says(c.step.title, q) or says(c.step.text, q)) then
      return true
    end
    for _, m in ipairs(c.messages) do
      if says(m.text, q) then
        return true
      end
    end
  end
  return false
end

--- The reviews, a line each, the one you are on with its open threads
--- under it; those that cannot be read last, saying why.
---@param P thread.Sheet
---@param o thread.HomeOpts
---@return thread.Part[]
function M.home(P, o)
  local list, broken = review.list()
  local out = {} ---@type thread.Part[]
  P.add ''
  for _, r in ipairs(list) do
    local closed = r.status == 'closed'
    if o.show == 'all' or (o.show == 'closed') == closed then
      local threads = {} ---@type thread.Thread[]
      for _, t in ipairs(r.threads) do
        if not thread.closed(t) and (not o.query or mentions(t, o.query)) then
          threads[#threads + 1] = t
        end
      end
      if not o.query or says(r.title, o.query) or says(r.introduction, o.query) or #threads > 0 then
        if #out > 0 then
          P.add ''
        end
        out[#out + 1] = review_draw.line(P, r, { width = o.width, indent = M.INDENT })
        if o.focus == r.id or o.query then
          local ids = 0
          for _, t in ipairs(threads) do
            ids = math.max(ids, #tostring(t.id))
          end
          for _, t in ipairs(threads) do
            P.add ''
            local p = thread_draw.row(P, r, t, { width = o.width - 2, indent = M.INDENT + 2, ids = ids })
            p.review = r
            out[#out + 1] = p
          end
        end
      end
    end
  end
  local ids = vim.tbl_keys(broken)
  table.sort(ids)
  for _, id in ipairs(ids) do
    review_draw.broken(P, id, broken[id][1] or '', { width = o.width, indent = M.INDENT })
  end
  if #out == 0 and #ids == 0 then
    local none = o.query and ('Nothing mentions “' .. o.query .. '”.')
      or o.show == 'closed' and 'No review is closed.'
      or 'No reviews yet. Start a thread on a line, or ask the agent for a review.'
    P.chunks({ { text.fit(none, o.width), 'ThreadMeta' } }, M.INDENT)
  end
  return out
end

--- A review's overview.
---@param P thread.Sheet
---@param r thread.Review
---@param o thread.ViewOpts
---@return thread.Part[]
function M.review(P, r, o)
  P.add ''
  return review_draw.overview(P, r, { width = o.width, indent = M.INDENT, open = o.open, files = o.files })
end

--- A thread whole.
---@param P thread.Sheet
---@param r thread.Review
---@param t thread.Thread
---@param o thread.ViewOpts
---@return thread.Part[]
function M.thread(P, r, t, o)
  P.add ''
  local out = thread_draw.whole(P, r, t, { width = o.width, indent = M.INDENT, open = o.open, files = o.files })
  draw.within(out, 1, { review = r })
  return out
end

--- A step whole, then its tour's outline, the step marked in it.
---@param P thread.Sheet
---@param r thread.Review
---@param t thread.Thread
---@param x thread.Tour
---@param s thread.Step
---@param width integer
---@return thread.Part[]
function M.step(P, r, t, x, s, width)
  P.add ''
  local out = step_draw.whole(P, r, t, x, s, { width = width, indent = M.INDENT })
  P.add ''
  vim.list_extend(out, tour_draw.outline(P, r, t, x, { width = width, indent = M.INDENT, here = s }))
  for _, p in ipairs(out) do
    if p.kind == 'step' or (p.kind == 'message' and p.step == s) or p.kind == 'check' then
      p.item = true
    end
  end
  draw.within(out, 1, { review = r })
  return out
end

return M
