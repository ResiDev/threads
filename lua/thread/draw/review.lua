--- A review: as a line, in Home's list; or its overview, what it is about,
--- its introduction, and its threads, a line each, the closed ones apart.
--- One that cannot be read is a line saying why.

local chunk = require 'thread.model.chunk'
local diff = require 'thread.base.diff'
local draw = require 'thread.draw'
local files = require 'thread.draw.files'
local labels = require 'thread.draw.labels'
local prose = require 'thread.prose'
local review = require 'thread.model.review'
local text = require 'thread.base.text'
local thread = require 'thread.model.thread'
local thread_draw = require 'thread.draw.thread'

local M = {}

---@class thread.ReviewOpts
---@field width integer
---@field indent integer|nil  else the sheet's
---@field open table<string, true>|nil  an overview: what is opened, by draw.key
---@field files boolean|nil  an overview: its chunks by file, not its threads
---@field fold boolean|nil  an overview: its introduction one row, its threads a row each
---@field code boolean|nil  an overview by file: each chunk's code
---@field groups table<string, boolean>|nil  an overview: groups folded or not, by name, apart from `fold`

--- What a review is about, said: its diff, or the code as it stands.
---@param r thread.Review
---@return string
local function about(r)
  local spec = chunk.spec(r.diff)
  return spec and spec.label or 'the code as it stands'
end

--- How many of its conversations want you, and how many wait on the
--- agent (thread.waiting); none in a closed review.
---@param r thread.Review
---@return integer you, integer agent
local function counts(r)
  local you = 0
  for _, t in ipairs(r.threads) do
    for _, c in ipairs(thread.conversations(t)) do
      you = you + (thread.for_you(r, c) and 1 or 0)
    end
  end
  return you, #thread.waiting(r)
end

