--- A line of prose read into spans: `code` first, then **bold**, links
--- and *italic* in what is left.

local link = require 'thread.prose.link'

local M = {}

--- Where the next *italic* or _italic_ run in `s` is, from `pos`: its
--- start, its text and the byte after it. A `*` or `_` opens one at the
--- start of a word, after a space or an opening bracket or quote, and
--- closes one at its end, before a space or punctuation; so `2 * 3`,
--- `snake_case_name`, `__init__.py`, `src/*.lua` and `a/_b_/c` are none.
---@param s string
---@param pos integer
---@return integer|nil from, string|nil inner, integer|nil after
local function italic_at(s, pos)
  local best ---@type integer|nil
  local inner, after ---@type string|nil, integer|nil
  for _, d in ipairs { '%*', '_' } do
    local from = pos
    while true do
      local a, body, e = s:match('()' .. d .. '([^%s' .. d .. '][^' .. d .. ']-)' .. d .. '()', from)
      if not a then
        break
      end
      local prev, follow = s:sub(a - 1, a - 1), s:sub(e, e)
      local ok = not body:match '%s$' and (prev == '' or prev:match '[%s%(%[{"\']') ~= nil and (follow == '' or follow:match '[%s%.,;:!?%)%]}"\']') ~= nil
      if ok then
        if not best or a < best then
          best, inner, after = a, body, e
        end
        break
      end
      from = a + 1
    end
  end
  return best, inner, after
end

--- A line of text as spans. `bold` is whether a bold run is open from the
--- line before. A `**` opens one before a word and closes one after a
--- word, so `x ** 2` is not bold. A link to one of `names`' contracts
--- reads as its name.
---@param line string
---@param bold boolean
---@param names table<integer, string>|nil
---@return thread.Span[] spans, boolean bold  open at its end
function M.of(line, bold, names)
  local out = {} ---@type thread.Span[]
  ---@param s string
  local function plain(s)
    local pos = 1
    while true do
      local from, inner, after = italic_at(s, pos)
      if not from then
        break
      end
      out[#out + 1] = { text = s:sub(pos, from - 1), bold = bold or nil }
      out[#out + 1] = { text = assert(inner), bold = bold or nil, italic = true }
      pos = assert(after)
    end
    out[#out + 1] = { text = s:sub(pos), bold = bold or nil }
  end
  ---@param s string
  local function linked(s)
    local pos = 1
    for _, at in ipairs(link.find(s)) do
      if at.first + 1 > pos then
        plain(s:sub(pos, at.first))
      end
      local l = at.link
      local name = names and l.kind == 'contract' and not l.review and names[l.id] or nil
      out[#out + 1] = { text = name or s:sub(at.first + 1, at.last), bold = bold or nil, link = l, contract = name and true or nil }
      pos = at.last + 1
    end
    if pos <= #s then
      plain(s:sub(pos))
    end
  end
  --- Text between code spans: `from`..`to` of the line.
  ---@param from integer
  ---@param to integer
  local function words(from, to)
    local pos = from
    for star in line:sub(from, to):gmatch '()%*%*' do
      star = from + star - 1
      local touches = bold and line:sub(star - 1, star - 1) or line:sub(star + 2, star + 2)
      if touches:match '%S' then
        linked(line:sub(pos, star - 1))
        bold, pos = not bold, star + 2
      end
    end
    linked(line:sub(pos, to))
  end
  local pos = 1
  for s, inner, e in line:gmatch '()`([^`]+)`()' do
    words(pos, s - 1)
    out[#out + 1] = { text = inner, code = true, bold = bold or nil }
    pos = e
  end
  words(pos, #line)
  return vim.tbl_filter(function(sp)
    return sp.text ~= ''
  end, out), bold
end

return M
