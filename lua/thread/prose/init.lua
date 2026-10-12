--- Prose as the agent writes it, in markdown: wrapped to a width, its
--- code fences kept, `code`, **bold** and `#12` links picked out. Stage 4
--- of the rebuild makes this the home of the prose primitives; for now it
--- is what base/text held about prose.

local measure = require 'thread.base.text'

local M = {}

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
    while measure.width(line) > width do
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
      local hang = string.rep(' ', measure.width(lead))
      local cur = ''
      for word in line:sub(#lead + 1):gmatch '%S+' do
        local candidate = cur == '' and (lead .. word) or (cur .. ' ' .. word)
        if cur ~= '' and measure.width(candidate) > width then
          out[#out + 1] = { text = cur }
          candidate = hang .. word
        end
        cur = candidate
        -- A word longer than the line is cut where it must be.
        while measure.width(cur) > width do
          local head = vim.fn.strcharpart(cur, 0, width)
          while measure.width(head) > width do
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
