--- What is drawn into the code besides bubbles and cards: a sign on every
--- line something covers, the notes of the thread or step you are on, and
--- a review's diff, its removed lines hung above where they went.

local bubble = require 'thread.code.bubble'
local chunk = require 'thread.model.chunk'
local diff = require 'thread.base.diff'
local hunks = require 'thread.ui.hunks'
local look = require 'thread.ui.look'
local prose = require 'thread.prose'
local sheet = require 'thread.ui.sheet'
local source = require 'thread.base.source'
local text = require 'thread.base.text'

local M = {}

---@class thread.Sign
---@field line integer
---@field text string  two columns
---@field hl string
---@field zone boolean|nil  the line is the current thread's or step's: washed

--- A sign on each line.
---@param buf integer
---@param ns integer
---@param signs thread.Sign[]
function M.signs(buf, ns, signs)
  for _, s in ipairs(signs) do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, s.line - 1, 0, {
      sign_text = s.text,
      sign_hl_group = s.hl,
      line_hl_group = s.zone and 'ThreadZone' or nil,
      priority = 20,
    })
  end
end

--- Notes on their lines: each line washed, its mark picked out, its
--- number and what it says at the line's end, or above the line when it
--- is too long to fit there.
---@param buf integer
---@param ns integer
---@param notes thread.Note[]
---@param spec thread.DiffSpec|nil  what their review is about
---@param room integer  the window's columns for text
function M.notes(buf, ns, notes, spec, room)
  local where = source.of_buf(buf)
  if not where then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for k, n in ipairs(notes) do
    local at = source.belongs(n, where) and chunk.locate(n, spec)
    if at and not at.old then
      local row = at.line - 1
      local last = math.min(#lines, at.line + (n.lines or 1) - 1) - 1
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, 0, { end_row = last + 1, end_col = 0, hl_eol = true, hl_group = 'ThreadNoteLine', priority = 12 })
      local s = n.mark and n.mark ~= '' and (lines[at.line] or ''):find(n.mark, 1, true)
      if s then
        pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, s - 1, { end_col = s - 1 + #n.mark, hl_group = 'ThreadNoteMark', priority = 140 })
      end
      local said = n.note or ''
      local free = room - text.width(lines[at.line] or '') - 6
      if text.width(said) <= free then
        pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, 0, {
          virt_text = { { '  ' .. look.num(k), 'ThreadNoteNum' }, { said ~= '' and (' ' .. said) or '', 'ThreadNote' } },
          virt_text_pos = 'eol',
          priority = 130,
        })
      else
        local indent = text.width((lines[at.line] or ''):match '^%s*')
        local P = sheet.new()
        prose.draw(P, said, math.max(20, room - indent - 6), { lead = { look.num(k) .. ' ', 'ThreadNoteNum' }, hl = 'ThreadNote' })
        local rows = {} ---@type thread.VirtChunk[][]
        for i = 0, #P.lines - 1 do
          local line = { { string.rep(' ', indent), 'Normal' } } ---@type thread.VirtChunk[]
          rows[#rows + 1] = vim.list_extend(line, bubble.chunks(P, i, 0, 'ThreadNote'))
        end
        pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, 0, { virt_lines = rows, virt_lines_above = true, priority = 105 })
      end
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

return M
