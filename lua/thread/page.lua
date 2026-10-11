--- A stop of a tour, opened: a stage, a page, the overview, or a step
--- opened with ⏎ on its card. A float in the middle of the editor with the
--- step's code, what the stop says, its diagram, the conversation in it if
--- you have replied. The overview lists the whole tour under it, `▸` where
--- you are; on any other stop `M` shows that list or hides it.
---
--- `L`/`H` walk on (a step takes you back to the code), `q` ends the walk
--- (or closes the page when you are not walking), `Esc` closes the page,
--- `r` replies in the stop, and `⏎` on a stop in the outline goes there, on
--- the code to its line, on a box of the diagram to its code, and on the
--- overview's words the tour from its first stop.

local anchor = require 'thread.anchor'
local config = require 'thread.config'
local render = require 'thread.render'
local store = require 'thread.store'
local tour = require 'thread.tour'

local M = {}

local ns = vim.api.nvim_create_namespace 'thread.page'
local draw_code
local width_of = vim.fn.strdisplaywidth
local PAD = 2

---@class thread.PageState
---@field win integer
---@field buf integer
---@field owner integer
---@field n integer
---@field rows table<integer, integer>  page line -> stop n, in the outline
---@field diagram { first: integer, drawn: table }|nil
---@field here integer|nil  the outline row of the stop you are on
---@type thread.PageState|nil
local S
-- The tour's outline under every page, not only the overview: `M`.
local outline = false

function M.is_open()
  return S ~= nil and vim.api.nvim_win_is_valid(S.win)
end

function M.close()
  if M.is_open() then
    vim.api.nvim_win_close(S.win, true)
  end
  S = nil
end

local function fit(s, w)
  if width_of(s) <= w then
    return s
  end
  local out = vim.fn.strcharpart(s, 0, w - 1)
  while width_of(out) > w - 1 do
    out = vim.fn.strcharpart(out, 0, vim.fn.strchars(out) - 1)
  end
  return out .. '…'
end

