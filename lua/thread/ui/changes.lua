--- What changed since a revision, shown: in CodeDiff when it is installed
--- (thread.base.codediff), else in Vim's diff mode and the quickfix list.

local codediff = require 'thread.base.codediff'
local git = require 'thread.base.git'
local repo = require 'thread.base.repo'

local M = {}

--- Open one file's diff from `base` to the working tree, on `line`.
---@param base string
---@param file string  repo-relative
---@param line integer|nil
function M.open_file(base, file, line)
  local path = repo.path(file)
  vim.cmd.tabedit(vim.fn.fnameescape(path))
  local code_win = vim.api.nvim_get_current_win()
  local function land()
    if line and vim.api.nvim_win_is_valid(code_win) then
      pcall(vim.api.nvim_win_set_cursor, code_win, { line, 0 })
      vim.api.nvim_win_call(code_win, function()
        vim.cmd 'normal! zz'
      end)
    end
  end
  if codediff.available() then
    vim.cmd('CodeDiff file ' .. base)
    -- CodeDiff draws asynchronously; find the working file's window after.
    vim.defer_fn(function()
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)) == vim.fn.fnamemodify(path, ':p') then
          code_win = win
        end
      end
      land()
    end, 200)
    return
  end
  land()
  local ft = vim.bo.filetype
  vim.cmd 'leftabove vnew'
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, git.show(base, file) or {})
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = ft
  pcall(vim.api.nvim_buf_set_name, buf, string.format('%s @ %s', file, base:sub(1, 7)))
  vim.cmd 'diffthis'
  vim.api.nvim_set_current_win(code_win)
  vim.cmd 'diffthis'
  land()
end

--- Everything changed since a revision: CodeDiff's explorer, or the files
--- in the quickfix list.
---@param base string
function M.open_all(base)
  if codediff.available() then
    vim.cmd('CodeDiff ' .. base)
    return
  end
  local out = git.run { 'diff', '--name-only', base } or ''
  local items = {}
  for file in out:gmatch '[^\n]+' do
    items[#items + 1] = { filename = repo.path(file), lnum = 1, text = 'changed since ' .. base:sub(1, 7) }
  end
  vim.fn.setqflist({}, ' ', { title = 'thread: changed since ' .. base:sub(1, 7), items = items })
  vim.cmd 'copen'
end

return M
