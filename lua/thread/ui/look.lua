--- How things are marked, the same on every screen: a note's number, how
--- far through a tour you are, and keys with what they do. How a note, a
--- step or a message is labelled is thread.draw.labels.

local M = {}

local NUMS = { '①', '②', '③', '④', '⑤', '⑥', '⑦', '⑧', '⑨', '⑩', '⑪', '⑫', '⑬', '⑭', '⑮', '⑯', '⑰', '⑱', '⑲', '⑳' }

--- A note's number: ①, or (21) past the twentieth.
---@param k integer
---@return string
function M.num(k)
  return NUMS[k] or ('(' .. k .. ')')
end

-- How each part of a tour's track is drawn: been, here, still to come.
M.TRACK = { done = 'ThreadLeads', here = 'ThreadTitle', left = 'ThreadMeta' }

--- A tour's track (thread.draw.labels.track) as chunks to draw.
---@param cells { [1]: string, [2]: 'done'|'here'|'left' }[]
---@param hls table<string, string>|nil  in place of M.TRACK
---@return { [1]: string, [2]: string }[]
function M.track(cells, hls)
  hls = hls or M.TRACK
  return vim.tbl_map(function(t)
    return { t[1], hls[t[2]] }
  end, cells)
end

--- Any mapping as it reads in a hint.
---@param lhs string|false|nil
---@return string|nil
function M.show_key(lhs)
  if not lhs then
    return nil
  end
  local leader = vim.g.mapleader == ' ' and '␣' or (vim.g.mapleader or '\\')
  return (lhs:gsub('<leader>', leader))
end

--- What a key that turns something on and off is listed as: ticked
--- while on.
---@param label string
---@param on boolean|nil
---@return string
function M.toggle(label, on)
  return on and (label .. ' ✓') or label
end

--- Keys and what they do, as chunks: `key label`, `sep` between.
---@param list { [1]: string, [2]: string }[]
---@param sep string|nil  default two spaces
---@return { [1]: string, [2]: string }[]
function M.hints(list, sep)
  local out = {}
  for i, k in ipairs(list) do
    if i > 1 then
      out[#out + 1] = { sep or '  ', 'ThreadKeyLabel' }
    end
    out[#out + 1] = { k[1], 'ThreadKey' }
    out[#out + 1] = { ' ' .. k[2], 'ThreadKeyLabel' }
  end
  return out
end

--- Keys as a float's footer: the hints, a space either side.
---@param list { [1]: string, [2]: string }[]
---@return { [1]: string, [2]: string|nil }[]
function M.footer(list)
  local out = M.hints(list)
  table.insert(out, 1, { ' ' })
  out[#out + 1] = { ' ' }
  return out
end

--- Keys as a float's footer, in groups of keys that do alike, a bar
--- between groups and a space either side.
---@param groups { [1]: string, [2]: string }[][]
---@return { [1]: string, [2]: string|nil }[]
function M.grouped(groups)
  local out = { { ' ' } }
  for i, list in ipairs(groups) do
    if i > 1 then
      out[#out + 1] = { '  │  ', 'FloatBorder' }
    end
    vim.list_extend(out, M.hints(list))
  end
  out[#out + 1] = { ' ' }
  return out
end

return M
