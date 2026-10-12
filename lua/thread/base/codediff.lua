--- CodeDiff, when it is installed: its revision buffers, its diff engine
--- (the changed words in each line) and its views. Everything thread.nvim
--- knows about CodeDiff is here; without it, git.lua falls back to Vim's own
--- diff.

local config = require 'thread.config'

local M = {}

local function wanted()
  return config.options.ui.diff ~= 'builtin'
end

--- The file a CodeDiff revision buffer holds: codediff:///<root>///<rev>/<path>.
---@param name string  a buffer's name
---@return string|nil root, string|nil rev, string|nil path
function M.buffer(name)
  local root, rev, path = name:match '^codediff:///(.-)///([^/]+)/(.+)$'
  if root then
    return root, rev, path
  end
end

local engine -- its diff module once found, or false when it is not there

--- CodeDiff's diff of two files' lines, as it draws them: changes with the
--- words that changed inside them; nil without CodeDiff.
---@param old string[]
---@param new string[]
---@return table|nil
function M.compute(old, new)
  if not wanted() then
    return nil
  end
  if engine == nil then
    local ok, d = pcall(require, 'codediff.core.diff')
    engine = ok and d or false
  end
  if not engine then
    return nil
  end
  -- Its colours are set when it starts; it may not have yet.
  if vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = 'CodeDiffLineInsert' })) then
    local ok, hl = pcall(require, 'codediff.ui.highlights')
    if ok then
      pcall(hl.setup)
    end
  end
  local ok, res = pcall(engine.compute_diff, old, new, {})
  return ok and res or nil
end

--- Whether CodeDiff can show a diff: installed, and not turned off.
function M.available()
  return wanted() and vim.fn.exists ':CodeDiff' == 2
end

--- Show the current file's diff from `base`, or every file's when `all`.
function M.open(base, all)
  vim.cmd('CodeDiff ' .. (all and '' or 'file ') .. base)
end

return M
