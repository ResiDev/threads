--- What draw/ drew into a sheet, as virtual lines to hang above a line of
--- code: framed, a note's bubble or a step's card, or its rows alone.
--- The frame is the colour of whose move it is, and says on its top edge
--- the review it is in and on its bottom edge its keys.

local text = require 'thread.base.text'

local M = {}

---@alias thread.VirtChunk { [1]: string, [2]: string|string[] }

--- A sheet's row as the chunks of a virtual line. Where highlights
--- overlap, the one with the higher priority wins; a wash (`hl_eol`) runs
--- on into the padding up to `width` columns.
---@param P thread.Sheet
---@param row integer  0-based
---@param width integer
---@param base string  the colour of what nothing colours
---@return thread.VirtChunk[]
function M.chunks(P, row, width, base)
  local line = P.lines[row + 1] or ''
  local cuts = { [0] = true, [#line] = true } ---@type table<integer, true>
  local spans, eol = {}, {} ---@type { s: integer, e: integer, group: string, pr: integer, n: integer }[], { group: string, pr: integer, n: integer }[]
  for n, h in ipairs(P.hls) do
    if h[1] == row and h[4] then
      local o = h[5] or {}
      local s = math.min(h[2], #line)
      local e = (h[3] < 0 or o.hl_eol) and #line or math.min(h[3], #line)
      local pr = o.priority or 0
      if o.hl_eol then
        eol[#eol + 1] = { group = h[4], pr = pr, n = n }
      end
      if s < e then
        spans[#spans + 1] = { s = s, e = e, group = h[4], pr = pr, n = n }
        cuts[s], cuts[e] = true, true
      end
    end
  end
  ---@param list { group: string, pr: integer, n: integer }[]
  ---@return string|string[]
  local function groups(list)
    if #list == 0 then
      return base
    end
    table.sort(list, function(a, b)
      return a.pr ~= b.pr and a.pr < b.pr or a.n < b.n
    end)
    local out = { base }
    for _, x in ipairs(list) do
      out[#out + 1] = x.group
    end
    return out
  end
  local at = vim.tbl_keys(cuts)
  table.sort(at)
  local out = {} ---@type thread.VirtChunk[]
  for i = 1, #at - 1 do
    local a, b = at[i], at[i + 1]
    local over = {} ---@type { group: string, pr: integer, n: integer }[]
    for _, sp in ipairs(spans) do
      if sp.s <= a and sp.e >= b then
        over[#over + 1] = sp
      end
    end
    out[#out + 1] = { line:sub(a + 1, b), groups(over) }
  end
  local pad = width - text.width(line)
  if pad > 0 then
    out[#out + 1] = { string.rep(' ', pad), groups(eol) }
  end
  return out
end

---@class thread.FrameOpts
---@field indent integer  the code line's, in columns
---@field width integer   what is inside, in columns
---@field border string
---@field top thread.Chunks|nil   on the top edge
---@field keys thread.Chunks|nil  on the bottom edge

--- A sheet framed, as virtual lines: a blank line above, the frame, and
--- under it a stem down to the line it is on.
---@param P thread.Sheet
---@param o thread.FrameOpts
---@return thread.VirtChunk[][]
function M.frame(P, o)
  local lead = { string.rep(' ', o.indent), 'Normal' }
  local b = o.border
  local out = { { { '', 'Normal' } } } ---@type thread.VirtChunk[][]
  local top = { lead, { '╭', b } } ---@type thread.VirtChunk[]
  if o.top then
    local said = text.fit_chunks(o.top, o.width - 1)
    top[#top + 1] = { '─ ', b }
    vim.list_extend(top, said)
    top[#top + 1] = { ' ' .. string.rep('─', math.max(0, o.width - text.width(said) - 1)) .. '╮', b }
  else
    top[#top + 1] = { string.rep('─', o.width + 2) .. '╮', b }
  end
  out[#out + 1] = top
  for row = 0, #P.lines - 1 do
    local line = { lead, { '│ ', b } } ---@type thread.VirtChunk[]
    vim.list_extend(line, M.chunks(P, row, o.width, 'ThreadText'))
    line[#line + 1] = { ' │', b }
    out[#out + 1] = line
  end
  local bottom = { lead, { '╰┬', b } } ---@type thread.VirtChunk[]
  local keys = o.keys and text.fit_chunks(o.keys, o.width - 2)
  if keys and #keys > 0 then
    bottom[#bottom + 1] = { string.rep('─', math.max(0, o.width - text.width(keys) - 2)) .. ' ', b }
    vim.list_extend(bottom, keys)
    bottom[#bottom + 1] = { ' ─╯', b }
  else
    bottom[#bottom + 1] = { string.rep('─', o.width + 1) .. '╯', b }
  end
  out[#out + 1] = bottom
  out[#out + 1] = { lead, { ' │', b } }
  return out
end

--- A sheet's rows as virtual lines, unframed, set in to the code line's
--- indent.
---@param P thread.Sheet
---@param indent integer
---@return thread.VirtChunk[][]
function M.lines(P, indent)
  local out = {} ---@type thread.VirtChunk[][]
  for row = 0, #P.lines - 1 do
    local line = { { string.rep(' ', indent), 'Normal' } } ---@type thread.VirtChunk[]
    out[#out + 1] = vim.list_extend(line, M.chunks(P, row, 0, 'ThreadText'))
  end
  return out
end

return M
