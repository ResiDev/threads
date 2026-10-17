--- What is drawn into the code besides bubbles and cards: a sign on every
--- line something covers, the lines of what the cursor is on washed, a
--- review's diff, its removed lines hung above where they went, and a
--- walk's dim around its step.

local diff = require 'thread.base.diff'
local hunks = require 'thread.ui.hunks'
local source = require 'thread.base.source'

local M = {}

---@class thread.Sign
---@field line integer
---@field text string  two columns
---@field hl string
---@field zone boolean|nil  the line is the current note's or step's: washed

--- A sign on each line.
---@param buf integer
---@param ns integer
---@param signs thread.Sign[]
function M.signs(buf, ns, signs)
  for _, s in ipairs(signs) do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, s.line - 1, 0, {
      sign_text = s.text,
      sign_hl_group = s.hl,
      -- Its own colour on the cursor's line too, which CursorLineSign
      -- would otherwise take, hiding a note's bracket where you are.
      cursorline_hl_group = s.hl,
      priority = 20,
    })
    if s.zone then
      -- A wash, not `line_hl_group`, which would cover every other
      -- background on the line, a lit name's too. Over the diff's added
      -- lines (11), under all else.
      pcall(
        vim.api.nvim_buf_set_extmark,
        buf,
        ns,
        s.line - 1,
        0,
        { end_row = s.line, end_col = 0, hl_group = 'ThreadZone', hl_eol = true, priority = 12, strict = false }
      )
    end
  end
end

--- A review's diff in the code: what it removed hung above where it was,
--- what it added washed. Only a diff that ends at the working tree, which
--- is what the buffer holds.
---@param buf integer
---@param ns integer
---@param spec thread.DiffSpec
---@param marks table<integer, string[]>|nil  a removed line's number -> a chunk said at its end
function M.diff(buf, ns, spec, marks)
  local where = source.of_buf(buf)
  if not where or where.rev or spec.new ~= nil then
    return
  end
  local f = diff.file(spec, where.file)
  if not f then
    return
  end
  local parts = {} ---@type thread.DiffPart[]
  for _, h in ipairs(f.hunks) do
    vim.list_extend(parts, h.parts)
  end
  hunks.draw(buf, ns, parts, { add = 'ThreadDiffAdd', del = 'ThreadDiffDelete', marks = marks })
end

--- Wash every line but `from` to `to` quiet: the foreground only, over
--- treesitter's, so the lines left read as the only ones at full colour.
---@param buf integer
---@param ns integer
---@param from integer  1-based
---@param to integer
function M.dim(buf, ns, from, to)
  local last = vim.api.nvim_buf_line_count(buf)
  for _, r in ipairs { { 0, from - 1 }, { to, last } } do
    if r[2] > r[1] then
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, r[1], 0, { end_row = r[2], end_col = 0, hl_group = 'ThreadDim', priority = 200, strict = false })
    end
  end
end

return M
