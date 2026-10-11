--- Changes drawn into the code: what each hunk removed, hung above where
--- it was in the colour of a deletion, and the lines it added washed.
--- The buffer's text is never touched.

local M = {}

---@class thread.DrawnHunk
---@field new_start integer  with new_count 0: the line the removal follows
---@field new_count integer
---@field old string[]       the lines it removed

---@param bufnr integer
---@param ns integer
---@param hunks thread.DrawnHunk[]
---@param hl { add: string, del: string }
function M.draw(bufnr, ns, hunks, hl)
  local count = vim.api.nvim_buf_line_count(bufnr)
  local win = vim.fn.bufwinid(bufnr)
  local width = win ~= -1 and vim.api.nvim_win_get_width(win) or 200
  for _, h in ipairs(hunks) do
    if #h.old > 0 then
      local removed = {}
      for _, l in ipairs(h.old) do
        local line = l:gsub('\t', '    ')
        -- Padded across the window, so the colour reads as a line.
        removed[#removed + 1] = { { line .. string.rep(' ', math.max(0, width - vim.fn.strdisplaywidth(line))), hl.del } }
      end
      -- Above the lines that replaced them; a removal hangs above the line
      -- after it, or at the end of the file below the last.
      local above = h.new_count > 0 or h.new_start < count
      local row = h.new_count > 0 and h.new_start - 1 or (above and h.new_start or count - 1)
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, math.max(0, math.min(row, count - 1)), 0, {
        virt_lines = removed,
        virt_lines_above = above,
        priority = 100,
      })
    end
    if h.new_count > 0 then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, h.new_start - 1, 0, {
        end_row = math.min(count, h.new_start - 1 + h.new_count),
        end_col = 0,
        hl_eol = true,
        hl_group = hl.add,
        priority = 11,
      })
    end
  end
end

return M
