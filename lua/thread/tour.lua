--- Tours. An agent's message can carry a `walk`: the stops of a tour, in
--- order, the way a `.tour` file lists them. A stop is one of:
---
--- - a **stage**: `stage` (its title), `point`, `body`, `verdict`,
---   `severity`, `diagram`. A page; the steps after it are its own.
--- - a **step**: `file`, `text`, `line` (`lines`, `rev`), `title`, `body`,
---   `notes`, `diagram`. A card above its line.
--- - a **page**: `title`, `body`, `diagram` and no file. A page.
---
--- Stops are not threads: they have no status and are no one's move. Reply
--- in one and a thread is made for it, `on = { thread = <owner>, step = <n> }`,
--- anchored where the stop is; from then on it is a conversation like any
--- other, drawn with the stop's words on top.

local store = require 'thread.store'

local M = {}

---@class thread.Stop
---@field stage string|nil
---@field point string|nil
---@field title string|nil
---@field body string|nil
---@field file string|nil
---@field text string|nil
---@field line integer|nil
---@field lines integer|nil
---@field rev string|nil
---@field notes thread.Note[]|nil
---@field diagram table|nil
---@field verdict string|nil
---@field severity string|nil

---@param e thread.Stop
---@return 'stage'|'step'|'page'
function M.kind(e)
  if type(e.stage) == 'string' and e.stage ~= '' then
    return 'stage'
  elseif store.anchored(e) then
    return 'step'
  end
  return 'page'
end

local function first_sentence(text)
  local s = vim.trim((text or ''):gsub('```.-```', ''))
  s = s:match '^(.-[.!?])%s' or s:match '^([^\n]*)' or s
  return (s:gsub('[`*]', ''))
end

---@param e thread.Stop
---@return string
function M.title(e)
  if M.kind(e) == 'stage' then
    return e.stage
  end
  if type(e.title) == 'string' and e.title ~= '' then
    return e.title
  end
  return first_sentence(e.body)
end