--- A review in one row: its state, its title, what it is about; on the
--- right, what wants you, what waits on the agent, and when it last
--- changed.
---@param P thread.Sheet
---@param r thread.Review
---@param o thread.ReviewOpts
---@return thread.Part
function M.line(P, r, o)
  local you, agent = counts(r)
  local g, hl = labels.state(r.status == 'closed', you > 0 and 'you' or agent > 0 and 'agent' or nil, you > 0)
  local right = {} ---@type thread.Chunks
  if you > 0 then
    right[#right + 1] = { you .. ' for you', 'ThreadSignAnswered' }
  end
  if agent > 0 then
    right[#right + 1] = { (#right > 0 and ' · ' or '') .. agent .. ' with the agent', 'ThreadSignWaiting' }
  end
  local when = text.ago(review.latest(r))
  if when then
    right[#right + 1] = { (#right > 0 and '  ' or '') .. when, 'ThreadMeta' }
  end
  local left = { { g .. ' ', hl }, { r.title, r.status == 'closed' and 'ThreadMeta' or 'ThreadTitle' }, { '  ' .. about(r), 'ThreadMeta' } }
  local row = draw.row(P, left, right, o.width, o.indent)
  return { kind = 'review', first = row, last = row, review = r, item = true }
end

--- A review that cannot be read, in one row: its name, and why.
---@param P thread.Sheet
---@param id string
---@param why string
---@param o thread.ReviewOpts
---@return integer row
function M.broken(P, id, why, o)
  return P.chunks(text.fit_chunks({ { '! ', 'ThreadBroken' }, { id, 'ThreadTitle' }, { '  cannot be read: ' .. why, 'ThreadBroken' } }, o.width), o.indent)
end

-- Rows of its introduction folded, until it is opened.
M.FOLDED = 1

-- Columns a group's bar or tree takes, left of its rows.
M.GUTTER = 3

--- What a group is known by, for the screen to fold it: its name; the
--- threads in no group, ''.
---@param g thread.Grouped
---@return string
function M.group_key(g)
  return g.group and g.group.name or ''
end

--- Its highlight groups: for its name, and for its bar or tree.
---@param r thread.Review
---@param g thread.Grouped
---@return string name, string line
local function colour(r, g)
  if not g.group then
    return 'ThreadGroupNone', 'ThreadGroupNoneLine'
  end
  -- One with none takes the palette's colour at its place.
  local c = g.group.colour or review.COLOURS[1]
  for i, other in ipairs(g.group.colour and {} or r.groups or {}) do
    if other == g.group then
      c = review.COLOURS[(i - 1) % #review.COLOURS + 1]
    end
  end
  local Name = 'ThreadGroup' .. c:sub(1, 1):upper() .. c:sub(2)
  return Name, Name .. 'Line'
end

--- Down the gutter at `indent`, on each row from `first` to `last`.
---@param P thread.Sheet
---@param first integer
---@param last integer
---@param glyph string
---@param hl string
---@param indent integer
local function gutter(P, first, last, glyph, hl, indent)
  for row = first, last do
    P.mark(row, 0, { virt_text = { { glyph, hl } }, virt_text_win_col = indent })
  end
end

--- A review's threads by the groups the agent put them in. Each group
--- folded is a card: a bar in its colour down its name and how its
--- threads stand added up, what it is about, and a row a thread. Open, a
--- tree: the same, each thread with the files its chunks are in under it
--- and a row between.
---@param P thread.Sheet
---@param r thread.Review
---@param o thread.ReviewOpts
---@return thread.Part[]
function M.groups(P, r, o)
  local indent = o.indent or P.indent
  local width = o.width - M.GUTTER
  local inner = indent + M.GUTTER
  local list = review.grouped(r)
  local rows = thread_draw.each(r.threads)
  for _, g in ipairs(list) do
    rows[#rows + 1] = g.threads
  end
  -- One grid for every group, so their counts line up down the review.
  local columns = thread_draw.columns(r, rows, width)
  local out = {} ---@type thread.Part[]
  for _, g in ipairs(list) do
    local key = M.group_key(g)
    local folded = o.fold
    if o.groups and o.groups[key] ~= nil then
      folded = o.groups[key]
    end
    local name, line = colour(r, g)
    P.add ''
    local head = thread_draw.grid(P, r, { { g.group and g.group.name or 'In no group', name } }, g.threads, columns, width, inner)
    local part = { kind = 'group', first = head, last = head, group = g, item = true } ---@type thread.Part
    out[#out + 1] = part
    gutter(P, head, head, folded and '▌' or '━━', line, indent)
    local summary = g.group and g.group.summary
    if summary then
      local from = #P.lines
      draw.prose(prose.draw(P, summary, math.min(width, 100), { indent = inner, hl = 'ThreadSummary' }), out)
      gutter(P, from, #P.lines - 1, folded and '▌' or '│', line, indent)
    end
    -- Folded, a row between what it is about and its threads, and each
    -- thread set in under a mark, so they stand apart from the summary.
    if folded and summary then
      P.add ''
      gutter(P, #P.lines - 1, #P.lines - 1, '▌', line, indent)
    end
    local set_in = vim.tbl_extend('force', columns, { title = columns.title - 2 })
    for i, t in ipairs(g.threads) do
      local last = i == #g.threads
      if not folded then
        P.add ''
        gutter(P, #P.lines - 1, #P.lines - 1, '│', line, indent)
      end
      local p = folded and thread_draw.row(P, r, t, { width = width - 2, indent = inner + 2, columns = set_in, fold = true })
        or thread_draw.row(P, r, t, { width = width, indent = inner, columns = columns })
      out[#out + 1] = p
      if folded then
        gutter(P, p.first, p.last, '▌', line, indent)
        gutter(P, p.first, p.first, '›', line, inner)
      else
        gutter(P, p.first, p.first, last and '└─' or '├─', line, indent)
        if not last then
          gutter(P, p.first + 1, p.last, '│', line, indent)
        end
      end
    end
    part.last = #P.lines - 1
  end
  return out
end

--- A review's overview: its title; what it is about, and its diff's size;
--- its introduction; its threads, by the groups the agent put them in
--- (M.groups); with none, its open threads, two rows each and a blank row
--- between, then its closed ones; how many hunks of its diff no thread is
--- on. With `files`, its open threads' chunks by file instead. Folded,
--- its introduction is its first row and each thread one row.
---@param P thread.Sheet
---@param r thread.Review
---@param o thread.ReviewOpts
---@return thread.Part[]  the review, then what in it goes somewhere
function M.overview(P, r, o)
  local indent = o.indent or P.indent
  local spec = chunk.spec(r.diff)
  local first = P.chunks(text.fit_chunks({ { r.title, 'ThreadTitle' }, { r.status == 'closed' and '  closed' or '', 'ThreadMeta' } }, o.width), indent)
  local out = { { kind = 'review', first = first, last = first, review = r, item = true } } ---@type thread.Part[]
  local said = { { about(r), 'ThreadCrumbHere' } } ---@type thread.Chunks
  if spec then
    local list, err = diff.files(spec)
    if err then
      said[#said + 1] = { ' · git cannot read it: ' .. err, 'ThreadBroken' }
    else
      local add, del = 0, 0
      for _, f in ipairs(list) do
        add, del = add + f.add, del + f.del
      end
      vim.list_extend(
        said,
        { { ' · ' .. text.plural(#list, 'file') .. ' ', 'ThreadMeta' }, { '+' .. add, 'ThreadAdded' }, { ' −' .. del, 'ThreadRemoved' } }
      )
    end
  end
  P.chunks(text.fit_chunks(said, o.width), indent)
  if r.introduction then
    P.add ''
    local whole = not o.fold or (o.open or {})[draw.key(out[1])]
    draw.prose(prose.draw(P, r.introduction, math.min(o.width, 100), { indent = indent, spec = spec, most = not whole and M.FOLDED or nil }), out)
  end
  if o.files then
    P.add ''
    P.chunks(labels.rule('files', o.width), indent)
    P.add ''
    vim.list_extend(out, files.draw(P, r, files.of_review(r), { width = o.width, indent = indent, open = o.open, threads = true, code = o.code }))
  elseif r.groups and #r.groups > 0 then
    vim.list_extend(out, M.groups(P, r, o))
  else
    local open, closed = {}, {} ---@type thread.Thread[], thread.Thread[]
    for _, t in ipairs(r.threads) do
      table.insert(thread.closed(t) and closed or open, t)
    end
    -- One grid for both lists, so the closed line up under the open.
    local columns = thread_draw.columns(r, thread_draw.each(r.threads), o.width)
    for _, list in ipairs { { 'threads', open }, { 'closed', closed } } do
      if #list[2] > 0 then
        P.add ''
        P.chunks(labels.rule(list[1] .. ' · ' .. #list[2], o.width), indent)
        for i, t in ipairs(list[2]) do
          -- Folded, a row each and none between.
          if i == 1 or not o.fold then
            P.add ''
          end
          out[#out + 1] = thread_draw.row(P, r, t, { width = o.width, indent = indent, columns = columns, fold = o.fold })
        end
      end
    end
  end
  local left = spec and #review.left_out(r) or 0
  if left > 0 then
    P.add ''
    P.chunks({ { text.fit(text.plural(left, 'hunk') .. ' of the diff ' .. (left == 1 and 'is' or 'are') .. ' in no thread', o.width), 'ThreadMeta' } }, indent)
  end
  out[1].last = #P.lines - 1
  draw.within(out, 1, { review = r })
  return out
end

return M
