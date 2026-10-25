-- thread.prose: markdown read into blocks and wrapped into rows, the
-- excerpts, diagrams, tables and links in it, and what `--check` reads
-- there.

local R = require 'tests.runner'
local H = require 'tests.helpers'

local check = require 'thread.prose.check'
local diagram = require 'thread.prose.diagram'
local fold = require 'thread.prose.fold'
local highlight = require 'thread.prose.highlight'
local link = require 'thread.prose.link'
local name = require 'thread.prose.name'
local prose = require 'thread.prose'
local review = require 'thread.model.review'
local sheet = require 'thread.ui.sheet'

--- A review held in memory, as if read from its file: H.draft with
--- `over`'s fields.
---@param over table|nil
---@param id string|nil
---@return thread.Review
local function made(over, id)
  local r, p = review.parse(H.draft(over), id or 'made')
  return assert(r, table.concat(p.errors, '\n'))
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

---@param blocks thread.Block[]
---@return string[]
local function kinds(blocks)
  return vim.tbl_map(function(b)
    return b.kind .. (b.lead and (' ' .. b.lead) or '') .. (b.heading and ' heading' or '') .. (b.unclosed and ' unclosed' or '')
  end, blocks)
end

local SHAPE = { kind = 'flow', nodes = { { id = 'a', label = 'get', chunk = 'get' }, { id = 'b', label = 'store' } }, edges = { { from = 'a', to = 'b' } } }

R.test('prose.parse: a block a line, a list item with its marker, a heading, a fence whole, an excerpt, a diagram and a table', function()
  local text = table.concat({
    'Intro line',
    '',
    '- item one',
    '2. item two',
    '## A heading',
    '```lua',
    'local x = 1',
    '```',
    '{{chunk:get}}',
    '  {{diagram:shape}}',
    '| a | b |',
    '|---|:-:|',
    '| 1 | `x` |',
    'after',
  }, '\n')
  local r = made { introduction = { text = text, diagrams = { shape = SHAPE } } }
  local blocks = prose.parse(r.introduction, r)
  R.eq(kinds(blocks), { 'text', 'blank', 'text - ', 'text 2. ', 'text heading', 'code', 'excerpt', 'diagram', 'table', 'text' }, 'kinds')
  R.eq(blocks[6].lines, { 'local x = 1' }, 'a fence as written')
  R.eq({ blocks[7].excerpt.id, blocks[7].excerpt.chunk }, { 'get', review.chunk(r, 'get') }, "an excerpt, on the review's chunk")
  R.eq({ blocks[8].name, blocks[8].diagram.nodes[1].file }, { 'shape', 'store.lua' }, 'a diagram, checked')
  R.eq(
    blocks[9].cells,
    { { { { text = 'a' } }, { { text = 'b' } } }, { { { text = '1' } }, { { text = 'x', code = true } } } },
    'a table: its rows, the rule dropped'
  )
  local alone = prose.parse '{{chunk:get}}\n{{diagram:shape}}'
  R.eq({ alone[1].excerpt.chunk, alone[2].diagram }, { nil, nil }, 'with no review: an excerpt of nothing, a diagram unchecked')
  R.eq(kinds(prose.parse 'see {{chunk:get}} here\n| not a table |\nplain'), { 'text', 'text', 'text' }, 'not alone on a line; a row with no rule under it')
end)

R.test('prose.parse: a fence closes on as many backticks alone; three on a line with text open none; one left open is marked', function()
  local blocks = prose.parse '````md\n```lua\n{{chunk:get}}\n```\n````\nafter'
  R.eq({ kinds(blocks), blocks[1].lines }, { { 'code', 'text' }, { '```lua', '{{chunk:get}}', '```' } }, 'a fence in a fence, what it quotes as written')
  R.eq(kinds(prose.parse 'Run ```make``` first.\n\nnext'), { 'text', 'blank', 'text' }, 'backticks on a line with text')
  R.eq(kinds(prose.parse '```lua\nx = 1\n\nmore'), { 'code unclosed' }, 'a fence never closed runs to the end')
end)

