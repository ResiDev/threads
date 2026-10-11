--- What a screen is built into before it is drawn: its lines, the
--- highlights and marks on them, who owns each line, and the items on it
--- that the cursor steps through. `apply` puts it in a buffer.
---
--- Rows are 0-based, as extmarks count them; a highlight's end of -1 runs
--- to the end of its line.

local text = require 'thread.text'

local M = {}

---@class thread.Item
---@field first integer  its first row, 0-based
---@field last integer

---@class thread.Sheet
---@field lines string[]
---@field hls table[]    { row, start, end, group, opts }
---@field marks table[]  { row, col, opts }
---@field owner table<integer, any>  line (1-based) -> who owns it
---@field items thread.Item[]
---@field indent integer  where rows of chunks start

---@param opts { indent: integer|nil, priority: integer|nil }|nil
---  `priority`: what a highlight gets when it names none
---@return thread.Sheet
function M.new(opts)
  opts = opts or {}
  local P = { lines = {}, hls = {}, marks = {}, owner = {}, items = {}, indent = opts.indent or 0 }
  local owner, open

  --- The rows added from now on belong to `who`.
  function P.own(who)
    owner = who
  end

  ---@return integer row
  function P.add(line)
    P.lines[#P.lines + 1] = line
    P.owner[#P.lines] = owner
    return #P.lines - 1
  end

  function P.hl(row, s, e, group, hl_opts)
    if group then
      P.hls[#P.hls + 1] = { row, s, e, group, hl_opts }
    end
  end

  function P.mark(row, col, mark_opts)
    P.marks[#P.marks + 1] = { row, col, mark_opts }
  end

  --- A row of chunks `{ text, hl }`, from `indent` (else the sheet's).
  ---@return integer row
  function P.chunks(chunks, indent)
    local line = string.rep(' ', indent or P.indent)
    local spans = {}
    for _, c in ipairs(chunks) do
      if c[1] ~= '' then
        spans[#spans + 1] = { #line, #line + #c[1], c[2] }
        line = line .. c[1]
      end
    end
    local row = P.add(line)
    for _, sp in ipairs(spans) do
      P.hl(row, sp[1], sp[2], sp[3])
    end
    return row
  end

  --- A row of chunks, and `right` pushed to end at column `width` (from
  --- the indent), at least two columns after them.
  ---@return integer row
  function P.spread(chunks, right, width)
    local used = text.width(chunks)
    local row = vim.list_extend({}, chunks)
    row[#row + 1] = { string.rep(' ', math.max(2, width - used - text.width(right[1]))) .. right[1], right[2] }
    return P.chunks(row)
  end

  --- Start an item on the next row; `done` ends it on the last row so far.
  function P.item(it)
    P.done()
    it.first = #P.lines
    P.items[#P.items + 1] = it
    open = it
    return it
  end

  function P.done()
    if open then
      open.last = math.max(open.first, #P.lines - 1)
      open = nil
    end
  end

  --- Write it into `buf`, left read-only: its lines, then its highlights
  --- and marks in `ns`.
  function P.apply(buf, ns)
    P.done()
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, P.lines)
    vim.bo[buf].modifiable = false
    vim.bo[buf].modified = false
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for _, h in ipairs(P.hls) do
      local len = #(P.lines[h[1] + 1] or '')
      local mark = { end_col = (h[3] < 0 or h[3] > len) and len or h[3], hl_group = h[4], priority = opts.priority }
      for k, v in pairs(h[5] or {}) do
        mark[k] = v
      end
      if mark.hl_eol then
        mark.end_row, mark.end_col = h[1] + 1, 0
      end
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, h[1], math.min(h[2], len), mark)
    end
    for _, m in ipairs(P.marks) do
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, m[1], m[2], m[3])
    end
  end

  return P
end

return M
