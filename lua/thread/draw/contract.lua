--- A contract's page: the contract itself as it is, what changed marked,
--- or against as it was, as a diff of its two sides, the words that
--- changed lit, or as two blocks when most of it changed; its prose; its conversation, straight after what it answers; its blast
--- radius, the code that depends on it grouped by how far the change
--- reached it, `missed` first, with what each had to do; and the tours,
--- steps and notes that touch it, worked out. Its files down the right,
--- as a review's are.

local chunk = require 'thread.model.chunk'
local chunk_draw = require 'thread.draw.chunk'
local contract = require 'thread.model.contract'
local contracts = require 'thread.draw.contracts'
local conversation = require 'thread.model.conversation'
local draw = require 'thread.draw'
local labels = require 'thread.draw.labels'
local message = require 'thread.draw.message'
local note_draw = require 'thread.draw.note'
local prose = require 'thread.prose'
local review = require 'thread.model.review'
local side = require 'thread.draw.side'
local source = require 'thread.prose.source'
local text = require 'thread.base.text'
local touch = require 'thread.model.touch'
local tour = require 'thread.model.tour'

local M = {}

---@class thread.ContractOpts
---@field width integer
---@field indent integer|nil  else the sheet's
---@field touches thread.Touches|nil  what touches what in the review, else worked out
---@field against boolean|nil  the contract against as it was, not only as it is

-- The widest prose reads well at.
local PROSE = 100

-- How each impact is said, and its colour.
M.IMPACT = {
  missed = { '✗', 'ThreadVerdictBad', 'missed' },
  reworked = { '↻', 'ThreadVerdictWarn', 'reworked' },
  adapted = { '~', 'ThreadVerdictInfo', 'adapted' },
  none = { '·', 'ThreadMeta', 'not reached' },
}

--- A section's rule, a blank row above it.
---@param P thread.Sheet
---@param label string
---@param width integer
---@param indent integer
local function rule(P, label, width, indent)
  P.add ''
  P.chunks(labels.rule(label, width), indent)
  P.add ''
end

