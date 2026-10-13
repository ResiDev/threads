--- The float you write in: a reply, or a thread you start. It opens under
--- the cursor, and is a markdown buffer, so editing works as it always
--- does. <C-s>, or ⏎ in normal mode, saves it; q or Esc in normal mode
--- throws it away; leaving it saves it. A thread you start goes in the
--- review you pick as you save it, an open one or a new one.

local actions = require 'thread.actions'
local go = require 'thread.go'
local review = require 'thread.model.review'
local source = require 'thread.base.source'

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

--- Open the float.
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
  local info = vim.fn.getwininfo(from_win)[1]
  local width = math.max(30, math.min(76, info.width - info.textoff - 4))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'cursor',
    row = 1,
    col = 0,
    width = width,
    height = 4,
    border = 'rounded',
    style = 'minimal',
    title = ' ' .. o.title .. ' ',
    title_pos = 'left',
    footer = ' <C-s> save · q cancel ',
    footer_pos = 'right',
    zindex = 60,
  })
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true

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
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    buffer = buf,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_set_height(win, math.max(4, math.min(14, vim.api.nvim_win_text_height(win, {}).all)))
      end
    end,
  })
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
  vim.cmd 'startinsert'
  return win, buf
end

--- Pick the review a thread goes in: an open one, newest first, or a new
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

--- The lines of the current buffer a chunk is on, to mark.
---@param c thread.Chunk|nil
---@return { buf: integer, from: integer, to: integer }|nil
local function marked_lines(c)
  local buf = vim.api.nvim_get_current_buf()
  local where = source.of_buf(buf)
  if not (c and where and source.belongs(c, where)) then
    return nil
  end
  return { buf = buf, from = c.line, to = c.line + (c.lines or 1) - 1 }
end

go.register('compose', {
  open = {
    compose = function(target)
      local replies = target.replies
      if replies and #replies > 0 then
        local t = replies[1].conversation.thread
        local title = #replies > 1 and ('A reply to ' .. #replies .. ' threads')
          or ('Reply in #' .. t.id .. (replies[1].conversation.step and ('.' .. replies[1].conversation.step.id) or '') .. (t.title and (' ' .. t.title) or ''))
        M.open {
          title = title,
          on_save = function(said)
            local missed = 0
            for _, x in ipairs(replies) do
              missed = missed + (actions.reply(x.review, x.conversation, said) and 0 or 1)
            end
            if missed > 0 then
              keep(said, missed == #replies and 'not saved: its thread has gone, or its review cannot be read' or ('not saved in ' .. missed .. ' of them'))
            end
          end,
        }
        return
      end
      local c = target.chunk
      M.open {
        title = c and ('A thread on ' .. c.file .. ':' .. c.line) or 'A question, on no line',
        lines = marked_lines(c),
        on_save = function(said)
          ---@param r thread.Review
          local function start(r)
            if not actions.start(r, c, said) then
              keep(said, 'not saved: ' .. r.id .. ' cannot be read')
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
