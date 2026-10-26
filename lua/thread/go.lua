--- How the surfaces reach each other. Each registers what it opens, by
--- name, and `go.open(name, target)` sends a target there without
--- requiring it. `go.press` opens what a part of a drawing means, where
--- it belongs. What one surface needs to know of another, such as the
--- walk you are on, it asks by name too.

local chunk = require 'thread.model.chunk'
local diagram = require 'thread.prose.diagram'
local file = require 'thread.store.file'
local link = require 'thread.prose.link'
local name = require 'thread.prose.name'
local review = require 'thread.model.review'
local source = require 'thread.base.source'

local M = {}

--- Where a target can be opened: the screen at a place (`home`,
--- `review`, `note`, `contract`), or in a float over the code (`focus` a
--- note, `page` a step, `briefing` a tour's); the code at a chunk; a walk,
--- on a tour's briefing or a step; a step's card in the code, gone into;
--- the float you write in; the map; the code painted again now, not
--- when it next would (`paint`); the screen back at a place the trail
--- kept (`place`).
---@alias thread.GoName 'home'|'review'|'note'|'contract'|'focus'|'page'|'briefing'|'code'|'card'|'walk'|'compose'|'map'|'paint'|'place'

--- What is opened. Each name reads what it needs: `code` a chunk, `walk`
--- a tour and maybe the step to start from (none: its briefing),
--- `compose` where to reply, or with none a note to start on `anchor`
--- (none: on no line) in `review` (none: one picked as it is saved).
---@class thread.Target
---@field review thread.Review|nil
---@field tour thread.Tour|nil
---@field step thread.Step|nil
---@field note thread.Note|nil
---@field chunk thread.Chunk|nil
---@field anchor thread.Anchor|nil  compose: the lines a new note is on
---@field contract thread.Contract|nil
---@field briefing boolean|nil  walk: on the tour's briefing, not where you left off
---@field link boolean|nil  card: the cursor on its first link
---@field replies { review: thread.Review, conversation: thread.Conversation }[]|nil  compose: the same reply in each
---@field edit integer|nil  compose: a message of yours in the one conversation of `replies`, by its place, to edit
---@field unsay integer|nil  compose: one to delete
---@field at table|nil  place: where the screen was, as the screen keeps it
---@field row integer|nil  place: the row its cursor was on, 0-based
---@field over boolean|nil  place: in a float over the code

--- Where a walk is, as the walk answers `walking`: on a step, or on its
--- tour's briefing.
---@class thread.Walking
---@field review string
---@field tour integer  its place among the review's tours
---@field step integer|nil  none: on the briefing
---@field dim boolean    the code but the step's chunk dimmed
---@field diff boolean   its review's diff drawn in
---@field removed boolean  its step on lines the diff removed, there only with the diff: drawn in, turned off or not
---@field highlight integer  the step's current highlight, by its number; 0, none
---@field picking boolean|nil  while gs waits for a digit: the card numbers each highlight

--- The step walked's highlights where the code drew its chunk, as the
--- code answers `highlights`: the buffer, the chunk's first line in it,
--- and the list.
---@class thread.Lit
---@field review string
---@field step integer
---@field buf integer
---@field from integer
---@field list thread.Highlight[]

--- Where you write a message in place, as a chat has you: your next
--- under a conversation's last, or one of yours over itself to edit it.
--- `col` and `width` are the columns its text takes in the rows given to
--- `put`, which hangs them under the place (under the message, editing),
--- shown, and says where the editor's first row goes, `top` rows into
--- them: negative, up over the message. `clear` takes them away. The
--- screen answers `reply_at` for a page, the code for a card.
---@class thread.ReplyAt
---@field col integer
---@field width integer
---@field covers integer|nil  editing: the message's rows, which the editor lies over
---@field put fun(rows: table[], top: integer): table|nil  rows of virtual text chunks; an nvim_open_win config's relative, win, bufpos, row and col
---@field clear fun()

---@class thread.Surface
---@field open table<string, fun(target: thread.Target)>  by the names it opens
---@field close fun()|nil  make way for another surface

local surfaces = {} ---@type table<string, thread.Surface>  by its own name
local owner = {} ---@type table<string, string>  a name it opens -> the surface
local answers = {} ---@type table<string, (fun(...): any)[]>

-- Opened over whatever is open, which stays.
local OVER = { compose = true, map = true }

-- Opening these takes you somewhere else: where you were is left first.
local ELSEWHERE = { home = true, review = true, note = true, contract = true, focus = true, page = true, briefing = true, code = true, walk = true }

local leaving = {} ---@type fun()[]
local within = 0 -- while a surface moves inside where you are

--- A surface says what it opens, and how it makes way for another.
---@param surface string  its own name: `screen`, `code`
---@param s thread.Surface
function M.register(surface, s)
  surfaces[surface] = s
  for n in pairs(s.open) do
    owner[n] = surface
  end
end

--- Open a target. `from`, the surface asking, makes way first, unless
--- it opens the target itself or the target opens over it.
---@param what thread.GoName
---@param target thread.Target
---@param from string|nil
function M.open(what, target, from)
  local to = owner[what]
  if not to then
    vim.notify('thread: nothing opens ' .. what, vim.log.levels.WARN)
    return
  end
  if ELSEWHERE[what] then
    M.leave()
  end
  local here = from and surfaces[from]
  if here and here.close and from ~= to and not OVER[what] then
    here.close()
  end
  surfaces[to].open[what](target)
end

--- Hear each time you are about to be taken from where you are: the
--- trail keeps where that was.
---@param fn fun()
function M.on_leave(fn)
  leaving[#leaving + 1] = fn
end

--- You are about to be taken from where you are, by a key or a link: a
--- surface says so when it moves you itself, not through `open`.
function M.leave()
  if within > 0 then
    return
  end
  for _, fn in ipairs(leaving) do
    fn()
  end
end

--- Run `fn` as a move inside where you are, which leaves nothing: a walk
--- from step to step, or the trail taking you back.
---@param fn fun()
function M.within(fn)
  within = within + 1
  local ok, err = pcall(fn)
  within = within - 1
  if not ok then
    error(err, 0)
  end
end

--- Ask a surface to make way, opening nothing.
---@param surface string
function M.close(surface)
  local s = surfaces[surface]
  if s and s.close then
    s.close()
  end
end

--- A surface answers a question by name, for another to ask. Several may
--- answer one: the first to answer, in the order they said so, is heard.
---@param question string
---@param fn fun(...): any
function M.answer(question, fn)
  answers[question] = answers[question] or {}
  table.insert(answers[question], fn)
end

--- Ask what a surface answers; nil when none does.
---@param question string
---@param ... any
---@return any
function M.ask(question, ...)
  for _, fn in ipairs(answers[question] or {}) do
    local got = fn(...)
    if got ~= nil then
      return got
    end
  end
end

--- Follow a link written in `r`: a note to its page, a step to walk
--- to, a contract to its page. False, and why, when it goes nowhere.
---@param r thread.Review
---@param l thread.Link
---@param from string|nil
---@return boolean ok
---@return string|nil why
function M.follow(r, l, from)
  local got, why = link.follow(l, r, function(id)
    local other, errors = review.read(id)
    -- With no file there is no such review, rather than one that cannot
    -- be read: the link says which.
    return other, file.mtime(id) and errors and errors[1] or nil
  end)
  if not got then
    return false, why
  end
  local c = got.conversation
  if c.contract then
    M.open('contract', { review = got.review, contract = c.contract }, from)
  elseif c.step then
    M.open('walk', { review = got.review, tour = c.tour, step = c.step }, from)
  else
    M.open('note', { review = got.review, note = c.note }, from)
  end
  return true
end

--- Where a name in prose points in the code: the best place, near the
--- chunk of the step or note it is written in.
---@param r thread.Review
---@param part thread.Part
---@return thread.Chunk|nil
local function named(r, part)
  local own = review.chunk(r, part.step and part.step.chunk or part.note and part.note.chunk)
  local p = name.resolve(assert(part.name), { file = own and own.file, line = own and own.line })[1]
  if not p then
    return nil
  end
  local line = (source.lines_of { file = p.file } or {})[p.line] or ''
  return { id = '', file = p.file, line = p.line, from = line, rev = 'now' }
end

--- What a part of a drawing means, opened where it belongs: a link
--- followed, code gone to, a step or a tour
--- walked to, a note, a contract or a review read. `row` and `col` find a
--- diagram's box.
---@param r thread.Review
---@param part thread.Part
---@param row integer  0-based
---@param col integer  0-based, in bytes
---@param from string|nil  the surface pressed in
---@return boolean ok  false when it goes nowhere
---@return string|nil why
function M.press(r, part, row, col, from)
  local k = part.kind
  if k == 'link' then
    return M.follow(r, assert(part.link), from)
  end
  local c ---@type thread.Chunk|nil
  if k == 'name' then
    c = named(r, part)
    if not c then
      return false, '`' .. tostring(part.name) .. '` names nothing found in the code'
    end
  elseif k == 'excerpt' then
    c = part.excerpt and part.excerpt.chunk
  elseif k == 'diagram' then
    local node = part.diagram and diagram.at(part.diagram, row, col)
    c = node and node.chunk and review.chunk(r, node.chunk) or nil
  elseif k == 'contract' and part.contract then
    M.open('contract', { review = r, contract = part.contract }, from)
    return true
  elseif k == 'chunk' or k == 'line' or k == 'change' then
    c = part.chunk
  end
  if c then
    if not chunk.locate(c, chunk.spec(r.diff)) then
      return false, c.file .. ' no longer has those lines'
    end
    M.open('code', { review = r, tour = part.tour, step = part.step, note = part.note, chunk = c }, from)
    return true
  end
  if k == 'step' or k == 'tour' then
    -- From a note's or a contract's page, the walk comes back to it.
    M.open('walk', { review = r, tour = part.tour, step = part.step, note = part.note, contract = part.contract }, from)
  elseif k == 'note' then
    M.open('note', { review = r, note = part.note }, from)
  elseif k == 'review' then
    M.open('review', { review = part.review or r }, from)
  else
    return false
  end
  return true
end

return M
