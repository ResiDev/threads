--- A tour or a contract of the review placed in prose, `{{tour:2}}` or
--- `{{contract:3}}` alone on a line, drawn there at its fold
--- (thread.prose.fold): a tour its steps, a contract itself, so prose can
--- explain with them rather than only link to them. A label above says
--- which it is. A tour's rows carry it, so ⏎ on its head walks it, and on
--- a step walks from that step; ⏎ on a contract's head opens its page.

local chunk = require 'thread.model.chunk'
local contract = require 'thread.model.contract'
local excerpt = require 'thread.prose.excerpt'
local fold = require 'thread.prose.fold'
local review = require 'thread.model.review'
local source = require 'thread.prose.source'
local text = require 'thread.base.text'

local M = {}

--- What a line of prose places that is drawn here.
---@class (exact) thread.Inline
---@field kind thread.FoldKind
---@field name string  its id, as written
---@field tour thread.Tour|nil  none: its review has no tour by that id
---@field contract thread.Contract|nil  none: its review has no contract by that id

--- Draws prose that a block holds: thread.prose's draw, which this
--- module is under.
---@alias thread.SayProse fun(P: thread.Sheet, x: thread.ProseLike, width: integer, o: thread.ProseOpts): thread.Drawn[]

-- What the change did to a contract, as its sign's colour.
local COLOUR = { ['+'] = 'ThreadAdded', ['~'] = 'ThreadFileModified', ['−'] = 'ThreadRemoved' }

--- What folds it.
---@param x thread.Inline
---@param r thread.Review|nil
---@return string
function M.key(x, r)
  return fold.key(x.kind, r and r.id, x.name)
end

--- A chunk of the review as an excerpt, by its id.
---@param r thread.Review|nil
---@param id string
---@return thread.Excerpt
local function excerpt_of(r, id)
  return { id = id, chunk = r and review.chunk(r, id), spec = r and chunk.spec(r.diff) }
end

