--- A link, as prose writes it: `#12` a thread, `#12.3` its step with id
--- 3, whichever tour it is in, and `other-review#12` the same in another
--- review. A step's id never changes, so a link stays on its step however
--- the agent moves steps or adds them. In format 3, steps and notes share
--- one run of ids, and `#12` is whichever has 12. Here a link is written
--- for a conversation, found in text, and followed to what it names.

local review = require 'thread.model.review'
local thread = require 'thread.model.thread'

local M = {}

---@class (exact) thread.Link
---@field review string|nil  another review's id; none: the one it is written in
---@field thread integer
---@field step integer|nil  its id

--- Where a link is in a run of text: byte columns, from 0 as extmarks
--- count them, its end not in it.
---@class thread.LinkAt
---@field first integer
---@field last integer
---@field link thread.Link

---@param l thread.Link
---@return string
function M.write(l)
  return (l.review or '') .. '#' .. l.thread .. (l.step and ('.' .. l.step) or '')
end

--- The link to a conversation: its thread's, or its step's.
---@param c thread.Conversation
---@return string
function M.to(c)
  -- A format 3 step is known by its own id.
  if c.thread.carrier and c.step then
    return M.write { thread = c.step.id }
  end
  return M.write { thread = c.thread.id, step = c.step and c.step.id }
end

--- Every link in a run of text. A `#` inside a word, a colour like
--- `#4acbe1`, a version like `#1.2.3` and a page's `/notes#12` are none,
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
    until not s:sub(pos, pos + 1):match '^%.%d' or #parts > 2
    if #parts <= 2 and not s:sub(from - 1, from - 1):match '[%w_#/]' and not s:sub(pos, pos):match '[%w_]' then
      local l = { review = head ~= '' and head or nil, thread = parts[1], step = parts[2] } ---@type thread.Link
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

--- A link into a format 3 review: a note's, or a step's, by its id.
---@param l thread.Link
---@param r thread.Review  the one it goes to
---@return thread.Followed|nil, string|nil
local function follow_three(l, r)
  if l.step then
    return nil, string.format("`%s` is format 2's: in format 3 a step is linked by its own id, `#%d`", M.write(l), l.step)
  end
  local t = l.thread ~= 0 and review.find(r, l.thread) or nil
  if t then
    return { review = r, conversation = thread.conversation(t) }
  end
  local carrier = review.carrier(r)
  local s, x ---@type thread.Step|nil, thread.Tour|nil
  if carrier then
    s, x = thread.step(carrier, l.thread)
  end
  if carrier and s then
    return { review = r, conversation = thread.conversation(carrier, s, x) }
  end
  return nil, string.format('`%s` goes to no step or note%s; if it is no link, put it in backticks', M.write(l), l.review and (' of ' .. l.review) or '')
end

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
  if there.format == 3 then
    return follow_three(l, there)
  end
  local t = review.find(there, l.thread)
  if not t then
    return nil, string.format('`%s` goes to no thread%s; if it is no link, put it in backticks', M.write(l), l.review and (' of ' .. l.review) or '')
  end
  local convs = thread.conversations(t)
  if not l.step then
    return { review = there, conversation = convs[1] }
  end
  local s = thread.step(t, l.step)
  if not s then
    local ids = {} ---@type integer[]
    for _, c in ipairs(convs) do
      ids[#ids + 1] = c.step and c.step.id or nil
    end
    table.sort(ids)
    return nil,
      string.format(
        '`%s` goes to no step: %s',
        M.write(l),
        #ids == 0 and string.format('thread %d has none', t.id) or string.format('the step ids of thread %d are %s', t.id, table.concat(ids, ', '))
      )
  end
  for _, c in ipairs(convs) do
    if c.step == s then
      return { review = there, conversation = c }
    end
  end
end

return M
