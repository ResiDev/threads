--- What `show.lua --check` reads in a review's prose, beside what the
--- model checks as it reads (thread.model.review) and in the code
--- (thread.model.review.unfound): in everything the agent wrote, each
--- link goes to something there is, each fence is closed, each excerpt
--- lights something the text named, and a diff fence leaves no lines
--- out; and apart, that each note the agent wrote opens with a short
--- lead that asks; and how many notes it opened, past a dozen. A link to nothing is a warning, since `#note:12` can
--- be text about one. Your messages are yours, so they are not read.

local chunk = require 'thread.model.chunk'
local fields = require 'thread.model.fields'
local link = require 'thread.prose.link'
local model_prose = require 'thread.model.prose'
local note = require 'thread.model.note'
local prose = require 'thread.prose'
local review = require 'thread.model.review'
local text = require 'thread.base.text'

local M = {}

-- A lead's words at most: the point, when, and the ask.
M.LEAD = 60

-- The open notes past which a review may be more than the user takes
-- in at once.
M.NOTES = 12

-- The kinds whose lead asks the user something.
local ASKS = { issue = true, decision = true, suggestion = true, question = true }

--- A note's lead, read: one there, short, and asking when its kind asks.
---@param p thread.Problems
---@param n thread.Note
local function lead(p, n)
  local first = n.messages[1]
  if not (first and first.from == 'agent') or note.closed(n) then
    return
  end
  local where = 'note ' .. n.id .. ', message 1'
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
  if ASKS[n.kind] and not said.text:find('?', 1, true) then
    fields.warn(p, where, 'its lead asks nothing: end it with what you want from the user, as a question')
  end
end

--- Whether an excerpt lights any name the text gave it, where its chunk
--- is found; one not found is said elsewhere (thread.model.review.unfound).
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

---@param r thread.Review
---@param get fun(id: string): thread.Review|nil, string|nil  another review by its id, for `other#note:12`, or why it cannot be read
---@return thread.Problems
function M.review(r, get)
  local p = fields.problems()
  for _, x in ipairs(review.prose(r)) do
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
        local spans = vim.list_extend({}, b.spans or {})
        for _, row in ipairs(b.cells or {}) do
          for _, cell in ipairs(row) do
            vim.list_extend(spans, cell)
          end
        end
        for _, sp in ipairs(spans) do
          if sp.link then
            local _, why = link.follow(sp.link, r, get)
            if why then
              fields.warn(p, x.where, why)
            end
          elseif not sp.code then
            for kind in sp.text:gmatch '#(%l+):%d' do
              if not vim.tbl_contains(link.KINDS, kind) then
                fields.warn(p, x.where, string.format('`#%s:` is no link: a link names a step, a note or a contract, `#step:7`', kind))
              end
            end
            for wiki in sp.text:gmatch '%[%[[^%]]*%]%]' do
              fields.warn(p, x.where, string.format('`%s` is no link and shows as written: a link is `#step:7`, `#note:12` or `#contract:3`', wiki))
            end
          end
        end
      end
    end
  end
  return p
end

--- Each note the agent wrote and the user has not settled, its lead:
--- there, short, and asking when its kind asks. Apart from the rest, since reviews written before a
--- note had a lead read well all the same.
---@param r thread.Review
---@return thread.Problems
function M.leads(r)
  local p = fields.problems()
  for _, n in ipairs(r.notes) do
    lead(p, n)
  end
  return p
end

--- How many notes the agent opened that are not settled, said when past
--- a dozen: a note, not a warning, since a big change can need them.
---@param r thread.Review
---@return string|nil
function M.notes(r)
  local open = 0
  for _, n in ipairs(r.notes) do
    if n.messages[1] and n.messages[1].from == 'agent' and not note.closed(n) then
      open = open + 1
    end
  end
  if open > M.NOTES then
    return string.format('%d of your notes are open, which may be more than the user takes in at once: could some be a line each in the introduction?', open)
  end
end

return M
