--- JSON the way a person or an agent wants to edit it: two-space indents,
--- keys in the order a schema gives, short arrays of scalars kept on one
--- line. A file edited by hand and by agents as text must not be
--- reshuffled by a reload and a save.

local M = {}

---@class thread.JsonSchema
---@field order string[]  keys first, in this order; any other after them, sorted
---@field lists table<string, true>  keys holding a list, so an empty one is `[]`

-- A schema's order as key -> place, worked out once per schema.
local places = setmetatable({}, { __mode = 'k' })

---@param schema thread.JsonSchema|nil
---@return table<string, integer>
local function place_of(schema)
  if not schema then
    return {}
  end
  if not places[schema] then
    local p = {}
    for i, key in ipairs(schema.order) do
      p[key] = i
    end
    places[schema] = p
  end
  return places[schema]
end

local function sorted_keys(t, place)
  local keys = vim.tbl_keys(t)
  table.sort(keys, function(a, b)
    local oa, ob = place[a] or math.huge, place[b] or math.huge
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

local function encode(v, indent, list_hint, out, place, lists)
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
      encode(item, indent + 1, false, out, place, lists)
      out[#out + 1] = i < #v and ',\n' or '\n'
    end
    out[#out + 1] = close .. ']'
    return
  end
  out[#out + 1] = '{\n'
  local keys = sorted_keys(v, place)
  for i, key in ipairs(keys) do
    out[#out + 1] = pad .. vim.json.encode(tostring(key)) .. ': '
    encode(v[key], indent + 1, lists[key], out, place, lists)
    out[#out + 1] = i < #keys and ',\n' or '\n'
  end
  out[#out + 1] = close .. '}'
end

--- `v` as JSON, its keys in `schema`'s order; with none, sorted.
---@param v any
---@param schema thread.JsonSchema|nil
---@return string
function M.encode(v, schema)
  local out = {}
  encode(v, 0, false, out, place_of(schema), schema and schema.lists or {})
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
