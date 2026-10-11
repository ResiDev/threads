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
---@return 'stage'|'step'|'page'|'aside'
function M.kind(e)
  if type(e.stage) == 'string' and e.stage ~= '' then
    return 'stage'
  elseif e.aside and store.anchored(e) then
    -- A review's affected code or tests: a step off the main path.
    return 'aside'
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

--- The tour a thread leads to: its latest message with a walk, or a
--- review, which is walked as one (thread.review).
---@param c thread.Comment
---@return thread.Stop[]|nil, integer|nil  the stops, and the message's index
function M.of(c)
  for i = #c.messages, 1, -1 do
    local m = c.messages[i]
    local w = m.walk
    if type(m.review) == 'table' then
      w = require('thread.review').walk(m.review)
    end
    if type(w) == 'table' and #w > 0 then
      return w, i
    end
  end
end

--- Whether a thread is a review.
---@param c thread.Comment
function M.is_review(c)
  return require('thread.review').of(c.real or c) ~= nil
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

--- `2 stages · 6 steps`, or `3 steps`; a review's `4 groups · 12 hunks`.
---@param list thread.Stop[]
function M.describe(list)
  if list[1] and list[1].review then
    local groups, hunks = 0, 0
    for _, e in ipairs(list) do
      if e.review.hunk then
        hunks = hunks + 1
      elseif not e.review.item and e.review.group > 0 then
        groups = groups + 1
      end
    end
    return string.format('%d group%s · %d hunk%s', groups, groups == 1 and '' or 's', hunks, hunks == 1 and '' or 's')
  end
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
        local kind = M.kind(e)
        if kind == 'step' or kind == 'aside' then
          d.cards[#d.cards + 1] = M.display(batch, owner, n)
        end
      end
    end
  end
  return d.cards
end

--- The tour's shape as a bar, and where stop `n` is in it: a cell per
--- stop, a gap where each stage starts, filled up to here. A tour too long for that (over 24 stops) gets the
--- even bar of `progress` instead.
---@param list thread.Stop[]
---@param n integer  0: the overview, before the first stop
---@return { [1]: string, [2]: 'done'|'here'|'left' }[]
function M.track(list, n)
  local main = 0
  for _, e in ipairs(list) do
    main = main + (M.kind(e) == 'aside' and 0 or 1)
  end
  if main > 24 then
    local done, left = M.progress(list, n)
    return { { done, 'done' }, { left, 'left' } }
  end
  local out = {}
  for i, e in ipairs(list) do
    local kind = M.kind(e)
    -- A review's lists off the path have no place on it.
    if kind ~= 'aside' then
      if kind == 'stage' and i > 1 then
        out[#out + 1] = { ' ', 'left' }
      end
      local state = i < n and 'done' or i == n and 'here' or 'left'
      out[#out + 1] = { state == 'left' and '▱' or '▰', state }
    end
  end
  return out
end

--- How far through a tour stop `n` is, counted as its place is (`stage
--- 2/4` in stages, `step 3/9` in steps), as a bar: at most 12 cells, so a
--- long tour fits too.
---@param list thread.Stop[]
---@param n integer
---@return string done, string left
function M.progress(list, n)
  local items, stages, steps = M.outline(list)
  local it = items[n]
  local total, done = #list, n
  if it and it.kind == 'stage' then
    total, done = stages, it.stage
  elseif it and it.kind == 'step' then
    total, done = steps, it.step
  end
  total = math.max(total, 1)
  local cells = math.min(total, 12)
  local filled = math.floor(done / total * cells + 0.5)
  return string.rep('▰', filled), string.rep('▱', cells - filled)
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
  if it.e.position then
    return it.e.position
  end
  if it.kind == 'stage' then
    return string.format('stage %d/%d', it.stage, stages)
  elseif it.kind == 'step' then
    return string.format('step %d/%d', it.step, steps)
  end
  return string.format('page %d/%d', n, #list)
end

return M
