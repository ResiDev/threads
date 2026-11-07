--- What `show.lua --check` reads in a topic's prose, beside what the
--- model checks as it reads (thread.model.topic) and in the code
--- (thread.model.topic.unfound): in everything the agent wrote, each
--- link goes to something there is, each fence is closed, each excerpt
--- lights something the text named, a diff fence leaves no lines out,
--- and a table in a card fits it whole; and apart, that each thread the agent
--- wrote opens with a short lead, and how many threads it opened, past a
--- dozen. A link to nothing is a warning, since `#thread:12` can be text
--- about one; so is a seam link seam cannot show. Your messages are
--- yours, so they are not read.

local chunk = require 'thread.model.chunk'
local fields = require 'thread.model.fields'
local link = require 'thread.prose.link'
local model_prose = require 'thread.model.prose'
local thread = require 'thread.model.thread'
local prose = require 'thread.prose'
local repo = require 'thread.base.repo'
local topic = require 'thread.model.topic'
local text = require 'thread.base.text'

local M = {}

-- A lead's words at most: the point, when, and the ask.
M.LEAD = 60

-- The open threads past which a topic may be more than the user takes
-- in at once.
M.THREADS = 12

-- A table's columns at most, and the widest it draws whole: a step's card
-- has 68 columns for its prose, and a table wider has its widest cells
-- cut short.
M.COLUMNS = 4
M.TABLE_WIDTH = 68

