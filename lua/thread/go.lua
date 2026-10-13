--- How the surfaces reach each other. Each registers what it opens, by
--- name, and `go.open(name, target)` sends a target there without
--- requiring it. `go.press` opens what a part of a drawing means, where
--- it belongs. What one surface needs to know of another, such as the
--- walk you are on, it asks by name too.

local actions = require 'thread.actions'
local chunk = require 'thread.model.chunk'
local diagram = require 'thread.prose.diagram'
local link = require 'thread.prose.link'
local name = require 'thread.prose.name'
local review = require 'thread.model.review'
local source = require 'thread.base.source'

local M = {}

--- Where a target can be opened: the screen at a depth (`home`, `review`,
--- `thread`), or in a float over the code (`focus` a thread, `page` a
--- step); the code at a chunk; a walk; the float you write in; the map.
---@alias thread.GoName 'home'|'review'|'thread'|'focus'|'page'|'code'|'walk'|'compose'|'map'

--- What is opened. Each name reads what it needs: `code` a chunk, `walk`
--- a thread's tour and maybe the step to start from, `compose` where to
--- reply, or with none a thread to start on `chunk` (none: on no line) in
--- `review` (none: one picked as it is saved).
---@class thread.Target
---@field review thread.Review|nil
---@field thread thread.Thread|nil
---@field tour thread.Tour|nil
---@field step thread.Step|nil
---@field chunk thread.Chunk|nil
---@field replies { review: thread.Review, conversation: thread.Conversation }[]|nil  compose: the same reply in each

--- Where a walk is, as the walk answers `walking`.
---@class thread.Walking
---@field review string
---@field thread integer
---@field step integer

---@class thread.Surface
---@field open table<string, fun(target: thread.Target)>  by the names it opens
---@field close fun()|nil  make way for another surface

local surfaces = {} ---@type table<string, thread.Surface>  by its own name
local owner = {} ---@type table<string, string>  a name it opens -> the surface
local answers = {} ---@type table<string, fun(...): any>

-- Opened over whatever is open, which stays.
local OVER = { compose = true, map = true }

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
  local here = from and surfaces[from]
  if here and here.close and from ~= to and not OVER[what] then
    here.close()
  end
  surfaces[to].open[what](target)
end

--- Ask a surface to make way, opening nothing.
---@param surface string
function M.close(surface)
  local s = surfaces[surface]
  if s and s.close then
    s.close()
  end
end

--- A surface answers a question by name, for another to ask.
---@param question string
---@param fn fun(...): any
function M.answer(question, fn)
  answers[question] = fn
end

--- Ask what a surface answers; nil when none does.
---@param question string
---@param ... any
---@return any
function M.ask(question, ...)
  local fn = answers[question]
  if fn then
    return fn(...)
  end
end

--- Follow a link written in `r`: a thread to the screen, a step to walk
--- to. False, and why, when it goes nowhere.
---@param r thread.Review
---@param l thread.Link
---@param from string|nil
---@return boolean ok
---@return string|nil why
function M.follow(r, l, from)
  local got, why = link.follow(l, r, function(id)
    local other, errors = review.read(id)
    return other, errors and errors[1]
  end)
  if not got then
    return false, why
  end
  local c = got.conversation
  if c.step then
    M.open('walk', { review = got.review, thread = c.thread, tour = c.tour, step = c.step }, from)
  else
    M.open('thread', { review = got.review, thread = c.thread }, from)
  end
  return true
end

--- Where a name in a thread's prose points in the code: the best place.
---@param part thread.Part
---@return thread.Chunk|nil
local function named(part)
  local t = part.thread
  local at = part.step and part.step.chunk or (t and t.chunk)
  local p = name.resolve(assert(part.name), { file = at and at.file, line = at and at.line })[1]
  if not p then
    return nil
  end
  local c = { file = p.file, line = p.line, text = '' } ---@type thread.Chunk
  c.text = (source.lines_of(c) or {})[p.line] or ''
  return c
end

--- What a part of a drawing means, opened where it belongs: a link
--- followed, code gone to, a step walked to, a thread or a review read,
--- a check run. `row` and `col` find a diagram's box.
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
    c = named(part)
    if not c then
      return false, '`' .. tostring(part.name) .. '` names nothing found in the code'
    end
  elseif k == 'excerpt' then
    c = part.excerpt and part.excerpt.chunk
  elseif k == 'diagram' then
    local node = part.diagram and diagram.at(part.diagram, row, col)
    if node and node.file then
      c = { file = node.file, line = node.line or 1, text = node.text or '', side = node.side }
    end
  elseif k == 'chunk' or k == 'line' or k == 'change' or k == 'note' then
    c = part.chunk
  end
  if c then
    if not chunk.locate(c, chunk.spec(r.diff)) then
      return false, c.file .. ' no longer has that line'
    end
    M.open('code', { review = r, thread = part.thread, chunk = c }, from)
    return true
  end
  if k == 'step' or k == 'tour' then
    M.open('walk', { review = r, thread = part.thread, tour = part.tour, step = part.step }, from)
  elseif k == 'thread' then
    M.open('thread', { review = r, thread = part.thread }, from)
  elseif k == 'review' then
    M.open('review', { review = part.review or r }, from)
  elseif k == 'check' then
    actions.run(assert(part.check))
  else
    return false
  end
  return true
end

return M
