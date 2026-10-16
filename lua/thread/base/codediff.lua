--- CodeDiff's revision buffers, when it is installed: the file and the
--- revision one holds, so its code is read as that revision.

local M = {}

--- The file a CodeDiff revision buffer holds: codediff:///<root>///<rev>/<path>.
---@param name string  a buffer's name
---@return string|nil root, string|nil rev, string|nil path
function M.buffer(name)
  local root, rev, path = name:match '^codediff:///(.-)///([^/]+)/(.+)$'
  if root then
    return root, rev, path
  end
end

return M
