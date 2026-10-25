--- Where you write: a reply, a note you start, or a message of yours
--- you edit; and where one of yours is deleted. A reply in a
--- conversation the screen shows is written where it will appear, under
--- the last message, set in as yours are, as a chat has you write; else
--- in a float under the cursor. Either is a markdown buffer, so editing
--- works as it always does. <C-s>, or ⏎ in normal mode, saves it; q or Esc in normal mode
--- throws it away; leaving it saves it. A note you start goes in the
--- review you pick as you save it, an open one or a new one: a comment
--- on lines, a question on none.

local actions = require 'thread.actions'
local go = require 'thread.go'
local labels = require 'thread.draw.labels'
local message = require 'thread.draw.message'
local review = require 'thread.model.review'
local source = require 'thread.base.source'
local text = require 'thread.base.text'

local M = {}

local ns = vim.api.nvim_create_namespace 'thread.compose'

--- What you wrote, not saved: kept in the unnamed register, and said.
---@param said string
---@param why string
local function keep(said, why)
  vim.fn.setreg('"', said)
  vim.notify('thread: ' .. why .. '; what you wrote is in the unnamed register', vim.log.levels.WARN)
end

---@class thread.ComposeOpts
---@field title string
---@field on_save fun(text: string)
---@field lines { buf: integer, from: integer, to: integer }|nil  the code's lines it is about, marked while you write
---@field at (fun(): thread.ReplyAt|nil)|nil  where it goes in place, asked again as what it is in redraws; none, or nil, a float
---@field text string|nil  what it starts with: the message you edit
---@field hint string|nil  what saving does, said under it: `send`, `save`

-- What it says under what you write, `send` or `save` in it.
---@param verb string
---@return string
local function hint(verb)
  return '<C-s> ' .. verb .. ' · q cancel'
end

