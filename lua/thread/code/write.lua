--- Writing in a card in the code, in place: the code's answer to where
--- a message goes. Your next under the card's last message, or one of
--- yours over itself to edit it; the card drawn whole, with rows made in
--- it for what you write, and the window scrolled to show them.

local go = require 'thread.go'
local paint = require 'thread.code.paint'

local S = paint.S

--- The card a conversation hangs in, in a window's buffer.
---@param win integer
---@param r thread.Review
---@param c thread.Conversation
---@return integer|nil buf, thread.Placed|nil
local function card(win, r, c)
  local buf = vim.api.nvim_win_get_buf(win)
  for _, p in ipairs(S.placed[buf] or {}) do
    local hung = (S.hung[buf] or {})[p.key]
    if not p.gone and p.review.id == r.id and paint.conversation(p).name == c.name and hung and hung.at then
      return buf, p
    end
  end
end

--- The window scrolled so the `n` rows above `line` show, when they do
--- not: those rows from its top.
---@param win integer
---@param line integer
---@param n integer
local function show(win, line, n)
  local info = vim.fn.getwininfo(win)[1]
  local at = vim.fn.screenpos(win, line, 1).row
  if at == 0 or at - n < info.winrow + info.winbar then
    vim.api.nvim_win_call(win, function()
      vim.fn.winrestview { topline = line, topfill = n }
    end)
  end
end

go.answer('reply_at', function(r, c, i)
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_config(win).relative ~= '' then
    return nil
  end
  local buf, p = card(win, r, c)
  if not (buf and p) then
    return nil
  end
  -- Its rows whole, as it will be drawn while you write.
  local _, parts = paint.whole(buf, p)
  local part ---@type thread.Part|nil
  for _, q in ipairs(parts) do
    local here = q.conversation and q.conversation.name == c.name
    if here and (i and (q.kind == 'message' and q.message == i) or (not i and q.kind == 'reply')) then
      part = part or q
    end
  end
  if not (part and part.cols) then
    return nil
  end
  local cols = assert(part.cols)
  local key = p.key
  ---@type thread.ReplyAt
  return {
    col = cols.col,
    width = cols.width,
    covers = i and (part.last - part.first + 1) or nil,
    put = function(rows, top)
      if not (vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_win_is_valid(win)) then
        return nil
      end
      S.writing = { key = key, writing = { after = i or #c.messages, rows = rows } }
      S.closed[key] = nil
      paint.paint(buf)
      local hung = (S.hung[buf] or {})[key]
      local made = hung and vim.iter(hung.parts):find(function(q)
        return q.kind == 'block' and q.name == 'writing'
      end)
      if not (hung and hung.col and made) then
        return nil
      end
      -- Rows hang above the line, the last right over it: the editor's
      -- first is that many rows up.
      local first = made.first + top
      show(win, p.line, hung.rows - first)
      return { relative = 'win', win = win, bufpos = { p.line - 1, 0 }, row = first - hung.rows, col = hung.col + cols.col }
    end,
    clear = function()
      if S.writing and S.writing.key == key then
        S.writing = nil
        paint.paint(buf)
      end
    end,
  }
end)

return {}
