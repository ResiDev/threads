--- Replying in place: the reply is typed into Home's own buffer, under the
--- thread's last message, its speaker label drawn as virtual text so the
--- text you type stays plain. <C-s> sends it, <C-c> throws it away. With
--- threads marked, one reply goes to each of them.

local look = require 'thread.look'
local store = require 'thread.store'
local text = require 'thread.text'

local M = {}

local ns = vim.api.nvim_create_namespace 'thread.home.reply'

local function home()
  return require 'thread.home'
end

--- Rows of the reply being typed, 0-based, from its first line to the hint.
local function rows(S)
  local hint = vim.api.nvim_buf_get_extmark_by_id(S.buf, ns, S.reply.hint_mark, {})[1]
  return S.reply.first, hint - 1
end

--- Label the reply's lines again, after it grew or shrank.
function M.relabel(S)
  if not (S and S.reply and S.reply.hint_mark) then
    return
  end
  local first, last = rows(S)
  S.reply.hint = last + 1
  vim.api.nvim_buf_clear_namespace(S.buf, ns, 0, -1)
  S.reply.hint_mark = vim.api.nvim_buf_set_extmark(S.buf, ns, last + 1, 0, {})
  for r = first, last do
    vim.api.nvim_buf_set_extmark(S.buf, ns, r, 0, {
      virt_text = {
        {
          r == first and (string.rep(' ', S.indent) .. text.pad(look.label { from = 'you' }, S.label)) or string.rep(' ', S.text_col),
          r == first and 'ThreadYou' or 'Normal',
        },
      },
      virt_text_pos = 'inline',
      right_gravity = false,
    })
  end
end

--- Start a reply to the focused thread, or to every marked one.
function M.start(S)
  if not S.focus then
    return
  end
  local ids = vim.tbl_keys(S.marked)
  S.reply = { id = S.focus, ids = #ids > 0 and ids or nil }
  if (S.levels[S.focus] or 1) < 1 then
    S.levels[S.focus] = 1
  end
  home().draw()
  S.reply.hint_mark = vim.api.nvim_buf_set_extmark(S.buf, ns, S.reply.hint, 0, {})
  M.relabel(S)
  vim.api.nvim_win_set_cursor(S.win, { S.reply.first + 1, 0 })
  vim.cmd 'startinsert'
end

--- End the reply: sent with `save`, else thrown away.
function M.finish(S, save)
  if not (S and S.reply) then
    return
  end
  local said = ''
  if S.reply.hint_mark then
    local first, last = rows(S)
    said = vim.trim(table.concat(vim.api.nvim_buf_get_lines(S.buf, first, last + 1, false), '\n'))
  end
  local id, ids = S.reply.id, S.reply.ids
  S.reply = nil
  vim.api.nvim_buf_clear_namespace(S.buf, ns, 0, -1)
  vim.cmd 'stopinsert'
  local batch = store.active()
  local c = batch and store.find(batch, id)
  if save and ids and said ~= '' then
    store.reply_all(batch, ids, said)
    S.marked = {}
  elseif save and c and said ~= '' then
    S.levels[id] = math.max(S.levels[id] or 1, 2)
    store.reply(batch, c, said) -- notifies, which redraws
  end
  if S.quick then
    -- Opened only to reply: back to the code.
    return home().close()
  end
  home().draw()
  if S.inside and S.items then
    require('thread.home.thread').select(S, #S.items)
    home().draw()
  end
end

return M