--- The blast radius: the code that depends on it, by how far the change
--- reached it, the furthest first; each dependent where it is and its
--- line, what it had to do under it.
---@param P thread.Sheet
---@param r thread.Review
---@param c thread.Contract
---@param width integer
---@param indent integer
---@param out thread.Part[]
local function radius(P, r, c, width, indent, out)
  local groups = contract.radius(c)
  local said = vim.tbl_map(function(g)
    return #g.dependents .. ' ' .. M.IMPACT[g.impact][3]
  end, groups)
  rule(P, 'blast radius · ' .. #(c.dependents or {}) .. (#said > 0 and (' · ' .. table.concat(said, ' · ')) or ''), width, indent)
  if #groups == 0 then
    P.chunks({ { text.fit('Nothing depends on it, as the agent found.', width), 'ThreadMeta' } }, indent)
    return
  end
  local spec = chunk.spec(r.diff)
  for k, g in ipairs(groups) do
    if k > 1 then
      P.add ''
    end
    local mark = M.IMPACT[g.impact]
    P.chunks({ { mark[1] .. ' ' .. mark[3] .. ' · ' .. #g.dependents, mark[2] } }, indent)
    for _, d in ipairs(g.dependents) do
      local ch = review.chunk(r, d.chunk)
      local left = {} ---@type thread.Chunks
      local lines = ch and chunk.code(ch, spec)
      if ch then
        vim.list_extend(left, chunk_draw.path(ch, spec, math.min(40, math.floor(width / 2))))
        left[#left + 1] = { '  ' .. vim.trim(lines and lines[1] or ch.from), 'ThreadCode' }
      end
      local row = P.chunks(text.fit_chunks(left, width - 2), indent + 2)
      local part = { kind = 'chunk', first = row, last = row, chunk = ch, item = true } ---@type thread.Part
      out[#out + 1] = part
      if d.text then
        draw.prose(prose.draw(P, d.text, math.min(width, PROSE) - 4, { indent = indent + 4, hl = 'ThreadMeta', review = r }), out)
        part.last = #P.lines - 1
      end
    end
  end
end

--- The tours, steps and notes whose chunks touch it, worked out: a tour
--- a row with the ids of its steps that do, a note a row.
---@param P thread.Sheet
---@param r thread.Review
---@param c thread.Contract
---@param T thread.Touches
---@param width integer
---@param indent integer
---@param out thread.Part[]
local function touched(P, r, c, T, width, indent, out)
  local by = T.touched[c] or {}
  local any = false
  for place, x in ipairs(tour.list(r)) do
    if by[x] then
      local steps = vim.tbl_filter(function(s)
        return by[s] == true
      end, x.steps)
      local ids = vim.tbl_map(function(s)
        return 'step ' .. s.id
      end, steps)
      local hl = labels.colour(x.colour, place)
      local row = draw.row(P, { { '▌ ', hl }, { x.title, 'ThreadTitle' } }, { { table.concat(ids, ' · '), 'ThreadMeta' } }, width, indent)
      out[#out + 1] = { kind = 'tour', first = row, last = row, tour = x, step = steps[1], item = true }
      any = true
    end
  end
  for _, n in ipairs(r.notes) do
    if by[n] then
      out[#out + 1] = note_draw.row(P, r, n, { width = width, indent = indent, label = true })
      any = true
    end
  end
  if not any then
    P.chunks({ { text.fit('Nothing in the tours or the notes touches it.', width), 'ThreadMeta' } }, indent)
  end
end

--- A contract's page, whole.
---@param P thread.Sheet
---@param r thread.Review
---@param c thread.Contract
---@param o thread.ContractOpts
---@return thread.Part[]  the contract, then what in it goes somewhere
function M.page(P, r, c, o)
  local indent = o.indent or P.indent
  local top = #P.lines
  local main = side.main(o.width)
  local width = main or o.width
  local T = o.touches or touch.index(r)
  local sign = contract.sign(c)
  local right = { { c.kind .. ' · ' .. c.source.change, 'ThreadMeta' } }
  local first = draw.row(P, { { sign .. ' ', contracts.COLOUR[sign] }, { c.name, 'ThreadContract' } }, right, width, indent)
  local out = { { kind = 'contract', first = first, last = first, contract = c, item = true } } ---@type thread.Part[]
  if c.why then
    draw.prose(prose.draw(P, c.why, math.min(width, PROSE), { indent = indent, hl = 'ThreadSummary', review = r }), out)
  end
  P.add ''
  local at, row = #out + 1, #P.lines
  for _, h in ipairs(source.draw(P, r, c, width, indent, chunk_draw.where, { against = o.against })) do
    out[#out + 1] = { kind = 'chunk', first = h.row, last = h.row, chunk = h.chunk, item = true }
  end
  table.insert(out, at, { kind = 'block', first = row, last = #P.lines - 1, name = 'source', item = true })
  if c.prose.text ~= '' then
    P.add ''
    at, row = #out + 1, #P.lines
    draw.prose(prose.draw(P, c.prose, math.min(width, PROSE), { indent = indent, review = r }), out)
    table.insert(out, at, { kind = 'block', first = row, last = #P.lines - 1, name = 'prose', item = true })
  end
  -- The conversation straight after what it answers.
  rule(P, 'conversation', width, indent)
  local conv = conversation.of_contract(c)
  if #conv.messages == 0 then
    P.chunks({ { text.fit('r asks or says something about it; the agent answers here.', width), 'ThreadMeta' } }, indent)
  end
  for i = 1, #conv.messages do
    if i > 1 then
      P.add ''
    end
    local drawn = message.draw(P, r, conv, i, { width = width, indent = indent })
    drawn[1].item = true
    vim.list_extend(out, drawn)
  end
  out[#out + 1] = message.reply(conv, #P.lines - 1, { width = width, indent = indent })
  if conversation.move(conv) == 'agent' then
    P.add ''
    P.chunks({ { 'waiting on the agent', 'ThreadMeta' } }, indent)
  end
  radius(P, r, c, width, indent, out)
  rule(P, 'touched by', width, indent)
  touched(P, r, c, T, width, indent, out)
  if main then
    M.side(P, r, c, top, indent + main + side.GAP, T)
  end
  draw.within(out, 1, { review = r, contract = c })
  return out
end

--- Its files down the right, from row `top`: its sides' and its
--- dependents', each marked with the tours whose steps are in it.
---@param P thread.Sheet
---@param r thread.Review
---@param c thread.Contract
---@param top integer
---@param col integer
---@param T thread.Touches
function M.side(P, r, c, top, col, T)
  local all = T.chunks[c] or {}
  if #all == 0 then
    return
  end
  local parts = {} ---@type thread.SidePart[]
  local by = T.touched[c] or {}
  for place, x in ipairs(tour.list(r)) do
    if by[x] then
      parts[#parts + 1] = { hl = (labels.colour(x.colour, place)), files = T.files[x] }
    end
  end
  side.beside(P, top, col, side.paths(all), parts)
end

return M