--- What a stop says, as the text of a message: a stage's point first, in
--- bold, then its body.
---@param e thread.Stop
---@return string
function M.body(e)
  local parts = {}
  if type(e.point) == 'string' and e.point ~= '' then
    parts[#parts + 1] = '**' .. e.point .. '**'
  end
  if type(e.body) == 'string' and e.body ~= '' then
    parts[#parts + 1] = e.body
  end
  return table.concat(parts, '\n\n')
end

--- The tour a thread leads to: its latest message with a walk.
---@param c thread.Comment
---@return thread.Stop[]|nil, integer|nil  the stops, and the message's index
function M.of(c)
  for i = #c.messages, 1, -1 do
    local w = c.messages[i].walk
    if type(w) == 'table' and #w > 0 then
      return w, i
    end
  end
end

function M.leads(c)
  return M.of(c) ~= nil
end

---@class thread.OutlineItem
---@field n integer       the stop's index in the walk
---@field e thread.Stop
---@field kind string
---@field stage integer   the stage it is in (or is); 0 before the first
---@field step integer|nil  its number among the steps, for a step

--- The stops with their numbers: the stage each is in, and each step's
--- number among the steps.
---@param list thread.Stop[]
---@return thread.OutlineItem[], integer stages, integer steps
function M.outline(list)
  local out, stage, step = {}, 0, 0
  for n, e in ipairs(list) do
    local kind = M.kind(e)
    if kind == 'stage' then
      stage = stage + 1
    end
    local item = { n = n, e = e, kind = kind, stage = stage }
    if kind == 'step' then
      step = step + 1
      item.step = step
    end
    out[#out + 1] = item
  end
  return out, stage, step
end

--- `2 stages · 6 steps`, or `3 steps`.
---@param list thread.Stop[]
function M.describe(list)
  local _, stages, steps = M.outline(list)
  local parts = {}
  if stages > 0 then
    parts[#parts + 1] = stages .. (stages == 1 and ' stage' or ' stages')
  end
  parts[#parts + 1] = steps .. (steps == 1 and ' step' or ' steps')
  return table.concat(parts, ' · ')
end

--- Every thread that leads to a tour.
---@param batch thread.Batch
---@return thread.Comment[]
function M.tours(batch)
  local out = {}
  for _, c in ipairs(batch.data.threads) do
    if M.leads(c) then
      out[#out + 1] = c
    end
  end
  return out
end

--- What is worked out once per load of the batch: which thread is the
--- conversation in each stop.
local function derived(batch)
  if not batch.derived then
    local on = {}
    for _, c in ipairs(batch.data.threads) do
      if type(c.on) == 'table' and c.on.thread and c.on.step then
        local key = c.on.thread .. ':' .. c.on.step
        on[key] = on[key] or c
      end
    end
    batch.derived = { on = on }
  end
  return batch.derived
end

--- The thread replying in stop `n` of `owner`'s tour, if anyone has.
---@param batch thread.Batch
---@param owner integer
---@param n integer
---@return thread.Comment|nil
function M.thread_at(batch, owner, n)
  return derived(batch).on[owner .. ':' .. n]
end

--- Every conversation in a tour's stops.
---@param batch thread.Batch
---@param owner integer
---@return integer
function M.talks(batch, owner)
  local n = 0
  for key in pairs(derived(batch).on) do
    if key:match '^(%d+):' == tostring(owner) then
      n = n + 1
    end
  end
  return n
end

--- The tour a reply thread is in: the thread that leads to it, the stop,
--- and its index.
---@param batch thread.Batch
---@param c thread.Comment
---@return thread.Comment|nil owner, thread.Stop|nil, integer|nil
function M.owner(batch, c)
  local on = c.stop or c.on
  if type(on) ~= 'table' then
    return nil
  end
  local id = on.owner or on.thread
  local n = on.n or on.step
  local o = store.find(batch, id)
  local list = o and M.of(o)
  return o, list and list[n], n
end

--- A stop as the code draws it, shaped like a thread: the conversation in
--- it with the stop's words as its first message, or until someone replies
--- a stand-in (`virtual`) with only those words.
---@param batch thread.Batch
---@param owner thread.Comment
---@param n integer
---@return thread.Comment|nil
function M.display(batch, owner, n)
  local list = M.of(owner)
  local e = list and list[n]
  if not e then
    return nil
  end
  local msg = { from = 'agent', text = M.body(e), notes = e.notes, diagram = e.diagram, verdict = e.verdict, severity = e.severity }
  local stop = { owner = owner.id, n = n }
  local real = M.thread_at(batch, owner.id, n)
  if real then
    local d = {}
    for k, v in pairs(real) do
      d[k] = v
    end
    d.messages = { msg }
    vim.list_extend(d.messages, real.messages)
    d.real, d.stop = real, stop
    d.title = real.title or M.title(e)
    return d
  end
  return {
    id = 's' .. owner.id .. '.' .. n,
    file = e.file,
    text = e.text,
    line = e.line,
    lines = e.lines,
    rev = e.rev,
    title = M.title(e),
    status = 'open',
    messages = { msg },
    stop = stop,
    virtual = true,
  }
end

--- Every step of every tour, drawn as cards in the code.
---@param batch thread.Batch
---@return thread.Comment[]
function M.cards(batch)
  local d = derived(batch)
  if not d.cards then
    d.cards = {}
    for _, owner in ipairs(M.tours(batch)) do
      for n, e in ipairs(M.of(owner)) do
        if M.kind(e) == 'step' then
          d.cards[#d.cards + 1] = M.display(batch, owner, n)
        end
      end
    end
  end
  return d.cards
end

--- Where a stop is in its tour, said short: `stage 2/4`, `step 3/9`.
---@param list thread.Stop[]
---@param n integer
---@return string
function M.position(list, n)
  local items, stages, steps = M.outline(list)
  local it = items[n]
  if not it then
    return ''
  end
  if it.kind == 'stage' then
    return string.format('stage %d/%d', it.stage, stages)
  elseif it.kind == 'step' then
    return string.format('step %d/%d', it.step, steps)
  end
  return string.format('page %d/%d', n, #list)
end

return M
