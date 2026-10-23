--- What the screen shows at each depth, drawn into a sheet: the reviews,
--- each with as many of what wants you in it as the fold says; a
--- review's overview; a note's page; a contract's page; a step whole,
--- its tour's outline under it; a tour's briefing.

local contract_draw = require 'thread.draw.contract'
local conversation = require 'thread.model.conversation'
local draw = require 'thread.draw'
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

--- How the screen draws a review: what is opened, whether its chunks are
--- laid out by file, and how much of it is folded.
---@class thread.ViewOpts
---@field width integer
---@field open table<string, true>
---@field files boolean
---@field fold boolean  its introduction one row
---@field code boolean  each chunk's code shown
---@field groups table<string, boolean>|nil  a review's tours folded or not, by draw.key, apart from `tours`
---@field contracts boolean|nil  every contract listed
---@field tours boolean|nil  every tour opened
---@field against boolean|nil  a contract's page: the contract against as it was
---@field touches thread.Touches|nil  what touches what in the review, else worked out

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
  P.add ''
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

--- A note's page, its code shown.
---@param P thread.Sheet
---@param r thread.Review
---@param n thread.Note
---@param o thread.ViewOpts
---@return thread.Part[]
function M.note(P, r, n, o)
  P.add ''
  local out = note_draw.whole(P, r, n, { width = o.width, indent = M.INDENT, code = true, touches = o.touches })
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
  local out = contract_draw.page(P, r, c, { width = o.width, indent = M.INDENT, touches = o.touches, against = o.against })
  draw.within(out, 1, { review = r })
  return out
end

--- A step whole, then its tour's outline, the step marked in it: the
--- tour's line and each step's an item, so the last of the page lit stops
--- above them.
---@param P thread.Sheet
---@param r thread.Review
---@param x thread.Tour
---@param s thread.Step
---@param width integer
---@return thread.Part[]
function M.step(P, r, x, s, width)
  P.add ''
  local out = step_draw.whole(P, r, x, s, { width = width, indent = M.INDENT })
  P.add ''
  local from = #out + 1
  vim.list_extend(out, tour_draw.outline(P, r, x, { width = width, indent = M.INDENT, here = s }))
  for i = from, #out do
    out[i].item = (out[i].kind == 'step' or out[i].kind == 'tour') or nil
  end
  draw.within(out, 1, { review = r })
  return out
end

--- A tour's briefing.
---@param P thread.Sheet
---@param r thread.Review
---@param x thread.Tour
---@param place integer
---@param width integer
---@return thread.Part[]
function M.tour(P, r, x, place, width)
  P.add ''
  local out = tour_draw.briefing(P, r, x, { width = width, indent = M.INDENT, place = place })
  for _, p in ipairs(out) do
    p.item = p.item or p.kind == 'step' or nil
  end
  draw.within(out, 1, { review = r })
  return out
end

return M
