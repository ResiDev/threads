--- Text as it is drawn: how wide it is, cut or padded to a width, counts
--- and times said the way a person says them. Prose is thread.prose.

local M = {}

--- How many columns `s` takes, or a list of chunks `{ text, hl }` does.
---@param s string|table
---@return integer
function M.width(s)
  if type(s) == 'table' then
    local w = 0
    for _, c in ipairs(s) do
      w = w + vim.fn.strdisplaywidth(c[1])
    end
    return w
  end
  return vim.fn.strdisplaywidth(s)
end

--- `s` cut to `w` columns, with an ellipsis when cut; '' with no room.
---@param s string
---@param w integer
---@return string
function M.fit(s, w)
  if w <= 0 then
    return ''
  end
  if M.width(s) <= w then
    return s
  end
  local lo, hi = 0, vim.fn.strchars(s)
  while lo < hi do
    local mid = math.ceil((lo + hi) / 2)
    if M.width(vim.fn.strcharpart(s, 0, mid)) <= w - 1 then
      lo = mid
    else
      hi = mid - 1
    end
  end
  return vim.fn.strcharpart(s, 0, lo) .. '…'
end

--- `s` with spaces after it, up to `w` columns.
---@param s string
---@param w integer
---@return string
function M.pad(s, w)
  return s .. string.rep(' ', math.max(0, w - M.width(s)))
end

--- `2 lines`, `1 line`, `3 matches`.
---@param n integer
---@param one string
---@param many string|nil  when not `one` with an s
---@return string
function M.plural(n, one, many)
  return n .. ' ' .. (n == 1 and one or (many or one .. 's'))
end

--- How long `secs` seconds is, as `just now`, `12m ago`, `3h ago`, `2d ago`.
---@param secs number
---@return string
function M.since(secs)
  if secs < 90 then
    return 'just now'
  elseif secs < 5400 then
    return math.floor(secs / 60 + 0.5) .. 'm ago'
  elseif secs < 129600 then
    return math.floor(secs / 3600 + 0.5) .. 'h ago'
  end
  return math.floor(secs / 86400 + 0.5) .. 'd ago'
end

--- How long ago an ISO time was, in words; nil when it is not one.
---@param stamp string|nil
---@return string|nil
function M.ago(stamp)
  local y, mo, d, h, mi, s = (stamp or ''):match '(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)'
  if not y then
    return nil
  end
  return M.since(os.time() - os.time { year = y, month = mo, day = d, hour = h, min = mi, sec = s })
end

return M
