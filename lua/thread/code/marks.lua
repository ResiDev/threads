--- What is drawn into the code besides bubbles and cards: a sign on every
--- line something covers, and a review's diff, its removed lines hung
--- above where they went.

local diff = require 'thread.base.diff'
local hunks = require 'thread.ui.hunks'
local source = require 'thread.base.source'

local M = {}

---@class thread.Sign
---@field line integer
---@field text string  two columns
---@field hl string
---@field zone boolean|nil  the line is the current note's or step's: washed

--- A sign on each line.
---@param buf integer
---@param ns integer
---@param signs thread.Sign[]
function M.signs(buf, ns, signs)
  for _, s in ipairs(signs) do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, s.line - 1, 0, {
      sign_text = s.text,
      sign_hl_group = s.hl,
      line_hl_group = s.zone and 'ThreadZone' or nil,
      priority = 20,
    })
  end
end

--- A review's diff in the code: what it removed hung above where it was,
--- what it added washed. Only a diff that ends at the working tree, which
--- is what the buffer holds.
---@param buf integer
---@param ns integer
---@param spec thread.DiffSpec
---@param marks table<integer, string[]>|nil  a removed line's number -> a chunk said at its end
function M.diff(buf, ns, spec, marks)
  local where = source.of_buf(buf)
  if not where or where.rev or spec.new ~= nil then
    return
  end
  local f = diff.file(spec, where.file)
  if not f then
    return
  end
  local parts = {} ---@type thread.DiffPart[]
  for _, h in ipairs(f.hunks) do
    vim.list_extend(parts, h.parts)
  end
  hunks.draw(buf, ns, parts, { add = 'ThreadDiffAdd', del = 'ThreadDiffDelete', marks = marks })
end

return M
