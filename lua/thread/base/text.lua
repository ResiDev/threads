--- Text as it is drawn: how wide it is, cut or padded to a width, counts
--- and times said the way a person says them. Prose is thread.prose.

local M = {}

--- A row as coloured pieces: `{ text, hl }` each.
---@alias thread.Chunks { [1]: string, [2]: string|nil }[]

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

--- Chunks `{ text, hl }` cut to `w` columns: those that fit, and the
--- first that does not, cut with an ellipsis.
---@param chunks thread.Chunks
---@param w integer
---@return thread.Chunks
function M.fit_chunks(chunks, w)
  local out, used = {}, 0
  for _, c in ipairs(chunks) do
    local cw = M.width(c[1])
    if used + cw > w then
      out[#out + 1] = { M.fit(c[1], w - used), c[2] }
      return out
    end
    out[#out + 1], used = c, used + cw
  end
  return out
end

--- `s` wrapped at spaces to rows of `w` columns at most; a word wider
--- than that is cut. Its line breaks are kept, and nothing is one row.
---@param s string
---@param w integer
---@return string[]
function M.wrap(s, w)
  local out = {} ---@type string[]
  for _, line in ipairs(vim.split(s, '\n', { plain = true })) do
    local row = ''
    for word in line:gmatch '%S+' do
      if row == '' then
        row = M.fit(word, w)
      elseif M.width(row) + 1 + M.width(word) <= w then
        row = row .. ' ' .. word
      else
        out[#out + 1] = row
        row = M.fit(word, w)
      end
    end
    out[#out + 1] = row
  end
  return out
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
function M.whole(line, name)
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

--- What a name in backticks is looked for as: as written, and a call
--- without its arguments, `load(read)` as `load`. One letter is no name.
---@param written string
---@return string[]
function M.forms(written)
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

return M
