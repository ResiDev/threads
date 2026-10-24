--- The screen's frame: the window it draws in, its top row and its
--- bottom rows. Full, it is the editor less its last rows, a blank row
--- over it: the top row, its winbar, says where you are, or is a
--- review's tabs; a window of its own under the page holds the keys,
--- what is under the cursor and where it is among its kind. Over the
--- code it is a float with a border, where it says those.

local float = require 'thread.ui.float'
local look = require 'thread.ui.look'
local text = require 'thread.base.text'

local M = {}

-- A border of one row, on top: the blank row over the top row. A float
-- moved a row down would show the code above it instead.
local TOP = { '', ' ', '', '', '', '', '', '' }

local ns = vim.api.nvim_create_namespace 'thread.screen.frame'

-- A full frame's windows in the editor's colours, not a float's.
local FULL = 'NormalFloat:Normal,FloatBorder:Normal,FloatTitle:Normal,WinBar:Normal,WinBarNC:Normal'

--- What the bottom rows say: the keys, and on their right where the
--- item is among its kind, `2 of 8`; over them, a blank row between, a
--- row about what is under the cursor.
---@class thread.FrameFoot
---@field keys { [1]: string, [2]: string }[][]  in groups of keys that do alike
---@field at string|nil
---@field line thread.Chunks|nil

--- A frame: the page's window and the one under it, full.
---@class thread.FrameWins
---@field win integer
---@field buf integer
---@field foot integer|nil  the bottom rows' window, full
---@field rows integer  how many bottom rows

--- The page's window's place, full, with `rows` bottom rows under it.
---@param rows integer
---@return table
local function full(rows)
  local height = vim.o.lines - vim.o.cmdheight - 1
  return { relative = 'editor', row = 0, col = 0, width = vim.o.columns, height = math.max(3, height - 1 - rows) }
end

--- The page's window, full or over the code, and the bottom rows'
--- window under it when full.
---@param over boolean
---@return thread.FrameWins
function M.open(over)
  local cfg = over and vim.tbl_extend('force', float.centred(math.min(vim.o.columns - 8, 100), 10), { title = ' ', footer = ' ', zindex = 45 })
    or vim.tbl_extend('force', full(2), { border = TOP, zindex = 40 })
  local win, buf = float.open {
    filetype = 'thread-screen',
    win = cfg,
    wo = {
      wrap = false,
      cursorline = true,
      number = false,
      signcolumn = 'no',
      -- Full, the page is the editor's own background, its top row too.
      winhighlight = not over and FULL or nil,
    },
  }
  local out = { win = win, buf = buf, rows = 2 } ---@type thread.FrameWins
  if not over then
    local fbuf = vim.api.nvim_create_buf(false, true)
    vim.bo[fbuf].bufhidden = 'wipe'
    local at = full(2)
    out.foot = vim.api.nvim_open_win(fbuf, false, {
      relative = 'editor',
      row = at.height + 1,
      col = 0,
      width = vim.o.columns,
      height = 2,
      style = 'minimal',
      focusable = false,
      zindex = 40,
    })
    vim.wo[out.foot].winhighlight = FULL
  end
  return out
end

--- Fit a full frame to the editor again, `rows` rows under the page.
---@param f thread.FrameWins
---@param rows integer
function M.place(f, rows)
  if not (f.foot and vim.api.nvim_win_is_valid(f.foot)) then
    return
  end
  f.rows = rows
  local at = full(rows)
  vim.api.nvim_win_set_config(f.win, at)
  vim.api.nvim_win_set_config(f.foot, { relative = 'editor', row = at.height + 1, col = 0, width = vim.o.columns, height = rows })
end

