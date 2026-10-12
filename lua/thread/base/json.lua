--- JSON the way a person or an agent wants to edit it: two-space indents,
--- keys in a fixed order, short arrays of scalars kept on one line. A batch
--- file is edited by hand and by agents as text, so a reload-and-save must
--- not reshuffle it.

local M = {}

local ORDER = {}
for i, key in ipairs {
  'id',
  'stage',
  'title',
  'kind',
  'direction',
  'risk',
  'risk_why',
  'on',
  'thread',
  'step',
  'point',
  'reply',
  'diff',
  'of',
  'base',
  'head',
  'rounds',
  'sent',
  'snapshot',
  'threads',
  'from',
  'round',
  'at',
  'file',
  'rev',
  'line',
  'lines',
  'text',
  'side',
  'mark',
  'note',
  'status',
  'verdict',
  'severity',
  'body',
  'messages',
  'notes',
  'changes',
  'diagram',
  'walk',
  'review',
  'groups',
  'hunks',
  'affected',
  'tests',
  'participants',
  'root',
  'nodes',
  'edges',
  'label',
  'to',
  'dashed',
  'children',
} do
  ORDER[key] = i
end

--- Keys that hold lists, so an empty one is written `[]` rather than `{}`.
local LISTS = {
  threads = true,
  rounds = true,
  messages = true,
  changes = true,
  notes = true,
  walk = true,
  groups = true,
  hunks = true,
  affected = true,
  tests = true,
  participants = true,
  nodes = true,
  edges = true,
  children = true,
}

local function sorted_keys(t)
  local keys = vim.tbl_keys(t)
  table.sort(keys, function(a, b)
    local oa, ob = ORDER[a] or math.huge, ORDER[b] or math.huge
    if oa ~= ob then
      return oa < ob
    end
    return tostring(a) < tostring(b)
  end)
  return keys
end

local function scalar(v)
  if v == nil or v == vim.NIL then
    return 'null'
  elseif type(v) == 'number' and v == math.floor(v) and math.abs(v) < 2 ^ 53 then
    return string.format('%d', v)
  end
  return vim.json.encode(v)
end

local function encode(v, indent, list_hint, out)
  if type(v) ~= 'table' or v == vim.NIL then
    out[#out + 1] = scalar(v)
    return
  end
  local pad = string.rep('  ', indent + 1)
  local close = string.rep('  ', indent)
  local is_list = vim.islist(v) and (next(v) ~= nil or list_hint)
  if next(v) == nil then
    out[#out + 1] = list_hint and '[]' or '{}'
    return
  end
  if is_list then
    local simple = true
    for _, item in ipairs(v) do
      simple = simple and type(item) ~= 'table'
    end
    if simple then
      local parts = vim.tbl_map(scalar, v)
      out[#out + 1] = '[' .. table.concat(parts, ', ') .. ']'
      return
    end
    out[#out + 1] = '[\n'
    for i, item in ipairs(v) do
      out[#out + 1] = pad
      encode(item, indent + 1, false, out)
      out[#out + 1] = i < #v and ',\n' or '\n'
    end
    out[#out + 1] = close .. ']'
    return
  end
  out[#out + 1] = '{\n'
  local keys = sorted_keys(v)
  for i, key in ipairs(keys) do
    out[#out + 1] = pad .. vim.json.encode(tostring(key)) .. ': '
    encode(v[key], indent + 1, LISTS[key], out)
    out[#out + 1] = i < #keys and ',\n' or '\n'
  end
  out[#out + 1] = close .. '}'
end

---@param v any
---@return string
function M.encode(v)
  local out = {}
  encode(v, 0, false, out)
  return table.concat(out) .. '\n'
end

---@param s string
---@return any|nil value, string|nil err
function M.decode(s)
  local ok, v = pcall(vim.json.decode, s, { luanil = { object = true, array = true } })
  if not ok then
    return nil, (tostring(v):gsub('^.-: ', ''))
  end
  return v
end

return M
