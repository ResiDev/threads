--- What the screen shows at each depth, drawn into a sheet: the reviews,
--- each with as many of its threads under it as the fold says; a
--- review's overview; a thread whole, its steps as blocks of code or its
--- chunks by file; a contract's page; a step whole, its tour's outline
--- under it.

local contract_draw = require 'thread.draw.contract'
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
---@field query string|nil  only what mentions it, every review's threads shown
---@field show 'open'|'closed'|'all'  which reviews
---@field fold thread.Fold|nil  how many of its threads each review shows; else 'some'

--- How much of each review Home shows: none of its threads; the first
--- few, a row each, which the cursor passes; or all of them, two rows
--- each, the cursor going from thread to thread.
---@alias thread.Fold 'none'|'some'|'all'

-- The threads Home shows of a review folded to 'some'.
M.SOME = 3

--- How the screen draws a review or a thread: what is opened, whether
--- its chunks are laid out by file, and how much of it is folded.
---@class thread.ViewOpts
---@field width integer
---@field open table<string, true>
---@field files boolean
---@field fold boolean  messages a row each
---@field code boolean  each chunk's code shown
---@field groups table<string, boolean>|nil  a review's groups or a thread's tours folded or not, by draw.key; a group apart from `fold`, a tour from `tours`
---@field contracts boolean|nil  every contract listed
---@field tours boolean|nil  a thread's tours opened
---@field touches thread.Touches|nil  what touches what in the review, else worked out

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
      for _, t in ipairs(review.ordered(r)) do
        if not thread.closed(t) and (not o.query or mentions(t, o.query)) then
          threads[#threads + 1] = t
        end
      end
      if not o.query or says(r.title, o.query) or says(r.introduction, o.query) or #threads > 0 then
        if #out > 0 then
          P.add ''
        end
        local line = review_draw.line(P, r, { width = o.width, indent = M.INDENT })
        out[#out + 1] = line
        -- A search shows every thread that mentions it, folded or not.
        local fold = o.query and 'all' or o.fold or 'some'
        if fold ~= 'none' then
          local some = fold == 'some'
          local most = some and M.SOME or #threads
          local shown = vim.list_slice(threads, 1, most)
          local columns = thread_draw.columns(r, thread_draw.each(shown), o.width - 2)
          for i = 1, #shown do
            -- The first few are a glimpse, a row each, that j and k pass.
            local p = thread_draw.row(P, r, shown[i], { width = o.width - 2, indent = M.INDENT + 2, columns = columns, fold = some })
            p.review, p.item = r, not some
            out[#out + 1] = p
          end
          if #threads > most then
            local more = '… ' .. text.plural(#threads - most, 'more thread') .. '   ⇥ shows them all'
            -- Under the ids, past where a thread's glyph goes.
            P.chunks({ { text.fit(more, o.width - 4), 'ThreadMeta' } }, M.INDENT + 4)
          end
          -- The review, as an item, is lit with the glimpse of its threads.
          line.last = #P.lines - 1
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
  return review_draw.overview(P, r, {
    width = o.width,
    indent = M.INDENT,
    open = o.open,
    files = o.files,
    fold = o.fold,
    code = o.code,
    groups = o.groups,
    contracts = o.contracts,
    tours = o.tours,
    touches = o.touches,
  })
end

--- A thread whole.
---@param P thread.Sheet
---@param r thread.Review
---@param t thread.Thread
---@param o thread.ViewOpts
---@return thread.Part[]
function M.thread(P, r, t, o)
  P.add ''
  local out = thread_draw.whole(P, r, t, {
    width = o.width,
    indent = M.INDENT,
    open = o.open,
    files = o.files,
    fold = o.fold,
    code = o.code,
    groups = o.groups,
    contracts = o.contracts,
    tours = o.tours,
    touches = o.touches,
  })
  draw.within(out, 1, { review = r })
  return out
end

--- A contract's page.
---@param P thread.Sheet
---@param r thread.Review
---@param c thread.Contract
---@param o thread.ViewOpts
---@return thread.Part[]
function M.contract(P, r, c, o)
  P.add ''
  return contract_draw.page(P, r, c, { width = o.width, indent = M.INDENT, code = o.code, touches = o.touches })
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
