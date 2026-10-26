--- Prose as the agent writes it, in markdown: read into blocks, a line of
--- text into spans, and wrapped to a width as rows to draw. Which
--- primitive a part of it is is decided here: `{{chunk:id}}` alone on a
--- line is an excerpt, `{{diagram:name}}` a diagram, `{{tour:name}}` and
--- `{{contract:3}}` drawn in place (thread.prose.inline), a `#note:12` a link,
--- a `#contract:3` a link that reads as the contract's name, and `code`
--- maybe a name in the code (thread.prose.name). Bold, italic, headings,
--- lists, quotes and tables are drawn; any other markdown shows as
--- written. A heading of any level starts a section, drawn with a bar down
--- its side.

local code = require 'thread.base.code'
local contract = require 'thread.model.contract'
local diagram = require 'thread.prose.diagram'
local excerpt = require 'thread.prose.excerpt'
local inline = require 'thread.prose.inline'
local model_prose = require 'thread.model.prose'
local review = require 'thread.model.review'
local spec_of = require('thread.model.chunk').spec
local span = require 'thread.prose.span'
local text = require 'thread.base.text'
local theme = require 'thread.ui.theme'

local M = {}

---@class (exact) thread.Span
---@field text string
---@field code boolean|nil  in backticks, which are dropped
---@field bold boolean|nil
---@field italic boolean|nil
---@field link thread.Link|nil
---@field contract boolean|nil  a link to a contract, read as its name
---@field number integer|nil  not written: a highlight's number after its name, while you pick one

--- A step's highlights as its text draws them: each one's number by what
--- it wrote for it (thread.prose.highlight), and the current one, it and
--- its sentence lit; 0, none.
---@class thread.ProseHighlights
---@field numbers table<string, integer>
---@field current integer
---@field picking boolean|nil  each one's number after its name, as `gs` lays them over the code

---@class (exact) thread.Block
---@field kind 'text'|'code'|'excerpt'|'diagram'|'inline'|'table'|'blank'
---@field spans thread.Span[]|nil  text: the line, read
---@field lead string|nil  a list item's marker, `- ` or `2. `; its lines wrap under its text
---@field heading boolean|nil
---@field quote boolean|nil  a line of a `>` quote
---@field section integer|nil  the heading it is under, counted from 1; none before the first
---@field lines string[]|nil  code: as written
---@field lang string|nil  code: the word after its opening backticks, its language
---@field excerpt thread.Excerpt|nil
---@field name string|nil  a diagram's
---@field diagram table|nil  a diagram, checked; nil when its prose has none by that name
---@field inline thread.Inline|nil  a tour or a contract placed
---@field cells thread.Span[][][]|nil  a table: its rows, each its cells' spans, the header first
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
---@field diagram { name: string, diagram: table|nil }|nil  drawn in place of the row
---@field inline thread.Inline|nil  drawn in place of the row
---@field section integer|nil  the section whose bar runs down it

--- Prose, or plain text written where prose goes: a title, a `why`.
---@alias thread.ProseLike thread.Prose|string|nil

---@param x thread.ProseLike
---@return thread.Prose|nil
local function as_prose(x)
  if type(x) == 'string' then
    return model_prose.of(x)
  end
  return x
end

