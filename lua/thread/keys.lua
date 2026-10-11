--- Keys thread.nvim lays over yours, and gives back.

local M = {}

--- The global normal-mode mapping of `lhs`, as maparg() gives it, ignoring
--- any mapping the current buffer has of its own.
---@param lhs string
---@return table|nil
function M.global(lhs)
  local want = vim.keycode(lhs)
  for _, m in ipairs(vim.api.nvim_get_keymap 'n') do
    if vim.keycode(m.lhs) == want then
      return m
    end
  end
end

return M
