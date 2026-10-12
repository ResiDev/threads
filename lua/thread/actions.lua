--- What you can do to threads, shared by the keys, Home and the menu.

local anchor = require 'thread.base.anchor'
local source = require 'thread.base.source'
local compose = require 'thread.compose'
local place = require 'thread.render.place'
local render = require 'thread.render'
local store = require 'thread.store'
local tour = require 'thread.tour'

local M = {}

local function notify(msg, level)
  vim.notify('thread: ' .. msg, level or vim.log.levels.INFO)
end

--- Open what a link names: the thread, or the stop of its tour.
---@param id integer|nil
---@param n integer|nil  a stop of the thread's tour
---@return boolean  whether there was one
function M.follow_link(id, n)
  local batch = store.active()
  local c = batch and id and store.find(batch, id)
  if not c then
    if id then
      notify('there is no thread ' .. id)
    end
    return false
  end
  if n and tour.of(c) then
    require('thread.walk').start(c.id, n)
  else
    require('thread.home').focus { thread = c }
  end
  return true
end

--- Start a thread on lines `from`..`to` of the current buffer.
---@param from integer
---@param to integer
function M.add(from, to)
  local bufnr = vim.api.nvim_get_current_buf()
  local a, err = anchor.capture(bufnr, from, to)
  if not a then
    return notify(err, vim.log.levels.WARN)
  end
  local where = a.file .. ':' .. a.line .. (a.lines and ('-' .. (a.line + a.lines - 1)) or '')
  compose.open {
    title = 'a thread on ' .. where,
    bufnr = bufnr,
    from = math.min(from, to),
    to = math.max(from, to),
    on_save = function(text)
      local batch = store.active(true)
      -- Made while a review's diff is drawn on a line it changes: a
      -- review thread, which brings the diff back when you go to it.
      local review = require 'thread.review'
      local extra
      if review.showing() and review.covers(batch, review.showing(), a) then
        extra = { review = review.showing() }
      end
      store.add(batch, a, text, extra)
      store.watch()
    end,
  }
end

--- Ask a question about no line: a thread shown as a page.
function M.ask()
  compose.open {
    title = 'a question about no line in particular',
    on_save = function(text)
      local batch = store.active(true)
      store.add(batch, nil, text)
      store.watch()
      notify 'asked · ask the agent to answer your threads'
    end,
  }
end

--- Reply in stop `n` of `owner`'s tour: the stop's thread, made now if no
--- one has replied in it yet, anchored where the stop is.
---@param owner integer
---@param n integer
function M.reply_stop(owner, n)
  local batch = store.active()
  local o = batch and store.find(batch, owner)
  local list = o and tour.of(o)
  local e = list and list[n]
  if not e then
    return
  end
  local existing = tour.thread_at(batch, owner, n)
  compose.open {
    title = 'a reply in ' .. tour.position(list, n) .. ' · ' .. tour.title(e),
    on_save = function(text)
      local b = store.active(true)
      local c = existing and store.find(b, existing.id)
      if c then
        store.reply(b, c, text)
      else
        local kind = tour.kind(e)
        local a = (kind == 'step' or kind == 'aside') and { file = e.file, text = e.text or '', line = e.line, lines = e.lines, rev = e.rev } or nil
        store.add(b, a, text, { on = { thread = owner, step = n, at = require('thread.review').key_of(o, n) } })
      end
      store.watch()
      notify 'replied · ask the agent to answer your threads'
    end,
  }
end

--- Where a thread sits now, or nil when its line is gone or it has none.
---@param thread thread.Anchor
---@return integer|nil
function M.locate(thread)
  if not store.anchored(thread) then
    return nil
  end
  local lines = source.lines_of(thread)
  local loc = lines and require('thread.review.lines').locate(thread, lines)
  return loc and loc.line
end