--- A table's row as its cells: what the `|`s part, those at either end
--- dropped. Nil for a line that is no row.
---@param line string
---@return string[]|nil
local function cells_of(line)
  local inner = line:match '^%s*|(.*)|%s*$'
  if not inner then
    return nil
  end
  local out = {} ---@type string[]
  for cell in (inner .. '|'):gmatch '(.-)|' do
    out[#out + 1] = vim.trim(cell)
  end
  return out
end

--- Whether a row of cells is a table's rule under its header: `---`,
--- `:--`, `--:` each.
---@param cells string[]
---@return boolean
local function rule(cells)
  for _, c in ipairs(cells) do
    if not c:match '^:?%-+:?$' then
      return false
    end
  end
  return #cells > 0
end

--- Its lines, and what places a chunk or a diagram, read into blocks: a
--- line of text each, a list item's with its marker, a table whole, each
--- fence whole. A fence opens on three backticks or more and a word, or
--- none, and closes on as many or more alone on a line; one left open
--- runs to the end. A bold run goes on to the end of its paragraph, which
--- a heading or a list item starts anew. A line opening `> ` is a quote's;
--- `>=` and `>>>` are not.
---@param x thread.ProseLike
---@param r thread.Review|nil  its review: for its chunks, and its contracts' names
---@return thread.Block[]
function M.parse(x, r)
  local p = as_prose(x)
  local names = r and contract.names(r) or nil
  local spec = r and spec_of(r.diff) or nil
  local lines = vim.split(model_prose.text(p), '\r?\n')
  local out = {} ---@type thread.Block[]
  local fence, ticks ---@type thread.Block|nil, integer
  local bold = false
  local section ---@type integer|nil
  local i = 1
  while i <= #lines do
    local line = lines[i]
    if fence then
      local close = line:match '^%s*(```+)%s*$'
      if close and #close >= ticks then
        fence = nil
      else
        table.insert(fence.lines, line)
      end
      i = i + 1
    else
      local open, lang = line:match '^%s*(```+)%s*([^`]-)%s*$'
      local kind, name = model_prose.place(line)
      local head = cells_of(line)
      local under = head and lines[i + 1] and cells_of(lines[i + 1])
      if open then
        fence, ticks = { kind = 'code', lines = {}, lang = lang ~= '' and lang or nil }, #open
        out[#out + 1], bold = fence, false
        i = i + 1
      elseif kind == 'chunk' and name then
        out[#out + 1], bold = { kind = 'excerpt', excerpt = { id = name, chunk = r and review.chunk(r, name), spec = spec } }, false
        i = i + 1
      elseif kind == 'diagram' and name then
        out[#out + 1], bold = { kind = 'diagram', name = name, diagram = model_prose.diagram(p, name) }, false
        i = i + 1
      elseif (kind == 'tour' or kind == 'contract') and name then
        local id = tonumber(name)
        local at = { kind = kind == 'tour' and 'tour' or 'contract', name = name } ---@type thread.Inline
        if kind == 'tour' then
          at.tour = r and id and review.tour(r, id) or nil
        else
          at.contract = r and id and review.contract(r, id) or nil
        end
        out[#out + 1], bold = { kind = 'inline', inline = at }, false
        i = i + 1
      elseif head and under and rule(under) then
        local rows = { head } ---@type string[][]
        i = i + 2
        while lines[i] and cells_of(lines[i]) do
          rows[#rows + 1] = assert(cells_of(lines[i]))
          i = i + 1
        end
        local cells = {} ---@type thread.Span[][][]
        for k, row in ipairs(rows) do
          cells[k] = vim.tbl_map(function(c)
            return (span.of(c, false, names))
          end, row)
        end
        out[#out + 1], bold = { kind = 'table', cells = cells }, false
      elseif not line:match '%S' then
        out[#out + 1], bold = { kind = 'blank' }, false
        i = i + 1
      else
        local b = { kind = 'text' } ---@type thread.Block
        local hashes, title = line:match '^(#+)%s+(%S.*)$'
        local quoted = line:match '^%s*>%s(.*)$' or (line:match '^%s*>$' and '')
        if hashes and #hashes <= 6 then
          b.heading, line = true, title
          section = (section or 0) + 1
        elseif quoted then
          b.quote, line = true, quoted
        else
          b.lead = line:match '^(%s*[-*+]%s+)' or line:match '^(%s*%d+[.)]%s+)'
          line = line:sub(#(b.lead or '') + 1)
        end
        if b.heading or b.lead then
          bold = false
        end
        b.spans, bold = span.of(line, bold, names)
        out[#out + 1] = b
        i = i + 1
      end
    end
    out[#out].section = section
  end
  if fence then
    fence.unclosed = true
  end
  return out
end

--- A text block's plain colour: a heading's, a quote's, or none for the
--- usual.
---@param b thread.Block
---@return string|nil
local function plain_of(b)
  return b.heading and 'ThreadHeading' or b.quote and 'ThreadQuote' or nil
end

--- A link's colour, by what it opens: a contract, a step or a note each
--- its own, a contract by its name.
---@param sp thread.Span
---@return string
local function link_colour(sp)
  local kind = sp.link and sp.link.kind
  if sp.contract then
    return 'ThreadContract'
  elseif kind == 'contract' then
    return 'ThreadLinkContract'
  elseif kind == 'step' then
    return 'ThreadLinkStep'
  elseif kind == 'note' then
    return 'ThreadLinkNote'
  end
  return 'ThreadLink'
end

---@param sp thread.Span
---@param plain string|nil  its block's plain colour (plain_of)
---@return string
local function colour(sp, plain)
  if sp.number then
    return 'ThreadHighlightLabel'
  elseif sp.code then
    return 'ThreadCode'
  elseif sp.link then
    return link_colour(sp)
  elseif plain then
    return plain
  elseif sp.bold then
    return sp.italic and 'ThreadPointItalic' or 'ThreadPoint'
  end
  return sp.italic and 'ThreadItalic' or 'ThreadText'
end

--- Whether a span names the current highlight.
---@param sp thread.Span
---@param hl thread.ProseHighlights|nil
---@return boolean
local function current_in(sp, hl)
  local current = hl and hl.current or 0
  return current > 0 and sp.code == true and not sp.link and hl ~= nil and hl.numbers[sp.text] == current
end

--- A highlight's colour, the current one's in it, a span in its
--- sentence on its wash; else its own.
---@param sp thread.Span
---@param plain string|nil
---@param hl thread.ProseHighlights|nil
---@param lit boolean|nil  in the current one's sentence
---@return string
local function shade(sp, plain, hl, lit)
  if current_in(sp, hl) then
    return 'ThreadHighlightHere'
  end
  local group = colour(sp, plain)
  return lit and theme.sentence(group) or group
end

--- Spans with each highlight's number after what it wrote for it, while
--- you pick one.
---@param spans thread.Span[]
---@param hl thread.ProseHighlights|nil
---@return thread.Span[]
local function numbered(spans, hl)
  if not (hl and hl.picking) then
    return spans
  end
  local out = {} ---@type thread.Span[]
  for _, sp in ipairs(spans) do
    out[#out + 1] = sp
    local n = sp.code and not sp.link and hl.numbers[sp.text]
    if n and n <= 9 then
      out[#out + 1] = { text = tostring(n), number = n }
    end
  end
  return out
end

--- A piece of a word: some of one span's text.
---@class thread.Piece
---@field text string
---@field span thread.Span

--- A text block's spans as words: what the spaces between them part. A
--- span in backticks and a link are whole words, or the start or end of
--- one, never cut at a space. `gap` is what colour the space before it
--- is; `sentence` which of the block's it is in, counted from 1, a word
--- ending in `.`, `?` or `!` the last of one.
---@param spans thread.Span[]
---@param plain string|nil
---@return { pieces: thread.Piece[], gap: string|nil, gap_span: thread.Span|nil, sentence: integer }[]
local function words_of(spans, plain)
  local out = {}
  local gap ---@type string|nil
  local gap_span ---@type thread.Span|nil
  local sentence = 1
  ---@param s string
  ---@param sp thread.Span
  local function piece(s, sp)
    if gap or #out == 0 then
      local last = out[#out]
      local tail = last and last.pieces[#last.pieces]
      if tail and not (tail.span.code or tail.span.number) and tail.text:match '[.!?][%)"\']*$' then
        sentence = sentence + 1
      end
      out[#out + 1] = { pieces = {}, gap = #out > 0 and gap or nil, gap_span = #out > 0 and gap_span or nil, sentence = sentence }
      gap, gap_span = nil, nil
    end
    table.insert(out[#out].pieces, { text = s, span = sp })
  end
  for _, sp in ipairs(spans) do
    if sp.code or sp.link or sp.number then
      piece(sp.text, sp)
    else
      for run, space in sp.text:gmatch '([^ \t]*)([ \t]*)' do
        if run ~= '' then
          piece(run, sp)
        end
        if space ~= '' and #out > 0 then
          gap, gap_span = colour(sp, plain), sp
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

--- A row being built: its chunks, and where in it things go somewhere.
---@param row thread.ProseRow
---@param s string
---@param hl string
local function put(row, s, hl)
  local last = row.chunks[#row.chunks]
  if last and last[2] == hl then
    last[1] = last[1] .. s
  else
    row.chunks[#row.chunks + 1] = { s, hl }
  end
end

---@param row thread.ProseRow
---@return integer
local function bytes(row)
  local n = 0
  for _, c in ipairs(row.chunks) do
    n = n + #c[1]
  end
  return n
end

-- What runs down a quote's side.
local QUOTE = '▏ '

--- A text block wrapped to `width`, as rows.
---@param b thread.Block
---@param width integer
---@param hl thread.ProseHighlights|nil
---@return thread.ProseRow[]
local function wrap(b, width, hl)
  local rows = {} ---@type thread.ProseRow[]
  local plain = plain_of(b)
  -- A quote's bar runs down every row of it.
  local lead = b.quote and QUOTE or b.lead or ''
  local hang = b.quote and QUOTE or string.rep(' ', text.width(lead))
  local row ---@type thread.ProseRow
  local used = 0 -- columns
  ---@param s string
  ---@param group string
  local function add(s, group)
    put(row, s, group)
    used = used + text.width(s)
  end
  ---@param start string
  local function new_row(start)
    row = { chunks = {}, spots = {} }
    rows[#rows + 1] = row
    used = 0
    if start ~= '' then
      add(start, b.quote and 'ThreadQuoteBar' or 'ThreadText')
    end
  end
  local words = words_of(numbered(b.spans or {}, hl), plain)
  -- The sentence the current highlight is in, lit.
  local lit = {} ---@type table<integer, true>
  for _, w in ipairs(words) do
    for _, p in ipairs(w.pieces) do
      if current_in(p.span, hl) then
        lit[w.sentence] = true
      end
    end
  end
  local here ---@type integer
  ---@param pieces thread.Piece[]
  local function place(pieces)
    for _, p in ipairs(pieces) do
      local sp = p.span
      local from = bytes(row)
      add(p.text, shade(sp, plain, hl, lit[here]))
      -- A link or a name cut over two rows is a spot on each.
      if sp.link or sp.code then
        row.spots[#row.spots + 1] = { first = from, last = bytes(row), link = sp.link, name = sp.code and sp.text or nil }
      end
    end
  end
  new_row(lead)
  local fresh = true -- nothing on the row but its lead or hang
  local before ---@type integer|nil
  for _, w in ipairs(words) do
    -- The space between two sentences is neither's.
    local within = lit[w.sentence] and before == w.sentence
    here, before = w.sentence, w.sentence
    local pieces = w.pieces
    local need = width_of(pieces) + (fresh and 0 or 1)
    if not fresh and used + need > width then
      new_row(hang)
      fresh = true
    end
    if not fresh then
      local gap = w.gap or 'ThreadText'
      add(' ', within and w.gap_span and shade(w.gap_span, plain, hl, true) or (within and theme.sentence(gap)) or gap)
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

---@param spans thread.Span[]
---@return integer
local function spans_width(spans)
  local n = 0
  for _, sp in ipairs(spans) do
    n = n + text.width(sp.text)
  end
  return n
end

-- What parts a table's columns.
local SEP = ' │ '

--- A table drawn as rows: each column as wide as its widest cell, the
--- widest cut down until the row fits `width`, a cell cut short ending
--- `…`; a rule under the header.
---@param b thread.Block
---@param width integer
---@param hl thread.ProseHighlights|nil
---@return thread.ProseRow[]
local function table_rows(b, width, hl)
  local cells = {} ---@type thread.Span[][][]
  for r, row in ipairs(b.cells or {}) do
    cells[r] = vim.tbl_map(function(cell)
      return numbered(cell, hl)
    end, row)
  end
  local n = 0
  for _, row in ipairs(cells) do
    n = math.max(n, #row)
  end
  local widths = {} ---@type integer[]
  for k = 1, n do
    widths[k] = 1
    for _, row in ipairs(cells) do
      widths[k] = math.max(widths[k], spans_width(row[k] or {}))
    end
  end
  local room = width - text.width(SEP) * (n - 1)
  local total = 0
  for _, w in ipairs(widths) do
    total = total + w
  end
  while total > room and total > n do
    local widest = 1
    for k, w in ipairs(widths) do
      widest = w > widths[widest] and k or widest
    end
    if widths[widest] <= 3 then
      break
    end
    widths[widest], total = widths[widest] - 1, total - 1
  end
  local out = {} ---@type thread.ProseRow[]
  for r, row in ipairs(cells) do
    local line = { chunks = {}, spots = {} } ---@type thread.ProseRow
    for k = 1, n do
      if k > 1 then
        put(line, SEP, 'ThreadMeta')
      end
      local left = widths[k]
      for _, sp in ipairs(row[k] or {}) do
        if left <= 0 then
          break
        end
        local s = sp.text
        if text.width(s) > left then
          s = text.fit(s, left)
        end
        local from = bytes(line)
        put(line, s, (r == 1 and not current_in(sp, hl)) and 'ThreadPoint' or shade(sp, nil, hl, false))
        if sp.link or sp.code then
          line.spots[#line.spots + 1] = { first = from, last = bytes(line), link = sp.link, name = sp.code and sp.text or nil }
        end
        left = left - text.width(s)
      end
      if k < n and left > 0 then
        put(line, string.rep(' ', left), 'ThreadText')
      end
    end
    out[#out + 1] = line
    if r == 1 then
      local parts = vim.tbl_map(function(w)
        return string.rep('─', w)
      end, widths)
      out[#out + 1] = { chunks = { { table.concat(parts, '─┼─'), 'ThreadMeta' } }, spots = {} }
    end
  end
  return out
end

--- A line of code as chunks, coloured by its syntax spans, the later of
--- two on a byte winning; its tabs drawn as spaces.
---@param line string
---@param spans { [1]: integer, [2]: integer, [3]: string }[]|nil
---@return { [1]: string, [2]: string }[]
local function coloured(line, spans)
  local hl = {} ---@type table<integer, string>
  for _, sp in ipairs(spans or {}) do
    for b = sp[1] + 1, math.min(sp[2], #line) do
      hl[b] = sp[3]
    end
  end
  local out = {} ---@type { [1]: string, [2]: string }[]
  for b = 1, #line do
    local group = hl[b] or 'ThreadCode'
    local last = out[#out]
    if last and last[2] == group then
      last[1] = last[1] .. line:sub(b, b)
    else
      out[#out + 1] = { line:sub(b, b), group }
    end
  end
  for _, c in ipairs(out) do
    c[1] = c[1]:gsub('\t', '    ')
  end
  return #out > 0 and out or { { '', 'ThreadCode' } }
end

-- Columns a section's bar takes before its rows: the bar and a space.
local GUTTER = 2
-- What runs down a section's side.
M.BAR = '▎'
local BAR = M.BAR

---@param row thread.ProseRow|nil
---@return boolean
local function empty(row)
  return row ~= nil and #row.chunks == 0 and not row.excerpt and not row.diagram and not row.inline
end

--- Prose wrapped to `width` as rows: text with its spans coloured, a
--- fence's lines as code, cut at the width, a table's rows, and a row
--- standing for each excerpt and each diagram. No blank rows at either
--- end, and one under each heading. With a heading, every row is moved
--- `gutter` columns right, where a section's bar goes: down its rows from
--- its heading to the last with something on it. A row of text has it written at its start; an
--- excerpt, a diagram or a tour placed, drawn as itself, has it drawn over
--- (prose.draw).
---@param x thread.ProseLike
---@param width integer
---@param r thread.Review|nil
---@param hl thread.ProseHighlights|nil  a step's highlights, the current one lit
---@return thread.ProseRow[] rows, integer gutter
function M.rows(x, width, r, hl)
  local blocks = M.parse(x, r)
  local gutter = 0
  for _, b in ipairs(blocks) do
    if b.heading then
      gutter = GUTTER
    end
  end
  width = math.max(1, width - gutter)
  local out = {} ---@type thread.ProseRow[]
  for _, b in ipairs(blocks) do
    local from = #out + 1
    if b.kind == 'text' then
      vim.list_extend(out, wrap(b, width, hl))
      -- A heading stands apart from what it heads.
      if b.heading then
        out[#out + 1] = { chunks = {}, spots = {} }
      end
    elseif b.kind == 'blank' then
      local last = out[#out]
      if not last or not empty(last) then
        out[#out + 1] = { chunks = {}, spots = {} }
      end
    elseif b.kind == 'excerpt' then
      out[#out + 1] = { chunks = {}, spots = {}, excerpt = b.excerpt }
    elseif b.kind == 'diagram' then
      out[#out + 1] = { chunks = {}, spots = {}, diagram = { name = assert(b.name), diagram = b.diagram } }
    elseif b.kind == 'inline' then
      out[#out + 1] = { chunks = {}, spots = {}, inline = b.inline }
    elseif b.kind == 'table' then
      vim.list_extend(out, table_rows(b, width, hl))
    else
      local lines = b.lines or {}
      local syntax = b.lang and code.syntax(lines, 'fence.' .. b.lang) or {}
      for k, l in ipairs(lines) do
        out[#out + 1] = { chunks = text.fit_chunks(coloured(l, syntax[k]), width), spots = {}, code = true }
      end
    end
    for k = from, #out do
      out[k].section = b.section
    end
  end
  while empty(out[1]) do
    table.remove(out, 1)
  end
  while empty(out[#out]) do
    out[#out] = nil
  end
  if gutter == 0 then
    return out, 0
  end
  local last = {} ---@type table<integer, integer>
  for k, row in ipairs(out) do
    if row.section and not empty(row) then
      last[row.section] = k
    end
  end
  for k, row in ipairs(out) do
    if row.section and k > (last[row.section] or 0) then
      row.section = nil
    end
    if not (row.excerpt or row.diagram or row.inline) and (row.section or not empty(row)) then
      local head = row.section and { BAR .. ' ', 'ThreadSectionBar' } or { string.rep(' ', gutter), 'ThreadText' }
      table.insert(row.chunks, 1, head)
      for _, sp in ipairs(row.spots) do
        sp.first, sp.last = sp.first + #head[1], sp.last + #head[1]
      end
    end
  end
  return out, gutter
end

--- Something drawn that goes somewhere, where it is in the sheet: a link
--- or a name on a row, an excerpt's rows, a diagram's.
---@class thread.Drawn
---@field first integer  its rows, 0-based
---@field last integer
---@field s integer|nil  a link's or a name's byte columns on its row
---@field e integer|nil
---@field link thread.Link|nil
---@field name string|nil
---@field excerpt thread.Excerpt|nil
---@field diagram thread.DrawnDiagram|nil
---@field fold string|nil  a tour or a contract placed: what folds it
---@field inline thread.FoldKind|nil  which of the two
---@field tour thread.Tour|nil  a tour placed: its block, its head and its steps
---@field step thread.Step|nil  one of its steps
---@field section integer|nil  a heading's section: its rows, and `span` the columns it is lit across
---@field span { from: integer, to: integer }|nil

---@class thread.ProseOpts
---@field indent integer|nil  where its rows start; else the sheet's
---@field review thread.Review|nil  its review: for its chunks, and its contracts' names
---@field lead { [1]: string, [2]: string }|nil  before its first row, the rest hung under its text: a label
---@field hl string|nil  its plain text's colour; else ThreadText
---@field most integer|nil  rows at most, an excerpt or a diagram drawn as one, where it is; past them a row says it goes on
---@field contract (fun(P: thread.Sheet, c: thread.Contract, width: integer, indent: integer): thread.Drawn[])|nil  a contract placed, drawn by this rather than at its fold
---@field measure integer|nil  its text wrapped this wide at most, what is drawn as itself still `width`
---@field highlights thread.ProseHighlights|nil  a step's: the current one and its sentence lit

--- Prose into a sheet, wrapped to `width`, excerpts drawn as their code
--- and diagrams laid out. A lead takes a row of its own when an excerpt or
--- a diagram comes first, or nothing comes after it.
---@param P thread.Sheet
---@param x thread.ProseLike
---@param width integer
---@param o thread.ProseOpts|nil
---@return thread.Drawn[]  what in it goes somewhere
function M.draw(P, x, width, o)
  o = o or {}
  local indent = o.indent or P.indent
  local lead = o.lead
  local hang = lead and text.width(lead[1]) or 0
  local rows, gutter = M.rows(x, math.min(o.measure or width, width) - hang, o.review, o.highlights)
  -- Where what is drawn as itself starts, past the lead and a section's bar.
  local inner = hang + gutter
  local short = o.most and #rows > o.most
  if short then
    rows = vim.list_slice(rows, 1, o.most)
    while #rows > 1 and #rows[#rows].chunks == 0 and not rows[#rows].excerpt and not rows[#rows].diagram and not rows[#rows].inline do
      rows[#rows] = nil
    end
  end
  local out = {} ---@type thread.Drawn[]
  if lead and (#rows == 0 or rows[1].excerpt or rows[1].diagram or rows[1].inline) then
    P.chunks({ lead }, indent)
    lead = nil
  end
  local sections = {} ---@type table<integer, { first: integer, last: integer }>
  for _, r in ipairs(rows) do
    local top = #P.lines
    if r.excerpt then
      local first, last
      if o.most then
        first = excerpt.line(P, r.excerpt, indent + inner, width - inner)
        last = first
      else
        first, last = excerpt.draw(P, r.excerpt, indent + inner, width - inner)
      end
      out[#out + 1] = { first = first, last = last, excerpt = r.excerpt }
    elseif r.inline then
      local drawn ---@type thread.Drawn[]
      if o.most then
        drawn = inline.line(P, r.inline, width - inner, indent + inner)
      elseif o.contract and r.inline.contract then
        drawn = o.contract(P, r.inline.contract, width - inner, indent + inner)
      else
        drawn = inline.draw(P, r.inline, o.review, width - inner, indent + inner, M.draw)
      end
      vim.list_extend(out, drawn)
    elseif r.diagram then
      local d = r.diagram.diagram
      if not d then
        P.chunks(
          text.fit_chunks({ { '{{diagram:' .. r.diagram.name .. '}}', 'ThreadCode' }, { ' · no diagram by that name', 'ThreadBroken' } }, width - inner),
          indent + inner
        )
      elseif o.most then
        P.chunks({ { text.fit('▦ a diagram', width - inner), 'ThreadMeta' } }, indent + inner)
      else
        local drawn = diagram.draw(P, d, width - inner, indent + inner)
        out[#out + 1] = { first = drawn.first, last = drawn.last, diagram = drawn }
      end
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
    if r.section and #P.lines > top then
      local at = sections[r.section] or { first = top }
      at.last, sections[r.section] = #P.lines - 1, at
      if r.excerpt or r.diagram or r.inline then
        for row = top, #P.lines - 1 do
          P.mark(row, 0, { virt_text = { { BAR, 'ThreadSectionBar' } }, virt_text_win_col = indent + hang, priority = 6 })
        end
      end
    end
  end
  local ks = vim.tbl_keys(sections)
  table.sort(ks)
  for _, k in ipairs(ks) do
    local at = sections[k]
    out[#out + 1] = { first = at.first, last = at.last, section = k, span = { from = indent + hang, to = indent + width } }
  end
  if short then
    P.chunks({ { string.rep(' ', inner) }, { '⋯', 'ThreadMeta' } }, indent)
  end
  return out
end

--- Whether prose drawn `most` rows at most is cut short: it runs past
--- them, or has an excerpt, a diagram, a tour or a contract, which is
--- then drawn as one row.
---@param x thread.ProseLike
---@param width integer
---@param most integer
---@param r thread.Review|nil
---@return boolean
function M.cut(x, width, most, r)
  local rows = M.rows(x, width, r)
  if #rows > most then
    return true
  end
  for _, row in ipairs(rows) do
    if row.excerpt or row.diagram or row.inline then
      return true
    end
  end
  return false
end

--- Prose said in one line: its first line with text, its markup dropped.
--- With its review, a contract linked reads as its name.
---@param x thread.ProseLike
---@param r thread.Review|nil
---@return string
function M.first_line(x, r)
  for _, b in ipairs(M.parse(x, r)) do
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
---@param x thread.ProseLike
---@param r thread.Review|nil
---@return string
function M.first_sentence(x, r)
  local line = M.first_line(x, r)
  return line:match '^(.-[.!?])%s' or line
end

return M
