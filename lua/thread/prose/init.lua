--- Prose as the agent writes it, in markdown: read into blocks, a line of
--- text into spans, and wrapped to a width as rows to draw. Which
--- primitive a part of it is is decided here: a ```code fence is an
--- excerpt, a `#12` a link, and `code` maybe a name in the code
--- (thread.prose.name). Bold, headings and lists are drawn; any other
--- markdown shows as written.

local excerpt = require 'thread.prose.excerpt'
local link = require 'thread.prose.link'
local text = require 'thread.base.text'

local M = {}

---@class (exact) thread.Span
---@field text string
---@field code boolean|nil  in backticks, which are dropped
---@field bold boolean|nil
---@field link thread.Link|nil
---@field contract boolean|nil  `[[id]]`, a contract named, its brackets dropped

---@class (exact) thread.Block
---@field kind 'text'|'code'|'excerpt'|'blank'
---@field spans thread.Span[]|nil  text: the line, read
---@field lead string|nil  a list item's marker, `- ` or `2. `; its lines wrap under its text
---@field heading boolean|nil
---@field lines string[]|nil  code: as written
---@field excerpt thread.Excerpt|nil
---@field unclosed boolean|nil  a fence never closed, so it runs to the end

--- Something in a row that goes somewhere: byte columns, from 0, its end
--- not in it.
---@class thread.Spot
---@field first integer
---@field last integer
---@field link thread.Link|nil
---@field name string|nil  `code`, which may name a place in the code

---@class thread.ProseRow
---@field chunks { [1]: string, [2]: string }[]  its text, coloured
---@field spots thread.Spot[]
---@field code boolean|nil  a line of a code fence
---@field excerpt thread.Excerpt|nil  drawn in place of the row

