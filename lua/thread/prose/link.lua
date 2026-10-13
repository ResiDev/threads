--- A link, as prose writes it: `#12` a thread, `#12.3` step 3 of its
--- first tour, `#12.2.3` step 3 of its second, and `other-review#12` the
--- same in another review. Steps have no ids, so a link says where one is:
--- tours count in the order of their messages, and the agent adds a tour
--- or a step only after the others (SKILL.md), so a link once written
--- stays on its step. Here a link is written for a conversation, found in
--- text, and followed to what it names.

local review = require 'thread.model.review'
local thread = require 'thread.model.thread'

local M = {}

---@class (exact) thread.Link
---@field review string|nil  another review's id; none: the one it is written in
---@field thread integer
---@field tour integer|nil   a step's tour: 1 when the link leaves it out
---@field step integer|nil

--- Where a link is in a run of text: byte columns, from 0 as extmarks
--- count them, its end not in it.
---@class thread.LinkAt
---@field first integer
---@field last integer
---@field link thread.Link

---@param l thread.Link
---@return string
function M.write(l)
  local out = (l.review or '') .. '#' .. l.thread
  if l.step then
    if l.tour and l.tour > 1 then
      out = out .. '.' .. l.tour
    end
    out = out .. '.' .. l.step
  end
  return out
end

--- The link to a conversation: its thread's, or its step's.
---@param c thread.Conversation
---@return string
function M.to(c)
  for k, x in ipairs(c.step and thread.tours(c.thread) or {}) do
    for n, s in ipairs(x.steps) do
      if s == c.step then
        return M.write { thread = c.thread.id, tour = k, step = n }
      end
    end
  end
  return M.write { thread = c.thread.id }
end

--- Every link in a run of text. A `#` inside a word, a colour like
--- `#4acbe1`, a version like `#1.2.3.4` and a page's `/notes#12` are none,
--- and a full stop after one ends its sentence. Before the `#`, a review's
--- id: lowercase letters, digits and `-`, as ids are made; what is no id,
--- as in `#3-#5`, is not part of it.
---@param s string
---@return thread.LinkAt[]
function M.find(s)
  local out = {}
  for at in s:gmatch '()#%d' do
    local hash = assert(tonumber(at))
    local head = s:sub(1, hash - 1):match '[a-z0-9-]*$'
    if not (head:match '^[a-z0-9]$' or head:match '^[a-z0-9][a-z0-9-]*[a-z0-9]$') then
      head = ''
    end
    local from = hash - #head
    -- Its numbers, each after a dot that a digit follows.
    local parts, pos = {}, hash ---@type integer[], integer
    repeat
      local n, e = s:match('^[#.](%d+)()', pos)
      parts[#parts + 1], pos = assert(tonumber(n)), assert(tonumber(e))
    until not s:sub(pos, pos + 1):match '^%.%d' or #parts > 3
    if #parts <= 3 and not s:sub(from - 1, from - 1):match '[%w_#/]' and not s:sub(pos, pos):match '[%w_]' then
      local l = { review = head ~= '' and head or nil, thread = parts[1] } ---@type thread.Link
      if parts[3] then
        l.tour, l.step = parts[2], parts[3]
      elseif parts[2] then
        l.tour, l.step = 1, parts[2]
      end
      out[#out + 1] = { first = from - 1, last = pos - 1, link = l }
    end
  end
  return out
end

--- What a link names: its review, and the conversation, its thread's or
--- its step's.
---@class thread.Followed
---@field review thread.Review
---@field conversation thread.Conversation

--- Follow a link from the review it is written in. Nil, and why for the
--- agent, when it goes nowhere.
---@param l thread.Link
---@param r thread.Review  the one it is written in
---@param get fun(id: string): thread.Review|nil, string|nil  another review by its id, or why it cannot be read
---@return thread.Followed|nil, string|nil
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
  local t = review.find(there, l.thread)
  if not t then
    return nil, string.format('`%s` goes to no thread%s; if it is no link, put it in backticks', M.write(l), l.review and (' of ' .. l.review) or '')
  end
  local convs = thread.conversations(t)
  if not l.step then
    return { review = there, conversation = convs[1] }
  end
  local tour = l.tour or 1
  local x = thread.tours(t)[tour]
  local s = x and x.steps[l.step]
  if not x then
    local n = #thread.tours(t)
    return nil, string.format('`%s` goes to no step: thread %d has %s', M.write(l), t.id, n == 0 and 'no tours' or n == 1 and 'one tour' or (n .. ' tours'))
  elseif not s then
    return nil, string.format('`%s` goes to no step: tour %d of thread %d has %d', M.write(l), tour, t.id, #x.steps)
  end
  for _, c in ipairs(convs) do
    if c.step == s then
      return { review = there, conversation = c }
    end
  end
end

return M
