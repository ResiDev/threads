--- What `show.lua --check` reads in a review's prose, beside what the
--- model checks (thread.model.review.unfound): in its introduction and in
--- everything the agent wrote in an open thread, each excerpt is a chunk in
--- the code now, each link goes to a thread or a step there is, and each
--- fence is closed. An excerpt is checked as any chunk is, so one that is
--- not there is an error; a link to nothing is a warning, since `#12` can
--- be another thing's number. Your messages are yours, so they are not
--- read.

local chunk = require 'thread.model.chunk'
local excerpt = require 'thread.prose.excerpt'
local fields = require 'thread.model.fields'
local link = require 'thread.prose.link'
local prose = require 'thread.prose'
local thread = require 'thread.model.thread'

local M = {}

---@param r thread.Review
---@param get fun(id: string): thread.Review|nil, string|nil  another review by its id, for `other#12`, or why it cannot be read
---@return thread.Problems
function M.review(r, get)
  local p = fields.problems()
  local spec = chunk.spec(r.diff)
  ---@param s string|nil
  ---@param where string
  local function text(s, where)
    local k = 0
    for _, b in ipairs(prose.parse(s)) do
      if b.excerpt then
        k = k + 1
        if b.unclosed then
          fields.bad(p, where .. ', excerpt ' .. k, 'its ```code fence is never closed: end it with ``` on a line of its own')
        else
          excerpt.check(p, where .. ', excerpt ' .. k, b.excerpt, spec)
        end
      elseif b.unclosed then
        fields.warn(p, where, 'a ``` fence is never closed, so all after it shows as code: end it with ``` on a line of its own')
      end
      for _, sp in ipairs(b.spans or {}) do
        if sp.link then
          local _, why = link.follow(sp.link, r, get)
          if why then
            fields.warn(p, where, why)
          end
        end
      end
    end
  end
  ---@param x { text: string|nil, notes: thread.Note[]|nil, checks: thread.Check[]|nil }
  ---@param where string
  local function said(x, where)
    text(x.text, where)
    for i, n in ipairs(x.notes or {}) do
      text(n.note, where .. ', note ' .. i)
    end
    for i, c in ipairs(x.checks or {}) do
      text(c.text, where .. ', check ' .. i)
    end
  end
  ---@param messages thread.Message[]
  ---@param where string
  ---@param each fun(m: thread.Message, mwhere: string)|nil
  local function conversation(messages, where, each)
    for i, m in ipairs(messages) do
      local mwhere = where .. ', message ' .. i
      if m.from == 'agent' then
        said(m, mwhere)
        if each then
          each(m, mwhere)
        end
      end
    end
  end
  text(r.introduction, 'the review, introduction')
  for _, t in ipairs(r.threads) do
    if not thread.closed(t) then
      local where = 'thread ' .. t.id
      said({ checks = t.checks }, where)
      conversation(t.messages, where, function(m, mwhere)
        for k, x in ipairs(m.tours or {}) do
          local xwhere = mwhere .. ', tour ' .. k
          text(x.introduction, xwhere .. ', introduction')
          for j, s in ipairs(x.steps) do
            local swhere = xwhere .. ', step ' .. j
            said(s, swhere)
            conversation(s.messages, swhere)
          end
        end
      end)
    end
  end
  return p
end

return M
