--- A step's highlights: the names its text puts in backticks that stand
--- whole in its chunk's lines, numbered 1..n in the order the text first
--- names them. Derived, never written: the code lights them, the card
--- lights the current one's sentence, and a walk moves between them.

local prose = require 'thread.prose'

local M = {}

---@class thread.Highlight
---@field n integer
---@field text string  the name as found in the chunk
---@field rows integer[]  the chunk's lines it stands on whole, 1-based, each once
---@field written string[]  what the text wrote in backticks for it, each once

--- What a name in backticks is looked for as: as written, and a call
--- without its arguments, `load(read)` as `load`. One letter is no name.
---@param written string
---@return string[]
local function forms(written)
  local out = {}
  local s = vim.trim(written)
  if #s < 2 then
    return out
  end
  out[1] = s
  local callee = s:match '^([%w_%.:]+)%b()$'
  if callee and #callee >= 2 then
    out[2] = callee
  end
  return out
end

--- Whether a byte is part of a word.
---@param c string
---@return boolean
local function word(c)
  return c ~= '' and c:match '[%w_]' ~= nil
end

--- Where a name stands whole in a line, not inside a longer word: its
--- first and last bytes, 1-based.
---@param line string
---@param name string
---@return { [1]: integer, [2]: integer }[]
function M.find(line, name)
  local out = {}
  local at = 1
  while true do
    local s, e = line:find(name, at, true)
    if not s then
      return out
    end
    local whole = not (word(name:sub(1, 1)) and word(line:sub(s - 1, s - 1))) and not (word(name:sub(-1)) and word(line:sub(e + 1, e + 1)))
    if whole then
      out[#out + 1] = { s, e }
    end
    at = e + 1
  end
end

--- A step's highlights in its chunk's `lines`. Each name in backticks is
--- looked for as written, then as a call's name; the first form found is
--- it, and a name the text gives again counts once.
---@param r thread.Review
---@param s thread.Step
---@param lines string[]  the chunk's, from its first line
---@return thread.Highlight[]
function M.of(r, s, lines)
  local out, by = {}, {} ---@type thread.Highlight[], table<string, thread.Highlight>
  ---@param written string
  local function take(written)
    for _, f in ipairs(forms(written)) do
      local h = by[f]
      if not h then
        local rows = {} ---@type integer[]
        for i, line in ipairs(lines) do
          if #M.find(line, f) > 0 then
            rows[#rows + 1] = i
          end
        end
        if #rows > 0 then
          h = { n = #out + 1, text = f, rows = rows, written = {} }
          out[#out + 1], by[f] = h, h
        end
      end
      if h then
        if not vim.tbl_contains(h.written, written) then
          h.written[#h.written + 1] = written
        end
        return
      end
    end
  end
  ---@param spans thread.Span[]|nil
  local function scan(spans)
    for _, sp in ipairs(spans or {}) do
      if sp.code and not sp.link then
        take(sp.text)
      end
    end
  end
  for _, b in ipairs(prose.parse(s.text, r)) do
    scan(b.spans)
    for _, row in ipairs(b.cells or {}) do
      for _, cell in ipairs(row) do
        scan(cell)
      end
    end
  end
  return out
end

--- Each highlight's number by what the text wrote for it, as prose
--- finds the current one in it.
---@param list thread.Highlight[]
---@return table<string, integer>
function M.numbers(list)
  local out = {} ---@type table<string, integer>
  for _, h in ipairs(list) do
    for _, w in ipairs(h.written) do
      out[w] = h.n
    end
  end
  return out
end

return M
