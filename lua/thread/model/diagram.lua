--- A diagram as the agent wrote it, checked: each kind's fields, every
--- node's anchor or link, every edge's ends. The errors are written for
--- the agent, relative to the diagram: `edges[2].to ...`. Laying a checked
--- one out is thread.ui.diagram.

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
  ---@cast parts table
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
  ---@cast msgs table
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
  ---@cast list table
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

return M
