--- The names a walked step's text puts in backticks, lit where they are
--- in its chunk in the code: the text says `start`, and `start` stands
--- out in the lines it is about.

local prose = require 'thread.prose'
local theme = require 'thread.ui.theme'

local M = {}

--- What a name in backticks is looked for as: as written, and a call
--- without its arguments, `load(read)` as `load`. One letter is no name.
---@param written string
---@return string[]
local function forms(written)
  local out = {}
  local s = vim.trim(written)
  if #s < 2 then
    return out
  end
  out[1] = s
  local callee = s:match '^([%w_%.:]+)%b()$'
  if callee and #callee >= 2 then
    out[2] = callee
  end
  return out
end

--- The names in backticks in a step's text, each once.
---@param s thread.Step
---@param r thread.Review
---@return string[]
function M.of(s, r)
  local out, seen = {}, {} ---@type string[], table<string, true>
  ---@param spans thread.Span[]|nil
  local function take(spans)
    for _, sp in ipairs(spans or {}) do
      if sp.code and not sp.link then
        for _, f in ipairs(forms(sp.text)) do
          if not seen[f] then
            seen[f], out[#out + 1] = true, f
          end
        end
      end
    end
  end
  for _, b in ipairs(prose.parse(s.text, r)) do
    take(b.spans)
    for _, row in ipairs(b.cells or {}) do
      for _, cell in ipairs(row) do
        take(cell)
      end
    end
  end
  return out
end

--- Whether a byte is part of a word.
---@param c string
---@return boolean
local function word(c)
  return c ~= '' and c:match '[%w_]' ~= nil
end

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

--- Light each name where it stands whole in lines `from` to `to`, not
--- inside a longer word, in its own colour lifted (thread.ui.theme.named).
---@param buf integer
---@param ns integer
---@param from integer  1-based
---@param to integer
---@param names string[]
function M.paint(buf, ns, from, to, names)
  if #names == 0 then
    return
  end
  -- Their colours are read from treesitter, which a buffer just opened
  -- has not parsed yet.
  local ok, parser = pcall(vim.treesitter.get_parser, buf, nil, { error = false })
  if ok and parser then
    pcall(parser.parse, parser, true)
  end
  local lines = vim.api.nvim_buf_get_lines(buf, from - 1, to, false)
  for i, line in ipairs(lines) do
    for _, n in ipairs(names) do
      local at = 1
      while true do
        local s, e = line:find(n, at, true)
        if not s then
          break
        end
        local whole = not (word(n:sub(1, 1)) and word(line:sub(s - 1, s - 1))) and not (word(n:sub(-1)) and word(line:sub(e + 1, e + 1)))
        if whole then
          local row = from + i - 2
          pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, s - 1, { end_col = e, hl_group = theme.named(colour(buf, row, s - 1 + key(n))), priority = 210 })
        end
        at = e + 1
      end
    end
  end
end

return M
