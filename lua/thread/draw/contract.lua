--- A contract's page, a page of Contracts. Its head: its name and kind,
--- what changed in a sentence, and the views of its change, the one shown
--- lit. Then its change, in that view, cut short when long; what the
--- agent says of it; its conversation, as Notes draws one; and its
--- callers, the furthest the change reached first, and beside them, or
--- under the one the cursor is on when narrow, that caller's code as the
--- change left it, in the same view. No labels: whitespace parts them.

local caller = require 'thread.draw.caller'
local chunk = require 'thread.model.chunk'
local chunk_draw = require 'thread.draw.chunk'
local contract = require 'thread.model.contract'
local contracts = require 'thread.draw.contracts'
local conversation = require 'thread.model.conversation'
local draw = require 'thread.draw'
local inbox = require 'thread.draw.inbox'
local prose = require 'thread.prose'
local review = require 'thread.model.review'
local sheet = require 'thread.ui.sheet'
local source = require 'thread.prose.source'
local text = require 'thread.base.text'

local M = {}

---@class thread.ContractOpts
---@field width integer
---@field indent integer|nil  else the sheet's
---@field view thread.SourceView|nil  how its change and its callers' show; else split
---@field here string|nil  the caller whose code shows, by draw.key; else the first
---@field wide boolean|nil  the callers and the code of one side by side; else that code under its row
---@field whole boolean|nil  its change uncut
---@field across integer|nil  its callers this wide, across what is beside the page; else `width`

-- The views, in the order Tab goes through them, and what each is called.
M.VIEWS = { 'split', 'side', 'is' }
M.NAMES = { split = 'split', side = 'side', is = 'as it is' }

-- The widest prose reads well at; rows of its change shown until it is
-- read whole; callers listed at once beside their code, the rest a row
-- away; columns between the list and the code.
M.PROSE, M.MOST, M.LIST, M.GAP = 88, 20, 12, 3

-- How far the change reached each caller, as a mark, its colour and a word.
---@type table<thread.Impact, { [1]: string, [2]: string, [3]: string }>
M.IMPACT = {
  missed = contracts.REACH.missed,
  reworked = contracts.REACH.reworked,
  adapted = contracts.REACH.adapted,
  none = { '·', 'ThreadMeta', 'untouched' },
}