--- Open the code at a place, as an agent's change names one: where its
--- quoted line is now, else where it was.
---@param a thread.Anchor
function M.go(a)
  if M.jump({ file = a.file, text = a.text or '', line = a.line, lines = a.lines, rev = a.rev }, { quiet = true }) then
    return
  end
  local where = source.of_buf(0)
  if not (where and where.file == a.file) then
    return notify('could not open ' .. a.file, vim.log.levels.WARN)
  end
  local count = vim.api.nvim_buf_line_count(0)
  vim.api.nvim_win_set_cursor(0, { math.max(1, math.min(count, a.line or 1)), 0 })
  notify(a.file .. ': its line is not there now; this is where it was')
end

--- Close a thread, or open it again.
function M.toggle_closed(batch, thread)
  store.set_status(batch, thread, store.status(thread) == 'closed' and 'open' or 'closed')
end

function M.delete(batch, thread)
  store.remove(batch, thread)
end

--- Open the code a thread is on. With `quiet`, a line that is gone is
--- left for the caller to say.
---@param thread thread.Thread
---@param opts { quiet: boolean|nil }|nil
---@return boolean
function M.jump(thread, opts)
  local quiet = opts and opts.quiet
  if not store.anchored(thread) then
    -- About no line: its page.
    require('thread.home').focus { thread = thread }
    return true
  end
  if thread.rev then
    -- A past revision shows only in a diff that has it open.
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local where = source.of_buf(vim.api.nvim_win_get_buf(win))
      if where and source.belongs(thread, where) then
        vim.api.nvim_set_current_win(win)
        local line = M.locate(thread)
        if line then
          vim.api.nvim_win_set_cursor(win, { line, 0 })
          vim.cmd 'normal! zz'
        end
        return true
      end
    end
    if not quiet then
      notify(string.format('thread %s is on %s at %s; open that diff to see it', thread.id, thread.file, thread.rev:sub(1, 7)))
    end
    return false
  end
  local path = store.root() .. '/' .. thread.file
  local function here()
    return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':p') == vim.fn.fnamemodify(path, ':p')
  end
  if not here() then
    local was = vim.api.nvim_get_current_buf()
    -- `:hide` leaves a modified buffer behind even with 'nohidden'; an error
    -- another plugin's autocmd throws comes after the file is open.
    pcall(vim.cmd, 'hide edit ' .. vim.fn.fnameescape(path))
    if not here() then
      if not quiet then
        notify(string.format('could not open %s', thread.file), vim.log.levels.WARN)
      end
      return false
    end
    -- A start screen left behind in the window still answers its cursor
    -- moving (snacks' dashboard errors on lines it does not have): wipe it.
    local ft = vim.api.nvim_buf_is_valid(was) and vim.bo[was].filetype or ''
    if ft == 'snacks_dashboard' or ft == 'alpha' or ft == 'dashboard' or ft == 'ministarter' then
      pcall(vim.api.nvim_buf_delete, was, { force = true })
    end
  end
  local line = M.locate(thread)
  if not line then
    if not quiet then
      notify(string.format('the line thread %s was on is gone', thread.id), vim.log.levels.WARN)
    end
    return false
  end
  -- A review thread means nothing without its diff: draw it.
  local batch = store.active()
  local review = require 'thread.review'
  local owner = batch and review.owner_of(batch, thread)
  if owner and review.showing() ~= owner.id then
    review.show(owner.id)
  end
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  -- The bubble hangs above the line: centre it so the bubble shows too.
  vim.cmd 'normal! zz'
  render.draw(vim.api.nvim_get_current_buf())
  if vim.fn.line 'w0' == 1 then
    -- Above the first line, a card shows only as filler the window is
    -- scrolled to: show all of it.
    vim.fn.winrestview { topline = 1, topfill = vim.o.lines }
  end
  return true
end

---@param batch thread.Batch
---@param thread thread.Thread
---@param target { change: thread.Anchor, index: integer }|nil
function M.changes(batch, thread, target)
  if not target then
    for i = #thread.messages, 1, -1 do
      local m = thread.messages[i]
      if m.changes and #m.changes > 0 then
        target = { change = m.changes[1], index = i }
        break
      end
    end
  end
  if not target then
    return notify(string.format('the agent has listed no changes for thread %d', thread.id))
  end
  local base = store.base_for(batch, thread, target.index) or 'HEAD'
  local line = M.locate(target.change) or target.change.line
  require('thread.ui.changes').open_file(base, target.change.file, line)
end

--- Everything changed since the batch was last sent.
---@param batch thread.Batch
function M.all_changes(batch)
  local round = batch.data.rounds[#batch.data.rounds]
  if not (round and round.snapshot) then
    return notify 'this batch has not been sent yet'
  end
  require('thread.ui.changes').open_all(round.snapshot)
end

--- Put back what a change replaced: the old lines of each of its hunks,
--- written to the file. Its buffer's own undo brings the change back.
---@param file string
---@param v { old: string[], new: string[], hunks: thread.WordHunk[] }  the change, as drawn (thread.home.model.change)
function M.undo_change(file, v)
  local buf = vim.fn.bufadd(store.root() .. '/' .. file)
  vim.fn.bufload(buf)
  if not vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), v.new) then
    return notify(file .. ' changed since this was drawn; look again and undo again', vim.log.levels.WARN)
  end
  local hunks = vim.deepcopy(v.hunks)
  table.sort(hunks, function(a, b)
    return a.new_start > b.new_start
  end)
  for _, h in ipairs(hunks) do
    local old = vim.list_slice(v.old, h.old_start, h.old_start + h.old_count - 1)
    local at = h.new_count == 0 and h.new_start or h.new_start - 1
    vim.api.nvim_buf_set_lines(buf, at, at + h.new_count, false, old)
  end
  vim.api.nvim_buf_call(buf, function()
    vim.cmd 'silent write'
  end)
  notify(string.format('undid the change in %s; u in that file brings it back', file))
