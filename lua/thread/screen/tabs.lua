--- A review on the screen is four tabs, Overview, Contracts, Tours and
--- Notes, which H and L go between. Each is a spec here: its title, how
--- wide its column is, whether the files go down its right, what its
--- items are, the keys its bottom row lists, and how it draws. The
--- screen keeps the id of the one shown and asks this for the rest.

local contracts = require 'thread.draw.contracts'
local inbox = require 'thread.draw.inbox'
local review = require 'thread.model.review'
local review_draw = require 'thread.draw.review'
local tour = require 'thread.model.tour'
local tour_draw = require 'thread.draw.tour'

local M = {}

---@alias thread.TabId 'overview'|'contracts'|'tours'|'notes'

--- How a tab draws its column: where it starts, how wide it is, what is
--- opened.
---@class thread.TabOpts
---@field indent integer
---@field width integer
---@field open table<string, true>  items drawn whole, by draw.key
---@field here string|nil  the item opened under the cursor, by draw.key
---@field touches thread.Touches

--- A key the bottom row lists, and what it does there; a label of nil
--- leaves the key out.
---@alias thread.TabKey { [1]: string, [2]: string|fun(r: thread.Review, p: thread.Part|nil): string|nil }

---@class thread.Tab
---@field id thread.TabId
---@field title string
---@field measure integer  its column's width, centred, when no files are beside it
---@field files boolean  the files down the right, in a window wide enough
---@field noun string|nil  the kind of part its items are, which the bottom row counts: `2 of 8`
---@field opens boolean|nil  the item under the cursor opens under its row
---@field keys thread.TabKey[]  the bottom row's, after H/L and before ?
---@field draw fun(P: thread.Sheet, r: thread.Review, o: thread.TabOpts): thread.Part[]

-- A list reads well this wide, prose a little narrower.
local LIST, PROSE = 100, 88

--- What `t` walks, said: the tour under the cursor, else the review's
--- first; with `from`, the step it picks up at once some is walked.
---@param r thread.Review
---@param p thread.Part|nil
---@param from boolean
---@return string|nil
local function walks(r, p, from)
  local x = (p and p.tour) or tour.list(r)[1]
  if not x then
    return nil
  end
  local i = from and tour.walked(r, x) > 0 and tour.next(r, x)
  if i then
    return 'walk from step ' .. x.steps[i].id
  end
  return 'walk tour ' .. (review.tour_place(r, x) or x.title)
end

---@type thread.Tab[]
M.LIST = {
  {
    id = 'overview',
    title = 'Overview',
    measure = PROSE,
    files = false,
    keys = {
      { 'w/b', 'link to link' },
      { '⏎', 'follow it' },
      {
        't',
        function(r, p)
          return walks(r, p, false)
        end,
      },
    },
    draw = function(P, r, o)
      return review_draw.head(P, r, { width = o.width, indent = o.indent })
    end,
  },
  {
    id = 'contracts',
    title = 'Contracts',
    measure = LIST,
    files = true,
    noun = 'contract',
    keys = { { 'j/k', 'contract' }, { '⏎', 'its page' }, { 'r', 'reply' } },
    draw = function(P, r, o)
      return contracts.draw(P, r.contracts, { width = o.width, indent = o.indent, all = true, review = r })
    end,
  },
  {
    id = 'tours',
    title = 'Tours',
    measure = LIST,
    files = true,
    noun = 'tour',
    keys = {
      { 'j/k', 'tour' },
      { '⏎', 'briefing' },
      {
        't',
        function(r, p)
          return walks(r, p, true)
        end,
      },
    },
    draw = function(P, r, o)
      -- A tour opened is unfolded while it is.
      local groups = {} ---@type table<string, boolean>
      for key in pairs(o.open) do
        if key:find '^tour:' then
          groups[key] = false
        end
      end
      return tour_draw.sections(P, r, { width = o.width, indent = o.indent, open = o.open, groups = groups })
    end,
  },
  {
    id = 'notes',
    title = 'Notes',
    measure = LIST,
    files = false,
    noun = 'note',
    opens = true,
    keys = { { 'j/k', 'note' }, { '⏎', 'its page' }, { 'r', 'reply' }, { 's', 'settle' } },
    draw = function(P, r, o)
      return inbox.draw(P, r, { width = o.width, indent = o.indent, here = o.here })
    end,
  },
}

local by = {} ---@type table<thread.TabId, thread.Tab>
for _, t in ipairs(M.LIST) do
  by[t.id] = t
end

--- The tab of an id.
---@param id thread.TabId
---@return thread.Tab
function M.get(id)
  return assert(by[id], id)
end

--- The tab `d` from one, round from the last to the first.
---@param id thread.TabId
---@param d 1|-1
---@return thread.TabId
function M.step(id, d)
  for i, t in ipairs(M.LIST) do
    if t.id == id then
      return M.LIST[(i - 1 + d) % #M.LIST + 1].id
    end
  end
  return M.LIST[1].id
end

-- The window narrower than this, the files beside are left out.
M.WIDE = 120

-- Columns the files take, the line between them and the page included.
M.FILES = 35

--- Where a page's column goes in a window `width` wide: down the left
--- with the files beside it from column `files`, when it has them and
--- there is room; else centred, as wide as it reads well.
---@class thread.Frame
---@field indent integer
---@field width integer
---@field files integer|nil  the column of the line between the page and the files

---@param tab { files: boolean, measure: integer }
---@param width integer  the window's
---@return thread.Frame
function M.frame(tab, width)
  if tab.files and width >= M.WIDE then
    local files = width - M.FILES
    return { indent = 3, width = files - 6, files = files }
  end
  local w = math.max(20, math.min(tab.measure, width - 8))
  return { indent = math.max(0, math.floor((width - w) / 2)), width = w }
end

return M
