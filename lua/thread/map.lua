--- The map: a float in the top right to jump from. Walking, it is the
--- tour's outline, the step you are on marked; else every open thread on a
--- line, by file. A letter goes there, or ⏎ on its row, for those past the
--- letters; q closes it.

local chunk = require 'thread.model.chunk'
local float = require 'thread.ui.float'
local go = require 'thread.go'
local review = require 'thread.model.review'
local sheet = require 'thread.ui.sheet'
local text = require 'thread.base.text'
local thread = require 'thread.model.thread'
local thread_draw = require 'thread.draw.thread'
local tour_draw = require 'thread.draw.tour'

local M = {}

local ns = vim.api.nvim_create_namespace 'thread.map'

-- A letter for each place, `q` left to close it.
local LETTERS = 'abcdefghijklmnoprstuvwxyz'

local win ---@type integer|nil

function M.close()
  float.close(win)
  win = nil
end

--- What the map lists: a row each, and what its letter does.
---@param P thread.Sheet
---@param width integer
---@return { row: integer, go: fun(), here: boolean|nil }[]
local function entries(P, width)
  local out = {}
  local w = go.ask 'walking'
  local r = w and review.read(w.review)
  local t = r and review.find(r, w.thread)
  local s, x ---@type thread.Step|nil, thread.Tour|nil
  if t and w then
    s, x = thread.step(t, w.step)
  end
  if r and t and x and s then
    for _, p in ipairs(tour_draw.outline(P, r, t, x, { width = width - 4, indent = 4, here = s })) do
      if p.kind == 'step' and p.step then
        local to = p.step
        out[#out + 1] = {
          row = p.first,
          here = to == s,
          go = function()
            go.open('walk', { review = r, thread = t, tour = x, step = to })
          end,
        }
      end
    end
    return out
  end
  local by_file = {} ---@type table<string, { review: thread.Review, thread: thread.Thread, line: integer }[]>
  for _, rv in ipairs((review.list())) do
    if rv.status == 'open' then
      for _, th in ipairs(rv.threads) do
        local at = th.chunk and not thread.closed(th) and chunk.locate(th.chunk, chunk.spec(rv.diff))
        if at and th.chunk then
          by_file[th.chunk.file] = by_file[th.chunk.file] or {}
          table.insert(by_file[th.chunk.file], { review = rv, thread = th, line = at.line })
        end
      end
    end
  end
  local files = vim.tbl_keys(by_file)
  table.sort(files)
  for _, f in ipairs(files) do
    P.chunks({ { text.fit(f, width - 2), 'Directory' } }, 2)
    table.sort(by_file[f], function(a, b)
      return a.line < b.line
    end)
    for _, e in ipairs(by_file[f]) do
      local p = thread_draw.line(P, e.review, e.thread, { width = width - 4, indent = 4 })
      out[#out + 1] = {
        row = p.first,
        go = function()
          go.open('code', { review = e.review, thread = e.thread, chunk = e.thread.chunk })
        end,
      }
    end
  end
  if #out == 0 then
    P.chunks({ { 'No open thread is on a line.', 'ThreadMeta' } }, 2)
  end
  return out
end

--- Open the map, entered, to jump from.
function M.open()
  M.close()
  local width = math.min(64, vim.o.columns - 4)
  local P = sheet.new()
  P.add ''
  local list = entries(P, width)
  P.add ''
  local jump = {} ---@type table<string, fun()>
  local on_row = {} ---@type table<integer, fun()>
  local start = list[1] and list[1].row or 0
  for i, e in ipairs(list) do
    local function to()
      M.close()
      e.go()
    end
    on_row[e.row] = to
    start = e.here and e.row or start
    local letter = LETTERS:sub(i, i)
    if letter ~= '' then
      P.mark(e.row, 1, { virt_text = { { letter, 'ThreadKey' } }, virt_text_pos = 'overlay' })
      jump[letter] = to
    end
  end
  jump['<CR>'] = function()
    local to = on_row[vim.api.nvim_win_get_cursor(0)[1] - 1]
    if to then
      to()
    end
  end
  jump.q, jump['<Esc>'] = M.close, M.close
  local mine, buf ---@type integer, integer
  mine, buf = float.open {
    filetype = 'thread-map',
    win = {
      row = 1,
      col = vim.o.columns - width - 2,
      width = width,
      height = math.min(#P.lines, float.max_height(2)),
      title = ' Map ',
      title_pos = 'left',
      footer = ' a–z or ⏎ go · q close ',
      footer_pos = 'right',
      zindex = 50,
    },
    wo = { wrap = false, cursorline = true },
    keys = jump,
    -- Its own: a map closed and opened again is not closed by the old one.
    on_leave = function()
      if win == mine then
        M.close()
      end
    end,
  }
  win = mine
  P.apply(buf, ns)
  pcall(vim.api.nvim_win_set_cursor, mine, { start + 1, 0 })
end

go.register('map', { open = { map = M.open }, close = M.close })

return M
