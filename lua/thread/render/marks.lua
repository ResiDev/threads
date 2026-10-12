--- What is drawn into the code besides the bubbles: a thread's notes on
--- their lines, the changes its agent made, and everything but the thread
--- you are on dimmed.

local anchor = require 'thread.base.anchor'
local code = require 'thread.base.code'
local config = require 'thread.config'
local look = require 'thread.ui.look'
local text = require 'thread.base.text'

local M = {}

local ns = vim.api.nvim_create_namespace 'thread'

--- The function or block around lines `lo`..`hi` of a buffer, by
--- treesitter; else the paragraph.
local function scope(bufnr, lo, hi)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if ok and parser then
    local tok, trees = pcall(parser.parse, parser)
    local root = tok and trees and trees[1] and trees[1]:root()
    if root then
      local slo, shi = code.enclosing(root, lo, hi)
      if slo then
        return slo, shi
      end
    end
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  while lo > 1 and (lines[lo - 1] or ''):match '%S' do
    lo = lo - 1
  end
  while hi < #lines and (lines[hi + 1] or ''):match '%S' do
    hi = hi + 1
  end
  return lo, hi
end

--- The notes of a thread's latest message that has any, on their lines: a
--- number, the note after the code or hung above it when it is long, the
--- line washed and its mark picked out.
function M.notes(bufnr, c, room)
  local notes
  for i = #c.messages, 1, -1 do
    if c.messages[i].notes and #c.messages[i].notes > 0 then
      notes = c.messages[i].notes
      break
    end
  end
  local where = anchor.of_buf(bufnr)
  if not (notes and where) then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for k, n in ipairs(notes) do
    local note = vim.tbl_extend('keep', n, { file = c.file, rev = c.rev })
    if anchor.belongs(note, where) then
      local loc = anchor.locate(note, lines)
      if loc then
        local row = loc.line - 1
        local last = math.min(#lines, loc.line + (note.lines or 1) - 1) - 1
        local num = look.num(k)
        pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, row, 0, {
          end_row = last + 1,
          end_col = 0,
          hl_eol = true,
          hl_group = 'ThreadNoteLine',
          priority = 12,
        })
        if type(note.mark) == 'string' and note.mark ~= '' then
          local s = (lines[loc.line] or ''):find(note.mark, 1, true)
          if s then
            pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, row, s - 1, { end_col = s - 1 + #note.mark, hl_group = 'ThreadNoteMark', priority = 140 })
          end
        end
        local said = type(note.note) == 'string' and note.note or ''
        local free = room - text.width(lines[loc.line] or '') - 6
        if said == '' or text.width(said) <= free then
          pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, row, 0, {
            virt_text = { { '  ' .. num, 'ThreadNoteNum' }, { said ~= '' and (' ' .. said) or '', 'ThreadNote' } },
            virt_text_pos = 'eol',
            priority = 130,
          })
        else
          local indent = text.width((lines[loc.line] or ''):match '^%s*')
          local rows = {}
          for i, l in ipairs(text.wrap(said, math.max(20, math.min(config.options.ui.width, room - indent - 6)))) do
            rows[#rows + 1] = { { string.rep(' ', indent), 'Normal' }, { i == 1 and (num .. ' ') or '  ', 'ThreadNoteNum' }, { l.text, 'ThreadNote' } }
          end
          pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, row, 0, { virt_lines = rows, virt_lines_above = true, priority = 105 })
        end
      end
    end
  end
end

--- A thread's changes drawn into the code: what each replaced, hung above
--- the lines that replaced it, and those lines washed.
function M.changes(bufnr, batch, c)
  local where = anchor.of_buf(bufnr)
  if not where or where.rev then
    return
  end
  local git = require 'thread.base.git'
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i = #c.messages, 1, -1 do
    local m = c.messages[i]
    if m.changes and #m.changes > 0 then
      local base = git.base_for(batch, c, i)
      local done = {} -- hunks drawn already: two changes may share one
      for _, ch in ipairs(m.changes) do
        if ch.file == where.file and base then
          local old = git.show(base, ch.file)
          if old then
            local loc = anchor.locate(ch, lines)
            local at = loc and loc.line or ch.line or 1
            local hunks, words = git.word_hunks(old, lines)
            local near = {}
            for _, h in ipairs(hunks) do
              local s = h.new_start
              local e = h.new_count == 0 and s + 1 or s + h.new_count - 1
              local key = h.old_start .. ':' .. h.new_start
              if not done[key] and e >= at - 1 and s <= at + (ch.lines or 1) then
                done[key] = true
                near[#near + 1] = { new_start = h.new_start, new_count = h.new_count, old = vim.list_slice(old, h.old_start, h.old_start + h.old_count - 1) }
              end
            end
            require('thread.ui.hunks').draw(
              bufnr,
              ns,
              near,
              words and { add = 'CodeDiffLineInsert', del = 'CodeDiffLineDelete' } or { add = 'DiffAdd', del = 'DiffDelete' }
            )
          end
        end
      end
      return
    end
  end
end

--- Dim everything but the function or block around lines `lo`..`hi`.
---@param bufnr integer
function M.dim(bufnr, lo, hi)
  lo, hi = scope(bufnr, lo, hi)
  local count = vim.api.nvim_buf_line_count(bufnr)
  if lo > 1 then
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, 0, 0, { end_row = lo - 1, end_col = 0, hl_group = 'ThreadDim', priority = 150 })
  end
  if hi < count then
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, hi, 0, { end_row = count, end_col = 0, hl_group = 'ThreadDim', priority = 150 })
  end
end

return M
