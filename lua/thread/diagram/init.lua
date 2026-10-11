--- Diagrams inside a step's card: validated from the tour's JSON, laid out as
--- box-drawing text, and handed back as `virt_lines`-style rows plus where each
--- node landed, so a cursor (in the prose window) or a picker can follow one.
---
--- Three kinds, each its own layout:
---   `calls`     an indented call tree rooted at an entry point
---   `sequence`  participants as lifelines, messages as arrows over time
---   `flow`      boxes and arrows, layered top-down or left-to-right
---
--- Every node may be anchored exactly the way a step is -- `file` plus `text`
--- or `line` -- or point at another step with `step`. The
--- anchors resolve through the same code as steps, so a node whose code has
--- gone is reported broken, never guessed at.
---
--- Pure: JSON-shaped tables in, chunk rows out.

local canvas = require 'thread.diagram.canvas'

local M = {}

M.KINDS = { calls = true, sequence = true, flow = true }

local ANCHOR_FIELDS = { 'text', 'line' }

local function fail(fmt, ...)
  return nil, string.format(fmt, ...)
end

local function nilify(v)
  if v == vim.NIL then
    return nil
  end
  return v
end

local function is_object(v)
  return type(v) == 'table' and not vim.islist(v)
end

local function is_array(v)
  return type(v) == 'table' and (vim.islist(v) or next(v) == nil)
end

----------------------------------------------------------------------
-- Validation
----------------------------------------------------------------------

--- One node, anchored like a step or not at all.
---@param raw any
---@param path string  where it sits, for the error message: `nodes[3]`
---@param opts { id: boolean, multiline: boolean }
---@return table|nil node, string|nil err
local function validate_node(raw, path, opts)
  if not is_object(raw) then
    return fail('%s must be an object', path)
  end

  local node = {}

  local label = nilify(raw.label)
  if type(label) ~= 'string' or vim.trim(label) == '' then
    return fail('%s.label must be a non-empty string', path)
  end
  if label:find '\n' and not opts.multiline then
    return fail('%s.label must be a single line', path)
  end
  node.label = label

  local id = nilify(raw.id)
  if opts.id then
    if type(id) ~= 'string' or id == '' then
      return fail('%s.id must be a non-empty string', path)
    end
  elseif id ~= nil and type(id) ~= 'string' then
    return fail('%s.id must be a string', path)
  end
  node.id = id

  local file = nilify(raw.file)
  if file ~= nil and (type(file) ~= 'string' or file == '') then
    return fail('%s.file must be a non-empty string', path)
  end
  node.file = file

  for _, field in ipairs(ANCHOR_FIELDS) do
    local v = nilify(raw[field])
    if v ~= nil then
      if not file then
        return fail('%s has `%s` but no `file` to find it in', path, field)
      end
      if field == 'line' then
        if type(v) ~= 'number' or v < 1 or v % 1 ~= 0 then
          return fail('%s.line must be a positive integer (1-indexed)', path)
        end
      elseif type(v) ~= 'string' or v == '' then
        return fail('%s.%s must be a non-empty string', path, field)
      elseif field == 'text' and v:find '\n' then
        return fail('%s.text must be a single line, quoted verbatim', path)
      end
      node[field] = v
    end
  end
  for _, field in ipairs { 'symbol', 'pattern' } do
    if nilify(raw[field]) ~= nil then
      return fail('%s.%s is not an anchor: quote the line in `text`', path, field)
    end
  end

  -- Review tours: which side of the diff the node's anchor reads.
  local side = nilify(raw.side)
  if side ~= nil then
    if side ~= 'old' and side ~= 'new' then
      return fail('%s.side must be "old" or "new"', path)
    end
    if not file then
      return fail('%s has `side` but no `file` to find it in', path)
    end
    node.side = side
  end

  local step = nilify(raw.step)
  if step ~= nil then
    if type(step) ~= 'number' or step < 1 or step % 1 ~= 0 then
      return fail('%s.step must be a positive integer (a step number of this tour)', path)
    end
    if file then
      return fail('%s links to code (`file`) and to a step (`step`); pick one', path)
    end
    node.step = step
  end

  -- A tour's overview links its boxes to stages; the parser turns the stage
  -- number into the step that opens it.
  local stage = nilify(raw.stage)
  if stage ~= nil then
    if type(stage) ~= 'number' or stage < 1 or stage % 1 ~= 0 then
      return fail('%s.stage must be a positive integer (a stage number of this tour)', path)
    end
    if file or step then
      return fail('%s links to a stage and to %s; pick one', path, file and 'code (`file`)' or 'a step (`step`)')
    end
    node.stage = stage
  end

  return node
