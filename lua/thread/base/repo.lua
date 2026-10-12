--- The repository the editor is in, and paths in it.

local M = {}

local roots = {} -- cwd -> repo root

--- The repository the editor is in: git's top level, or the cwd outside git.
---@return string
function M.root()
  local cwd = vim.fn.getcwd()
  if not roots[cwd] then
    local out = vim.system({ 'git', '-C', cwd, 'rev-parse', '--show-toplevel' }, { text = true }):wait()
    roots[cwd] = out.code == 0 and vim.trim(out.stdout) or cwd
  end
  return roots[cwd]
end

--- A file in the repository, from its path relative to the root.
---@param file string
---@return string
function M.path(file)
  return M.root() .. '/' .. file
end

return M
