--- Every batch, the way tour.nvim lists tours: pick one to make it current,
--- start a new one, rename or delete one.

local store = require 'thread.store'
local text = require 'thread.text'
local list = require 'thread.list'

local M = {}

--- Every batch, a row each: its title, how many threads stand where, its
--- reply mode, its round and when it last changed.
---@param P thread.Sheet
---@return string title
function M.view(P)
  local active = store.active_id()
  local batches = store.list()
  if #batches == 0 then
    P.add '  No batches yet. n starts one; so does your first thread.'
    return 'batches'
  end
  local widest = 0
  for _, b in ipairs(batches) do
    widest = math.max(widest, text.width(b.data.title))
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
    local tours = #require('thread.tour').tours(b)
    local mark = b.id == active and '▸' or ' '
    P.own(b)
    P.chunks {
      { ' ' .. mark .. ' ' .. text.pad(vim.fn.strcharpart(b.data.title, 0, 40), widest), b.id == active and 'ThreadYou' or 'Normal' },
      {
        string.format(
          '   %d open · %d answered · %d done · %s   %s · round %d · %s',
          counts.open,
          counts.answered,
          counts.done,
          text.plural(tours, 'tour'),
          b.data.reply == 'chat' and 'replies in chat' or 'replies inline',
          #b.data.rounds,
          text.since(os.time() - math.floor(b.mtime / 1e9))
        ),
        'ThreadMeta',
      },
    }
  end
  P.own(nil)
  return 'batches'
end

local shown -- the list on screen

function M.open()
  if shown and shown.is_open() then
    shown.close()
  end
  shown = list.open {
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
      n = function()
        vim.ui.input({ prompt = 'New batch: ' }, function(title)
          if title then
            store.new(title)
            store.watch()
            -- An input float may have closed the menu; bring it back.
            M.open()
          end
        end)
      end,
      R = function(_, b)
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
  if shown and shown.is_open() then
    shown.redraw()
  end
end

return M
