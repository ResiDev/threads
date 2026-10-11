--- What you can do to threads, shared by the keys, Home and the menu.

local anchor = require 'thread.anchor'
local compose = require 'thread.compose'
local git = require 'thread.git'
local render = require 'thread.render'
local store = require 'thread.store'

local M = {}

local function notify(msg, level)
  vim.notify('thread: ' .. msg, level or vim.log.levels.INFO)
end

--- Comment on lines `from`..`to` of the current buffer.
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
      store.add(batch, a, text)
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
  local tour = require 'thread.tour'
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
        local a = tour.kind(e) == 'step' and { file = e.file, text = e.text or '', line = e.line, lines = e.lines, rev = e.rev } or nil
        store.add(b, a, text, { on = { thread = owner, step = n } })
      end
      store.watch()
      notify 'replied · ask the agent to answer your threads'
    end,
  }
end

--- Where a thread sits now, or nil when its line is gone or it has none.
---@param comment thread.Anchor
---@return integer|nil
function M.locate(comment)
  if not store.anchored(comment) then
    return nil
  end
  local lines = anchor.lines_of(comment)
  local loc = lines and anchor.locate(comment, lines)
  return loc and loc.line
end

--- Close a thread, or open it again.
function M.toggle_closed(batch, comment)
  store.set_status(batch, comment, store.status(comment) == 'closed' and 'open' or 'closed')
end

function M.delete(batch, comment)
  store.remove(batch, comment)
end

--- Close every open thread whose line is gone.
---@param batch thread.Batch
---@return integer
function M.close_stale(batch)
  local n = 0
  for _, c in ipairs(batch.data.threads) do
    if store.anchored(c) and store.status(c) ~= 'closed' and not M.locate(c) then
      c.status = 'closed'
      n = n + 1
    end
  end
  if n > 0 then
    store.save(batch)
    store.notify()
  end
  return n
end

--- Open the code a comment is on.
---@param comment thread.Comment
---@return boolean
function M.jump(comment)
  if not store.anchored(comment) then
    -- About no line: its page.
    require('thread.home').focus { comment = comment }
    return true
  end
  if comment.rev then
    -- A past revision shows only in a diff that has it open.
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local where = anchor.of_buf(vim.api.nvim_win_get_buf(win))
      if where and anchor.belongs(comment, where) then
        vim.api.nvim_set_current_win(win)
        local line = M.locate(comment)
        if line then
          vim.api.nvim_win_set_cursor(win, { line, 0 })
          vim.cmd 'normal! zz'
        end
        return true
      end
    end
    notify(string.format('thread %d is on %s at %s; open that diff to see it', comment.id, comment.file, comment.rev:sub(1, 7)))
    return false
  end
  local path = store.root() .. '/' .. comment.file
  if vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':p') ~= vim.fn.fnamemodify(path, ':p') then
    vim.cmd.edit(vim.fn.fnameescape(path))
  end
  local line = M.locate(comment)
  if not line then
    notify(string.format('the line thread %d was on is gone', comment.id), vim.log.levels.WARN)
    return false
  end
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  -- The bubble hangs above the line: centre it so the bubble shows too.
  vim.cmd 'normal! zz'
  render.draw(vim.api.nvim_get_current_buf())
  return true
end

---@param batch thread.Batch
---@param comment thread.Comment
---@param target { change: thread.Anchor, index: integer }|nil
function M.changes(batch, comment, target)
  if not target then
    for i = #comment.messages, 1, -1 do
      local m = comment.messages[i]
      if m.changes and #m.changes > 0 then
        target = { change = m.changes[1], index = i }
        break
      end
    end
  end
  if not target then
    return notify(string.format('the agent has listed no changes for thread %d', comment.id))
  end
  local base = git.base_for(batch, comment, target.index) or 'HEAD'
  local line = M.locate(target.change) or target.change.line
  git.open_file_diff(base, target.change.file, line)
end

--- Everything changed since the batch was last sent.
---@param batch thread.Batch
function M.all_changes(batch)
  local round = batch.data.rounds[#batch.data.rounds]
  if not (round and round.snapshot) then
    return notify 'this batch has not been sent yet'
  end
  git.open_all(round.snapshot)
end

--- The comments `]n` goes through, in file and line order: those where it
--- is your move, or with `all` every open one.
---@param batch thread.Batch
---@param all boolean|nil
---@return { comment: thread.Comment, line: integer }[]
local function stops(batch, all)
  local out = {}
  for _, c in ipairs(batch.data.threads) do
    local status = store.status(c)
    local wanted = all and status ~= 'closed' and status ~= 'info' or status == 'draft' or status == 'answered'
    if wanted and not c.rev and store.anchored(c) then
      local line = M.locate(c)
      if line then
        out[#out + 1] = { comment = c, line = line }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.comment.file ~= b.comment.file then
      return a.comment.file < b.comment.file
    end
    return a.line < b.line
  end)
  return out
end

--- Go to the next (or previous) comment where it is your move, or with
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
  local here = anchor.of_buf(0)
  local file = here and not here.rev and here.file or ''
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local pick
  if dir > 0 then
    for _, item in ipairs(list) do
      if item.comment.file > file or (item.comment.file == file and item.line > lnum) then
        pick = item
        break
      end
    end
    pick = pick or list[1]
  else
    for i = #list, 1, -1 do
      local item = list[i]
      if item.comment.file < file or (item.comment.file == file and item.line < lnum) then
        pick = item
        break
      end
    end
    pick = pick or list[#list]
  end
  M.jump(pick.comment)
  require('thread.map').flash()
end

--- Focus the comment the cursor is on: its code and whole thread in a float
--- in the middle, with Home's keys. With `reply`, straight into a reply.
---@param opts { reply: boolean|nil }|nil
function M.focus(opts)
  local comment = render.at_cursor()
  if not comment then
    return notify 'no thread on this line'
  end
  if comment.stop then
    -- A tour's stop: opened as its page, where you reply in it with r.
    if opts and opts.reply then
      return M.reply_stop(comment.stop.owner, comment.stop.n)
    end
    return require('thread.page').open(comment.stop.owner, comment.stop.n)
  end
  local buf = vim.api.nvim_get_current_buf()
  local here = render.covering(render.placed[buf] or {}, vim.api.nvim_win_get_cursor(0)[1])
  local others = {}
  for _, p in ipairs(here) do
    if not p.comment.virtual then
      others[#others + 1] = p.comment.id
    end
  end
  require('thread.home').focus { comment = comment, others = others, reply = opts and opts.reply }
end

--- Close the comment the cursor is on, or reopen it.
function M.close_here()
  local comment = render.at_cursor()
  if not comment then
    return notify 'no thread on this line'
  end
  if comment.virtual then
    return notify 'a stop of a tour: there is nothing to close until you reply in it'
  end
  M.toggle_closed(store.active(), comment.real or comment)
end

--- Draw the changes of the thread the cursor is on into the code, or stop.
function M.diff_here()
  local comment = render.at_cursor()
  if not comment then
    return notify 'no thread on this line'
  end
  local on = render.toggle_drawn((comment.real or comment).id)
  notify(on and 'its changes drawn in the code' or 'its changes hidden')
end

--- Show more (or less) of the comment the cursor is on.
---@param n integer
---@return boolean  whether there was one
function M.resize_here(n)
  local comment = render.at_cursor()
  if not comment then
    return false
  end
  render.resize(store.active(), comment, n)
  render.paint(vim.api.nvim_get_current_buf())
  return true
end

return M