--- The view after `view`, round.
---@param view thread.SourceView
---@return thread.SourceView
function M.next(view)
  for i, v in ipairs(M.VIEWS) do
    if v == view then
      return M.VIEWS[i % #M.VIEWS + 1]
    end
  end
  return M.VIEWS[1]
end

--- Its callers with their chunks, the furthest the change reached first,
--- as the agent listed them within each.
---@param r thread.Review
---@param c thread.Contract
---@return { dependent: thread.Dependent, chunk: thread.Chunk }[]
function M.callers(r, c)
  local out = {}
  for _, impact in ipairs(contract.IMPACTS) do
    for _, d in ipairs(c.dependents or {}) do
      local ch = d.impact == impact and review.chunk(r, d.chunk)
      if ch then
        out[#out + 1] = { dependent = d, chunk = ch }
      end
    end
  end
  return out
end

--- A caller's key, as the screen keeps the one whose code shows.
---@param ch thread.Chunk
---@return string
function M.key(ch)
  return draw.key { kind = 'chunk', first = 0, last = 0, chunk = ch }
end

--- The views along the head's right, as the tabs are drawn: the one
--- shown lit, the rest quiet.
---@param view thread.SourceView
---@return thread.Chunks
local function switcher(view)
  local out = {} ---@type thread.Chunks
  for i, v in ipairs(M.VIEWS) do
    if i > 1 then
      out[#out + 1] = { ' ' }
    end
    -- Lit, padded to its wash; quiet, the last ends where its name does.
    local lit = v == view
    out[#out + 1] = { ' ' .. M.NAMES[v] .. ((lit or i < #M.VIEWS) and ' ' or ''), lit and 'ThreadTabHere' or 'ThreadTab' }
  end
  return out
end

--- What the marks mean, in a row, or two when narrower than that.
---@param P thread.Sheet
---@param width integer
---@param indent integer
local function legend(P, width, indent)
  local each = {} ---@type thread.Chunks[]
  for _, impact in ipairs(contract.IMPACTS) do
    local m = M.IMPACT[impact]
    each[#each + 1] = { { m[1], m[2] }, { ' ' .. m[3], 'ThreadMeta' } }
  end
  ---@param list thread.Chunks[]
  ---@return thread.Chunks
  local function row(list)
    local out = {} ---@type thread.Chunks
    for i, x in ipairs(list) do
      if i > 1 then
        out[#out + 1] = { '  ' }
      end
      vim.list_extend(out, x)
    end
    return out
  end
  local all = row(each)
  if text.width(all) <= width then
    P.chunks(all, indent)
    return
  end
  P.chunks(text.fit_chunks(row { each[1], each[2] }, width), indent)
  P.chunks(text.fit_chunks(row { each[3], each[4] }, width), indent)
end

--- A caller's row: its mark and where it is; one the change did not
--- reach quiet; the one whose code shows, its file bright.
---@param r thread.Review
---@param x { dependent: thread.Dependent, chunk: thread.Chunk }
---@param width integer
---@param shown boolean|nil
---@return thread.Chunks
local function row_of(r, x, width, shown)
  local m = M.IMPACT[x.dependent.impact]
  local out = { { m[1], m[2] }, { ' ' } } ---@type thread.Chunks
  local quiet = x.dependent.impact == 'none'
  for _, p in ipairs(chunk_draw.path(x.chunk, chunk.spec(r.diff), width - 2)) do
    local hl = p[2] == 'Directory' and (shown and 'ThreadTitle' or 'ThreadFile') or p[2]
    out[#out + 1] = { p[1], quiet and not shown and 'ThreadMeta' or hl }
  end
  return out
end

--- How many callers, and how many the change missed: the list's head.
---@param list { dependent: thread.Dependent }[]
---@return thread.Chunks
local function counted(list)
  local missed = #vim.tbl_filter(function(x)
    return x.dependent.impact == 'missed'
  end, list)
  local out = { { text.plural(#list, 'caller'), 'ThreadMetaHi' } } ---@type thread.Chunks
  if missed > 0 then
    vim.list_extend(out, { { '  ' }, { ' ' .. missed .. ' missed ', 'ThreadBadgeMissed' } })
  end
  return out
end

--- Parts drawn in a sheet set beside, moved where it was set.
---@param parts thread.Part[]
---@param top integer
---@param shift table<integer, integer>
---@param out thread.Part[]
local function moved(parts, top, shift, out)
  for _, p in ipairs(parts) do
    local by = shift[p.first] or 0
    p.s, p.e = p.s and p.s + by, p.e and p.e + by
    p.first, p.last = p.first + top, p.last + top
    out[#out + 1] = p
  end
end

--- The callers in a column, and beside it the code of the one `here`
--- names: as tall as the tallest caller's code, whichever is shown, so
--- moving between them moves nothing else; past M.LIST callers, the list
--- shows those around the one shown, a row above and below saying how
--- many more, which the cursor goes on to as to a caller.
---@param P thread.Sheet
---@param r thread.Review
---@param list { dependent: thread.Dependent, chunk: thread.Chunk }[]
---@param here integer
---@param view thread.SourceView
---@param width integer
---@param indent integer
---@param out thread.Part[]
local function beside(P, r, list, here, view, width, indent, out)
  local lw = 0
  for _, x in ipairs(list) do
    lw = math.max(lw, text.width(row_of(r, x, 1000)))
  end
  -- As wide as its widest row and its legend, a third of the page at most.
  local P2 = sheet.new()
  legend(P2, 1000, 0)
  lw = math.min(math.max(28, lw, text.width(P2.lines[1])), math.floor(width * 0.34))
  local col = indent + lw + M.GAP
  local rw = width - lw - M.GAP
  local top = #P.lines
  P.chunks(text.fit_chunks(counted(list), lw), indent)
  P.add ''
  local from, to = 1, #list
  if #list > M.LIST then
    from = math.max(1, math.min(#list - M.LIST + 1, here - math.floor(M.LIST / 2)))
    to = from + M.LIST - 1
  end
  ---@param x { chunk: thread.Chunk }
  ---@param row integer
  ---@param first boolean|nil
  local function part(x, row, first)
    local span = { from = math.max(0, indent - 2), to = indent + lw + 1 }
    out[#out + 1] = { kind = 'chunk', first = row, last = row, chunk = x.chunk, item = true, alone = true, span = span, name = first and 'callers' or nil }
  end
  -- Past the list's ends, a row each way, kept as it grows and shrinks.
  ---@param n integer
  ---@param x { chunk: thread.Chunk }|nil
  ---@param said string
  local function more(n, x, said)
    if not x then
      P.add ''
      return
    end
    part(x, P.chunks({ { text.fit('… ' .. n .. ' ' .. said, lw), 'ThreadMeta' } }, indent + 2))
  end
  if #list > M.LIST then
    more(from - 1, list[from - 1], 'above')
  end
  for i = from, to do
    part(list[i], P.chunks(text.fit_chunks(row_of(r, list[i], lw, i == here), lw), indent), i == 1)
  end
  if #list > M.LIST then
    more(#list - to, list[to + 1], 'more')
  end
  P.add ''
  legend(P, lw, indent)
  -- As tall as the tallest of their code.
  local tall = 0
  for i, x in ipairs(list) do
    if i ~= here then
      local Q = sheet.new()
      caller.draw(Q, r, x.dependent, { width = rw, indent = 0, view = view, plain = true })
      tall = math.max(tall, #Q.lines)
    end
  end
  local Q = sheet.new()
  local parts = caller.draw(Q, r, list[here].dependent, { width = rw, indent = 0, view = view })
  tall = math.max(tall, #Q.lines, #P.lines - top)
  while #P.lines < top + tall do
    P.add ''
  end
  moved(parts, top, sheet.beside(P, Q, top, col), out)
  for row = top, top + tall - 1 do
    P.mark(row, 0, { virt_text = { { '│', 'ThreadPaneRule' } }, virt_text_win_col = indent + lw + 1 })
  end
end

--- The callers in a column, the code of the one `here` names under its
--- row, as the tabs open the item under the cursor.
---@param P thread.Sheet
---@param r thread.Review
---@param list { dependent: thread.Dependent, chunk: thread.Chunk }[]
---@param here integer
---@param view thread.SourceView
---@param width integer
---@param indent integer
---@param out thread.Part[]
local function stacked(P, r, list, here, view, width, indent, out)
  P.chunks(text.fit_chunks(counted(list), width), indent)
  P.add ''
  for i, x in ipairs(list) do
    local row = P.chunks(text.fit_chunks(row_of(r, x, width, i == here), width), indent)
    out[#out + 1] = { kind = 'chunk', first = row, last = row, chunk = x.chunk, item = true, alone = true, name = i == 1 and 'callers' or nil }
    if i == here then
      vim.list_extend(out, caller.draw(P, r, x.dependent, { width = width - 4, indent = indent + 4, view = view }))
      P.add ''
    end
  end
  P.add ''
  legend(P, width, indent)
end

--- Its conversation as Notes draws a thread, then where you answer: one
--- quiet row when there is none yet.
---@param P thread.Sheet
---@param r thread.Review
---@param c thread.Contract
---@param width integer
---@param indent integer
---@param out thread.Part[]
local function talk(P, r, c, width, indent, out)
  local room = math.min(width, M.PROSE) - 2
  inbox.talk(P, r, conversation.of_contract(c), { x = indent, room = room, ask = 'ask or say something about it' }, out)
end

--- A contract's page, whole.
---@param P thread.Sheet
---@param r thread.Review
---@param c thread.Contract
---@param o thread.ContractOpts
---@return thread.Part[]  its head, then what in it goes somewhere
function M.page(P, r, c, o)
  local indent = o.indent or P.indent
  local width = o.width
  local view = M.NAMES[o.view] and o.view or 'split'
  local measure = math.min(width, M.PROSE)
  local sign = contract.sign(c)
  local own = contracts.home(r, c)
  local right = switcher(view)
  if own and o.wide then
    right = vim.list_extend(vim.list_extend(chunk_draw.place(own, chunk.spec(r.diff)), { { '   ' } }), right)
  end
  -- Where it is gives way to the views, and the views, narrow, to the one shown.
  if text.width(right) > width / 2 then
    right = { { ' ' .. M.NAMES[view] .. ' ', 'ThreadTabHere' } }
  end
  local left = { { sign .. ' ', contracts.SIGN[sign] }, { c.name, contracts.NAME[sign] }, { '  ' .. c.kind, 'ThreadKind' } }
  local rw = text.width(right)
  local head = text.fit_chunks(left, math.max(1, width - rw - 2))
  head[#head + 1] = { string.rep(' ', math.max(2, width - text.width(head) - rw)) }
  local first = P.chunks(vim.list_extend(head, right), indent)
  local out = { { kind = 'contract', first = first, last = first, contract = c, item = true, alone = true } } ---@type thread.Part[]
  if c.why then
    draw.prose(prose.draw(P, c.why, measure, { indent = indent, hl = 'ThreadSummary', review = r }), out)
    out[1].last = #P.lines - 1
  end
  ---@param name string
  ---@param fn fun()
  local function block(name, fn)
    P.add ''
    local at, row = #out + 1, #P.lines
    fn()
    -- Its prose washed as an item is; its code, washed already, barred.
    table.insert(out, at, { kind = 'block', name = name, first = row, last = #P.lines - 1, item = true, bar = name ~= 'prose' or nil })
  end
  block('source', function()
    source.draw(P, r, c, width, indent, chunk_draw.where, { view = view, head = 'ThreadMetaHi', bound = true, most = not o.whole and M.MOST or nil })
  end)
  if c.prose.text ~= '' then
    block('prose', function()
      draw.prose(prose.draw(P, c.prose, measure, { indent = indent, review = r }), out)
    end)
  end
  -- Its conversation after what it answers, before its callers.
  P.add ''
  talk(P, r, c, width, indent, out)
  P.add ''
  local list = M.callers(r, c)
  local region = #P.lines
  if #list == 0 then
    P.chunks({ { text.fit('Nothing depends on it, as the agent found.', width), 'ThreadMeta' } }, indent)
  else
    local here = 1
    for i, x in ipairs(list) do
      if M.key(x.chunk) == o.here then
        here = i
      end
    end
    local across = o.across or width
    if o.wide then
      beside(P, r, list, here, view, across, indent, out)
    else
      stacked(P, r, list, here, view, across, indent, out)
    end
    out[#out + 1] = { kind = 'block', name = 'callers', first = region, last = #P.lines - 1, wide = o.across ~= nil or nil }
  end
  draw.within(out, 1, { review = r, contract = c })
  return out
end

return M
