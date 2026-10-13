--- A note: a line a message or a step points at, a word on it picked
--- out, and what it says. Where it is in the code is its chunk's; here is
--- what drawing it anywhere shares: its number, where its mark is on its
--- line, and what it says, listed under its number.

local excerpt = require 'thread.prose.excerpt'
local look = require 'thread.ui.look'
local prose = require 'thread.prose'
local text = require 'thread.base.text'

local M = {}

--- A note's number, `①`, by its place among its message's or step's.
---@param k integer
---@return string
function M.num(k)
  return look.num(k)
end

--- Where a note's mark is on its line: byte columns, from 0, its end not
--- in it. Nil with no mark, or one not on the line.
---@param n thread.Note
---@param line string  its line as it reads now
---@return integer|nil s, integer|nil e
function M.mark(n, line)
  if not n.mark or n.mark == '' then
    return nil
  end
  local s = line:find(n.mark, 1, true)
  if s then
    return s - 1, s - 1 + #n.mark
  end
end

--- What a note says, under its number: `① the only check`, wrapped to
--- `width` and hung under its text, an excerpt in it drawn as its code.
--- Nothing when it says nothing.
---@param P thread.Sheet
---@param k integer
---@param n thread.Note
---@param width integer
---@param o thread.ProseOpts|nil
---@return thread.Drawn[]  what in it goes somewhere
function M.draw(P, k, n, width, o)
  o = o or {}
  local indent = o.indent or P.indent
  local out = {} ---@type thread.Drawn[]
  if not n.note or vim.trim(n.note) == '' then
    return out
  end
  local num = M.num(k) .. ' '
  local hang = string.rep(' ', text.width(num))
  local head = num
  for _, r in ipairs(prose.rows(n.note, width - #hang)) do
    if r.excerpt then
      if head == num then
        P.chunks({ { num, 'ThreadNoteNum' } }, indent)
      end
      local first, last = excerpt.draw(P, r.excerpt, o.spec, indent + #hang, width - #hang)
      out[#out + 1] = { first = first, last = last, excerpt = r.excerpt }
    else
      local chunks = { { head, 'ThreadNoteNum' } }
      for _, c in ipairs(r.chunks) do
        chunks[#chunks + 1] = { c[1], c[2] == 'ThreadText' and 'ThreadNote' or c[2] }
      end
      local row = P.chunks(chunks, indent)
      for _, sp in ipairs(r.spots) do
        out[#out + 1] = { first = row, last = row, s = indent + #head + sp.first, e = indent + #head + sp.last, link = sp.link, name = sp.name }
      end
    end
    head = hang
  end
  return out
end

return M
