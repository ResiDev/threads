-- thread.prose: markdown read into blocks and wrapped into rows, the
-- excerpts and links in it, and what `--check` reads there.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local check = require 'thread.prose.check'
local diagram = require 'thread.prose.diagram'
local link = require 'thread.prose.link'
local name = require 'thread.prose.name'
local prose = require 'thread.prose'
local review = require 'thread.model.review'
local sheet = require 'thread.ui.sheet'
local thread = require 'thread.model.thread'

local CODE = { 'local M = {}', '', 'function M.get(t, k)', '  return t[k]', 'end', '', 'return M' }

--- A review held in memory, as if read from its file.
---@param threads table[]
---@param o table|nil  more of its fields
---@return thread.Review
local function made(threads, o)
  local raw = vim.tbl_extend('force', { format = 2, title = 'T', threads = threads }, o or {})
  local r, p = review.parse(raw, 'made')
  assert(r, table.concat(p.errors, '\n'))
  return r
end

--- A thread with a tour of `n` steps on each of the agent's first
--- messages, its steps numbered in order.
---@param id integer
---@param tours integer[]  each tour's number of steps
---@return table
local function toured(id, tours)
  local messages, ids = {}, 0
  for k, n in ipairs(tours) do
    local steps = {}
    for i = 1, n do
      ids = ids + 1
      steps[i] = { id = ids, title = 'step ' .. k .. '.' .. i, text = 't' }
    end
    messages[#messages + 1] = { from = 'agent', text = 'm', tours = { { title = 'T' .. k, steps = steps } } }
  end
  return { id = id, title = 'Toured', messages = messages }
end

---@param rows thread.ProseRow[]
---@return string[]
local function texts(rows)
  return vim.tbl_map(function(r)
    return table.concat(vim.tbl_map(function(c)
      return c[1]
    end, r.chunks))
  end, rows)
end

R.test('prose.parse: a block a line, a list item with its marker, a heading, and each fence whole', function()
  local blocks =
    prose.parse 'Intro line\n\n- item one\n2. item two\n## A heading\n```lua\nlocal x = 1\n```\n```code\n{ "file": "a.lua", "line": 1, "text": "x" }\n```'
  R.eq(
    vim.tbl_map(function(b)
      return b.kind .. (b.lead and (' ' .. b.lead) or '') .. (b.heading and ' heading' or '')
    end, blocks),
    { 'text', 'blank', 'text - ', 'text 2. ', 'text heading', 'code', 'excerpt' },
    'kinds'
  )
  R.eq(blocks[6].lines, { 'local x = 1' }, 'a fence as written')
  R.eq(blocks[7].excerpt.chunk, { file = 'a.lua', line = 1, text = 'x' }, 'a ```code fence is an excerpt, read as a chunk')
end)

R.test('prose.parse: a fence closes on as many backticks alone; three on a line with text open none; one left open is marked', function()
  local function kinds(s)
    return vim.tbl_map(function(b)
      return b.kind .. (b.unclosed and ' unclosed' or '')
    end, prose.parse(s))
  end
  local blocks = prose.parse '````md\n```code\n{}\n```\n````\nafter'
  R.eq({ kinds '````md\n```code\n{}\n```\n````\nafter', blocks[1].lines }, { { 'code', 'text' }, { '```code', '{}', '```' } }, 'a fence in a fence')
  R.eq(kinds 'Run ```make``` first.\n\nnext', { 'text', 'blank', 'text' }, 'backticks on a line with text')
  blocks = prose.parse 'see\n```code\n{ "file": "a.lua", "line": 1, "text": "x" }'
  R.eq({ blocks[2].unclosed, blocks[2].excerpt.chunk ~= nil }, { true, true }, 'an excerpt never closed, still read')
  R.eq(kinds '```lua\nx = 1\n\nmore', { 'code unclosed' }, 'a fence never closed runs to the end')
end)

R.test('prose.parse: `code` first, then links and bold in the rest; a bold run goes on to the end of its paragraph', function()
  local blocks = prose.parse 'See `#3` and #4, **bold\nstill** plain\n\nnot **open'
  local spans = blocks[1].spans
  R.eq(
    vim.tbl_map(function(sp)
      return { sp.text, sp.code or false, sp.bold or false, sp.link and link.write(sp.link) or false }
    end, spans),
    {
      { 'See ', false, false, false },
      { '#3', true, false, false },
      { ' and ', false, false, false },
      { '#4', false, false, '#4' },
      { ', ', false, false, false },
      { 'bold', false, true, false },
    },
    'a link in backticks is code'
  )
  R.eq(blocks[2].spans[1], { text = 'still', bold = true }, 'the run carries to the next line')
  R.eq(blocks[2].spans[2], { text = ' plain' }, 'and ends')
  R.eq(blocks[4].spans[2], { text = 'open', bold = true }, 'a new paragraph starts plain')
  blocks = prose.parse '**open\n## Heading\n- item\nIt is x ** 2, or **x**.'
  R.eq({ blocks[2].spans[1].bold, blocks[3].spans[1].bold }, { nil, nil }, 'a heading and a list item start anew')
  R.eq(blocks[4].spans, { { text = 'It is x ** 2, or ' }, { text = 'x', bold = true }, { text = '.' } }, '** with a space on both sides is no bold')
end)

R.test('prose.rows: wrapped at the width; a list item hangs; `code with spaces` is one word; a word too long is cut', function()
  R.eq(texts(prose.rows('one two three four five', 9)), { 'one two', 'three', 'four five' }, 'words')
  R.eq(texts(prose.rows('- one two three', 9)), { '- one two', '  three' }, 'hung under its text')
  R.eq(texts(prose.rows('a `b c d` e', 6)), { 'a', 'b c d', 'e' }, 'kept whole')
  R.eq(texts(prose.rows('abcdefghij', 4)), { 'abcd', 'efgh', 'ij' }, 'cut')
  R.eq(texts(prose.rows('**bold**, then', 20)), { 'bold, then' }, 'markers dropped, the comma kept on its word')
  R.eq(texts(prose.rows('\n\na\n\n\n\nb\n\n', 20)), { 'a', '', 'b' }, 'one blank row between, none at the ends')
  local rows = prose.rows('```\nlong line of code\n```', 8)
  R.eq({ texts(rows), rows[1].code }, { { 'long li…' }, true }, 'a fence cut at the width')
  R.eq(texts(prose.rows('漢字 漢字 漢字', 9)), { '漢字 漢字', '漢字' }, 'by the columns a character takes, not its bytes')
  R.eq(texts(prose.rows('漢字漢字漢字', 5)), { '漢字', '漢字', '漢字' }, 'a wide word cut between characters')
end)

R.test('prose.rows: a spot on each link and name, at its byte columns in the row', function()
  local rows = prose.rows('— see #12.3, then `M.get` and other-review#4.', 80)
  R.ok(#rows == 1 and #'—' == 3, 'one row, after a character of three bytes')
  local line = texts(rows)[1]
  R.eq(
    vim.tbl_map(function(sp)
      return { line:sub(sp.first + 1, sp.last), sp.link and link.write(sp.link) or sp.name }
    end, rows[1].spots),
    { { '#12.3', '#12.3' }, { 'M.get', 'M.get' }, { 'other-review#4', 'other-review#4' } },
    'each spot over its text'
  )
end)

R.test('prose.draw: an excerpt as its lines from the file, numbered; one gone says so; links where they are drawn', function()
  H.reset()
  local root = H.repo { ['a.lua'] = CODE }
  local P = sheet.new { indent = 2 }
  local fence = '```code\n{ "file": "a.lua", "line": 3, "text": "function M.get(t, k)", "lines": 2 }\n```'
  local drawn = prose.draw(P, 'Read #1:\n\n' .. fence, 40)
  R.eq(P.lines, { '  Read #1:', '', '  a.lua:3', '     3  function M.get(t, k)', '     4    return t[k]' }, 'drawn')
  R.eq({ drawn[1].first, drawn[1].s, drawn[1].e, link.write(drawn[1].link) }, { 0, 7, 9, '#1' }, 'the link, in the sheet')
  R.eq({ drawn[2].first, drawn[2].last, drawn[2].excerpt ~= nil }, { 2, 4, true }, 'the excerpt, its rows')
  vim.fn.writefile({ 'return {}' }, root .. '/a.lua')
  P = sheet.new()
  prose.draw(P, fence, 60)
  R.eq(P.lines, { 'a.lua:3 · its line is gone: function M.get(t, k)' }, 'gone')
  P = sheet.new()
  prose.draw(P, '```code\nnot json\n```', 40)
  R.eq(P.lines, { 'not json' }, 'not a chunk: what it says')
end)

R.test('prose.draw: an excerpt in the width, saying when it is not the code now', function()
  H.reset()
  local root = H.repo { ['a.lua'] = { 'local function a_long_name(with, many, arguments) end', 'return 1' } }
  local function drawn(chunk, width, spec)
    local P = sheet.new()
    prose.draw(P, '```code\n' .. vim.json.encode(chunk) .. '\n```', width, { spec = spec })
    return P.lines
  end
  R.eq(drawn({ file = 'a.lua', line = 1, text = 'local function a_long_name(with, many, arguments) end', lines = 1 }, 30), {
    'a.lua:1',
    '   1  local function a_long_n…',
  }, 'cut at the width')
  R.eq(drawn({ file = 'a.lua', line = 2, text = 'return 1', lines = 1, rev = 'HEAD' }, 40), { 'a.lua:2 · at HEAD', '   2  return 1' }, 'at a commit')
  R.eq(drawn({ file = 'a.lua', line = 2, text = 'return 2', lines = 1 }, 40), { 'a.lua:2 · not as quoted', '   2  return 1' }, 'found by likeness')
  R.eq(
    drawn({ file = 'a.lua', line = 2, text = 'return 1', side = 'old' }, 80),
    { 'a.lua:2 · a removed line, with no diff to read it from: return 1' },
    'a removed line, no diff'
  )
  vim.fn.writefile({ 'return 1' }, root .. '/a.lua')
  local spec = require('thread.model.chunk').spec { of = 'uncommitted' }
  R.eq(
    drawn({ file = 'a.lua', line = 1, text = 'local function a_long_name(with, many, arguments) end', side = 'old', lines = 1 }, 30, spec),
    { 'a.lua:1 · removed', '   1  local function a_long_n…' },
    'a removed line, from the diff'
  )
end)

R.test('prose.first_line and first_sentence: of the first line with text, its markup dropped', function()
  R.eq(prose.first_line '\n  first `line`, **bold**  \nsecond', 'first line, bold')
  R.eq(prose.first_line(nil), '')
  R.eq(prose.first_line '```code\n{}\n```\n- Only line', 'Only line')
  R.eq(prose.first_sentence 'It reads `the store`. Then more.', 'It reads the store.')
  R.eq(prose.first_sentence 'No stop here', 'No stop here')
end)

R.test('link.find: #step:7, #note:12, #contract:3, other#note:12; #12, #12.3; not a colour, a version, another kind or inside a word', function()
  local function found(s)
    return vim.tbl_map(function(at)
      return { s:sub(at.first + 1, at.last), at.link }
    end, link.find(s))
  end
  R.eq(found 'Walk #step:7, see #note:12 and (#contract:3).', {
    { '#step:7', { kind = 'step', id = 7 } },
    { '#note:12', { kind = 'note', id = 12 } },
    { '#contract:3', { kind = 'contract', id = 3 } },
  }, 'each names its kind; a full stop after one ends its sentence')
  R.eq(found 'in other-review#note:4.', { { 'other-review#note:4', { review = 'other-review', kind = 'note', id = 4 } } }, 'another review')
  R.eq(found '#tour:1 #step:x #note:1.2 #note:1:2 a_b#step:1 #step:1a #Step:1', {}, 'none of these')
  R.eq(found '#12, and (#12.3).', {
    { '#12', { id = 12 } },
    { '#12.3', { id = 12, step = 3 } },
  }, "format 2's, and format 3's before each kind counted its own")
  R.eq(found 'in other-review#4.1', { { 'other-review#4.1', { review = 'other-review', id = 4, step = 1 } } }, 'another review')
  R.eq(found '#4acbe1 #1.2.3 a_b#3 X#3 -x#3 ##3 https://example.com/notes#12', {}, 'none of these')
  R.eq(found 'threads #3-#5', { { '#3', { id = 3 } }, { '#5', { id = 5 } } }, 'what is no review id is not part of one')
end)

R.test('link.to: #12 a thread, #12.3 its step with id 3, whichever tour it is in', function()
  local r = made { toured(1, { 2 }), toured(2, { 2, 1 }) }
  local function links(t)
    return vim.tbl_map(link.to, thread.conversations(t))
  end
  R.eq(links(r.threads[1]), { '#1', '#1.1', '#1.2' }, 'one tour')
  R.eq(links(r.threads[2]), { '#2', '#2.1', '#2.2', '#2.3' }, 'two')
end)

R.test('link.follow: to a thread, a step by its id, a thread in another review; why, when it goes nowhere', function()
  local r = made { toured(1, { 2 }), toured(2, { 2, 1 }) }
  local other = made { toured(7, { 1 }) }
  local function get(id)
    if id == 'broken' then
      return nil, 'thread 1: no `messages`'
    end
    return id == 'other' and other or nil
  end
  local function follow(s)
    local f, why = link.follow(link.find(s)[1].link, r, get)
    if not f then
      return why
    end
    local c = f.conversation
    return { f.review == other and 'other' or 'here', c.thread.id, c.step and c.step.title or false }
  end
  R.eq(follow '#2', { 'here', 2, false }, 'a thread')
  R.eq(follow '#2.2', { 'here', 2, 'step 1.2' }, 'a step')
  R.eq(follow '#2.3', { 'here', 2, 'step 2.1' }, 'one in its second tour')
  R.eq(follow 'other#7.1', { 'other', 7, 'step 1.1' }, 'in another review')
  R.eq(follow '#9', '`#9` goes to no thread; if it is no link, put it in backticks', 'no thread')
  R.eq(follow '#1.3', '`#1.3` goes to no step: the step ids of thread 1 are 1, 2', 'no step')
  R.eq(follow 'gone#1', '`gone#1` goes to no review gone', 'no review')
  R.eq(follow 'broken#1', '`broken#1` goes to review broken, which cannot be read: thread 1: no `messages`', 'one that cannot be read')
  local steps = r.threads[2].messages[1].tours[1].steps
  table.insert(steps, 1, { id = 4, title = 'put in front', text = 't', messages = {} })
  steps[2], steps[3] = steps[3], steps[2]
  R.eq(
    { follow '#2.2', follow '#2.4' },
    { { 'here', 2, 'step 1.2' }, { 'here', 2, 'put in front' } },
    'a step put in front, and two swapped: each link stays on its step'
  )
end)

R.test("check.review: the agent's excerpts, links and fences, wherever it wrote in an open thread; not yours, nor a closed thread's", function()
  H.reset()
  H.repo { ['a.lua'] = CODE }
  local fence = '```code\n{ "file": "a.lua", "line": 3, "text": "print(42)" }\n```'
  local step = {
    id = 1,
    title = 'A step',
    text = 'to #16',
    checks = { { text = 'to #18', run = 'true' } },
    messages = { { from = 'you', text = 'to #19' }, { from = 'agent', text = 'to #20' } },
  }
  local r = made({
    {
      id = 1,
      title = 'Open',
      messages = {
        { from = 'agent', text = 'See #9 and #1.1.1.\n\n```code\n{ "file": "a.lua" \n```\n\n```code\n{ "file": "a.lua", "line": 1 }\n```\n\n' .. fence },
        { from = 'you', text = 'And #8? ' .. fence },
        {
          from = 'agent',
          text = 'More.\n```lua\nnever closed',
          tours = { { title = 'T', introduction = 'to #15', steps = { step } } },
        },
      },
      checks = { { text = 'ran #7', run = 'true' } },
    },
    { id = 2, title = 'Closed', status = 'fixed', messages = { { from = 'agent', text = 'See #9.' } } },
    { id = 3, title = 'Open too', messages = { { from = 'agent', text = 'x\n\n```code\n{ "file": "a.lua", "line": 1, "text": "local M = {}" }' } } },
  }, { introduction = 'Starts at #14.' })
  local p = check.review(r, function() end)
  R.eq(
    vim.tbl_map(function(w)
      return (w:gsub('; if it is no link, put it in backticks$', ''))
    end, p.warnings),
    {
      'the review, introduction: `#14` goes to no thread',
      'thread 1, check 1: `#7` goes to no thread',
      'thread 1, message 1: `#9` goes to no thread',
      "thread 1, message 1: `#1.1.1` is no link: a step's link is its thread's and its id, `#1.<id>`",
      'thread 1, message 3: a ``` fence is never closed, so all after it shows as code: end it with ``` on a line of its own',
      'thread 1, message 3, tour 1, introduction: `#15` goes to no thread',
      'thread 1, message 3, tour 1, step 1: `#16` goes to no thread',
      'thread 1, message 3, tour 1, step 1, check 1: `#18` goes to no thread',
      'thread 1, message 3, tour 1, step 1, message 2: `#20` goes to no thread',
    },
    'links everywhere the agent wrote, and a fence left open'
  )
  R.eq(#p.errors, 4, vim.inspect(p.errors))
  R.ok(p.errors[1]:find '^thread 1, message 1, excerpt 1: a ```code fence holds one chunk, as JSON, and this is not JSON', 'not JSON')
  R.eq(p.errors[2], 'thread 1, message 1, excerpt 2: no `text`: quote its first line, as it reads', 'not a chunk')
  R.ok(p.errors[3]:find '^thread 1, message 1, excerpt 3: a.lua has no line reading "print%(42%)"', 'not in the code')
  R.eq(p.errors[4], 'thread 3, message 1, excerpt 1: its ```code fence is never closed: end it with ``` on a line of its own', 'an excerpt left open')
end)

R.test('diagram.draw: laid out into the sheet, and the box under a row and a byte column found', function()
  local d = assert(require('thread.model.diagram').validate {
    kind = 'flow',
    nodes = { { id = 'a', label = 'read', file = 'a.lua', line = 1, text = 'local M = {}' }, { id = 'b', label = 'write' } },
    edges = { { from = 'a', to = 'b' } },
  })
  local P = sheet.new()
  P.add 'before'
  local drawn = diagram.draw(P, d, 40, 4)
  R.eq(drawn.first, 1, 'after what was there')
  R.ok(P.lines[drawn.first + 2]:find 'read', 'its first box drawn: ' .. table.concat(P.lines, '\n'))
  local row = assert(vim.iter(ipairs(P.lines)):find(function(i, l)
    return i > drawn.first + 1 and l:find 'read' ~= nil
  end)) - 1
  -- Its right edge: past two characters of three bytes each.
  local col = assert(P.lines[row + 1]:find '│%s*$') - 1
  R.ok(col > vim.fn.strdisplaywidth(P.lines[row + 1]:sub(1, col)), 'past characters of more than a byte')
  local node = diagram.at(drawn, row, col)
  R.eq(node and node.label, 'read', 'found at its row and column')
  R.eq(diagram.at(drawn, 0, 0), nil, 'nothing outside it')
end)

R.test('name.resolve: a place written after it, a path, and a definition before its uses', function()
  H.reset()
  H.repo { ['lua/store.lua'] = { 'local M = {}', 'function M.save(x)', '  return x', 'end', 'return M' }, ['lua/use.lua'] = { 'store.save(1)' } }
  name.reset()
  R.eq(name.resolve('save', {}, ' (store.lua:3)'), { { file = 'lua/store.lua', line = 3, def = true } }, 'written after it')
  R.eq(name.resolve('lua/use.lua', {}), { { file = 'lua/use.lua', line = 1, def = true } }, 'a path')
  R.eq(name.resolve('store.save', {})[1], { file = 'lua/store.lua', line = 2, def = true }, 'where it is defined')
  R.eq(name.resolve('[]', {}), {}, 'not a name')
end)