--- Open it, in place or in a float.
---@param o thread.ComposeOpts
---@return integer win, integer buf
function M.open(o)
  local from_win = vim.api.nvim_get_current_win()
  if o.lines then
    vim.api.nvim_buf_set_extmark(o.lines.buf, ns, o.lines.from - 1, 0, { end_row = o.lines.to - 1, line_hl_group = 'ThreadRange' })
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'markdown'
  local at = o.at and o.at() ---@type thread.ReplyAt|nil

  -- In place: rows made under the last message, your mark beside the
  -- first the editor lies over and the keys under it; editing, over the
  -- message, the rows it grows past made under it. Where the editor
  -- goes, as tall as it is.
  ---@param height integer
  ---@return table|nil
  local function made(height)
    local here = assert(at)
    local said = hint(o.hint or 'send')
    local rows = {} ---@type table[]
    local top = 1
    if here.covers then
      for _ = 1, height - here.covers do
        rows[#rows + 1] = { { ' ' } }
      end
      top = -here.covers
    else
      local g, hl = labels.label('you', false)
      rows[1] = { { ' ' } }
      for i = 1, height do
        rows[#rows + 1] = i == 1 and { { string.rep(' ', math.max(0, here.col - message.LABEL)) }, { g, hl } } or { { ' ' } }
      end
    end
    rows[#rows + 1] = { { string.rep(' ', math.max(0, here.col + here.width - text.width(said))) }, { said, 'ThreadMeta' } }
    local cfg = here.put(rows, top)
    if cfg then
      cfg.width, cfg.height = here.width, math.max(height, here.covers or 1)
    end
    return cfg
  end

  local win ---@type integer
  local cfg = at and made(1)
  if not cfg then
    at = nil
  end
  if cfg then
    win = vim.api.nvim_open_win(buf, true, vim.tbl_extend('force', cfg, { style = 'minimal', zindex = 60 }))
    vim.wo[win].winhighlight = 'NormalFloat:ThreadCompose,EndOfBuffer:ThreadCompose'
  else
    local info = vim.fn.getwininfo(from_win)[1]
    local width = math.max(30, math.min(76, info.width - info.textoff - 4))
    win = vim.api.nvim_open_win(buf, true, {
      relative = 'cursor',
      row = 1,
      col = 0,
      width = width,
      height = 4,
      border = 'rounded',
      style = 'minimal',
      title = ' ' .. o.title .. ' ',
      title_pos = 'left',
      footer = ' ' .. hint(o.hint or 'send') .. ' ',
      footer_pos = 'right',
      zindex = 60,
    })
  end
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  -- Over a card, the code's cursor stays on it while you write.
  vim.w[win].thread_card = true

  local shown = 1 -- the rows of what is written, as last placed
  ---@param height integer
  local function place(height)
    shown = height
    if at and vim.api.nvim_win_is_valid(win) then
      local to = made(height)
      if to then
        vim.api.nvim_win_set_config(win, to)
      end
    end
  end
  if o.text then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(o.text, '\n'))
    place(vim.api.nvim_win_text_height(win, {}).all)
  end

  ---@return string
  local function written()
    if not vim.api.nvim_buf_is_valid(buf) then
      return ''
    end
    return vim.trim(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'))
  end

  local done = false
  ---@param save boolean
  ---@param said string|nil  what was written, read before the buffer went
  local function close(save, said)
    if done then
      return
    end
    done = true
    said = said or written()
    if o.lines and vim.api.nvim_buf_is_valid(o.lines.buf) then
      vim.api.nvim_buf_clear_namespace(o.lines.buf, ns, 0, -1)
    end
    if at then
      at.clear()
      pcall(vim.api.nvim_del_augroup_by_name, 'thread.compose')
    end
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_win_is_valid(from_win) then
      vim.api.nvim_set_current_win(from_win)
    end
    vim.cmd 'stopinsert'
    if save and said ~= '' then
      o.on_save(said)
    end
  end
  ---@param modes string|string[]
  ---@param lhs string
  ---@param fn fun()
  local function map(modes, lhs, fn)
    vim.keymap.set(modes, lhs, fn, { buffer = buf, nowait = true })
  end
  map({ 'n', 'i' }, '<C-s>', function()
    close(true)
  end)
  map('n', '<CR>', function()
    close(true)
  end)
  map('n', 'q', function()
    close(false)
  end)
  map('n', '<Esc>', function()
    close(false)
  end)
  -- It grows with what you write, up to a point.
  local MIN = at and 1 or 4
  shown = math.max(MIN, shown)
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    buffer = buf,
    callback = function()
      if not vim.api.nvim_win_is_valid(win) then
        return
      end
      local height = math.max(MIN, math.min(14, vim.api.nvim_win_text_height(win, {}).all))
      if height ~= shown then
        shown = height
        if at then
          place(height)
        else
          vim.api.nvim_win_set_height(win, height)
        end
      end
    end,
  })
  -- In place, it follows what it is in as that redraws, after it has.
  if at then
    local group = vim.api.nvim_create_augroup('thread.compose', { clear = true })
    vim.api.nvim_create_autocmd('User', {
      group = group,
      pattern = 'ThreadChanged',
      callback = function()
        vim.schedule(function()
          if not done then
            at = assert(o.at)() or at
            place(shown)
          end
        end)
      end,
    })
  end
  -- Read now: after `:q` the buffer is wiped before the close runs.
  vim.api.nvim_create_autocmd('WinLeave', {
    buffer = buf,
    once = true,
    callback = function()
      local said = written()
      vim.schedule(function()
        close(true, said)
      end)
    end,
  })
  if o.text then
    vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
    vim.cmd 'startinsert!'
  else
    vim.cmd 'startinsert'
  end
  return win, buf
end

--- Pick the review a note goes in: an open one, newest first, or a new
--- one, which needs a title. Nothing picked, what was written is kept in
--- the unnamed register.
---@param said string
---@param done fun(r: thread.Review)
local function pick(said, done)
  local list = vim.tbl_filter(function(r)
    return r.status == 'open'
  end, (review.list()))
  local items = vim.tbl_map(function(r)
    return r.title
  end, list)
  items[#items + 1] = 'A new review…'
  local function lost()
    keep(said, 'not saved')
  end
  vim.ui.select(items, { prompt = 'Put it in' }, function(choice, i)
    if not choice then
      return lost()
    end
    if i <= #list then
      return done(list[i])
    end
    vim.ui.input({ prompt = 'The new review, its title: ' }, function(title)
      if not (title and vim.trim(title) ~= '') then
        return lost()
      end
      done(actions.new_review(title))
    end)
  end)
end

--- The lines of the current buffer a note is about, to mark: from its
--- first to its last, as they were captured.
---@param a thread.Anchor|nil
---@return { buf: integer, from: integer, to: integer }|nil
local function marked_lines(a)
  local buf = vim.api.nvim_get_current_buf()
  local where = source.of_buf(buf)
  if not (a and where and source.belongs(a, where)) then
    return nil
  end
  local lines = vim.api.nvim_buf_get_lines(buf, a.line - 1, -1, false)
  local last = a.line
  if a.to then
    for i = 2, #lines do
      if lines[i] == a.to then
        last = a.line + i - 1
        break
      end
    end
  end
  return { buf = buf, from = a.line, to = last }
end

--- What a conversation is called in a reply's title: `step 3 its title`.
---@param c thread.Conversation
---@return string
local function called(c)
  local title = c.contract and c.contract.name or c.step and c.step.title or c.note and c.note.title or ''
  return c.kind .. ' ' .. c.id .. (title ~= '' and (' ' .. title) or '')
end

--- Delete a message of yours, what it said kept in the unnamed register.
--- A note's first, the note is only what you wrote: asked first, since
--- the note goes with it.
---@param r thread.Review
---@param c thread.Conversation
---@param i integer
local function unsay(r, c, i)
  local said = c.messages[i].prose.text
  local function now()
    local ok, why = actions.unsay(r, c, i)
    if ok then
      vim.fn.setreg('"', said)
      vim.notify 'thread: deleted; what it said is in the unnamed register'
    else
      vim.notify('thread: not deleted: ' .. why, vim.log.levels.WARN)
    end
  end
  if not (c.note and i == 1) then
    now()
    return
  end
  vim.ui.select({ 'Delete the note', 'Keep it' }, { prompt = 'Note ' .. c.note.id .. ' is only what you wrote. Delete it?' }, function(_, k)
    if k == 1 then
      now()
    end
  end)
end

go.register('compose', {
  open = {
    compose = function(target)
      local replies = target.replies
      if target.unsay and replies and replies[1] then
        unsay(replies[1].review, replies[1].conversation, target.unsay)
        return
      end
      local i = target.edit
      if i and replies and replies[1] then
        local x = replies[1]
        M.open {
          title = 'Edit your message in ' .. called(x.conversation),
          text = x.conversation.messages[i].prose.text,
          hint = 'save',
          at = function()
            return go.ask('reply_at', x.review, x.conversation, i)
          end,
          on_save = function(said)
            if said == vim.trim(x.conversation.messages[i].prose.text) then
              return
            end
            local ok, why = actions.edit(x.review, x.conversation, i, said)
            if not ok then
              keep(said, 'not saved: ' .. why)
            end
          end,
        }
        return
      end
      if replies and #replies > 0 then
        local c = replies[1].conversation
        local title = #replies > 1 and ('A reply to ' .. #replies .. ' conversations') or ('Reply in ' .. called(c))
        M.open {
          title = title,
          at = #replies == 1 and function()
            return go.ask('reply_at', replies[1].review, c)
          end or nil,
          on_save = function(said)
            local missed = 0
            for _, x in ipairs(replies) do
              missed = missed + (actions.reply(x.review, x.conversation, said) and 0 or 1)
            end
            if missed > 0 then
              keep(said, missed == #replies and 'not saved: what it was in has gone, or its review cannot be read' or ('not saved in ' .. missed .. ' of them'))
            end
          end,
        }
        return
      end
      local a = target.anchor
      M.open {
        title = a and ('A note on ' .. a.file .. ':' .. a.line) or 'A question, on no line',
        lines = marked_lines(a),
        on_save = function(said)
          ---@param r thread.Review
          local function start(r)
            local n = actions.start(r, a, said)
            if not n then
              keep(said, 'not saved: ' .. r.id .. ' cannot be read')
              return
            end
            -- Written on the screen, its page, so you see where it went.
            local fresh = go.ask 'screen open' and review.read(r.id)
            if fresh then
              go.open('note', { review = fresh, note = review.note(fresh, n.id) })
            end
          end
          if target.review then
            start(target.review)
            return
          end
          pick(said, start)
        end,
      }
    end,
  },
})

return M