R.test('prose.parse: `code` first, then links and bold in the rest; a bold run goes on to the end of its paragraph', function()
  local blocks = prose.parse 'See `#step:3` and #step:4, **bold\nstill** plain\n\nnot **open'
  R.eq(
    vim.tbl_map(function(sp)
      return { sp.text, sp.code or false, sp.bold or false, sp.link and link.write(sp.link) or false }
    end, blocks[1].spans),
    {
      { 'See ', false, false, false },
      { '#step:3', true, false, false },
      { ' and ', false, false, false },
      { '#step:4', false, false, '#step:4' },
      { ', ', false, false, false },
      { 'bold', false, true, false },
    },
    'a link in backticks is code'
  )
  R.eq(blocks[2].spans, { { text = 'still', bold = true }, { text = ' plain' } }, 'the run carries to the next line, and ends')
  R.eq(blocks[4].spans[2], { text = 'open', bold = true }, 'a new paragraph starts plain')
  blocks = prose.parse '**open\n## Heading\n- item\nIt is x ** 2, or **x**.'
  R.eq({ blocks[2].spans[1].bold, blocks[3].spans[1].bold }, { nil, nil }, 'a heading and a list item start anew')
  R.eq(blocks[4].spans, { { text = 'It is x ** 2, or ' }, { text = 'x', bold = true }, { text = '.' } }, '** with a space on both sides is no bold')
end)