end

--- Nodes keyed by id, rejecting duplicates.
local function index_nodes(list, what)
  local by_id = {}
  for i, node in ipairs(list) do
    if by_id[node.id] then
      return fail('%s[%d].id %q is used twice', what, i, node.id)
    end
    by_id[node.id] = node
  end
  return by_id
end

local function validate_calls(raw)
  local count = 0
  local function walk(r, path, depth)
    if depth > 32 then
      return fail('%s: the tree is nested more than 32 deep', path)
    end
    local node, err = validate_node(r, path, { id = false, multiline = false })
    if not node then
      return nil, err
    end
    count = count + 1
    local children = nilify(r.children)
    if children ~= nil then
      if not is_array(children) then
        return fail('%s.children must be an array', path)
      end
      node.children = {}
      for i, c in ipairs(children) do
        local child, cerr = walk(c, string.format('%s.children[%d]', path, i), depth + 1)
        if not child then
          return nil, cerr
        end
        node.children[i] = child
      end
    end
    return node
  end

  local root = nilify(raw.root)
  if root == nil then
    return fail '`calls` needs a `root` node'
  end
  local tree, err = walk(root, 'root', 1)
  if not tree then
    return nil, err
  end
  return { kind = 'calls', root = tree }
end

local function validate_sequence(raw)
  local parts = nilify(raw.participants)
  if not is_array(parts) or #parts == 0 then
    return fail '`sequence` needs a non-empty `participants` array'
  end
  local participants = {}
  for i, p in ipairs(parts) do
    local node, err = validate_node(p, string.format('participants[%d]', i), { id = true, multiline = false })
    if not node then
      return nil, err
    end
    participants[i] = node
  end
  local by_id, ierr = index_nodes(participants, 'participants')
  if not by_id then
    return nil, ierr
  end

  local msgs = nilify(raw.messages)
  if not is_array(msgs) or #msgs == 0 then
    return fail '`sequence` needs a non-empty `messages` array'
  end
  local messages = {}
  for i, m in ipairs(msgs) do
    local path = string.format('messages[%d]', i)
    if not is_object(m) then
      return fail('%s must be an object with `from`, `to` and `label`', path)
    end
    for _, end_ in ipairs { 'from', 'to' } do
      local id = nilify(m[end_])
      if type(id) ~= 'string' or not by_id[id] then
        return fail('%s.%s %s is not a participant id', path, end_, vim.inspect(id))
      end
    end
    local label = nilify(m.label)
    if label ~= nil and (type(label) ~= 'string' or label:find '\n') then
      return fail('%s.label must be a single-line string', path)
    end
    local reply = nilify(m.reply)
    if reply ~= nil and type(reply) ~= 'boolean' then
      return fail('%s.reply must be true or false', path)
    end
    messages[i] = { from = m.from, to = m.to, label = label, reply = reply or false }
  end

  return { kind = 'sequence', participants = participants, messages = messages }
end