end

--- Pick the diff the batch asks the agent to review.
function M.pick_diff()
  local batch = store.active()
  if not batch then
    return
  end
  local cur = type(batch.data.diff) == 'table' and batch.data.diff or {}
  local function set(d)
    batch.data.diff = d
    store.save(batch)
    store.notify()
    notify('the diff to review is ' .. require('thread.review').spec(d).label .. '; ask the agent to review it')
  end
  local choices = {
    { 'uncommitted: everything since the last commit', { of = 'uncommitted' } },
    { 'staged: what the next commit would hold', { of = 'staged' } },
    { 'unstaged: what is not staged yet', { of = 'unstaged' } },
    { 'since a commit, to the working tree', 'base' },
    { 'between two commits', 'range' },
  }
  vim.ui.select(choices, {
    prompt = 'Review which diff?',
    format_item = function(x)
      return x[1]
    end,
  }, function(x)
    if not x then
      return
    elseif type(x[2]) == 'table' then
      return set(x[2])
    end
    vim.ui.input({ prompt = 'From (a commit, branch or tag): ', default = cur.base or 'main' }, function(base)
      if not base or vim.trim(base) == '' then
        return
      elseif x[2] == 'base' then
        return set { base = vim.trim(base) }
      end
      vim.ui.input({ prompt = 'To: ', default = cur.head or 'HEAD' }, function(head)
        if head and vim.trim(head) ~= '' then
          set { base = vim.trim(base), head = vim.trim(head) }
        end
      end)
    end)
  end)
end

--- The threads `]n` goes through, in file and line order: those where it
--- is your move, or with `all` every open one.
---@param batch thread.Batch
---@param all boolean|nil
---@return { thread: thread.Thread, line: integer }[]
local function stops(batch, all)
  local out = {}
  for _, c in ipairs(batch.data.threads) do
    local status = store.status(c)
    local wanted = all and status ~= 'closed' and status ~= 'info' or status == 'answered'
    if wanted and not c.rev and store.anchored(c) then
      local line = M.locate(c)
      if line then
        out[#out + 1] = { thread = c, line = line }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.thread.file ~= b.thread.file then
      return a.thread.file < b.thread.file
    end
    return a.line < b.line
  end)
  return out
