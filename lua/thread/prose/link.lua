--- A link, as prose writes it. In format 3 it names what it goes to and
--- its id, as each kind counts its own: `#step:7`, `#note:12`,
--- `#contract:3`, and `other-review#note:12` the same in another review.
--- In format 2, `#12` a thread, `#12.3` its step with id 3, whichever tour
--- it is in. An id never changes, so a link stays on what it names
--- however the agent moves steps or adds them. A bare `#7` in format 3 is
--- how links were written when steps and notes shared one run of ids: it
--- goes to whichever has 7, and is told to name it. Here a link is
--- written for a conversation, found in text, and followed to what it
--- names.

local contract = require 'thread.model.contract'
local review = require 'thread.model.review'
local thread = require 'thread.model.thread'

local M = {}

--- What a format 3 link can name.
M.KINDS = { 'step', 'note', 'contract' }

---@alias thread.LinkKind 'step'|'note'|'contract'

---@class (exact) thread.Link
---@field review string|nil  another review's id; none: the one it is written in
---@field kind thread.LinkKind|nil  format 3's: what it names; none: a bare `#12`
---@field id integer  a thread's, or what `kind` names
---@field step integer|nil  format 2's: its thread's step with this id

--- Where a link is in a run of text: byte columns, from 0 as extmarks
--- count them, its end not in it.
---@class thread.LinkAt
---@field first integer
---@field last integer
---@field link thread.Link

---@param l thread.Link
---@return string
function M.write(l)
  return (l.review or '') .. '#' .. (l.kind and (l.kind .. ':') or '') .. l.id .. (l.step and ('.' .. l.step) or '')
end

--- The link to a conversation: its thread's, or its step's; in format 3
--- its step's, its note's or its contract's.
---@param c thread.Conversation
---@return string
function M.to(c)
  if c.contract then
    local id = c.contract.id
    -- One named before contracts were numbered is linked as it was.
    if type(id) == 'string' then
      return '[[' .. id .. ']]'
    end
    return M.write { kind = 'contract', id = id }
  end
  if c.thread.carrier and c.step then
    return M.write { kind = 'step', id = c.step.id }
  elseif c.thread.note then
    return M.write { kind = 'note', id = c.thread.id }
  end
  return M.write { id = c.thread.id, step = c.step and c.step.id }
end

local KIND = {} ---@type table<string, true>
for _, k in ipairs(M.KINDS) do
  KIND[k] = true
end

--- Every link in a run of text. A `#` inside a word, a colour like
--- `#4acbe1`, a version like `#1.2.3` and a page's `/notes#12` are none,
--- nor is a kind no link names, `#tour:1`, and a full stop after one ends
--- its sentence. Before the `#`, a review's id: lowercase letters, digits
--- and `-`, as ids are made; what is no id, as in `#3-#5`, is not part of
--- it.
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
    local l, pos ---@type thread.Link|nil, integer
    local kind, n, e = s:match('^#(%l+):(%d+)()', hash)
    if kind and KIND[kind] then
      l, pos = { kind = kind, id = assert(tonumber(n)) }, assert(tonumber(e))
      -- `#note:12.3` and `#note:12:3` are no links.
      if s:sub(pos, pos + 1):match '^[.:]%d' then
        l = nil
      end
    elseif s:match('^#%d', hash) then
      -- Its numbers, each after a dot that a digit follows.
      local parts = {} ---@type integer[]
      pos = hash
      repeat
        local d, de = s:match('^[#.](%d+)()', pos)
        parts[#parts + 1], pos = assert(tonumber(d)), assert(tonumber(de))
      until not s:sub(pos, pos + 1):match '^%.%d' or #parts > 2
      l = #parts <= 2 and { id = parts[1], step = parts[2] } or nil
    end
    if l and not s:sub(from - 1, from - 1):match '[%w_#/]' and not s:sub(pos, pos):match '[%w_]' then
      l.review = head ~= '' and head or nil
      out[#out + 1] = { first = from - 1, last = pos - 1, link = l }
    end
  end
  return out
end

--- What a link names: its review, and the conversation, its thread's or
--- its step's, or in format 3 its step's, its note's or its contract's.
---@class thread.Followed
---@field review thread.Review
---@field conversation thread.Conversation

--- A link into a format 3 review, by what it names and its id. A bare
--- `#7` goes to the step or the note that has 7, and says how to write
--- it; when both have 7 it goes nowhere, and that is an error.
---@param l thread.Link
---@param r thread.Review  the one it goes to
---@return thread.Followed|nil, string|nil why, boolean|nil wrong
local function follow_three(l, r)
  local of = l.review and (' of ' .. l.review) or ''
  if l.step then
    return nil,
      string.format(
        "`%s` is format 2's: in format 3 a step is linked by its own id, `%s`",
        M.write(l),
        M.write { review = l.review, kind = 'step', id = l.step }
      )
  end
  local carrier = review.carrier(r)
  ---@type table<thread.LinkKind, fun(id: integer): thread.Conversation|nil>
  local find = {
    step = function(id)
      local s, x ---@type thread.Step|nil, thread.Tour|nil
      if carrier then
        s, x = thread.step(carrier, id)
      end
      return s and thread.conversation(assert(carrier), s, x) or nil
    end,
    note = function(id)
      local t = id ~= 0 and review.find(r, id) or nil
      return t and thread.conversation(t) or nil
    end,
    contract = function(id)
      local c = contract.find(r, id)
      return c and carrier and thread.about(carrier, c) or nil
    end,
  }
  if l.kind then
    local c = find[l.kind](l.id)
    if c then
      return { review = r, conversation = c }
    end
    return nil, string.format('`%s` goes to no %s%s; if it is no link, put it in backticks', M.write(l), l.kind, of)
  end
  local s, n = find.step(l.id), find.note(l.id)
  ---@param kind thread.LinkKind
  ---@return string
  local function named(kind)
    return M.write { review = l.review, kind = kind, id = l.id }
  end
  if s and n then
    return nil,
      string.format('`%s` is step %d and note %d both%s: name which it goes to, `%s` or `%s`', M.write(l), l.id, l.id, of, named 'step', named 'note'),
      true
  elseif s or n then
    return { review = r, conversation = assert(s or n) }, string.format('`%s` names no kind: write it `%s`', M.write(l), named(s and 'step' or 'note'))
  end
  return nil, string.format('`%s` goes to no step or note%s; if it is no link, put it in backticks', M.write(l), of)
end

--- Follow a link from the review it is written in. Nil, and why for the
--- agent, when it goes nowhere. A link written as format 3's were before
--- each kind counted its own ids goes where it did, and why says how to
--- write it now. `wrong`: why is an error, not something to tidy.
---@param l thread.Link
---@param r thread.Review  the one it is written in
---@param get fun(id: string): thread.Review|nil, string|nil  another review by its id, or why it cannot be read
---@return thread.Followed|nil, string|nil why, boolean|nil wrong
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
  if l.kind then
    return nil, string.format("`%s` is format 3's: in format 2 a link is a thread's number, `#12`, or its step's, `#12.3`", M.write(l))
  end
  local t = review.find(there, l.id)
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