local function validate_flow(raw)
  local list = nilify(raw.nodes)
  if not is_array(list) or #list == 0 then
    return fail '`flow` needs a non-empty `nodes` array'
  end
  local nodes = {}
  for i, n in ipairs(list) do
    local node, err = validate_node(n, string.format('nodes[%d]', i), { id = true, multiline = true })
    if not node then
      return nil, err
    end
    nodes[i] = node
  end
  local by_id, ierr = index_nodes(nodes, 'nodes')
  if not by_id then
    return nil, ierr
  end

  local raw_edges = nilify(raw.edges)
  if raw_edges ~= nil and not is_array(raw_edges) then
    return fail '`edges` must be an array'
  end
  local edges = {}
  for i, e in ipairs(raw_edges or {}) do
    local path = string.format('edges[%d]', i)
    if not is_object(e) then
      return fail('%s must be an object with `from` and `to`', path)
    end
    for _, end_ in ipairs { 'from', 'to' } do
      local id = nilify(e[end_])
      if type(id) ~= 'string' or not by_id[id] then
        return fail('%s.%s %s is not a node id', path, end_, vim.inspect(id))
      end
    end
    local label = nilify(e.label)
    if label ~= nil and (type(label) ~= 'string' or label:find '\n') then
      return fail('%s.label must be a single-line string', path)
    end
    local dashed = nilify(e.dashed)
    if dashed ~= nil and type(dashed) ~= 'boolean' then
      return fail('%s.dashed must be true or false', path)
    end
    edges[i] = { from = e.from, to = e.to, label = label ~= '' and label or nil, dashed = dashed or false }
  end

  local direction = nilify(raw.direction) or 'down'
  if direction ~= 'down' and direction ~= 'right' then
    return fail('`direction` must be "down" or "right", got %s', vim.inspect(direction))
  end

  return { kind = 'flow', nodes = nodes, edges = edges, direction = direction }
end

--- Validate a step's `diagram` field.
---@param raw any
---@return table|nil diagram, string|nil err  err is relative: `edges[2].to ...`
function M.validate(raw)
  if not is_object(raw) then
    return fail '`diagram` must be an object with a `kind`'
  end
  local kind = nilify(raw.kind)
  if not M.KINDS[kind] then
    return fail('`diagram.kind` must be "calls", "sequence" or "flow", got %s', vim.inspect(kind))
  end
  if kind == 'calls' then
    return validate_calls(raw)
  elseif kind == 'sequence' then
    return validate_sequence(raw)
  end
  return validate_flow(raw)
end