--- `left` and `right` on one row, `right` ending at the width.
---@param P thread.Sheet
---@param left thread.Chunks
---@param right thread.Chunks
---@param width integer
---@param indent integer
---@return integer row
local function row(P, left, right, width, indent)
  local rw = text.width(right)
  local fitted = text.fit_chunks(left, math.max(1, width - rw - 2))
  if rw > 0 then
    fitted[#fitted + 1] = { string.rep(' ', math.max(2, width - text.width(fitted) - rw)) }
    vim.list_extend(fitted, right)
  end
  return P.chunks(fitted, indent)
end

--- A row saying what is placed and that it names nothing.
---@param P thread.Sheet
---@param x thread.Inline
---@param width integer
---@param indent integer
---@return thread.Drawn[]
local function broken(P, x, width, indent)
  local why = ' · no ' .. x.kind .. ' has that id'
  P.chunks(text.fit_chunks({ { '{{' .. x.kind .. ':' .. x.name .. '}}', 'ThreadCode' }, { why, 'ThreadBroken' } }, width), indent)
  return {}
end

--- `── label ─────` across `width`, over what it says what it is.
---@param P thread.Sheet
---@param label string
---@param width integer
---@param indent integer
local function label_row(P, label, width, indent)
  P.chunks({ { '── ' .. label .. ' ', 'ThreadCrumb' }, { string.rep('─', math.max(2, width - #label - 4)), 'ThreadTabRule' } }, indent)
end

--- A tour's head row: its title, and how many steps.
---@param P thread.Sheet
---@param t thread.Tour
---@param width integer
---@param indent integer
---@return integer row
local function tour_head(P, t, width, indent)
  return row(P, { { '◇ ', 'ThreadMeta' }, { t.title, 'ThreadTitle' } }, { { text.plural(#t.steps, 'step', 'steps'), 'ThreadMeta' } }, width, indent)
end

--- A tour at its fold: its steps' titles, numbered; with `where` each
--- step's text and where its code is, with `code` its code too.
---@param P thread.Sheet
---@param x thread.Inline
---@param r thread.Review|nil
---@param width integer
---@param indent integer
---@param say thread.SayProse
---@param out thread.Drawn[]
local function tour(P, x, r, width, indent, say, out)
  local t = assert(x.tour)
  local how = fold.get('tour', M.key(x, r))
  local head = tour_head(P, t, width, indent)
  out[1].tour = t
  out[#out + 1] = { first = head, last = head, tour = t }
  local inner = indent + 5
  for i, s in ipairs(t.steps) do
    if how ~= 'titles' and i > 1 then
      P.add ''
    end
    local first = P.chunks(text.fit_chunks({ { string.format('%3d  ', i), 'ThreadMeta' }, { s.title, 'ThreadPoint' } }, width), indent)
    local ex = s.chunk and excerpt_of(r, s.chunk) or nil
    if how ~= 'titles' then
      if s.text then
        vim.list_extend(out, say(P, s.text, width - 5, { indent = inner, review = r }))
      end
      if ex and how == 'code' then
        excerpt.draw(P, ex, inner, width - 5)
      elseif ex then
        excerpt.line(P, ex, inner, width - 5)
      end
    end
    -- The whole step, under the links in its text: ⏎ walks from it.
    out[#out + 1] = { first = first, last = #P.lines - 1, tour = t, step = s, excerpt = ex }
  end
end

--- A contract's head row, the whole of it a link to its page: what the
--- change did to it, its name and why; its kind on the right.
---@param P thread.Sheet
---@param c thread.Contract
---@param width integer
---@param indent integer
---@param out thread.Drawn[]
local function contract_head(P, c, width, indent, out)
  local sign = contract.sign(c)
  local left = { { sign .. ' ', COLOUR[sign] }, { c.name, 'ThreadContract' } } ---@type thread.Chunks
  if c.why then
    left[#left + 1] = { '  ' .. c.why, 'ThreadSummary' }
  end
  local at = row(P, left, { { c.kind, 'ThreadMeta' } }, width, indent)
  out[#out + 1] = { first = at, last = at, s = 0, e = indent + width, link = { kind = 'contract', id = c.id } }
end

--- A contract at its fold: its head row; with `source` the contract
--- itself, as its page draws it.
---@param P thread.Sheet
---@param x thread.Inline
---@param r thread.Review|nil
---@param width integer
---@param indent integer
---@param out thread.Drawn[]
local function contract_block(P, x, r, width, indent, out)
  local c = assert(x.contract)
  local how = fold.get('contract', M.key(x, r))
  contract_head(P, c, width, indent, out)
  if how == 'source' then
    for _, h in ipairs(source.draw(P, r, c, width - 2, indent + 2, excerpt.where)) do
      local ex = excerpt_of(r, h.chunk.id)
      out[#out + 1] = { first = h.row, last = h.row, excerpt = ex }
    end
  end
end

--- A block drawn at its fold, from `indent` in `width` columns: first
--- the block itself, then what in it goes somewhere.
---@param P thread.Sheet
---@param x thread.Inline
---@param r thread.Review|nil
---@param width integer
---@param indent integer
---@param say thread.SayProse
---@return thread.Drawn[]
function M.draw(P, x, r, width, indent, say)
  if not (x.tour or x.contract) then
    return broken(P, x, width, indent)
  end
  local whole = { first = #P.lines, last = #P.lines, fold = M.key(x, r), inline = x.kind } ---@type thread.Drawn
  local out = { whole } ---@type thread.Drawn[]
  label_row(P, x.kind, width, indent)
  if x.tour then
    tour(P, x, r, width, indent, say, out)
  else
    contract_block(P, x, r, width, indent, out)
  end
  whole.last = #P.lines - 1
  return out
end

--- A block in one row, for prose cut short: its head.
---@param P thread.Sheet
---@param x thread.Inline
---@param width integer
---@param indent integer
---@return thread.Drawn[]
function M.line(P, x, width, indent)
  if x.tour then
    tour_head(P, x.tour, width, indent)
    return {}
  elseif x.contract then
    local out = {} ---@type thread.Drawn[]
    contract_head(P, x.contract, width, indent, out)
    return out
  end
  return broken(P, x, width, indent)
end

return M
