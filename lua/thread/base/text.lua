--- Text as it is drawn: how wide it is, cut or padded to a width, prose
--- wrapped into rows and those rows into highlighted chunks, and times said
--- the way a person says them.

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

--- A message said in one line: its first line with text, trimmed, its
--- backticks dropped.
---@param s string|nil
---@return string
function M.first_line(s)
  return (vim.trim((s or ''):match '^%s*([^\n]*)'):gsub('`', ''))
end

--- The first sentence of prose, its code fences and markup dropped.
---@param s string|nil
---@return string
function M.first_sentence(s)
  s = vim.trim((s or ''):gsub('```.-```', ''))
  s = s:match '^(.-[.!?])%s' or s:match '^([^\n]*)' or s
  return (s:gsub('[`*]', ''))
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

--- Text broken into display lines no wider than `width`. Paragraphs keep
--- their breaks; fenced code is kept as it is, cut at the width.
---@param text string
---@param width integer
---@return { text: string, code: boolean }[]
function M.wrap(text, width)
  local out = {}
  local fenced, excerpt = false, nil
  -- A line of code, kept as it is, cut at the width.
  local function code_row(line)
    while M.width(line) > width do
      line = vim.fn.strcharpart(line, 0, vim.fn.strchars(line) - 1)
    end
    out[#out + 1] = { text = line, code = true }
  end
  for line in (text .. '\n'):gmatch '(.-)\r?\n' do
    if line:match '^%s*```' then
      fenced = not fenced
      -- A ```code fence holds an anchor, as in a tour: the code it points at.
      if fenced and line:match '^%s*```code%s*$' then
        excerpt = {}
      elseif not fenced and excerpt then
        local ok, a = pcall(vim.json.decode, table.concat(excerpt, '\n'))
        if ok and type(a) == 'table' and a.file then
          out[#out + 1] = { text = '▤ ' .. a.file .. (a.line and (':' .. a.line) or ''), code = true, excerpt = a }
        else
          -- Not an anchor: show what it says rather than nothing.
          for _, l in ipairs(excerpt) do
            code_row(l)
          end
        end
        excerpt = nil
      end
    elseif excerpt then
      excerpt[#excerpt + 1] = line
    elseif fenced then
      code_row(line)
    elseif line:match '^%s*$' then
      out[#out + 1] = { text = '' }
    else
      -- `code with spaces` wraps as one word: its spaces held as no-break
      -- spaces until the line is cut.
      line = line:gsub('`[^`]+`', function(code)
        return (code:gsub(' ', '\u{a0}'))
      end)
      local lead = line:match '^(%s*[-*] )' or line:match '^(%s*%d+[.)] )' or ''
      -- A list item's continuation lines hang under its text.
      local hang = string.rep(' ', M.width(lead))
      local cur = ''
      for word in line:sub(#lead + 1):gmatch '%S+' do
        local candidate = cur == '' and (lead .. word) or (cur .. ' ' .. word)
        if cur ~= '' and M.width(candidate) > width then
          out[#out + 1] = { text = cur }
          candidate = hang .. word
        end
        cur = candidate
        -- A word longer than the line is cut where it must be.
        while M.width(cur) > width do
          local head = vim.fn.strcharpart(cur, 0, width)
          while M.width(head) > width do
            head = vim.fn.strcharpart(head, 0, vim.fn.strchars(head) - 1)
          end
          out[#out + 1] = { text = head }
          cur = hang .. vim.fn.strcharpart(cur, vim.fn.strchars(head))
        end
      end
      if vim.trim(cur) ~= '' then
        out[#out + 1] = { text = cur }
      end
    end
  end
  while #out > 0 and out[#out].text == '' do
    out[#out] = nil
  end
  -- A **bold** run that a line break cuts goes on into the next line.
  local open = false
  for _, o in ipairs(out) do
    o.text = o.text:gsub('\u{a0}', ' ')
    if not o.code then
      o.bold = open
      local _, n = o.text:gsub('%*%*', '')
      if n % 2 == 1 then
        open = not open
      end
      if o.text == '' then
        open = false
      end
    end
  end
  return out
end

--- One line of prose as chunks: `code` picked out, **bold** made bold.
--- `bold` carries a bold run over from the line before.
function M.segments(line)
  if line.code then
    return { { line.text, 'ThreadCode' } }
  end
  local chunks = {}
  local bold = line.bold
  local function plain(text, hl)
    -- A link to a thread, `#12`, or to a stop of its tour, `#12.3`.
    local pos = 1
    for a, link, b in text:gmatch '()(#%d+%.?%d*)()' do
      local before = a > 1 and text:sub(a - 1, a - 1) or ' '
      -- Not a colour, `#4acbe1`, nor inside a word.
      if not before:match '[%w#]' and not text:sub(b, b):match '[%w_]' then
        if a > pos then
          chunks[#chunks + 1] = { text:sub(pos, a - 1), hl }
        end
        link = link:gsub('%.$', '')
        chunks[#chunks + 1] = { link, 'ThreadLink' }
        pos = a + #link
      end
    end
    if pos <= #text then
      chunks[#chunks + 1] = { text:sub(pos), hl }
    end
  end
  local function prose(text)
    -- **bold**, its markers dropped; a run left open goes on to the end.
    local pos = 1
    while pos <= #text do
      local s = text:find('**', pos, true)
      if not s then
        plain(text:sub(pos), bold and 'ThreadPoint' or 'ThreadText')
        break
      end
      if s > pos then
        plain(text:sub(pos, s - 1), bold and 'ThreadPoint' or 'ThreadText')
      end
      bold = not bold
      pos = s + 2
    end
  end
  local pos = 1
  for s, code, e in line.text:gmatch '()`([^`]+)`()' do
    if s > pos then
      prose(line.text:sub(pos, s - 1))
    end
    chunks[#chunks + 1] = { code, 'ThreadCode' }
    pos = e
  end
  if pos <= #line.text then
    prose(line.text:sub(pos))
  end
  return chunks
end

--- The link to a thread under column `col` (0-based) of `text`: `#12`, or
--- `#12.3` for stop 3 of its tour.
---@param text string
---@param col integer
---@return integer|nil id, integer|nil n
function M.link_at(text, col)
  for a, id, n, b in text:gmatch '()#(%d+)%.?(%d*)()' do
    if col >= a - 1 and col < b - 1 and not text:sub(b, b):match '[%w_]' then
      return tonumber(id), tonumber(n)
    end
  end
end

return M
