--- A walked step's highlights, lit where they are in its chunk in the
--- code: the text says `start`, and `start` stands out in the lines it is
--- about.

local highlight = require 'thread.prose.highlight'
local theme = require 'thread.ui.theme'

local M = {}

--- The colour code is drawn in at a place: an LSP's semantic token's over
--- treesitter's, as on screen; nil when neither colours it.
---@param buf integer
---@param row integer  0-based
---@param col integer  0-based, in bytes
---@return integer|nil
local function colour(buf, row, col)
  local ok, at = pcall(vim.inspect_pos, buf, row, col, { syntax = false, extmarks = false, treesitter = true, semantic_tokens = true })
  if not ok then
    return nil
  end
  local fg, best ---@type integer|nil, integer|nil
  for _, c in ipairs(at.treesitter or {}) do
    fg = vim.api.nvim_get_hl(0, { name = c.hl_group, link = false }).fg or fg
  end
  for _, t in ipairs(at.semantic_tokens or {}) do
    local def = vim.api.nvim_get_hl(0, { name = t.opts.hl_group, link = false })
    if def.fg and (not best or t.opts.priority >= best) then
      fg, best = def.fg, t.opts.priority
    end
  end
  return fg
end

--- Where in a name its colour is read: its last word before any call,
--- `parse` of `M.parse`, `get` of `M.get(store, key)`. 0-based.
---@param n string
---@return integer
local function key(n)
  local head = n:match '^[^(]*'
  return (head:find '[%w_]+$' or 1) - 1
end

--- Light each highlight where it stands whole in the chunk from line
--- `from`, in its own colour lifted (thread.ui.theme.named). With one
--- current (`current` > 0), it stands out and its lines are washed, the
--- rest quieter.
---@param buf integer
---@param ns integer
---@param from integer  the chunk's first line, 1-based
---@param list thread.Highlight[]
---@param current integer  0: none
function M.paint(buf, ns, from, list, current)
  if #list == 0 then
    return
  end
  -- Their colours are read from treesitter, which a buffer just opened
  -- has not parsed yet.
  local ok, parser = pcall(vim.treesitter.get_parser, buf, nil, { error = false })
  if ok and parser then
    pcall(parser.parse, parser, true)
  end
  for _, h in ipairs(list) do
    local here = h.n == current
    for _, i in ipairs(h.rows) do
      local row = from + i - 2
      local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ''
      for _, at in ipairs(highlight.find(line, h.text)) do
        local hl = here and 'ThreadHighlightHere' or theme.named(colour(buf, row, at[1] - 1 + key(h.text)), current > 0)
        pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, at[1] - 1, { end_col = at[2], hl_group = hl, priority = here and 220 or 210 })
      end
      if here then
        -- A wash, not `line_hl_group`, which would cover the names' own.
        pcall(
          vim.api.nvim_buf_set_extmark,
          buf,
          ns,
          row,
          0,
          { end_row = row + 1, end_col = 0, hl_group = 'ThreadHighlightLine', hl_eol = true, priority = 13, strict = false }
        )
      end
    end
  end
end

return M