--- `left`, then `right` ending at `width`, two columns apart at least;
--- the left cut short to make room.
---@param left thread.Chunks
---@param right thread.Chunks
---@param width integer
---@return thread.Chunks
function M.spread(left, right, width)
  local rw = text.width(right)
  local row = text.fit_chunks(left, math.max(1, width - rw - 2))
  row[#row + 1] = { string.rep(' ', math.max(2, width - text.width(row) - rw)) }
  return vim.list_extend(row, right)
end

--- Keys and what they do, a row: `key label`, three columns between.
---@param keys { [1]: string, [2]: string }[]
---@return thread.Chunks
local function hints(keys)
  local out = {} ---@type thread.Chunks
  for i, k in ipairs(keys) do
    vim.list_extend(out, { { (i > 1 and '   ' or '') .. k[1], 'ThreadKey' }, { ' ' .. k[2], 'ThreadKeyLabel' } })
  end
  return out
end

--- The top row: full, the winbar, a column in as a border's title is,
--- so it stays put as the page scrolls; over the code, the border's
--- title.
---@param f thread.FrameWins
---@param chunks thread.Chunks
function M.top(f, chunks)
  if not f.foot then
    vim.api.nvim_win_set_config(f.win, { title = #chunks > 0 and chunks or ' ', title_pos = 'left' })
    return
  end
  local bar = { ' ' } ---@type string[]
  for _, c in ipairs(chunks) do
    bar[#bar + 1] = (c[2] and '%#' .. c[2] .. '#' or '%*') .. c[1]:gsub('%%', '%%%%')
  end
  vim.wo[f.win].winbar = table.concat(bar)
end

--- The bottom rows; over the code, the keys in the border's footer,
--- a bar between their groups.
---@param f thread.FrameWins
---@param said thread.FrameFoot
function M.bottom(f, said)
  if not f.foot then
    vim.api.nvim_win_set_config(f.win, { footer = look.grouped(said.keys), footer_pos = 'right' })
    return
  end
  local rows = said.line and { said.line, {} } or { {} } ---@type thread.Chunks[]
  local keys = {} ---@type { [1]: string, [2]: string }[]
  for _, g in ipairs(said.keys) do
    vim.list_extend(keys, g)
  end
  rows[#rows + 1] = M.spread(vim.list_extend({ { ' ' } }, hints(keys)), said.at and { { said.at, 'ThreadMeta' }, { ' ' } } or {}, vim.o.columns)
  if #rows ~= f.rows then
    M.place(f, #rows)
  end
  local buf = vim.api.nvim_win_get_buf(assert(f.foot))
  local lines, hls = {}, {} ---@type string[], { [1]: integer, [2]: integer, [3]: integer, [4]: string }[]
  for i, chunks in ipairs(rows) do
    local line = ''
    for _, c in ipairs(chunks) do
      if c[2] then
        hls[#hls + 1] = { i - 1, #line, #line + #c[1], c[2] }
      end
      line = line .. c[1]
    end
    lines[i] = line
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_set_extmark(buf, ns, h[1], h[2], { end_col = h[3], hl_group = h[4] })
  end
end

--- A review's tabs as the top row: `H ‹`, each tab's title, the one
--- shown lit, `› L`; its title on the right, dim, as far as it fits.
--- The top row starts a column in, so H is over the keys' first.
---@param titles string[]
---@param here integer  the one shown
---@param title string  the review's
---@param width integer  the window's
---@return thread.Chunks
function M.tabs(titles, here, title, width)
  width = width - 1
  local left = { { 'H', 'ThreadKey' }, { ' ‹ ', 'ThreadTabArrow' } } ---@type thread.Chunks
  for i, t in ipairs(titles) do
    vim.list_extend(left, { { ' ' .. t .. ' ', i == here and 'ThreadTabHere' or 'ThreadTab' }, { ' ' } })
  end
  vim.list_extend(left, { { '› ', 'ThreadTabArrow' }, { 'L', 'ThreadKey' } })
  local room = width - text.width(left) - 5
  if room < 12 then
    return left
  end
  return M.spread(left, { { text.fit(title, room), 'ThreadReviewTitle' }, { ' ' } }, width)
end

--- A page's top row: what is here, then where H and L go, the start of
--- each's title, the next pushed to the right; `here` empty, left out.
---@param here string
---@param before string|nil
---@param after string|nil
---@param width integer  the window's
---@param over boolean  in a float over the code
---@return thread.Chunks
function M.beside(here, before, after, width, over)
  -- Over the code the row is the border's, a line across it.
  local rule = over and '─' or ' '
  local out = {} ---@type thread.Chunks
  local room = width - 2
  if here ~= '' then
    here = text.fit(here, math.floor(room / 3))
    out[#out + 1] = { ' ' .. here .. ' ', 'FloatTitle' }
    room = room - text.width(here) - 2
  end
  -- Each side: `─ H ‹ title… ` and ` title… › L ─`.
  local each = math.floor((room - 4) / 2) - 8
  local left = before and { { rule .. ' ', 'FloatBorder' }, { 'H', 'ThreadKey' }, { ' ‹ ' .. text.fit(before, each) .. ' ', 'ThreadMeta' } } or {}
  local right = after and { { ' ' .. text.fit(after, each) .. ' › ', 'ThreadMeta' }, { 'L', 'ThreadKey' }, { ' ' .. rule, 'FloatBorder' } } or {}
  vim.list_extend(out, left)
  local used = 0
  for _, c in ipairs(out) do
    used = used + text.width(c[1])
  end
  for _, c in ipairs(right) do
    used = used + text.width(c[1])
  end
  if #right > 0 then
    out[#out + 1] = { string.rep(rule, math.max(1, width - 2 - used)), 'FloatBorder' }
    vim.list_extend(out, right)
  end
  return out
end

--- Close the bottom rows' window; the page's goes with the screen.
---@param f thread.FrameWins
function M.close(f)
  float.close(f.foot)
end

return M
