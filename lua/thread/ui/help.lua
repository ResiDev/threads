--- Keys and what they do, in a float in the middle of the editor: a
--- section a heading, its rows a key and what it does, each description
--- wrapped under itself. `q`, `?`, `g?`, `Esc` or `⏎` closes it.

local float = require 'thread.ui.float'
local sheet = require 'thread.ui.sheet'
local text = require 'thread.base.text'

local M = {}

local ns = vim.api.nvim_create_namespace 'thread.help'

-- Columns the keys take, before what each does.
local KEY = 10

-- The help is this wide at most, so a description reads as lines, not one
-- row across the screen.
local WIDEST = 96

--- A section: a heading, and its rows, each a key and what it does; or
--- lines drawn as they are.
---@class thread.HelpSection
---@field head string
---@field rows { [1]: string, [2]: string }[]|nil
---@field lines thread.Chunks[]|nil

---@param sections thread.HelpSection[]
---@param width integer
---@return thread.Sheet
local function content(sections, width)
  local P = sheet.new { indent = 4 }
  -- The float's border and a column either side of the text.
  local room = math.max(20, width - 4 - KEY - 2)
  for _, s in ipairs(sections) do
    P.add ''
    P.chunks({ { s.head, 'ThreadTitle' } }, 2)
    for _, line in ipairs(s.lines or {}) do
      P.chunks(line)
    end
    for _, row in ipairs(s.rows or {}) do
      for i, line in ipairs(text.wrap(row[2], room)) do
        P.chunks { { text.pad(i == 1 and row[1] or '', KEY), 'ThreadKey' }, { line, 'ThreadKeyLabel' } }
      end
    end
  end
  P.add ''
  return P
end

--- Open it; `done` runs once it closes.
---@param title string
---@param sections thread.HelpSection[]
---@param done fun()|nil
function M.open(title, sections, done)
  local P = content(sections, math.min(WIDEST, vim.o.columns - 4))
  local width = 0
  for _, l in ipairs(P.lines) do
    width = math.max(width, text.width(l) + 2)
  end
  local win ---@type integer
  local function close()
    if vim.api.nvim_win_is_valid(win) then
      float.close(win)
      if done then
        done()
      end
    end
  end
  local keys = {} ---@type table<string, fun()>
  for _, lhs in ipairs { 'q', '?', 'g?', '<Esc>', '<CR>' } do
    keys[lhs] = close
  end
  local cfg = float.centred(width, #P.lines)
  local buf
  win, buf =
    float.open { win = vim.tbl_extend('force', cfg, { title = ' ' .. title .. ' ', title_pos = 'center', zindex = 60 }), keys = keys, on_leave = close }
  P.apply(buf, ns)
end

return M