--- How wide a table is drawn with nothing cut: each column its widest
--- cell, ` │ ` between. Nil when it fits and has few enough columns, else
--- what to say of it.
---@param cells thread.Span[][][]
---@param card boolean  drawn in a card, where width counts; a page is wider
---@return string|nil
local function too_wide(cells, card)
  local widths = {} ---@type integer[]
  for _, row in ipairs(cells) do
    for k, cell in ipairs(row) do
      local w = 0
      for _, sp in ipairs(cell) do
        w = w + text.width(sp.text)
      end
      widths[k] = math.max(widths[k] or 0, w)
    end
  end
  local total = 3 * (#widths - 1)
  for _, w in ipairs(widths) do
    total = total + w
  end
  if #widths > M.COLUMNS then
    return string.format('a table has %d columns: keep it to %d, a few words a cell, or split it', #widths, M.COLUMNS)
  end
  if card and total > M.TABLE_WIDTH then
    return string.format('a table is %d columns wide and a card %d, so its widest cells are cut short with …: a few words a cell', total, M.TABLE_WIDTH)
  end
end

--- A thread's lead, read: one there, and short. Whether it ends on a
--- question is the agent's to judge, so it is not read.
---@param p thread.Problems
---@param n thread.Thread
local function lead(p, n)
  local first = n.messages[1]
  if not (first and first.from == 'agent') or thread.closed(n) then
    return
  end
  local where = 'thread ' .. n.id .. ', message 1'
  local said = model_prose.split(first.prose)
  if not said then
    fields.warn(p, where, 'it opens with no lead: first say its point, when it happens and what you ask, in two or three sentences; the reading goes below')
    return
  end
  local words = select(2, said.text:gsub('%S+', ''))
  if words > M.LEAD then
    fields.warn(
      p,
      where,
      string.format('its lead is %d words: keep it to the point and the ask, %d at most, and put the rest under a heading below', words, M.LEAD)
    )
  end
end

--- Whether an excerpt lights any name the text gave it, where its chunk
--- is found; one not found is said elsewhere (thread.model.topic.unfound).
---@param x thread.Excerpt
---@return boolean
local function lights(x)
  local lines = x.chunk and chunk.code(x.chunk, x.spec)
  if not lines then
    return true
  end
  for _, written in ipairs(x.names or {}) do
    for _, f in ipairs(text.forms(written)) do
      for _, l in ipairs(lines) do
        if #text.whole(l, f) > 0 then
          return true
        end
      end
    end
  end
  return false
end

---@param r thread.Topic
---@param get fun(id: string): thread.Topic|nil, string|nil  another topic by its id, for `other#thread:12`, or why it cannot be read
---@return thread.Problems
function M.topic(r, get)
  local p = fields.problems()
  -- Asked of seam only when a seam link is met: thread works without it.
  local seam ---@type { check: fun(target: string, root: string): string|nil }|false|nil
  ---@param where string
  ---@param l thread.SeamLink
  local function seam_link(where, l)
    if seam == nil then
      local ok, m = pcall(require, 'seam')
      seam = ok and m or false
      if not seam then
        fields.warn(p, where, 'seam links go to seam.nvim, which is not installed: they go nowhere without it')
      end
    end
    local why = seam and seam.check(l.target, repo.root())
    if why then
      fields.warn(p, where, string.format('`seam:%s` goes nowhere: %s', l.target, why))
    end
  end
  for _, x in ipairs(topic.prose(r)) do
    if x.from == 'agent' then
      for _, b in ipairs(prose.parse(x.prose, r)) do
        if b.unclosed then
          fields.warn(p, x.where, 'a ``` fence is never closed, so all after it shows as code: end it with ``` on a line of its own')
        end
        if b.excerpt and not lights(b.excerpt) then
          fields.warn(p, x.where, string.format('{{chunk:%s}} lights nothing: name in backticks, in the text before it, what in it to look at', b.excerpt.id))
        end
        if b.lang == 'diff' and vim.iter(b.lines or {}):any(function(l)
          return l:match '^%s*%.%.%.%s*$' or l:match '⋯'
        end) then
          fields.warn(p, x.where, 'a diff fence leaves lines out: write the lines that change and their context, so the fix can be checked')
        end
        local wide = b.cells and too_wide(b.cells, x.card)
        if wide then
          fields.warn(p, x.where, wide)
        end
        local spans = vim.list_extend({}, b.spans or {})
        for _, row in ipairs(b.cells or {}) do
          for _, cell in ipairs(row) do
            vim.list_extend(spans, cell)
          end
        end
        for _, sp in ipairs(spans) do
          if sp.link and sp.link.kind == 'seam' then
            seam_link(x.where, sp.link)
          elseif sp.link then
            local _, why = link.follow(sp.link, r, get)
            if why then
              fields.warn(p, x.where, why)
            end
          elseif not sp.code then
            for kind in sp.text:gmatch '#(%l+):%d' do
              if not vim.tbl_contains(link.KINDS, kind) then
                fields.warn(
                  p,
                  x.where,
                  string.format(
                    '`#%s:` is no link: a link names a step, a thread or a contract, `#step:7`, or a seam screen, `[who calls save](seam:src/store.ts:save@Map)`',
                    kind
                  )
                )
              end
            end
            for wiki in sp.text:gmatch '%[%[[^%]]*%]%]' do
              fields.warn(
                p,
                x.where,
                string.format(
                  '`%s` is no link and shows as written: a link is `#step:7`, `#thread:12`, `#contract:3` or `[who calls save](seam:src/store.ts:save@Map)`',
                  wiki
                )
              )
            end
          end
        end
      end
    end
  end
  return p
end

--- Each thread the agent wrote and the user has not settled, its lead:
--- there, and short. Apart from the rest, since topics written before a
--- thread had a lead read well all the same.
---@param r thread.Topic
---@return thread.Problems
function M.leads(r)
  local p = fields.problems()
  for _, n in ipairs(r.threads) do
    lead(p, n)
  end
  return p
end

--- How many threads the agent opened that are not settled, said when past
--- a dozen: a thread, not a warning, since a big change can need them.
---@param r thread.Topic
---@return string|nil
function M.threads(r)
  local open = 0
  for _, n in ipairs(r.threads) do
    if n.messages[1] and n.messages[1].from == 'agent' and not thread.closed(n) then
      open = open + 1
    end
  end
  if open > M.THREADS then
    return string.format('%d of your threads are open, which may be more than the user takes in at once: could some be a line each in the introduction?', open)
  end
end

return M
