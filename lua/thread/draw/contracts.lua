--- Contracts as a list. On a review's Contracts tab, in groups by what
--- they ask of you: a row of two lines each, what the change did to it,
--- its name and kind, the callers the change reached and where it is;
--- then why, in a sentence. The one under the cursor opens its was and
--- is under its row, and the files beside say where it reaches. On a
--- page, a row each, the first few, then how many more until the list is
--- opened, so a long one never buries what comes after it.

local chunk = require 'thread.model.chunk'
local chunk_draw = require 'thread.draw.chunk'
local contract = require 'thread.model.contract'
local conversation = require 'thread.model.conversation'
local draw = require 'thread.draw'
local labels = require 'thread.draw.labels'
local prose = require 'thread.prose'
local review = require 'thread.model.review'
local source = require 'thread.prose.source'
local step = require 'thread.model.step'
local text = require 'thread.base.text'

local M = {}

---@class thread.ContractsOpts
---@field width integer
---@field indent integer|nil  else the sheet's
---@field all boolean|nil  every one, not only the first few
---@field review thread.Review|nil  theirs, for how their conversations stand

-- The rows a list shows until it is opened.
M.SOME = 6

-- What the change did to each, as its sign's colour.
M.COLOUR = { ['+'] = 'ThreadAdded', ['~'] = 'ThreadFileModified', ['−'] = 'ThreadRemoved' }