--- Every node of a diagram, in reading order.
---@param d table validated diagram
---@return table[]
function M.nodes(d)
  if d.kind == 'flow' then
    return d.nodes
  elseif d.kind == 'sequence' then
    return d.participants
  end
  local out = {}
  local function walk(n)
    out[#out + 1] = n
    for _, c in ipairs(n.children or {}) do
      walk(c)
    end
  end
  walk(d.root)
  return out
end

--- Whether a node goes anywhere when followed.
function M.is_linked(node)
  return node.file ~= nil or node.step ~= nil or node.stage ~= nil
end

----------------------------------------------------------------------
-- Rendering
----------------------------------------------------------------------

--- Shorten `s` to at most `w` display columns, marking the cut.
---@param s string
---@param w integer
---@return string
function M.truncate(s, w)
  if canvas.width_of(s) <= w then
    return s
  end
  if w <= 1 then
    return '…'
  end
  local chars = vim.fn.split(s, '\\zs')
  local out, used = {}, 0
  for _, ch in ipairs(chars) do
    local cw = canvas.width_of(ch)
    if used + cw > w - 1 then
      break
    end
    out[#out + 1] = ch
    used = used + cw
  end
  return table.concat(out) .. '…'
end

--- The highlight group of a node's label and border, by how it resolved.
---@param node table
---@param status table<table, 'ok'|'broken'|'here'>|nil
---@return string label_hl, string border_hl
function M.node_hl(node, status)
  local s = status and status[node]
  if s == 'broken' then
    return 'ThreadBroken', 'ThreadBroken'
  elseif s == 'here' then
    return 'ThreadDiagramHere', 'ThreadDiagramHere'
  end
  if M.is_linked(node) then
    return 'ThreadDiagramNode', 'ThreadDiagramBox'
  end
  return 'ThreadDiagramText', 'ThreadDiagramBox'
end

---@class thread.DiagramHit
---@field node table   the node, as validated
---@field row integer  0-indexed row in `rows`
---@field col integer  0-indexed display column
---@field width integer
---@field height integer

---@class thread.DiagramRender
---@field rows [string, string][][]  one chunk list per row, all `width` wide
---@field width integer
---@field hits thread.DiagramHit[]
---@field degraded string|nil  why the diagram was drawn simpler than asked

--- The last resort when nothing fits: one row per connection, no geometry. Not
--- pretty, but every label is still there and every node still followable.
local function list_fallback(d, max_width, status)
  local c = canvas.new()
  local hits = {}
  local row = 0
  local by_id = {}
  for _, n in ipairs(M.nodes(d)) do
    if n.id then
      by_id[n.id] = n
    end
  end

  local function node_text(r, col, node, w)
    local label = M.truncate((node.label:gsub('\n', ' ')), w)
    local hl = M.node_hl(node, status)
    hits[#hits + 1] = { node = node, row = r, col = col, width = canvas.width_of(label), height = 1 }
    return c:text(r, col, label, hl)
  end

  local pairs_ = {}
  if d.kind == 'flow' then
    for _, e in ipairs(d.edges) do
      pairs_[#pairs_ + 1] = { by_id[e.from], by_id[e.to], e.label }
    end
  elseif d.kind == 'sequence' then
    for _, m in ipairs(d.messages) do
      pairs_[#pairs_ + 1] = { by_id[m.from], by_id[m.to], m.label }
    end
  end

  -- Each row is budgeted so it cannot overflow: the connection's label gets
  -- a quarter, the two ends split what is left, and a short arrow replaces
  -- the labelled one when there is no room for it at all.
  for _, p in ipairs(pairs_) do
    local arrow = ' → '
    if p[3] then
      local labelled = ' ── ' .. M.truncate(p[3], math.max(3, math.floor(max_width / 4))) .. ' ─▶ '
      if max_width - canvas.width_of(labelled) >= 8 then
        arrow = labelled
      end
    elseif max_width >= 16 then
      arrow = ' ──▶ '
    end
    local room = max_width - canvas.width_of(arrow)
    local left_w = math.max(1, math.min(canvas.width_of(p[1].label), math.floor(room / 2)))
    local col = node_text(row, 0, p[1], left_w)
    col = c:text(row, col, arrow, 'ThreadDiagramLabel')
    node_text(row, col, p[2], math.max(1, max_width - col))
    row = row + 1
  end
  -- Nodes that no connection mentions would vanish from the list otherwise.
  local seen = {}
  for _, p in ipairs(pairs_) do
    seen[p[1]], seen[p[2]] = true, true
  end
  for _, n in ipairs(M.nodes(d)) do
    if not seen[n] then
      node_text(row, 0, n, max_width)
      row = row + 1
    end
  end
  return c, hits
end

--- Crop a laid-out canvas to what was drawn and package it.
local function finish(c, hits, degraded)
  local first, last = c:extent()
  local top, bottom = c:row_extent()
  if not first then
    return { rows = {}, width = 0, hits = {}, degraded = degraded }
  end
  local rows = c:rows(first, last + 1)
  rows = vim.list_slice(rows, top + 1, bottom + 1)
  local shifted = {}
  for _, h in ipairs(hits) do
    shifted[#shifted + 1] = { node = h.node, row = h.row - top, col = h.col - first, width = h.width, height = h.height }
  end
  return { rows = rows, width = last - first + 1, hits = shifted, degraded = degraded }
end

--- Lay a diagram out in at most `max_width` columns.
---@param d table validated diagram
---@param opts { max_width: integer, status: table|nil }
---@return thread.DiagramRender
function M.render(d, opts)
  local max_width = math.max(16, opts.max_width or 80)
  local layout = require('thread.diagram.' .. d.kind)
  local c, hits, degraded = layout.layout(d, { max_width = max_width, status = opts.status })
  if c then
    local first, last = c:extent()
    if not first or last - first + 1 <= max_width then
      return finish(c, hits, degraded)
    end
  end
  local fc, fhits = list_fallback(d, max_width, opts.status)
  return finish(fc, fhits, string.format('too wide for %d columns; shown as a list', max_width))
end

--- The node, if any, drawn at a display position of the rendered diagram.
---@param r thread.DiagramRender
---@param row integer 0-indexed
---@param col integer 0-indexed display column
---@return table|nil node
function M.hit(r, row, col)
  for _, h in ipairs(r.hits) do
    if row >= h.row and row < h.row + h.height and col >= h.col and col < h.col + h.width then
      return h.node
    end
  end
end

--- Plain text of the rendered rows.
---@param r thread.DiagramRender
---@return string[]
function M.text(r)
  return vim.tbl_map(function(chunks)
    return table.concat(vim.tbl_map(function(ch)
      return ch[1]
    end, chunks))
  end, r.rows)
end

return M
