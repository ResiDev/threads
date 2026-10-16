--- A link, as prose writes it: what it goes to and its id, as each kind
--- counts its own, `#step:7`, `#note:12`, `#contract:3`; and
--- `other-review#note:12` the same in another review. An id never
--- changes, so a link stays on what it names however the agent moves
--- steps or adds them. Here a link is found in text and followed to the
--- conversation it names.

local review = require 'thread.model.review'

local M = {}

--- What a link can name.
M.KINDS = { 'step', 'note', 'contract' }

---@alias thread.LinkKind 'step'|'note'|'contract'

---@class (exact) thread.Link
---@field review string|nil  another review's id; none: the one it is written in
---@field kind thread.LinkKind
---@field id integer

--- Where a link is in a run of text: byte columns, from 0 as extmarks
--- count them, its end not in it.
---@class thread.LinkAt
---@field first integer
---@field last integer
---@field link thread.Link

---@param l thread.Link
---@return string
function M.write(l)
  return (l.review or '') .. '#' .. l.kind .. ':' .. l.id
end

local KIND = {} ---@type table<string, true>
for _, k in ipairs(M.KINDS) do
  KIND[k] = true
end

--- Every link in a run of text. A `#` inside a word, a colour like
--- `#4acbe1`, a page's `/notes#12` and a kind no link names, `#tour:1`,
--- are none, and a full stop after one ends its sentence. Before the `#`,
--- a review's id: lowercase letters, digits and `-`, as ids are made.
---@param s string
---@return thread.LinkAt[]
function M.find(s)
  local out = {}
  for at in s:gmatch '()#' do
    local hash = assert(tonumber(at))
    local head = s:sub(1, hash - 1):match '[a-z0-9-]*$'
    if not (head:match '^[a-z0-9]$' or head:match '^[a-z0-9][a-z0-9-]*[a-z0-9]$') then
      head = ''
    end
    local from = hash - #head
    local kind, n, e = s:match('^#(%l+):(%d+)()', hash)
    local pos = e and assert(tonumber(e))
    -- `#note:12.3` and `#note:12:3` are no links.
    if kind and KIND[kind] and pos and not s:sub(pos, pos + 1):match '^[.:]%d' then
      if not s:sub(from - 1, from - 1):match '[%w_#/]' and not s:sub(pos, pos):match '[%w_]' then
        ---@cast kind thread.LinkKind
        out[#out + 1] = { first = from - 1, last = pos - 1, link = { kind = kind, id = assert(tonumber(n)), review = head ~= '' and head or nil } }
      end
    end
  end
  return out
end

--- What a link names: its review, and the conversation it goes to.
---@class thread.Followed
---@field review thread.Review
---@field conversation thread.Conversation

--- Follow a link from the review it is written in. Nil, and why for the
--- agent, when it goes nowhere.
---@param l thread.Link
---@param r thread.Review  the one it is written in
---@param get fun(id: string): thread.Review|nil, string|nil  another review by its id, or why it cannot be read
---@return thread.Followed|nil, string|nil why
function M.follow(l, r, get)
  local there = r
  if l.review and l.review ~= r.id then
    local other, why = get(l.review)
    if not other then
      return nil,
        why and string.format('`%s` goes to review %s, which cannot be read: %s', M.write(l), l.review, why) or string.format(
          '`%s` goes to no review %s',
          M.write(l),
          l.review
        )
    end
    there = other
  end
  local c = review.conversation(there, l.kind, l.id)
  if not c then
    return nil, string.format('`%s` goes to no %s%s; if it is no link, put it in backticks', M.write(l), l.kind, l.review and (' of ' .. l.review) or '')
  end
  return { review = there, conversation = c }
end

return M