--- What the list's rule says: how many, and of each change.
---@param list thread.Contract[]
---@return string
local function counts(list)
  local n = {} ---@type table<string, integer>
  for _, c in ipairs(list) do
    local change = c.source and c.source.change or 'changed'
    n[change] = (n[change] or 0) + 1
  end
  local out = { 'contracts' }
  for _, change in ipairs(contract.CHANGES) do
    if n[change] then
      out[#out + 1] = n[change] .. ' ' .. change
    end
  end
  return table.concat(out, ' · ')
end

--- A rule saying how many, then a row a contract: its sign and its name
--- in a column, why it is; on the right whose move its conversation is.
--- Each row is an item; past the first few a row says how many more.
---@param P thread.Sheet
---@param list thread.Contract[]
---@param o thread.ContractsOpts
---@return thread.Part[]
function M.draw(P, list, o)
  local indent = o.indent or P.indent
  local out = {} ---@type thread.Part[]
  if #list == 0 then
    return out
  end
  P.chunks(labels.rule(counts(list), o.width), indent)
  local shown = o.all and #list or math.min(#list, M.SOME)
  local name = 0
  for i = 1, shown do
    name = math.max(name, text.width(list[i].name))
  end
  name = math.min(name, math.floor(o.width * 0.4))
  for i = 1, shown do
    local c = list[i]
    local sign = contract.sign(c)
    local right = o.review and labels.count(o.review, { conversation.of_contract(c) }) or {}
    local left =
      { { sign .. ' ', M.COLOUR[sign] }, { text.pad(text.fit(c.name, name), name), 'ThreadContract' }, { '  ' .. (c.why or c.kind), 'ThreadSummary' } }
    local row
    if #right > 0 then
      local fitted = text.fit_chunks(left, math.max(1, o.width - text.width(right) - 2))
      fitted[#fitted + 1] = { string.rep(' ', math.max(2, o.width - text.width(fitted) - text.width(right))) }
      row = P.chunks(vim.list_extend(fitted, right), indent)
    else
      row = P.chunks(text.fit_chunks(left, o.width), indent)
    end
    out[#out + 1] = { kind = 'contract', first = row, last = row, contract = c, item = true }
  end
  if shown < #list then
    P.chunks({ { text.fit('… ' .. (#list - shown) .. ' more   ⇥ shows them all', o.width - 2), 'ThreadMeta' } }, indent + 2)
  end
  return out
end

-- The tab

---@alias thread.ContractGroup 'needs'|'read'|'walked'

--- A group of the tab: its name, its name's colour, and why a contract
--- is in it.
---@class thread.ContractGroupSpec
---@field id thread.ContractGroup
---@field name string
---@field head string
---@field why string

-- The groups, in the order to read them.
---@type thread.ContractGroupSpec[]
M.GROUPS = {
  { id = 'needs', name = 'Needs you', head = 'ThreadNeedsYou', why = 'a caller the change missed' },
  { id = 'read', name = 'To read', head = 'ThreadGroupHead', why = 'not walked in a tour yet' },
  { id = 'walked', name = 'Walked', head = 'ThreadGroupDone', why = 'the code it is on, walked in a tour' },
}

--- What a contract is to a file: where it lives, or how far the change
--- reached a caller there; a symbol, its colour and its word.
---@alias thread.Reach 'here'|'missed'|'reworked'|'adapted'
---@type table<thread.Reach, { [1]: string, [2]: string, [3]: string }>
M.REACH = {
  here = { '◉', 'ThreadReachHere', 'lives here' },
  missed = { '✗', 'ThreadImpactMissed', 'missed' },
  reworked = { '●', 'ThreadImpactReworked', 'reworked' },
  adapted = { '○', 'ThreadImpactAdapted', 'adapted' },
}

-- A file with more than one, the first of these: a missed caller asks
-- the most.
local FIRST = { 'missed', 'here', 'reworked', 'adapted' }

-- What the change did to each, as its sign's colour on the tab.
local SIGN = { ['+'] = 'ThreadSignAdded', ['~'] = 'ThreadSignChanged', ['−'] = 'ThreadSignRemoved' }

-- Columns the file at a row's end has, at least, and between it and the
-- callers; cells the callers' bar takes, at most.
local FILE, GAP, BAR = 17, 4, 12

-- Rows of code each side opened under its row shows, at most, so the
-- rest of the list stays in view.
M.MOST = 6

--- The chunk a contract is on now: as it is, or as it was once removed;
--- nil when it is written out.
---@param r thread.Review
---@param c thread.Contract
---@return thread.Chunk|nil
local function home(r, c)
  local side = c.source.after or c.source.before
  return type(side) == 'string' and review.chunk(r, side) or nil
end

--- The chunks of the steps you have walked.
---@param r thread.Review
---@return thread.Chunk[]
local function walked_chunks(r)
  local out = {} ---@type thread.Chunk[]
  for _, x in ipairs(r.tours) do
    for _, s in ipairs(x.steps) do
      local c = step.walked(r, s) and review.chunk(r, s.chunk)
      if c then
        out[#out + 1] = c
      end
    end
  end
  return out
end

--- A contract's group: a caller the change missed needs you; the code it
--- is on walked in a tour, walked; else to read.
---@param r thread.Review
---@param c thread.Contract
---@param walked thread.Chunk[]  the chunks of the steps walked
---@return thread.ContractGroup
function M.group(r, c, walked)
  for _, d in ipairs(c.dependents or {}) do
    if d.impact == 'missed' then
      return 'needs'
    end
  end
  local own = home(r, c)
  if own then
    local spec = chunk.spec(r.diff)
    for _, w in ipairs(walked) do
      if w.id == own.id or chunk.overlap(w, own, spec) then
        return 'walked'
      end
    end
  end
  return 'read'
end

--- How many callers the change reached, by how far; those it did not
--- reach are not counted.
---@param c thread.Contract
---@return table<'missed'|'reworked'|'adapted', integer>, integer all
function M.reached(c)
  local n = { missed = 0, reworked = 0, adapted = 0 }
  for _, d in ipairs(c.dependents or {}) do
    if n[d.impact] then
      n[d.impact] = n[d.impact] + 1
    end
  end
  return n, n.missed + n.reworked + n.adapted
end

--- Each file a contract reaches, and what it is to it: where it lives,
--- or how far the change reached a caller there.
---@param r thread.Review
---@param c thread.Contract
---@return table<string, thread.Reach>
function M.reach(r, c)
  local found = {} ---@type table<string, table<thread.Reach, true>>
  ---@param id any
  ---@param what thread.Reach
  local function add(id, what)
    local ch = type(id) == 'string' and review.chunk(r, id)
    if ch then
      found[ch.file] = found[ch.file] or {}
      found[ch.file][what] = true
    end
  end
  add(c.source.after or c.source.before, 'here')
  for _, d in ipairs(c.dependents or {}) do
    if d.impact ~= 'none' then
      add(d.chunk, d.impact --[[@as thread.Reach]])
    end
  end
  local out = {} ---@type table<string, thread.Reach>
  for file, has in pairs(found) do
    for _, what in ipairs(FIRST) do
      if has[what] then
        out[file] = what
        break
      end
    end
  end
  return out
end

--- The callers the change reached, for a row's right: a block when it
--- missed some, a bar of a cell each in its colour, how many.
---@param c thread.Contract
---@param done boolean
---@return thread.Chunks
local function callers(c, done)
  local n, all = M.reached(c)
  if all == 0 then
    return {}
  end
  local out = {} ---@type thread.Chunks
  if n.missed > 0 then
    out = { { ' ' .. n.missed .. ' missed ', 'ThreadBadgeMissed' }, { '  ' } }
  end
  local scale = math.min(1, BAR / all)
  for _, k in ipairs { 'missed', 'reworked', 'adapted' } do
    if n[k] > 0 then
      out[#out + 1] = { string.rep('━', math.max(1, math.floor(n[k] * scale + 0.5))), M.REACH[k][2] }
    end
  end
  out[#out + 1] = { ' ' .. text.plural(all, 'caller'), done and 'ThreadMeta' or 'ThreadMetaHi' }
  return out
end

--- `chunks` from column `col` of `row`, the row padded to it.
---@param row thread.Chunks
---@param col integer
---@param chunks thread.Chunks
local function at(row, col, chunks)
  local w = text.width(row)
  if w < col then
    row[#row + 1] = { string.rep(' ', col - w) }
  end
  vim.list_extend(row, chunks)
end

--- Where a side is read from, over it: `e089472 · state.lua:9`.
---@param ch thread.Chunk
---@param located thread.Located|nil
---@return thread.Chunks
local function read_at(ch, located)
  if not located then
    return { { vim.fs.basename(ch.file) .. ' · its line is gone', 'ThreadBroken' } }
  end
  local rev = located.rev
  local said = 'working tree'
  if rev == '' then
    said = 'index'
  elseif rev then
    said = rev:match '^%x+$' and rev:sub(1, 7) or rev
  end
  return { { said .. ' · ' .. vim.fs.basename(ch.file) .. ':' .. located.line, 'ThreadMeta' } }
end

---@class thread.ContractRowOpts
---@field width integer
---@field indent integer
---@field done boolean|nil  walked: quieter

--- A contract's row, two lines: its sign, name and kind, then on the
--- right the callers the change reached and, last, where it is; under
--- them why, in a sentence.
---@param P thread.Sheet
---@param r thread.Review
---@param c thread.Contract
---@param o thread.ContractRowOpts
---@return thread.Part[]  the contract, lit over its rows alone, then what in its why goes somewhere
function M.row(P, r, c, o)
  local sign = contract.sign(c)
  local own = home(r, c)
  local place = own and chunk_draw.place(own, chunk.spec(r.diff)) or { { 'written out', 'ThreadMeta' } }
  local right = callers(c, o.done == true)
  local pw, rw = text.width(place), text.width(right)
  local file = o.width - math.max(FILE, pw)
  local left = {
    { sign, o.done and 'ThreadSevDone' or SIGN[sign] },
    { ' ' },
    { c.name, o.done and 'ThreadDone' or 'ThreadContract' },
    { '  ' .. c.kind, 'ThreadKind' },
  }
  local stop = rw > 0 and file - GAP - rw or file
  local line = text.fit_chunks(left, math.max(1, stop - 2))
  if rw > 0 then
    at(line, stop, right)
  end
  at(line, o.width - pw, place)
  local first = P.chunks(line, o.indent)
  local out = { { kind = 'contract', first = first, last = first, contract = c, item = true, alone = true } } ---@type thread.Part[]
  if c.why then
    draw.prose(prose.draw(P, c.why, o.width - 2, { indent = o.indent + 2, hl = o.done and 'ThreadDone' or 'ThreadSummary', review = r }), out)
    out[1].last = #P.lines - 1
  end
  return out
end

---@class thread.ContractsTabOpts
---@field width integer
---@field indent integer
---@field here string|nil  the contract opened, by draw.key: the one under the cursor

--- A review's Contracts tab: each group with contracts in it, its head,
--- a blank row, its rows a blank row apart, two before the next head.
--- The one `o.here` names opens under its row: as it was and as it is.
---@param P thread.Sheet
---@param r thread.Review
---@param o thread.ContractsTabOpts
---@return thread.Part[]
function M.tab(P, r, o)
  local walked = walked_chunks(r)
  local by = {} ---@type table<thread.ContractGroup, thread.Contract[]>
  for _, c in ipairs(r.contracts) do
    local g = M.group(r, c, walked)
    by[g] = by[g] or {}
    table.insert(by[g], c)
  end
  local out = {} ---@type thread.Part[]
  for _, g in ipairs(M.GROUPS) do
    local list = by[g.id]
    if list then
      if #out > 0 then
        P.add ''
      end
      local said = { { g.name, g.head }, { '  ' .. #list, 'ThreadMetaHi' }, { '   ' .. g.why, 'ThreadMeta' } }
      local head = P.chunks(text.fit_chunks(said, o.width), o.indent)
      out[#out + 1] = { kind = 'heading', first = head, last = head, name = g.id }
      P.add ''
      for _, c in ipairs(list) do
        vim.list_extend(out, M.row(P, r, c, { width = o.width, indent = o.indent, done = g.id == 'walked' }))
        if o.here == draw.key { kind = 'contract', first = 0, last = 0, contract = c } then
          P.add ''
          source.draw(P, r, c, o.width - 2, o.indent + 2, read_at, { against = true, head = 'ThreadMetaHi', bound = true, most = M.MOST })
        end
        P.add ''
      end
    end
  end
  return out
end

--- The files beside the tab: where the contract under the cursor
--- reaches, a symbol after each file's name, and what the symbols mean.
---@param r thread.Review
---@return thread.SidePane
function M.pane(r)
  local key = {} ---@type thread.Chunks[]
  for _, pair in ipairs { { 'here', 'missed' }, { 'reworked', 'adapted' } } do
    local row = {} ---@type thread.Chunks
    for i, what in ipairs(pair) do
      local m = M.REACH[what]
      at(row, (i - 1) * 14, { { m[1], m[2] }, { ' ' .. m[3], 'ThreadMeta' } })
    end
    key[#key + 1] = row
  end
  ---@param p thread.Part
  ---@return table<string, thread.Reach>|nil
  local function reach(p)
    return p.contract and M.reach(r, p.contract) or nil
  end
  return {
    head = function()
      return { { { 'where it reaches', 'ThreadSideHead' } }, {} }
    end,
    parts = {},
    lit = function(p)
      local found = reach(p)
      if not found then
        return nil
      end
      local out = {} ---@type table<string, true>
      for file in pairs(found) do
        out[file] = true
      end
      return out
    end,
    mark = function(path, p)
      local what = (reach(p) or {})[path]
      return what and { { M.REACH[what][1], M.REACH[what][2] } } or nil
    end,
    foot = function()
      return key
    end,
  }
end

return M
