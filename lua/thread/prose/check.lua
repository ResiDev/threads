--- What `show.lua --check` reads in a review's prose, beside what the
--- model checks as it reads (thread.model.review) and in the code
--- (thread.model.review.unfound): in everything the agent wrote, each
--- link goes to something there is, and each fence is closed. A link to
--- nothing is a warning, since `#note:12` can be text about one. Your
--- messages are yours, so they are not read.

local fields = require 'thread.model.fields'
local link = require 'thread.prose.link'
local prose = require 'thread.prose'
local review = require 'thread.model.review'

local M = {}

---@param r thread.Review
---@param get fun(id: string): thread.Review|nil, string|nil  another review by its id, for `other#note:12`, or why it cannot be read
---@return thread.Problems
function M.review(r, get)
  local p = fields.problems()
  for _, x in ipairs(review.prose(r)) do
    if x.from == 'agent' then
      for _, b in ipairs(prose.parse(x.prose, r)) do
        if b.unclosed then
          fields.warn(p, x.where, 'a ``` fence is never closed, so all after it shows as code: end it with ``` on a line of its own')
        end
        local spans = vim.list_extend({}, b.spans or {})
        for _, row in ipairs(b.cells or {}) do
          for _, cell in ipairs(row) do
            vim.list_extend(spans, cell)
          end
        end
        for _, sp in ipairs(spans) do
          if sp.link then
            local _, why = link.follow(sp.link, r, get)
            if why then
              fields.warn(p, x.where, why)
            end
          elseif not sp.code then
            for kind in sp.text:gmatch '#(%l+):%d' do
              if not vim.tbl_contains(link.KINDS, kind) then
                fields.warn(p, x.where, string.format('`#%s:` is no link: a link names a step, a note or a contract, `#step:7`', kind))
              end
            end
            for wiki in sp.text:gmatch '%[%[[^%]]*%]%]' do
              fields.warn(p, x.where, string.format('`%s` is no link and shows as written: a link is `#step:7`, `#note:12` or `#contract:3`', wiki))
            end
          end
        end
      end
    end
  end
  return p
end

return M