end

--- Go to the next (or previous) thread where it is your move, or with
--- `all` any open one, across files. The map shows for a moment after.
---@param dir 1|-1
---@param all boolean|nil
function M.step(dir, all)
  local batch = store.active()
  if not batch then
    return notify 'no batch yet'
  end
  local list = stops(batch, all)
  if #list == 0 then
    return notify(all and 'no open threads on lines in this batch' or 'nothing is your move: every open thread is with the agent')
  end
  local here = source.of_buf(0)
  local file = here and not here.rev and here.file or ''
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local pick
  if dir > 0 then
    for _, item in ipairs(list) do
      if item.thread.file > file or (item.thread.file == file and item.line > lnum) then
        pick = item
        break
      end
    end
    pick = pick or list[1]
  else
    for i = #list, 1, -1 do
      local item = list[i]
      if item.thread.file < file or (item.thread.file == file and item.line < lnum) then
        pick = item
        break
      end
    end
    pick = pick or list[#list]
  end
  M.jump(pick.thread)
  require('thread.map').flash()
end

--- Focus the thread the cursor is on: its code and whole thread in a float
--- in the middle, with Home's keys. With `reply`, straight into a reply.
---@param opts { reply: boolean|nil }|nil
function M.focus(opts)
  local thread = place.at_cursor()
  if not thread then
    return notify 'no thread on this line'
  end
  if thread.stop then
    -- A tour's stop: opened as its page, where you reply in it with r.
    if opts and opts.reply then
      return M.reply_stop(thread.stop.owner, thread.stop.n)
    end
    return require('thread.page').open(thread.stop.owner, thread.stop.n)
  end
  local buf = vim.api.nvim_get_current_buf()
  local here = place.covering(place.placed[buf] or {}, vim.api.nvim_win_get_cursor(0)[1])
  local others = {}
  for _, p in ipairs(here) do
    if not p.thread.virtual then
      others[#others + 1] = p.thread.id
    end
  end
  require('thread.home').focus { thread = thread, others = others, reply = opts and opts.reply }
end

--- Close the thread the cursor is on, or reopen it.
function M.close_here()
  local thread = place.at_cursor()
  if not thread then
    return notify 'no thread on this line'
  end
  if thread.virtual then
    return notify 'a stop of a tour: there is nothing to close until you reply in it'
  end
  M.toggle_closed(store.active(), thread.real or thread)
end

--- Draw the changes of the thread the cursor is on into the code, or stop.
--- In a review, or on one of its threads, the review's diff.
function M.diff_here()
  local thread = place.at_cursor()
  local review = require 'thread.review'
  local batch = store.active()
  local owner = batch and thread and review.owner_of(batch, thread)
  if owner or (not thread and review.showing()) then
    local on = review.showing() == nil
    review.show(on and owner.id or nil)
    render.refresh()
    return notify(on and "the review's diff drawn in the code" or "the review's diff hidden")
  end
  if not thread then
    return notify 'no thread on this line'
  end
  local on = render.toggle_drawn((thread.real or thread).id)
  notify(on and 'its changes drawn in the code' or 'its changes hidden')
end

--- The thread the cursor is on to one line, or whole.
function M.fold_here()
  local thread = place.at_cursor()
  if thread then
    render.fold(store.active(), thread)
    render.paint(vim.api.nvim_get_current_buf())
  end
end

--- Show more (or less) of the thread the cursor is on.
---@param n integer
---@return boolean  whether there was one
function M.resize_here(n)
  local thread = place.at_cursor()
  if not thread then
    return false
  end
  render.resize(store.active(), thread, n)
  render.paint(vim.api.nvim_get_current_buf())
  return true
end

return M
