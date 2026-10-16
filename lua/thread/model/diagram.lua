--- A diagram as the agent wrote it, checked: each kind's fields, every
--- node's anchor or link, every edge's ends. The errors are written for
--- the agent, relative to the diagram: `edges[2].to ...`. Laying a checked
--- one out is thread.ui.diagram.

local M = {}

M.KINDS = { calls = true, sequence = true, flow = true }

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

--- A field `raw` has that `allowed` does not, said; nil when it has none.
--- Every object of a diagram is exact, as the rest of a review is.
---@param raw table
---@param path string|nil  where it sits; none: the diagram itself
---@param allowed string[]
---@return string|nil err
local function extra(raw, path, allowed)
  local names = vim.tbl_keys(raw)
  table.sort(names, function(a, b)
    return tostring(a) < tostring(b)
  end)
  for _, k in ipairs(names) do
    if not vim.tbl_contains(allowed, k) then
      local name = path and (path .. '.' .. tostring(k)) or ('`' .. tostring(k) .. '`')
      return string.format('%s is not a field (it has %s)', name, table.concat(allowed, ', '))
    end
  end
end

--- One node, on a chunk of the review or on none.
---@param raw any
---@param path string  where it sits, for the error message: `nodes[3]`
---@param opts { id: boolean, multiline: boolean, children: boolean|nil, file: fun(id: string): string|nil }
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

  for _, field in ipairs { 'file', 'text', 'line', 'side', 'symbol', 'pattern', 'step', 'stage' } do
    if nilify(raw[field]) ~= nil then
      return fail("%s.%s is not a field: a node is on code by `chunk`, the id of one of the review's chunks", path, field)
    end
  end
  local bad = extra(raw, path, opts.children and { 'id', 'label', 'chunk', 'children' } or { 'id', 'label', 'chunk' })
  if bad then
    return nil, bad
  end
  local chunk = nilify(raw.chunk)
  if chunk ~= nil then
    if type(chunk) ~= 'string' or chunk == '' then
      return fail("%s.chunk must be a chunk's id", path)
    end
    local file = opts.file(chunk)
    if not file then
      return fail('%s.chunk is "%s", which is not one of the review\'s chunks', path, chunk)
    end
    node.chunk, node.file = chunk, file
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

local function validate_calls(raw, file)
  local bad = extra(raw, nil, { 'kind', 'root' })
  if bad then
    return nil, bad
  end
  local count = 0
  local function walk(r, path, depth)
    if depth > 32 then
      return fail('%s: the tree is nested more than 32 deep', path)
    end
    local node, err = validate_node(r, path, { id = false, multiline = false, children = true, file = file })
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

local function validate_sequence(raw, file)
  local bad = extra(raw, nil, { 'kind', 'participants', 'messages' })
  if bad then
    return nil, bad
  end
  local parts = nilify(raw.participants)
  if not is_array(parts) or #parts == 0 then
    return fail '`sequence` needs a non-empty `participants` array'
  end
  ---@cast parts table
  local participants = {}
  for i, p in ipairs(parts) do
    local node, err = validate_node(p, string.format('participants[%d]', i), { id = true, multiline = false, file = file })
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
    bad = extra(m, path, { 'from', 'to', 'label', 'reply' })
    if bad then
      return nil, bad
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

local function validate_flow(raw, file)
  local bad = extra(raw, nil, { 'kind', 'nodes', 'edges', 'direction' })
  if bad then
    return nil, bad
  end
  local list = nilify(raw.nodes)
  if not is_array(list) or #list == 0 then
    return fail '`flow` needs a non-empty `nodes` array'
  end
  ---@cast list table
  local nodes = {}
  for i, n in ipairs(list) do
    local node, err = validate_node(n, string.format('nodes[%d]', i), { id = true, multiline = true, file = file })
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
    bad = extra(e, path, { 'from', 'to', 'label', 'dashed' })
    if bad then
      return nil, bad
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

--- A diagram, checked: a copy, each node on a chunk with that chunk's
--- file beside its id, for drawing.
---@param raw any
---@param file fun(id: string): string|nil  a chunk's file, by its id; nil when the review has none
---@return table|nil diagram, string|nil err  err is relative: `edges[2].to ...`
function M.validate(raw, file)
  if not is_object(raw) then
    return fail '`diagram` must be an object with a `kind`'
  end
  local kind = nilify(raw.kind)
  if not M.KINDS[kind] then
    return fail('its `kind` must be "calls", "sequence" or "flow", got %s', vim.inspect(kind))
  end
  if kind == 'calls' then
    return validate_calls(raw, file)
  elseif kind == 'sequence' then
    return validate_sequence(raw, file)
  end
  return validate_flow(raw, file)
end

return M
