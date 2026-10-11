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
local blocks = require 'thread.blocks'
local code = require 'thread.code'
local config = require 'thread.config'
local float = require 'thread.float'
local look = require 'thread.look'
local sheet = require 'thread.sheet'
local store = require 'thread.store'
local text = require 'thread.text'
local tour = require 'thread.tour'

local M = {}

local ns = vim.api.nvim_create_namespace 'thread.page'
local PAD = 2

---@class thread.PageState
---@field win integer
---@field buf integer
---@field owner integer
---@field n integer
---@field items thread.Item[]  the outline's stops (`n`), the step's code (`code`), the diagram (`drawn`)
---@type thread.PageState|nil
local S
-- The tour's outline under every page, not only the overview: `M`.
local outline = false

local function width()
  return math.min(vim.o.columns - 8, 100)
end

function M.is_open()
  return S ~= nil and vim.api.nvim_win_is_valid(S.win)
end

function M.close()
  if M.is_open() then
    float.close(S.win)
  end
  S = nil
end

--- A step's code: its lines and a few after, its own line lit, each note's
--- number on its line and the notes listed under it.
local function draw_code(P, e)
  local lines = anchor.lines_of(e)
  local loc = lines and anchor.locate(e, lines)
  if not loc then
    P.chunks { { 'The line this step was on moved or went: ', 'ThreadBroken' }, { e.file .. (e.line and (':' .. e.line) or ''), 'Directory' } }
    P.chunks { { 'it was ', 'ThreadMeta' }, { vim.trim(e.text or ''), 'ThreadCode' } }
    return
  end
  local lo = loc.line
  local hi = math.min(#lines, lo + math.max(6, (e.lines or 1) + 3))
  local nums = {}
  for k, n in ipairs(e.notes or {}) do
    local at = anchor.locate(vim.tbl_extend('keep', n, { file = e.file }), lines)
    if at and (n.file == nil or n.file == e.file) then
      nums[at.line] = (nums[at.line] or '') .. look.num(k)
      hi = math.min(#lines, math.max(hi, at.line + 1))
    end
  end
  hi = math.min(hi, lo + 14)
  P.chunks { { e.file .. ':' .. lo, 'Directory' } }
  local slice = vim.list_slice(lines, lo, hi)
  local spans = code.syntax(slice, e.file)
  P.item { code = true }
  for i, l in ipairs(slice) do
    local num = lo + i - 1
    local row = blocks.code_line(P, PAD, {
      num = num,
      line = l,
      spans = spans[i],
      num_hl = num == lo and 'ThreadCrumbHere' or nil,
      wash = num < lo + (e.lines or 1) and 'ThreadNoteLine' or nil,
    })
    if nums[num] then
      P.lines[row + 1] = P.lines[row + 1] .. '  ' .. nums[num]
      P.hl(row, #P.lines[row + 1] - #nums[num], -1, 'ThreadNoteNum')
    end
  end
  P.done()
  local any = false
  for k, n in ipairs(e.notes or {}) do
    if type(n.note) == 'string' and n.note ~= '' then
      if not any then
        P.add ''
        any = true
      end
      P.chunks { { look.num(k) .. ' ', 'ThreadNoteNum' }, { n.note, 'ThreadNote' } }
    end
  end
end

--- The whole tour, one stop a line: stages, the steps under them indented.
local function draw_outline(P, batch, owner, list, room)
  blocks.rule(P, 'the tour · ' .. tour.describe(list), room)
  local files = {}
  P.item { n = 0 }
  P.chunks { { S.n == 0 and '▸ ' or '  ', 'ThreadFocus' }, { 'overview', S.n == 0 and 'ThreadCrumbHere' or 'ThreadMeta' } }
  for _, it in ipairs(tour.outline(list)) do
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
    local chunks = {
      { here and '▸ ' or '  ', 'ThreadFocus' },
      { indent },
      { num, it.kind == 'stage' and 'ThreadTitle' or 'LineNr' },
      { text.fit(tour.title(it.e), math.max(10, room - #indent - 16 - text.width(where))), here and 'ThreadCrumbHere' or (it.kind == 'stage' and 'ThreadTitle' or (been and 'ThreadMeta' or nil)) },
    }
    if talk then
      local g, ghl = look.glyph(store.status(talk), store.unseen(batch, talk), false)
      chunks[#chunks + 1] = { ' ' .. g, ghl }
    elseif been and it.kind ~= 'stage' then
      chunks[#chunks + 1] = { ' ✓', 'ThreadSignDone' }
    end
    P.item { n = it.n }
    P.spread(chunks, { where, 'LineNr' }, room)
  end
  P.done()
end

--- The keys, the ones you least need left out when they do not all fit.
local function footer()
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
  local function keys()
    local out = {}
    for _, k in ipairs(list) do
      if k[1] then
        out[#out + 1] = { look.show_key(k[1]), k[2] }
      end
    end
    return look.footer(out)
  end
  for _, drop in ipairs { 'Esc', 'h/l', w.map, '⏎' } do
    if text.width(keys()) <= width() - 6 then
      break
    end
    for _, k in ipairs(list) do
      if k[1] == drop then
        k[1] = nil
      end
    end
  end
  return keys()
end

local function draw()
  local batch = store.active()
  local owner = batch and store.find(batch, S.owner)
  local list = owner and tour.of(owner)
  if not list then
    return M.close()
  end
  local room = vim.api.nvim_win_get_width(S.win) - PAD * 2
  local P = sheet.new { indent = PAD }
  local e = list[S.n]
  -- The overview is the message that leads to the tour.
  local said = e or owner.messages[select(2, tour.of(owner))]
  local verdict = said.verdict and look.verdict_of { messages = { said } }
  P.add ''
  local head = { { e and tour.title(e) or store.title(owner), 'ThreadTitle' } }
  if verdict then
    vim.list_extend(head, { { '  ' }, { ' ' .. verdict.text .. ' ', verdict.hl } })
  end
  P.chunks(head)
  P.add ''
  if e and (tour.kind(e) == 'step' or tour.kind(e) == 'aside') then
    draw_code(P, e)
    P.add ''
  end
  blocks.prose(P, e and tour.body(e) or said.text, room)
  if type(said.diagram) == 'table' then
    P.add ''
    local first, last, drawn = blocks.diagram(P, said.diagram, room)
    if drawn then
      table.insert(P.items, { first = first, last = last, drawn = drawn })
    end
  end
  local talk = S.n > 0 and tour.thread_at(batch, S.owner, S.n)
  if talk then
    blocks.talk(P, batch, talk, room)
  end
  if S.n == 0 or outline then
    draw_outline(P, batch, owner, list, room)
  end
  P.add ''
  P.apply(S.buf, ns)
  S.items = P.items

  local title = { { ' ▶ ', 'ThreadLeads' }, { text.fit(store.title(owner), 50), 'ThreadTitle' } }
  if S.n == 0 then
    title[#title + 1] = { ' · overview ', 'ThreadCrumb' }
  else
    -- Where it is: the count, and beside it how far through.
    title[#title + 1] = { ' · ' .. tour.position(list, S.n) .. ' ', 'ThreadCrumb' }
    vim.list_extend(title, look.progress(list, S.n))
    title[#title + 1] = { ' ', 'ThreadCrumb' }
  end
  local cfg = float.centred(width(), math.max(3, math.min(float.max_height(4), #P.lines)))
  cfg.title, cfg.footer, cfg.footer_pos = title, footer(), 'right'
  vim.api.nvim_win_set_config(S.win, cfg)
end

--- The item under the cursor.
local function under(row)
  for _, it in ipairs(S.items) do
    if row - 1 >= it.first and row - 1 <= it.last then
      return it
    end
  end
end

--- ⏎: a link, a stop in the outline, the step's code, a box of the
--- diagram; on the overview anywhere else, the tour from its start.
local function enter()
  local row = vim.api.nvim_win_get_cursor(S.win)[1]
  local id, at = text.link_at(vim.api.nvim_get_current_line(), vim.api.nvim_win_get_cursor(S.win)[2])
  if id then
    M.close()
    return require('thread.render').follow_link(id, at)
  end
  local it = under(row) or {}
  if it.n then
    return M.walk_to(it.n)
  elseif it.code then
    return M.walk_to(S.n)
  end
  local node = it.drawn and require('thread.diagram').hit(it.drawn, row - 1 - it.first, vim.fn.virtcol '.' - 1 - PAD)
  if node and node.file then
    M.close()
    if require('thread.walk').state() then
      -- Out to the code, still walking: L picks up where you were.
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_config(win).relative == '' then
          vim.api.nvim_set_current_win(win)
          break
        end
      end
    end
    return require('thread.actions').jump { id = 0, file = node.file, text = node.text or '', line = node.line }
  end
  if S.n == 0 then
    M.walk_to(1)
  end
end

local function reply()
  local owner, n = S.owner, S.n
  if n > 0 then
    return require('thread.actions').reply_stop(owner, n)
  end
  local batch = store.active()
  local c = batch and store.find(batch, owner)
  if c then
    M.close()
    require('thread.home').focus { comment = c, reply = true }
  end
end

--- Walk to stop `n` of this page's tour: on with the walk going, or a walk
--- started there.
function M.walk_to(n)
  local walk = require 'thread.walk'
  local batch = store.active()
  local owner = batch and store.find(batch, S.owner)
  local list = owner and tour.of(owner)
  if not list or n > #list or n < 0 or (n == 0 and store.anchored(owner)) then
    return vim.notify(n > 0 and 'thread: the end of the tour' or 'thread: the start of the tour')
  end
  local w = walk.state()
  if w and w.owner == S.owner then
    return walk.go(n)
  end
  walk.start(S.owner, n)
end

--- Out of the tour to the threads either side, as in the focused float:
--- from this stop's conversation if it has one, else the tour's thread.
local function side(dir)
  local batch = store.active()
  local here = batch and (tour.thread_at(batch, S.owner, S.n) or store.find(batch, S.owner))
  local c = here and require('thread.home').neighbour(here.id, dir)
  if c then
    M.close()
    require('thread.home').focus { comment = c }
  end
end

local function keys()
  local w = config.options.walk
  local walk = require 'thread.walk'
  local out = {
    ['<Esc>'] = M.close,
    ['<CR>'] = enter,
    r = reply,
    h = function()
      side(-1)
    end,
    l = function()
      side(1)
    end,
  }
  local function add(lhs, fn)
    if lhs then
      out[lhs] = fn
    end
  end
  add(config.options.mappings.reply, reply)
  add(w.next, function()
    M.walk_to(S.n + 1)
  end)
  add(w.prev, function()
    M.walk_to(S.n - 1)
  end)
  add(w.quit, function()
    if walk.state() then
      walk.stop()
    else
      M.close()
    end
  end)
  add(w.map, function()
    outline = not outline
    M.refresh()
  end)
  return out
end

--- Open the page for stop `n` of `owner`'s tour (0: its overview).
---@param owner integer
---@param n integer
function M.open(owner, n)
  -- A review has its own screen.
  local batch = store.active()
  local o = batch and store.find(batch, owner)
  if o and tour.is_review(o) then
    return require('thread.review.screen').open { owner = owner, n = n > 0 and n or nil }
  end
  if M.is_open() then
    vim.api.nvim_set_current_win(S.win)
  else
    local win, buf = float.open {
      filetype = 'thread-page',
      win = { width = width(), height = 3, title = ' ', footer = ' ', zindex = 50 },
      wo = { wrap = false, cursorline = true, winhighlight = 'NormalFloat:Normal,FloatBorder:ThreadBorderInfo,CursorLine:ThreadZone' },
      keys = keys(),
      -- Leaving for anything but the reply float closes the page.
      on_leave = function()
        local cur = vim.api.nvim_get_current_win()
        if M.is_open() and cur ~= S.win and vim.bo[vim.api.nvim_win_get_buf(cur)].filetype ~= 'markdown' then
          M.close()
        end
      end,
    }
    S = { win = win, buf = buf, items = {} }
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