--- The page being built: lines and their highlights.
local function builder()
  local P = { lines = {}, hls = {} }
  function P.add(text)
    P.lines[#P.lines + 1] = text
    return #P.lines - 1
  end
  function P.hl(row, s, e, group)
    P.hls[#P.hls + 1] = { row, s, e, group }
  end
  --- Chunks of { text, hl } as one line.
  function P.chunks(chunks)
    local text, col, spans = string.rep(' ', PAD), PAD, {}
    for _, c in ipairs(chunks) do
      spans[#spans + 1] = { col, col + #c[1], c[2] }
      text = text .. c[1]
      col = col + #c[1]
    end
    local row = P.add(text)
    for _, sp in ipairs(spans) do
      if sp[3] then
        P.hl(row, sp[1], sp[2], sp[3])
      end
    end
    return row
  end
  return P
end

--- Prose, wrapped, with `code` and **bold** picked out, and excerpts drawn
--- as the code they point at.
local function prose(P, text, width)
  for _, l in ipairs(render.wrap(text or '', width)) do
    if l.excerpt then
      local a = l.excerpt
      local lines = anchor.lines_of { file = a.file }
      local loc = lines and anchor.locate({ file = a.file, text = a.text or '', line = a.line }, lines)
      if not loc then
        P.chunks { { '▤ ' .. a.file .. ' · its line is gone', 'ThreadBroken' } }
      else
        local count = math.max(1, math.min(15, tonumber(a.lines) or 6))
        local lo, hi = loc.line, math.min(#lines, loc.line + count - 1)
        P.chunks { { a.file .. ':' .. lo, 'Directory' } }
        local slice = vim.list_slice(lines, lo, hi)
        local spans = require('thread.home').syntax(slice, a.file)
        for i, code in ipairs(slice) do
          local prefix = string.rep(' ', PAD) .. string.format('%4d  ', lo + i - 1)
          local row = P.add(prefix .. code:gsub('\t', '    '))
          P.hl(row, PAD, PAD + 4, 'LineNr')
          if not code:find '\t' then
            for _, sp in ipairs(spans[i] or {}) do
              P.hl(row, #prefix + sp[1], #prefix + sp[2], sp[3])
            end
          end
        end
      end
    else
      P.chunks(render.segments(l))
    end
  end
end

--- A step's code: its lines and a few after, its own line lit, each note's
--- number on its line and the notes listed under it.
function draw_code(P, e)
  local lines = anchor.lines_of(e)
  local loc = lines and anchor.locate(e, lines)
  if not loc then
    P.chunks { { 'The line this step was on moved or went: ', 'ThreadBroken' }, { e.file .. (e.line and (':' .. e.line) or ''), 'Directory' } }
    P.chunks { { 'it was ', 'ThreadMeta' }, { vim.trim(e.text or ''), 'ThreadCode' } }
    return
  end
  local lo = loc.line
  local hi = math.min(#lines, lo + math.max(6, (e.lines or 1) + 3))
  local marks = {}
  for k, n in ipairs(e.notes or {}) do
    local nl = anchor.locate(vim.tbl_extend('keep', n, { file = e.file }), lines)
    if nl and (n.file == nil or n.file == e.file) then
      marks[nl.line] = (marks[nl.line] or '') .. (render.NUMS[k] or ('(' .. k .. ')'))
      hi = math.min(#lines, math.max(hi, nl.line + 1))
    end
  end
  hi = math.min(hi, lo + 14)
  P.chunks { { e.file .. ':' .. lo, 'Directory' } }
  local slice = vim.list_slice(lines, lo, hi)
  local spans = require('thread.home').syntax(slice, e.file)
  S.code = { first = #P.lines + 1, line = lo }
  for i, code in ipairs(slice) do
    local num = lo + i - 1
    local prefix = string.rep(' ', PAD) .. string.format('%4d  ', num)
    local text = prefix .. code:gsub('\t', '    ')
    local row = P.add(text)
    P.hl(row, PAD, PAD + 4, num == lo and 'ThreadCrumbHere' or 'LineNr')
    if num < lo + (e.lines or 1) then
      P.hl(row, #prefix, -1, 'ThreadNoteLine')
    end
    if not code:find '\t' then
      for _, sp in ipairs(spans[i] or {}) do
        P.hl(row, #prefix + sp[1], #prefix + sp[2], sp[3])
      end
    end
    if marks[num] then
      P.lines[row + 1] = P.lines[row + 1] .. '  ' .. marks[num]
      P.hl(row, #text + 2, -1, 'ThreadNoteNum')
    end
  end
  S.code.last = #P.lines
  local any = false
  for k, n in ipairs(e.notes or {}) do
    if type(n.note) == 'string' and n.note ~= '' then
      if not any then
        P.add ''
        any = true
      end
      P.chunks { { (render.NUMS[k] or ('(' .. k .. ')')) .. ' ', 'ThreadNoteNum' }, { n.note, 'ThreadNote' } }
    end
  end
end

local function draw_diagram(P, raw, width)
  local diagram = require 'thread.diagram'
  local d, err = diagram.validate(raw)
  if not d then
    P.chunks { { 'diagram: ' .. (err or '?'), 'ThreadBroken' } }
    return
  end
  local drawn = diagram.render(d, { max_width = width })
  S.diagram = { first = #P.lines, drawn = drawn }
  for _, chunks in ipairs(drawn.rows) do
    local row = P.chunks(chunks)
    P.lines[row + 1] = P.lines[row + 1]:gsub('%s+$', '')
  end
  if drawn.degraded then
    P.chunks { { '(' .. drawn.degraded .. ')', 'ThreadMeta' } }
  end
end

local function rule(P, label, width)
  P.add ''
  local row = P.chunks { { '── ' .. label .. ' ', 'ThreadCrumb' }, { string.rep('─', math.max(2, width - width_of(label) - 4)), 'ThreadTabRule' } }
  return row
end

--- The whole tour, one stop a line: stages, the steps under them indented.
local function draw_outline(P, batch, owner, list, width)
  rule(P, 'the tour · ' .. tour.describe(list), width)
  local items = tour.outline(list)
  local files = {}
  local function row_for(n, chunks)
    local row = P.chunks(chunks)
    S.rows[row + 1] = n
    if n == S.n then
      S.here = row + 1
    end
    return row
  end
  local mark = S.n == 0 and '▸ ' or '  '
  row_for(0, { { mark, 'ThreadFocus' }, { 'overview', S.n == 0 and 'ThreadCrumbHere' or 'ThreadMeta' } })
  for _, it in ipairs(items) do
    local here = it.n == S.n
    local indent = it.kind == 'stage' and '' or (it.stage > 0 and '    ' or '')
    local num = it.kind == 'stage' and (it.stage .. ' ') or it.kind == 'step' and (it.step .. ' ') or '· '
    local been = store.visited(batch, owner.id, it.n)
    local talk = tour.thread_at(batch, owner.id, it.n)
    local where = ''
    if it.kind == 'step' then
      if files[it.e.file] == nil then
        files[it.e.file] = anchor.lines_of(it.e) or false
      end
      local loc = files[it.e.file] and anchor.locate(it.e, files[it.e.file])
      where = vim.fs.basename(it.e.file) .. ':' .. (loc and loc.line or '–')
    end
    local name = fit(tour.title(it.e), math.max(10, width - #indent - 16 - width_of(where)))
    local chunks = {
      { here and '▸ ' or '  ', 'ThreadFocus' },
      { indent },
      { num, it.kind == 'stage' and 'ThreadTitle' or 'LineNr' },
      { name, here and 'ThreadCrumbHere' or (it.kind == 'stage' and 'ThreadTitle' or (been and 'ThreadMeta' or nil)) },
    }
    if talk then
      local g, ghl = render.glyph(store.status(talk), store.unseen(batch, talk), false)
      chunks[#chunks + 1] = { ' ' .. g, ghl }
    elseif been and it.kind ~= 'stage' then
      chunks[#chunks + 1] = { ' ✓', 'ThreadSignDone' }
    end
    local used = 0
    for _, c in ipairs(chunks) do
      used = used + width_of(c[1])
    end
    chunks[#chunks + 1] = { string.rep(' ', math.max(2, width - used - width_of(where))) .. where, 'LineNr' }
    row_for(it.n, chunks)
  end
end

--- The conversation in this stop, if you have replied in it.
local function draw_talk(P, batch, c, width)
  local function when(i)
    return render.ago(store.when(batch, c, i))
  end
  local g, ghl = render.glyph(store.status(c), store.unseen(batch, c), false)
  rule(P, 'your thread here · ' .. g .. ' ' .. store.status(c), width)
  for i, m in ipairs(c.messages) do
    if i > 1 then
      P.add ''
    end
    if m.from ~= 'you' then
      local label = render.label(m)
      for j, l in ipairs(render.wrap(m.text or '', render.side(width, 3))) do
        local chunks = { { j == 1 and (label .. string.rep(' ', 3 - width_of(label))) or string.rep(' ', 3), 'ThreadAgent' } }
        vim.list_extend(chunks, render.segments(l))
        local time = j == 1 and when(i)
        if time then
          local used = 0
          for _, ch in ipairs(chunks) do
            used = used + width_of(ch[1])
          end
          chunks[#chunks + 1] = { string.rep(' ', math.max(2, width - used - width_of(time))) .. time, 'ThreadMeta' }
        end
        P.chunks(chunks)
      end
    else
      -- Yours on the right, as in a chat.
      for _, r in ipairs(render.chat(m.text, width, 3, when(i))) do
        P.chunks(r)
      end
    end
  end
end

local function keys_footer()
  local w = config.options.walk
  local walking = require('thread.walk').state() ~= nil
  local list = {
    { 'h/l', 'threads' },
    { w.next, walking and 'next' or 'walk on' },
    { w.prev, walking and 'prev' or 'walk back' },
    { '⏎', S.n == 0 and 'walk from the start' or 'walk from here' },
    { 'r', 'reply' },
    S.n > 0 and { w.map, outline and 'hide the tour' or 'the tour' } or {},
    { w.quit, walking and 'end the walk' or 'close' },
    walking and { 'Esc', 'close' } or {},
  }
  local out = { { ' ' } }
  for _, k in ipairs(list) do
    if k[1] then
      out[#out + 1] = { render.show_key(k[1]) or k[1], 'ThreadKey' }
      out[#out + 1] = { ' ' .. k[2] .. '  ', 'ThreadKeyLabel' }
    end
  end
  return out
end

local function draw()
  local batch = store.active()
  local owner = batch and store.find(batch, S.owner)
  local list = owner and tour.of(owner)
  if not list then
    return M.close()
  end
  local width = vim.api.nvim_win_get_width(S.win) - PAD * 2
  local P = builder()
  S.rows, S.diagram, S.here, S.code = {}, nil, nil, nil
  local e = list[S.n]
  local verdict, diagram, body
  if e then
    body = tour.body(e)
    verdict = e.verdict and render.verdict_of { messages = { e } }
    diagram = e.diagram
  else
    -- The overview: the message that leads to the tour.
    local _, index = tour.of(owner)
    local m = owner.messages[index]
    body, diagram = m.text, m.diagram
    verdict = m.verdict and render.verdict_of { messages = { m } }
  end
  P.add ''
  local head = { { e and tour.title(e) or store.title(owner), 'ThreadTitle' } }
  if verdict then
    head[#head + 1] = { '  ' }
    head[#head + 1] = { ' ' .. verdict.text .. ' ', verdict.hl }
  end
  P.chunks(head)
  P.add ''
  if e and tour.kind(e) == 'step' then
    draw_code(P, e)
    P.add ''
  end
  prose(P, body, width)
  if type(diagram) == 'table' then
    P.add ''
    draw_diagram(P, diagram, width)
  end
  local talk = S.n > 0 and tour.thread_at(batch, S.owner, S.n)
  if talk then
    draw_talk(P, batch, talk, width)
    store.mark_seen(batch, talk)
  end
  if S.n == 0 or outline then
    draw_outline(P, batch, owner, list, width)
  end
  P.add ''

  vim.bo[S.buf].modifiable = true
  vim.api.nvim_buf_set_lines(S.buf, 0, -1, false, P.lines)
  vim.bo[S.buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(S.buf, ns, 0, -1)
  for _, h in ipairs(P.hls) do
    local len = #(P.lines[h[1] + 1] or '')
    pcall(vim.api.nvim_buf_set_extmark, S.buf, ns, h[1], math.min(h[2], len), { end_col = (h[3] < 0 or h[3] > len) and len or h[3], hl_group = h[4] })
  end

  local title = { { ' ▶ ', 'ThreadLeads' }, { fit(store.title(owner), 50), 'ThreadTitle' } }
  if S.n == 0 then
    title[#title + 1] = { ' · overview ', 'ThreadCrumb' }
  else
    -- Where it is: the count, and beside it how far through.
    title[#title + 1] = { ' · ' .. tour.position(list, S.n) .. ' ', 'ThreadCrumb' }
    vim.list_extend(title, render.progress(list, S.n))
    title[#title + 1] = { ' ', 'ThreadCrumb' }
  end
  local cols = math.min(vim.o.columns - 8, 100)
  local max = vim.o.lines - vim.o.cmdheight - 6
  local height = math.max(3, math.min(max, #P.lines))
  vim.api.nvim_win_set_config(S.win, {
    relative = 'editor',
    row = math.floor((vim.o.lines - vim.o.cmdheight - height) / 2) - 1,
    col = math.floor((vim.o.columns - cols) / 2),
    width = cols,
    height = height,
    title = title,
    footer = keys_footer(),
    footer_pos = 'right',
  })
end

--- ⏎: a stop in the outline goes there; a box of the diagram to its code.
local function enter()
  local row = vim.api.nvim_win_get_cursor(S.win)[1]
  local n = S.rows[row]
  if n then
    return M.walk_to(n)
  end
  if S.code and row >= S.code.first and row <= S.code.last then
    return M.walk_to(S.n)
  end
  local function off_boxes()
    -- The overview, off the outline and the diagram's boxes with code: the
    -- tour from its first stop.
    if S.n == 0 then
      return M.walk_to(1)
    end
  end
  local d = S.diagram
  if d then
    local col = vim.fn.virtcol '.' - 1 - PAD
    local node = require('thread.diagram').hit(d.drawn, row - 1 - d.first, col)
    if node and node.file then
      local walk = require 'thread.walk'
      M.close()
      local state = walk.state()
      if state then
        -- Out to the code, still walking: L picks up where you were.
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
          if vim.api.nvim_win_get_config(win).relative == '' then
            vim.api.nvim_set_current_win(win)
            break
          end
        end
      end
      require('thread.actions').jump { id = 0, file = node.file, text = node.text or '', line = node.line }
      return
    end
  end
  off_boxes()
end

local function reply()
  local owner, n = S.owner, S.n
  if n == 0 then
    local batch = store.active()
    local c = batch and store.find(batch, owner)
    if c then
      M.close()
      return require('thread.home').focus { comment = c, reply = true }
    end
    return
  end
  require('thread.actions').reply_stop(owner, n)
end

--- Walk to stop `n` of this page's tour: on with the walk going, or a walk
--- started there.
function M.walk_to(n)
  local walk = require 'thread.walk'
  local w = walk.state()
  local batch = store.active()
  local owner = batch and store.find(batch, S.owner)
  local list = owner and tour.of(owner)
  if not list or n > #list or n < 0 or (n == 0 and store.anchored(owner)) then
    return vim.notify(n > 0 and 'thread: the end of the tour' or 'thread: the start of the tour')
  end
  if w and w.owner == S.owner then
    return walk.go(n)
  end
  walk.start(S.owner, n)
end

--- Open the page for stop `n` of `owner`'s tour (0: its overview).
---@param owner integer
---@param n integer
function M.open(owner, n)
  if not M.is_open() then
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].filetype = 'thread-page'
    local win = vim.api.nvim_open_win(buf, true, {
      relative = 'editor',
      row = 1,
      col = 1,
      width = math.min(vim.o.columns - 8, 100),
      height = 3,
      border = 'rounded',
      style = 'minimal',
      title = ' ',
      footer = ' ',
      zindex = 50,
    })
    vim.wo[win].wrap = false
    vim.wo[win].cursorline = true
    vim.wo[win].winhighlight = 'NormalFloat:Normal,FloatBorder:ThreadBorderInfo,CursorLine:ThreadZone'
    S = { win = win, buf = buf, owner = owner, n = n, rows = {} }
    local walk = require 'thread.walk'
    local function map(lhs, fn)
      if lhs then
        vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true })
      end
    end
    local w = config.options.walk
    map(w.next, function()
      M.walk_to(S.n + 1)
    end)
    map(w.prev, function()
      M.walk_to(S.n - 1)
    end)
    map(w.quit, function()
      if walk.state() then
        walk.stop()
      else
        M.close()
      end
    end)
    map('<Esc>', M.close)
    -- Out of the tour to the threads either side, as in the focused float:
    -- from this stop's conversation if it has one, else the tour's thread.
    local function side(dir)
      local batch = store.active()
      local here = batch and (tour.thread_at(batch, S.owner, S.n) or store.find(batch, S.owner))
      local c = here and require('thread.home').neighbour(here.id, dir)
      if c then
        M.close()
        require('thread.home').focus { comment = c }
      end
    end
    map('h', function()
      side(-1)
    end)
    map('l', function()
      side(1)
    end)
    map(w.map, function()
      outline = not outline
      M.refresh()
    end)
    map('<CR>', enter)
    map('r', reply)
    map(config.options.mappings.reply, reply)
    vim.api.nvim_create_autocmd('WinLeave', {
      buffer = buf,
      callback = function()
        -- Leaving for anything but the reply float closes the page.
        vim.schedule(function()
          local cur = vim.api.nvim_get_current_win()
          if M.is_open() and cur ~= S.win and vim.bo[vim.api.nvim_win_get_buf(cur)].filetype ~= 'markdown' then
            M.close()
          end
        end)
      end,
    })
  else
    vim.api.nvim_set_current_win(S.win)
  end
  S.owner, S.n = owner, n
  draw()
  vim.api.nvim_win_set_cursor(S.win, { 1, 0 })
end

--- The batch changed: draw it again.
function M.refresh()
  if M.is_open() then
    local cur = vim.api.nvim_win_get_cursor(S.win)
    draw()
    pcall(vim.api.nvim_win_set_cursor, S.win, cur)
  end
end

return M
