--- Every batch, the way tour.nvim lists tours: pick one to make it current,
--- start a new one, rename or delete one.

local store = require 'thread.store'
local ui = require 'thread.ui'

local M = {}

local function ago(ns)
  local s = os.time() - math.floor(ns / 1e9)
  if s < 90 then
    return 'just now'
  elseif s < 5400 then
    return math.floor(s / 60 + 0.5) .. 'm ago'
  elseif s < 129600 then
    return math.floor(s / 3600 + 0.5) .. 'h ago'
  end
  return math.floor(s / 86400 + 0.5) .. 'd ago'
end

function M.view()
  local lines, hls, items = {}, {}, {}
  local active = store.active_id()
  local batches = store.list()
  if #batches == 0 then
    lines[1] = '  No batches yet. n starts one; so does your first thread.'
    return { lines = lines, hls = hls, items = items, title = 'batches' }
  end
  local widest = 0
  for _, b in ipairs(batches) do
    widest = math.max(widest, vim.fn.strdisplaywidth(b.data.title))
  end
  widest = math.min(widest, 40)
  for _, b in ipairs(batches) do
    local counts = { open = 0, answered = 0, done = 0 }
    for _, c in ipairs(b.data.threads) do
      local s = store.status(c)
      if s == 'closed' then
        counts.done = counts.done + 1
      elseif s == 'answered' then
        counts.answered = counts.answered + 1
      elseif s ~= 'info' then
        counts.open = counts.open + 1
      end
    end
    local tours = #require('thread.tree').tours(b)
    local mark = b.id == active and '▸' or ' '
    local title = vim.fn.strcharpart(b.data.title, 0, 40)
    title = title .. string.rep(' ', widest - vim.fn.strdisplaywidth(title))
    local text = string.format(
      ' %s %s   %d open · %d answered · %d done · %d tour%s   %s · round %d · %s',
      mark,
      title,
      counts.open,
      counts.answered,
      counts.done,
      tours,
      tours == 1 and '' or 's',
      b.data.reply == 'chat' and 'replies in chat' or 'replies inline',
      #b.data.rounds,
      ago(b.mtime)
    )
    lines[#lines + 1] = text
    items[#lines] = b
    local row = #lines - 1
    local title_end = #(' ' .. mark .. ' ' .. title)
    hls[#hls + 1] = { row, 0, title_end, b.id == active and 'ThreadYou' or 'Normal' }
    hls[#hls + 1] = { row, title_end, -1, 'ThreadMeta' }
  end
  return { lines = lines, hls = hls, items = items, title = 'batches' }
end

local list

function M.open()
  if list and list.is_open() then
    list.close()
  end
  list = ui.open {
    footer = '⏎ use · n new · R rename · m reply mode · D delete',
    render = M.view,
    keys = {
      ['<CR>'] = function(l, b)
        if b then
          store.set_active(b.id)
          l.close()
          require('thread.home').open()
        end
      end,
      n = function(l)
        vim.ui.input({ prompt = 'New batch: ' }, function(title)
          if title then
            store.new(title)
            store.watch()
            -- An input float may have closed the menu; bring it back.
            M.open()
          end
        end)
      end,
      R = function(l, b)
        if not b then
          return
        end
        vim.ui.input({ prompt = 'Rename batch: ', default = b.data.title }, function(title)
          if title and vim.trim(title) ~= '' then
            b.data.title = vim.trim(title)
            store.save(b)
            M.open()
          end
        end)
      end,
      m = function(l, b)
        if b then
          b.data.reply = b.data.reply == 'chat' and 'inline' or 'chat'
          store.save(b)
          l.redraw()
        end
      end,
      D = function(l, b)
        if b and vim.fn.confirm(string.format('Delete batch "%s" and its %d threads?', b.data.title, #b.data.threads), '&Yes\n&No', 2) == 1 then
          store.delete(b.id)
          store.notify()
          l.redraw()
        end
      end,
    },
  }
end

function M.refresh()
  if list and list.is_open() then
    list.redraw()
  end
end

return M