R.test('prose.parse: a link to a contract reads as its name, with its review; one in another review as written', function()
  local contract = { id = 3, name = 'M.get(store, key)', kind = 'function', source = { change = 'added', after = 'get' }, prose = { text = 'p' } }
  local r = made { contracts = { contract } }
  local spans = prose.parse('Through #contract:3, not other#contract:3.', r)[1].spans
  R.eq(spans[2], { text = 'M.get(store, key)', link = { kind = 'contract', id = 3 }, contract = true }, 'by its name')
  R.eq(spans[4].text, 'other#contract:3', 'as written')
  R.eq(prose.first_sentence('Through #contract:3. Then more.', r), 'Through M.get(store, key).', 'in a sentence too')
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
  rows = prose.rows('```lua\nlocal x = 1\n```', 20)
  R.eq({ texts(rows), rows[1].chunks[1] }, { { 'local x = 1' }, { 'local', '@keyword.lua' } }, 'a fence coloured as the language it names')
  R.eq(prose.rows('```\nlocal x = 1\n```', 20)[1].chunks, { { 'local x = 1', 'ThreadCode' } }, 'one naming none, plain')
  R.eq(texts(prose.rows('漢字 漢字 漢字', 9)), { '漢字 漢字', '漢字' }, 'by the columns a character takes, not its bytes')
  R.eq(texts(prose.rows('漢字漢字漢字', 5)), { '漢字', '漢字', '漢字' }, 'a wide word cut between characters')
  rows = prose.rows('{{chunk:get}}\n\n{{diagram:shape}}', 20)
  R.eq({ #rows, rows[1].excerpt.id, rows[3].diagram.name }, { 3, 'get', 'shape' }, 'a row standing for each excerpt and diagram')
end)

R.test('prose.rows: a table, each column its widest cell, a rule under its header, cut to the width', function()
  local t = '| name | what |\n|---|---|\n| `get` | reads #step:1 |\n| set | writes |'
  R.eq(
    texts(prose.rows(t, 40)),
    { 'name │ what', '─────┼──────────────', 'get  │ reads #step:1', 'set  │ writes' },
    'laid out'
  )
  local rows = prose.rows(t, 40)
  R.eq(
    vim.tbl_map(function(sp)
      return sp.link and link.write(sp.link) or sp.name
    end, rows[3].spots),
    { 'get', '#step:1' },
    'its names and links go somewhere'
  )
  R.eq(
    texts(prose.rows(t, 14)),
    { 'name │ what', '─────┼────────', 'get  │ reads …', 'set  │ writes' },
    'the widest column cut first'
  )
end)

R.test('prose.rows: a spot on each link and name, at its byte columns in the row', function()
  local rows = prose.rows('— see #step:12, then `M.get` and other-review#note:4.', 80)
  R.ok(#rows == 1 and #'—' == 3, 'one row, after a character of three bytes')
  local line = texts(rows)[1]
  R.eq(
    vim.tbl_map(function(sp)
      return { line:sub(sp.first + 1, sp.last), sp.link and link.write(sp.link) or sp.name }
    end, rows[1].spots),
    { { '#step:12', '#step:12' }, { 'M.get', 'M.get' }, { 'other-review#note:4', 'other-review#note:4' } },
    'each spot over its text'
  )
end)

R.test('prose.draw: an excerpt as its lines from the file, numbered; one gone says so; links where they are drawn', function()
  H.reset()
  local root = H.repo(H.fixture)
  local r = made()
  local P = sheet.new { indent = 2 }
  local drawn = prose.draw(P, 'Read #step:1.\n\n{{chunk:get}}', 40, { review = r })
  R.eq(P.lines, {
    '  Read #step:1.',
    '',
    '  store.lua:3–6',
    '     3  function M.get(store, key)',
    '     4    local cache = {}',
    '     5    return store[key]',
    '     6  end',
  }, 'drawn')
  R.eq({ drawn[1].first, drawn[1].s, drawn[1].e, link.write(drawn[1].link) }, { 0, 7, 14, '#step:1' }, 'the link, in the sheet')
  R.eq({ drawn[2].first, drawn[2].last, drawn[2].excerpt.id }, { 2, 6, 'get' }, 'the excerpt, its rows')
  P = sheet.new()
  prose.draw(P, 'Read:\n\n{{chunk:get}}', 40, { review = r, most = 5 })
  R.eq(P.lines, { 'Read:', '', 'store.lua:3–6' }, 'with rows to spare, an excerpt in one')
  vim.fn.writefile({ 'return {}' }, root .. '/store.lua')
  P = sheet.new()
  prose.draw(P, '{{chunk:get}}\n{{chunk:nope}}\n{{diagram:none}}', 60, { review = r })
  R.eq(P.lines, {
    'store.lua:3 · its line is gone: function M.get(store, key)',
    '{{chunk:nope}} · no chunk has that id',
    '{{diagram:none}} · no diagram by that name',
  }, 'what is not there, said')
end)

R.test('prose.draw: an excerpt says where it is when that is not the code now', function()
  H.reset()
  local _, base = H.two_commits({ ['a.lua'] = { 'local function a_long_name(with, many, arguments) end', 'return 1' } }, { ['a.lua'] = { 'return 1' } })
  local function drawn(c, about, width)
    local r = made { diff = about, tours = {}, chunks = { vim.tbl_extend('force', { id = 'x', file = 'a.lua' }, c) } }
    local P = sheet.new()
    prose.draw(P, '{{chunk:x}}', width or 40, { review = r })
    return P.lines
  end
  local long = 'local function a_long_name(with, many, arguments) end'
  R.eq(
    drawn({ line = 1, from = long, rev = base }, nil, 30),
    { 'a.lua:1 · at ' .. base:sub(1, 7), '   1  local function a_long_n…' },
    'at a commit, cut at the width'
  )
  R.eq(drawn { line = 1, from = 'return 2', rev = 'now' }, { 'a.lua:1 · not as quoted', '   1  return 1' }, 'found by likeness')
  R.eq(
    drawn({ line = 1, from = long, rev = 'base' }, { base = base, head = 'HEAD' }, 30),
    { 'a.lua:1 · removed', '   1  local function a_long_n…' },
    'a removed line, at the base'
  )
  R.eq(
    drawn({ line = 2, from = 'return 1', rev = 'base' }, { base = base, head = 'HEAD' }),
    { 'a.lua:2 · as it was', '   2  return 1' },
    'a kept one, at the base'
  )
  R.eq(drawn({ line = 1, from = 'return 1', rev = 'head' }, { base = base, head = 'HEAD' }), { 'a.lua:1', '   1  return 1' }, 'at the head, as it is')
end)

R.test("prose.draw: a tour placed, its steps' titles, then with where each is, then with their code, as Tab turns it", function()
  H.reset()
  H.repo(H.fixture)
  local r = made {
    tours = {
      {
        id = 1,
        title = 'A read',
        listed = false,
        steps = {
          { id = 1, title = 'get reads', text = { text = 'From the store.' }, chunk = 'get' },
          { id = 2, title = 'Done', text = { text = 'Nothing more.' } },
        },
      },
    },
  }
  local x = 'How:\n\n{{tour:1}}'
  local P = sheet.new()
  local drawn = prose.draw(P, x, 50, { review = r })
  R.eq(P.lines, {
    'How:',
    '',
    '── tour ──────────────────────────────────────────',
    '◇ A read                                   2 steps',
    '  1  get reads',
    '  2  Done',
  }, "at first, its title and its steps'")
  R.eq({ drawn[1].first, drawn[1].last, drawn[1].inline }, { 2, 5, 'tour' }, 'the tour, its rows, under its label')
  fold.turn('tour', assert(drawn[1].fold))
  P = sheet.new()
  prose.draw(P, x, 50, { review = r })
  R.eq(vim.list_slice(P.lines, 4), {
    '◇ A read                                   2 steps',
    '  1  get reads',
    '     From the store.',
    '     store.lua:3–6',
    '',
    '  2  Done',
    '     Nothing more.',
  }, "then each step's text and where its code is")
  fold.turn('tour', assert(drawn[1].fold))
  P = sheet.new()
  prose.draw(P, x, 50, { review = r })
  R.eq(vim.list_slice(P.lines, 5, 11), {
    '  1  get reads',
    '     From the store.',
    '     store.lua:3–6',
    '        3  function M.get(store, key)',
    '        4    local cache = {}',
    '        5    return store[key]',
    '        6  end',
  }, 'then with its code')
  fold.turn('tour', assert(drawn[1].fold))
  P = sheet.new()
  prose.draw(P, x, 50, { review = r })
  R.eq(vim.list_slice(P.lines, 4), { '◇ A read                                   2 steps', '  1  get reads', '  2  Done' }, 'and round to its titles')
  P = sheet.new()
  prose.draw(P, x, 50, { review = r, most = 3 })
  R.eq(P.lines, { 'How:', '', '◇ A read                                   2 steps' }, 'cut short, one row')
end)

R.test(
  'prose.draw: a contract placed, under its label, itself as it is, then against as it was, then a row, as Tab turns it; one added, as it is, then a row',
  function()
    H.reset()
    H.repo(H.fixture)
    local r = made {
      contracts = {
        {
          id = 1,
          name = 'M.get(store, key)',
          kind = 'function',
          source = { change = 'changed', before = { lang = 'lua', text = 'function M.get(key)' }, after = 'get' },
          why = 'It takes the store.',
          prose = { text = 'Now with a store.' },
          dependents = { { chunk = 'get', impact = 'adapted', text = 'Passes it.' } },
        },
      },
    }
    local P = sheet.new()
    local drawn = prose.draw(P, '{{contract:1}}', 60, { review = r })
    R.eq(P.lines, {
      '── contract ────────────────────────────────────────────────',
      '~ M.get(store, key)  It takes the store.            function',
      '  as it is  store.lua:3–6',
      '  + function M.get(store, key)',
      '  +   local cache = {}',
      '  +   return store[key]',
      '  + end',
    }, 'at first, the contract as its page draws it: as it is, what changed marked')
    R.eq(
      { drawn[1].inline, drawn[2].first, drawn[2].s, drawn[2].e, link.write(drawn[2].link) },
      { 'contract', 1, 0, 60, '#contract:1' },
      'its head row, all of it a link to its page'
    )
    fold.turn('contract', assert(drawn[1].fold))
    P = sheet.new()
    prose.draw(P, '{{contract:1}}', 60, { review = r })
    R.eq(vim.list_slice(P.lines, 3), {
      '  was  written out · lua',
      '  - function M.get(key)',
      '  is  store.lua:3–6',
      '  + function M.get(store, key)',
      '  +   local cache = {}',
      '  +   return store[key]',
      '  + end',
    }, 'then against as it was, a diff of its sides')
    fold.turn('contract', assert(drawn[1].fold))
    P = sheet.new()
    prose.draw(P, '{{contract:1}}\n{{contract:2}}', 60, { review = r })
    R.eq(P.lines, {
      '── contract ────────────────────────────────────────────────',
      '~ M.get(store, key)  It takes the store.            function',
      '{{contract:2}} · no contract has that id',
    }, 'then one row; one the review has not, said')
    r.contracts[1].source = { change = 'added', after = 'get' }
    P = sheet.new()
    drawn = prose.draw(P, '{{contract:1}}', 60, { review = r })
    R.eq(drawn[1].inline, 'side', 'one added has nothing to be set against')
    R.eq(fold.turn('side', assert(drawn[1].fold)), 'source', 'from a row, as it is')
    R.eq(fold.turn('side', assert(drawn[1].fold)), 'row', 'then a row again')
  end
)

R.test('prose.first_line and first_sentence: of the first line with text, its markup dropped', function()
  R.eq(prose.first_line '\n  first `line`, **bold**  \nsecond', 'first line, bold')
  R.eq(prose.first_line(nil), '')
  R.eq(prose.first_line { text = '```lua\nx\n```\n{{chunk:a}}\n- Only line' }, 'Only line', 'prose, past a fence and an excerpt')
  R.eq(prose.first_sentence 'It reads `the store`. Then more.', 'It reads the store.')
  R.eq(prose.first_sentence 'No stop here', 'No stop here')
end)

R.test('link.find: #step:7, #note:12, #contract:3, other#note:12; not a colour, a page, another kind or inside a word', function()
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
  R.eq(
    found 'notes #note:3-#note:5',
    { { '#note:3', { kind = 'note', id = 3 } }, { '#note:5', { kind = 'note', id = 5 } } },
    'what is no review id is not part of one'
  )
  R.eq(
    found '#tour:1 #step:x #note:1.2 #note:1:2 a_b#step:1 #step:1a #Step:1 #12 #12.3 #4acbe1 ##step:3 https://example.com/notes#step:12',
    {},
    'none of these'
  )
  R.eq(vim.tbl_map(link.write, { { kind = 'step', id = 7 }, { review = 'other', kind = 'note', id = 2 } }), { '#step:7', 'other#note:2' }, 'written back')
end)

R.test('link.follow: to a step, a note, a contract, one in another review; why, when it goes nowhere', function()
  local contract = { id = 2, name = 'M.get', kind = 'function', source = { change = 'added', after = 'get' }, prose = { text = 'p' } }
  local n = { id = 12, kind = 'comment', title = 'n', messages = { { from = 'agent', prose = { text = 'n' } } } }
  local r = made { contracts = { contract }, notes = { n } }
  local other = made({ notes = { vim.deepcopy(n) } }, 'other')
  local function get(id)
    if id == 'broken' then
      return nil, 'the review: no `title`'
    end
    return id == 'other' and other or nil
  end
  local function follow(s)
    local f, why = link.follow(link.find(s)[1].link, r, get)
    if not f then
      return why
    end
    return { f.review.id, f.conversation.name }
  end
  R.eq({ follow '#step:1', follow '#note:12', follow '#contract:2', follow 'other#note:12', follow 'made#note:12' }, {
    { 'made', 'step:1' },
    { 'made', 'note:12' },
    { 'made', 'contract:2' },
    { 'other', 'note:12' },
    { 'made', 'note:12' },
  }, 'each, its own review by its id too')
  R.eq(follow '#step:9', '`#step:9` goes to no step; if it is no link, put it in backticks', 'no step')
  R.eq(follow 'other#step:9', '`other#step:9` goes to no step of other; if it is no link, put it in backticks', 'none there')
  R.eq(follow 'gone#note:1', '`gone#note:1` goes to no review gone', 'no review')
  R.eq(follow 'broken#note:1', '`broken#note:1` goes to review broken, which cannot be read: the review: no `title`', 'one that cannot be read')
end)

R.test('check.review: the links and fences in all the agent wrote, tables too; not yours', function()
  local n = {
    id = 1,
    kind = 'question',
    status = 'open',
    title = 'q',
    messages = { { from = 'agent', prose = { text = 'See #step:1 and #contract:1.' } }, { from = 'you', prose = { text = 'And #note:8? ```' } } },
  }
  local r = made {
    introduction = { text = 'Starts at #step:9 and #tour:1, not `#step:5`.' },
    tours = {
      {
        id = 1,
        title = 'T',
        colour = 'teal',
        introduction = { text = '| a | b |\n|---|---|\n| #note:7 | x |' },
        steps = {
          {
            id = 1,
            title = 's',
            chunk = 'get',
            text = { text = 'More.\n```lua\nnever closed' },
            messages = { { from = 'agent', prose = { text = 'other#note:1, broken#note:1 and gone#step:1' } } },
          },
        },
      },
    },
    notes = { n },
  }
  local other = made({ notes = { vim.deepcopy(n) } }, 'other')
  local p = check.review(r, function(id)
    if id == 'broken' then
      return nil, 'the review: no `title`'
    end
    return id == 'other' and other or nil
  end)
  R.eq(p.errors, {}, 'no errors: a link to nothing may be text about one')
  R.eq(p.warnings, {
    'the review, introduction: `#step:9` goes to no step; if it is no link, put it in backticks',
    'the review, introduction: `#tour:` is no link: a link names a step, a note or a contract, `#step:7`',
    'tour 1, introduction: `#note:7` goes to no note; if it is no link, put it in backticks',
    'step 1, text: a ``` fence is never closed, so all after it shows as code: end it with ``` on a line of its own',
    'step 1, message 1: `broken#note:1` goes to review broken, which cannot be read: the review: no `title`',
    'step 1, message 1: `gone#step:1` goes to no review gone',
    'note 1, message 1: `#contract:1` goes to no contract; if it is no link, put it in backticks',
  }, 'each, where it is')
end)

R.test('diagram.draw: laid out into the sheet, and the box under a row and a byte column found', function()
  local d = assert(require('thread.model.diagram').validate(SHAPE, function()
    return 'store.lua'
  end))
  local P = sheet.new()
  P.add 'before'
  local drawn = diagram.draw(P, d, 40, 4)
  R.eq(drawn.first, 1, 'after what was there')
  local row = assert(vim.iter(ipairs(P.lines)):find(function(i, l)
    return i > drawn.first + 1 and l:find 'get' ~= nil
  end)) - 1
  -- Its right edge: past two characters of three bytes each.
  local col = assert(P.lines[row + 1]:find '│%s*$') - 1
  R.ok(col > vim.fn.strdisplaywidth(P.lines[row + 1]:sub(1, col)), 'past characters of more than a byte')
  local node = diagram.at(drawn, row, col)
  R.eq(node and { node.label, node.chunk }, { 'get', 'get' }, 'found at its row and column, with its chunk')
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

R.test(
  'highlight.of: numbered in the order the text first names them; one not in the chunk not counted, one named twice once, a call found as its name',
  function()
    local r = made()
    local s = { id = 1, title = 'x', text = { text = '`load(read)` calls `missing`, then `store`; `load` again, `x`, and `store` again.' } }
    local got = vim.tbl_map(function(h)
      return { h.n, h.text, h.rows, h.written }
    end, highlight.of(r, s, { 'local v = load(f)', 'store.go()', 'return store, loader' }))
    R.eq(got, {
      { 1, 'load', { 1 }, { 'load(read)', 'load' } },
      { 2, 'store', { 2, 3 }, { 'store' } },
    }, 'load first, found by its name; store on two lines, named twice; not missing, nor loader, nor one letter')
    R.eq(highlight.numbers(highlight.of(r, s, { 'load()', 'store' })), { ['load(read)'] = 1, load = 1, store = 2 }, 'by what the text wrote')
  end
)

R.test("prose.draw: a step's highlights drawn with no number; the current one and its sentence lit", function()
  local P = sheet.new()
  prose.draw(P, 'First `load` here. Then `store` and more.', 80, { highlights = { numbers = { load = 1, store = 2 }, current = 2 } })
  R.eq(P.lines, { 'First load here. Then store and more.' }, 'no digit after a name')
  local groups = {} ---@type string[]
  for _, h in ipairs(P.hls) do
    groups[#groups + 1] = P.lines[1]:sub(h[2] + 1, h[3]) .. '=' .. h[4]
  end
  R.eq(groups, {
    'First =ThreadText',
    'load=ThreadCode',
    ' here. =ThreadText',
    'Then =ThreadTextSentence',
    'store=ThreadHighlightHere',
    ' and more.=ThreadTextSentence',
  }, 'the second sentence lit, its name reversed')
end)
