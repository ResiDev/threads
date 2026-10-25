--- What the screen shows at Home and on a page, drawn into a sheet: the
--- reviews, each with as many of what wants you in it as the fold says;
--- a note's page; a contract's page; a step whole, its tour's outline
--- under it; a tour's briefing. Each is drawn in the column its place's
--- frame gives it; a review's tabs draw themselves (thread.screen.places).

local contract_draw = require 'thread.draw.contract'
local conversation = require 'thread.model.conversation'
local labels = require 'thread.draw.labels'
local model_prose = require 'thread.model.prose'
local note_draw = require 'thread.draw.note'
local review = require 'thread.model.review'
local review_draw = require 'thread.draw.review'
local step_draw = require 'thread.draw.step'
local text = require 'thread.base.text'
local tour_draw = require 'thread.draw.tour'

local M = {}

-- Columns either side of what is drawn.
M.INDENT = 2

---@class thread.HomeOpts
---@field width integer
---@field query string|nil  only what mentions it, every review's conversations shown
---@field show 'open'|'closed'  which reviews
---@field fold thread.Fold|nil  how much of each review Home shows; else 'some'

--- How much of each review Home shows: none of what is in it; the first
--- few of what wants you, a row each, which the cursor passes; or all of
--- them, the cursor going from one to the next.
---@alias thread.Fold 'none'|'some'|'all'

-- What Home shows of a review folded to 'some'.
M.SOME = 3

--- Whether `s` says `q`, case aside.
---@param s string|nil
---@param q string
---@return boolean
local function says(s, q)
  return s ~= nil and s:lower():find(q:lower(), 1, true) ~= nil
end

--- Whether a conversation says `q`: its step's or note's title, or
--- anything written in it.
---@param c thread.Conversation
---@param q string
---@return boolean
local function mentions(c, q)
  local own = c.step or c.note or c.contract
  if own and says(own.title or own.name, q) then
    return true
  end
  if c.step and c.step.text and says(model_prose.text(c.step.text), q) then
    return true
  end
  for _, m in ipairs(c.messages) do
    if says(model_prose.text(m.prose), q) then
      return true
    end
  end
  return false
end

--- A conversation as a row under its review at Home: a note's index row,
--- a step's line, a contract's name. Each is named by its kind, `step 2`,
--- `note 2`, since the rows of a review mix them and ids repeat across
--- kinds.
---@param P thread.Sheet
---@param r thread.Review
---@param c thread.Conversation
---@param width integer
---@param indent integer
---@return thread.Part
local function row(P, r, c, width, indent)
  if c.note then
    return note_draw.row(P, r, c.note, { width = width, indent = indent, label = true })
  elseif c.step then
    return step_draw.line(P, r, assert(c.tour), c.step, { width = width, indent = indent, label = true })
  end
  local k = assert(c.contract)
  local g, hl = labels.conversation(r, c)
  local at = P.chunks(text.fit_chunks({ { g .. ' ', hl }, { 'contract ' .. k.id .. '  ', 'ThreadMeta' }, { k.name, 'ThreadContract' } }, width), indent)
  return { kind = 'contract', first = at, last = at, contract = k }
end

--- The reviews, a line each, with what wants you in each under it; those
--- that cannot be read last, saying why.
---@param P thread.Sheet
---@param o thread.HomeOpts
---@return thread.Part[]
function M.home(P, o)
  local list, broken = review.list()
  local out = {} ---@type thread.Part[]
  for _, r in ipairs(list) do
    local closed = r.status == 'closed'
    if (o.show == 'closed') == closed then
      local wants = {} ---@type thread.Conversation[]
      for _, c in ipairs(conversation.all(r)) do
        if o.query and mentions(c, o.query) or (not o.query and conversation.for_you(r, c)) then
          wants[#wants + 1] = c
        end
      end
      local about = r.introduction and model_prose.text(r.introduction)
      if not o.query or says(r.title, o.query) or says(about, o.query) or #wants > 0 then
        if #out > 0 then
          P.add ''
        end
        local line = review_draw.line(P, r, { width = o.width, indent = M.INDENT })
        out[#out + 1] = line
        -- A search shows everything that mentions it, folded or not.
        local fold = o.query and 'all' or o.fold or 'some'
        if fold ~= 'none' then
          local some = fold == 'some'
          local most = some and M.SOME or #wants
          for i = 1, math.min(most, #wants) do
            -- The first few are a glimpse, a row each, that j and k pass.
            local p = row(P, r, wants[i], o.width - 2, M.INDENT + 2)
            p.review, p.item = r, not some
            out[#out + 1] = p
          end
          if #wants > most then
            local more = '… ' .. (#wants - most) .. ' more   ⇥ shows them all'
            P.chunks({ { text.fit(more, o.width - 4), 'ThreadMeta' } }, M.INDENT + 4)
          end
          -- The review, as an item, is lit with the glimpse under it.
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
      or 'No reviews yet. Start a note on a line, or ask the agent for a review.'
    P.chunks({ { text.fit(none, o.width), 'ThreadMeta' } }, M.INDENT)
  end
  return out
end

--- A note's page, its code shown, its head a row further down than a
--- tab's first.
---@param P thread.Sheet
---@param o thread.ScreenObjects
---@param f thread.Frame
---@param s thread.ScreenState
---@return thread.Part[]
function M.note(P, o, f, s)
  P.add ''
  return note_draw.whole(P, assert(o.review), assert(o.note), { width = f.width, indent = f.indent, code = true, touches = s.touches, here = s.here })
end

--- A contract's page, in the view the screen keeps, the caller under the
--- cursor's code shown; its change whole once opened to read.
---@param P thread.Sheet
---@param o thread.ScreenObjects
---@param f thread.Frame
---@param s thread.ScreenState
---@param wide boolean  its callers beside their code
---@return thread.Part[]
function M.contract(P, o, f, s, wide)
  local whole = s.open and s.open['block:source'] or nil
  return contract_draw.page(P, assert(o.review), assert(o.contract), {
    width = f.width,
    indent = f.indent,
    view = s.view,
    here = s.here,
    wide = wide,
    whole = whole,
    -- The callers across the files beside too.
    across = f.files and (f.files + assert(f.side) - 1 - f.indent) or nil,
  })
end

--- A step whole, then its tour's outline, the step marked in it: the
--- tour's line and each step's an item, so the last of the page lit stops
--- above them.
---@param P thread.Sheet
---@param o thread.ScreenObjects
---@param f thread.Frame
---@return thread.Part[]
function M.step(P, o, f)
  local r, x, s = assert(o.review), assert(o.tour), assert(o.step)
  local out = step_draw.whole(P, r, x, s, { width = f.width, indent = f.indent })
  P.add ''
  local from = #out + 1
  vim.list_extend(out, tour_draw.outline(P, r, x, { width = f.width, indent = f.indent, here = s }))
  for i = from, #out do
    out[i].item = (out[i].kind == 'step' or out[i].kind == 'tour') or nil
  end
  return out
end

--- A tour's briefing, a page of the Tours tab, each step an item.
---@param P thread.Sheet
---@param o thread.ScreenObjects
---@param f thread.Frame
---@param s thread.ScreenState
---@return thread.Part[]
function M.briefing(P, o, f, s)
  local out = tour_draw.briefing(P, assert(o.review), assert(o.tour), { width = f.width, indent = f.indent, place = assert(s.tour) })
  for _, p in ipairs(out) do
    p.item = p.item or p.kind == 'step' or nil
  end
  return out
end

return M