--- A line of text as spans: `code` first, then **bold** and links in what
--- is left. `bold` is whether a bold run is open from the line before. A
--- `**` opens one before a word and closes one after a word, so `x ** 2`
--- is not bold.
---@param line string
---@param bold boolean
---@return thread.Span[] spans, boolean bold  open at its end
local function spans_of(line, bold)
  local out = {} ---@type thread.Span[]
  ---@param s string
  local function linked(s)
    local pos = 1
    for _, at in ipairs(link.find(s)) do
      if at.first + 1 > pos then
        out[#out + 1] = { text = s:sub(pos, at.first), bold = bold or nil }
      end
      out[#out + 1] = { text = s:sub(at.first + 1, at.last), bold = bold or nil, link = at.link }
      pos = at.last + 1
    end
    if pos <= #s then
      out[#out + 1] = { text = s:sub(pos), bold = bold or nil }
    end
  end
  --- Contracts named, `[[id]]`, then links in what is left.
  ---@param s string
  local function plain(s)
    local pos = 1
    for from, inner, e in s:gmatch '()%[%[([^%]]+)%]%]()' do
      linked(s:sub(pos, from - 1))
      out[#out + 1] = { text = inner, contract = true, bold = bold or nil }
      pos = e
    end
    linked(s:sub(pos))
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
        plain(line:sub(pos, star - 1))
        bold, pos = not bold, star + 2
      end
    end
    plain(line:sub(pos, to))
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

--- Prose read into blocks: a line of text each, a list item's with its
--- marker, and each fence whole. A fence opens on three backticks or more
--- and a word, and closes on as many or more alone on a line; one left
--- open runs to the end. A bold run goes on to the end of its paragraph,
--- which a heading or a list item starts anew.
---@param s string|nil
---@return thread.Block[]
function M.parse(s)
  local out = {} ---@type thread.Block[]
  local fence, ticks ---@type thread.Block|nil, integer
  local bold = false
  for line in ((s or '') .. '\n'):gmatch '(.-)\r?\n' do
    if fence then
      local close = line:match '^%s*(```+)%s*$'
      if close and #close >= ticks then
        if fence.kind == 'excerpt' then
          fence.excerpt = excerpt.read(fence.lines)
        end
        fence = nil
      else
        table.insert(fence.lines, line)
      end
    else
      local open, info = line:match '^%s*(```+)%s*([^`]-)%s*$'
      if open then
        fence, ticks = { kind = info == 'code' and 'excerpt' or 'code', lines = {} }, #open
        out[#out + 1], bold = fence, false
      elseif not line:match '%S' then
        out[#out + 1], bold = { kind = 'blank' }, false
      else
        local b = { kind = 'text' } ---@type thread.Block
        local hashes, title = line:match '^(#+)%s+(.*)$'
        if hashes and #hashes <= 6 then
          b.heading, line = true, title
        else
          b.lead = line:match '^(%s*[-*+]%s+)' or line:match '^(%s*%d+[.)]%s+)'
          line = line:sub(#(b.lead or '') + 1)
        end
        if b.heading or b.lead then
          bold = false
        end
        b.spans, bold = spans_of(line, bold)
        out[#out + 1] = b
      end
    end
  end
  if fence then
    fence.unclosed = true
    if fence.kind == 'excerpt' then
      fence.excerpt = excerpt.read(fence.lines)
    end
  end
  return out
end

---@param sp thread.Span
---@param heading boolean|nil
---@return string
local function colour(sp, heading)
  if sp.code then
    return 'ThreadCode'
  elseif sp.link then
    return 'ThreadLink'
  elseif sp.contract then
    return 'ThreadContract'
  end
  return (sp.bold or heading) and 'ThreadPoint' or 'ThreadText'
end

--- A piece of a word: some of one span's text.
---@class thread.Piece
---@field text string
---@field span thread.Span

--- A text block's spans as words: what the spaces between them part. A
--- span in backticks and a link are whole words, or the start or end of
--- one, never cut at a space. `gap` is what colour the space before it is.
---@param spans thread.Span[]
---@param heading boolean|nil
---@return { pieces: thread.Piece[], gap: string|nil }[]
local function words_of(spans, heading)
  local out = {}
  local gap ---@type string|nil
  ---@param s string
  ---@param sp thread.Span
  local function piece(s, sp)
    if gap or #out == 0 then
      out[#out + 1] = { pieces = {}, gap = #out > 0 and gap or nil }
      gap = nil
    end
    table.insert(out[#out].pieces, { text = s, span = sp })
  end
  for _, sp in ipairs(spans) do
    if sp.code or sp.link then
      piece(sp.text, sp)
    else
      for run, space in sp.text:gmatch '([^ \t]*)([ \t]*)' do
        if run ~= '' then
          piece(run, sp)
        end
        if space ~= '' and #out > 0 then
          gap = colour(sp, heading)
        end
      end
    end
  end
  return out
end

---@param pieces thread.Piece[]
---@return integer
local function width_of(pieces)
  local n = 0
  for _, p in ipairs(pieces) do
    n = n + text.width(p.text)
  end
  return n
end

--- The pieces that fit in `room` columns, and the rest: a word too long
--- for a line is cut where it must be, one character at least.
---@param pieces thread.Piece[]
---@param room integer
---@return thread.Piece[] head, thread.Piece[] rest
local function cut(pieces, room)
  local head, used = {}, 0 ---@type thread.Piece[], integer
  for i, p in ipairs(pieces) do
    local w = text.width(p.text)
    if used + w > room then
      local n, k = vim.fn.strchars(p.text), 0
      while k < n and used + text.width(vim.fn.strcharpart(p.text, 0, k + 1)) <= room do
        k = k + 1
      end
      if k == 0 and #head == 0 then
        k = 1
      end
      if k > 0 then
        head[#head + 1] = { text = vim.fn.strcharpart(p.text, 0, k), span = p.span }
      end
      local rest = { { text = vim.fn.strcharpart(p.text, k), span = p.span } }
      if rest[1].text == '' then
        rest = {}
      end
      return head, vim.list_extend(rest, pieces, i + 1)
    end
    head[#head + 1], used = p, used + w
  end
  return head, {}
end

--- A text block wrapped to `width`, as rows.
---@param b thread.Block
---@param width integer
---@return thread.ProseRow[]
local function wrap(b, width)
  local rows = {} ---@type thread.ProseRow[]
  local lead = b.lead or ''
  local hang = string.rep(' ', text.width(lead))
  local row ---@type thread.ProseRow
  local col, used = 0, 0 -- bytes, columns
  ---@param s string
  ---@param hl string
  local function put(s, hl)
    local last = row.chunks[#row.chunks]
    if last and last[2] == hl then
      last[1] = last[1] .. s
    else
      row.chunks[#row.chunks + 1] = { s, hl }
    end
    col, used = col + #s, used + text.width(s)
  end
  ---@param start string
  local function new_row(start)
    row = { chunks = {}, spots = {} }
    rows[#rows + 1] = row
    col, used = 0, 0
    if start ~= '' then
      put(start, 'ThreadText')
    end
  end
  ---@param pieces thread.Piece[]
  local function place(pieces)
    for _, p in ipairs(pieces) do
      local sp = p.span
      local from = col
      put(p.text, colour(sp, b.heading))
      -- A link or a name cut over two rows is a spot on each.
      if sp.link or sp.code then
        row.spots[#row.spots + 1] = { first = from, last = col, link = sp.link, name = sp.code and sp.text or nil }
      end
    end
  end
  new_row(lead)
  local fresh = true -- nothing on the row but its lead or hang
  for _, w in ipairs(words_of(b.spans or {}, b.heading)) do
    local pieces = w.pieces
    local need = width_of(pieces) + (fresh and 0 or 1)
    if not fresh and used + need > width then
      new_row(hang)
      fresh = true
    end
    if not fresh then
      put(' ', w.gap or 'ThreadText')
    end
    while used + width_of(pieces) > width and width > used do
      local head, rest = cut(pieces, width - used)
      place(head)
      pieces = rest
      if #rest == 0 then
        break
      end
      new_row(hang)
    end
    place(pieces)
    fresh = false
  end
  return rows
end

--- Prose wrapped to `width` as rows: text with its spans coloured, a
--- fence's lines as code, cut at the width, and a row standing for each
--- excerpt. No blank rows at either end.
---@param s string|nil
---@param width integer
---@return thread.ProseRow[]
function M.rows(s, width)
  local out = {} ---@type thread.ProseRow[]
  for _, b in ipairs(M.parse(s)) do
    if b.kind == 'text' then
      vim.list_extend(out, wrap(b, width))
    elseif b.kind == 'blank' then
      local last = out[#out]
      if not last or #last.chunks > 0 or last.excerpt then
        out[#out + 1] = { chunks = {}, spots = {} }
      end
    elseif b.kind == 'excerpt' then
      out[#out + 1] = { chunks = {}, spots = {}, excerpt = b.excerpt }
    else
      for _, l in ipairs(b.lines or {}) do
        out[#out + 1] = { chunks = { { text.fit((l:gsub('\t', '    ')), width), 'ThreadCode' } }, spots = {}, code = true }
      end
    end
  end
  while #out > 0 and #out[1].chunks == 0 and not out[1].excerpt do
    table.remove(out, 1)
  end
  while #out > 0 and #out[#out].chunks == 0 and not out[#out].excerpt do
    out[#out] = nil
  end
  return out
end

--- Something drawn that goes somewhere, where it is in the sheet: a link
--- or a name on a row, an excerpt's rows, or a note's line.
---@class thread.Drawn
---@field first integer  its rows, 0-based
---@field last integer
---@field s integer|nil  a link's or a name's byte columns on its row
---@field e integer|nil
---@field link thread.Link|nil
---@field name string|nil
---@field excerpt thread.Excerpt|nil
---@field chunk thread.Chunk|nil  a note's line of code (thread.prose.note)

---@class thread.ProseOpts
---@field indent integer|nil  where its rows start; else the sheet's
---@field spec thread.DiffSpec|nil  what the review is about, for an excerpt on its diff
---@field lead { [1]: string, [2]: string }|nil  before its first row, the rest hung under its text: a label, a note's number
---@field hl string|nil  its plain text's colour; else ThreadText
---@field most integer|nil  rows at most, an excerpt drawn as one, where it is; past them a row says it goes on
---@field names table<string, string>|nil  contracts' names by id, for `[[id]]` (thread.model.contract.names)

--- `[[id]]` as `[[name]]`, for each contract `names` has.
---@param s string|nil
---@param names table<string, string>|nil
---@return string|nil
function M.named(s, names)
  if not (s and names) then
    return s
  end
  return (s:gsub('%[%[([^%]]+)%]%]', function(id)
    return '[[' .. (names[id] or id) .. ']]'
  end))
end

--- Prose into a sheet, wrapped to `width`, excerpts drawn as their code.
--- A lead takes a row of its own when an excerpt comes first, or nothing
--- comes after it.
---@param P thread.Sheet
---@param s string|nil
---@param width integer
---@param o thread.ProseOpts|nil
---@return thread.Drawn[]  what in it goes somewhere
function M.draw(P, s, width, o)
  o = o or {}
  s = M.named(s, o.names)
  local indent = o.indent or P.indent
  local lead = o.lead
  local hang = lead and text.width(lead[1]) or 0
  local rows = M.rows(s, width - hang)
  local short = o.most and #rows > o.most
  if short then
    rows = vim.list_slice(rows, 1, o.most)
    while #rows > 1 and #rows[#rows].chunks == 0 and not rows[#rows].excerpt do
      rows[#rows] = nil
    end
  end
  local out = {} ---@type thread.Drawn[]
  if lead and (#rows == 0 or rows[1].excerpt) then
    P.chunks({ lead }, indent)
    lead = nil
  end
  for _, r in ipairs(rows) do
    if r.excerpt then
      local first, last
      if o.most then
        first = excerpt.line(P, r.excerpt, o.spec, indent + hang, width - hang)
        last = first
      else
        first, last = excerpt.draw(P, r.excerpt, o.spec, indent + hang, width - hang)
      end
      out[#out + 1] = { first = first, last = last, excerpt = r.excerpt }
    elseif #r.chunks == 0 then
      P.add ''
    else
      local head = lead or { string.rep(' ', hang) }
      lead = nil
      local chunks = { head }
      for _, c in ipairs(r.chunks) do
        chunks[#chunks + 1] = { c[1], (o.hl and c[2] == 'ThreadText') and o.hl or c[2] }
      end
      local row = P.chunks(chunks, indent)
      local at = indent + #head[1]
      for _, sp in ipairs(r.spots) do
        out[#out + 1] = { first = row, last = row, s = at + sp.first, e = at + sp.last, link = sp.link, name = sp.name }
      end
    end
  end
  if short then
    P.chunks({ { string.rep(' ', hang) }, { '⋯', 'ThreadMeta' } }, indent)
  end
  return out
end

--- Whether prose drawn `most` rows at most is cut short: it runs past
--- them, or has an excerpt, which is then drawn as one row.
---@param s string|nil
---@param width integer
---@param most integer
---@return boolean
function M.cut(s, width, most)
  local rows = M.rows(s, width)
  if #rows > most then
    return true
  end
  for _, r in ipairs(rows) do
    if r.excerpt then
      return true
    end
  end
  return false
end

--- Prose said in one line: its first line with text, its markup dropped.
---@param s string|nil
---@return string
function M.first_line(s)
  for _, b in ipairs(M.parse(s)) do
    if b.kind == 'text' then
      return vim.trim(table.concat(vim.tbl_map(function(sp)
        return sp.text
      end, b.spans or {})))
    end
  end
  return ''
end

--- The first sentence of prose: of its first line with text, up to a full
--- stop, a question or an exclamation mark that a space follows.
---@param s string|nil
---@return string
function M.first_sentence(s)
  local line = M.first_line(s)
  return line:match '^(.-[.!?])%s' or line
end

--- What prose is about, in a sentence: its first, past a bold run-in
--- heading such as `**What is wrong.**`.
---@param s string|nil
---@return string
function M.gist(s)
  local past = (s or ''):gsub('^%s*%*%*[^*\n]+%*%*%s*', '')
  return M.first_sentence(past)
end

return M
