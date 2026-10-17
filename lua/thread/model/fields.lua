--- Reading what the agent wrote, a field at a time, and saying what is
--- wrong for the agent: where it is, and what to write instead. Each
--- primitive's parse uses these, and the problems add up over the file.
--- What is read is checked in place: the table read is the one returned.

local M = {}

---@class thread.Problems
---@field errors string[]    what stops the review being read
---@field warnings string[]  what reads, but could say more

---@return thread.Problems
function M.problems()
  return { errors = {}, warnings = {} }
end

---@param p thread.Problems
---@param where string  `note 12, message 2`
---@param msg string
function M.bad(p, where, msg)
  p.errors[#p.errors + 1] = where .. ': ' .. msg
end

---@param p thread.Problems
---@param where string
---@param msg string
function M.warn(p, where, msg)
  p.warnings[#p.warnings + 1] = where .. ': ' .. msg
end

-- Fields of shapes before this one, and where what they held went,
-- wherever they turn up; an object's own are said where it is read.
local GONE = {
  format = 'a review has no format number: write it as the skill says',
  threads = "a review's `tours` walk the change, and anything else is one of its `notes`",
  groups = 'tours are what groups were',
  rounds = 'a message of yours has its `at`; nothing else counts rounds',
  round = 'a message of yours has its `at`; nothing else counts rounds',
  checks = 'what the agent ran goes in its prose',
  verdict = 'an issue is a note of `kind` "issue", on the same chunk',
  risk = 'a risk is a note of `kind` "issue" with `issue` "risk"',
  risk_why = 'a risk is a note of `kind` "issue" with `issue` "risk"',
  diagram = 'prose has `diagrams`, by name, each placed in its text with `{{diagram:name}}`',
  notes = 'what a mark on a line said goes in the text, naming the code in backticks',
  walk = "a review's `tours`",
  body = 'it is `text`',
}

local sets = setmetatable({}, { __mode = 'k' }) ---@type table<string[], table<string, true>>

--- Whether `raw` is an object whose every field `known` names.
---@param p thread.Problems
---@param where string
---@param raw any
---@param known string[]
---@param gone table<string, string>|nil  its own fields from before, and where they went
---@return boolean
function M.object(p, where, raw, known, gone)
  if type(raw) ~= 'table' or (next(raw) ~= nil and vim.islist(raw)) then
    M.bad(p, where, 'must be an object')
    return false
  end
  local set = sets[known]
  if not set then
    set = {}
    for _, k in ipairs(known) do
      set[k] = true
    end
    sets[known] = set
  end
  local names = vim.tbl_keys(raw)
  table.sort(names, function(a, b)
    return tostring(a) < tostring(b)
  end)
  for _, k in ipairs(names) do
    if not set[k] then
      local went = (gone and gone[k]) or GONE[k]
      M.bad(p, where, string.format('`%s` is not a field%s', tostring(k), went and ('; ' .. went) or (' (it has ' .. table.concat(known, ', ') .. ')')))
    end
  end
  return true
end

--- A string. `need`: it must be there, and not blank.
---@param p thread.Problems
---@param where string
---@param raw table
---@param name string
---@param need boolean|nil
---@return string|nil
function M.text(p, where, raw, name, need)
  local v = raw[name]
  if v == nil then
    if need then
      M.bad(p, where, string.format('no `%s`', name))
    end
    return nil
  end
  if type(v) ~= 'string' then
    M.bad(p, where, string.format('`%s` must be a string', name))
    return nil
  end
  if need and vim.trim(v) == '' then
    M.bad(p, where, string.format('`%s` is blank', name))
    return nil
  end
  return v
end

--- Whether `s` is one line: no line breaks, tabs or other control
--- characters, so it is drawn as one row as wide as it measures.
---@param s string
---@return boolean
function M.is_line(s)
  return not s:find '%c'
end

--- `s` made one line (M.is_line), for a title the plugin makes from what
--- you wrote: each run of spaces, line breaks, tabs and other control
--- characters one space.
---@param s string
---@return string
function M.to_line(s)
  return (s:gsub('[%s%c]+', ' '))
end

--- A string that is one line (M.is_line): every one the agent writes that
--- is not prose or code. `need`: it must be there, and not blank.
---@param p thread.Problems
---@param where string
---@param raw table
---@param name string
---@param need boolean|nil
---@return string|nil
function M.line(p, where, raw, name, need)
  local v = M.text(p, where, raw, name, need)
  if v and not M.is_line(v) then
    M.bad(p, where, string.format('`%s` is one line, with no line breaks or tabs', name))
    return nil
  end
  return v
end

--- A whole number, 1 or more.
---@param p thread.Problems
---@param where string
---@param raw table
---@param name string
---@param need boolean|nil
---@return integer|nil
function M.count(p, where, raw, name, need)
  local v = raw[name]
  if v == nil then
    if need then
      M.bad(p, where, string.format('no `%s`', name))
    end
    return nil
  end
  if type(v) ~= 'number' or v < 1 or v % 1 ~= 0 then
    M.bad(p, where, string.format('`%s` must be a whole number, 1 or more', name))
    return nil
  end
  return v
end

--- One of `values`.
---@param p thread.Problems
---@param where string
---@param raw table
---@param name string
---@param values string[]
---@param need boolean|nil
---@return string|nil
function M.one_of(p, where, raw, name, values, need)
  local v = raw[name]
  if v == nil then
    if need then
      M.bad(p, where, string.format('no `%s`', name))
    end
    return nil
  end
  if not vim.tbl_contains(values, v) then
    local quoted = vim.tbl_map(function(x)
      return '"' .. x .. '"'
    end, values)
    M.bad(p, where, string.format('`%s` is %s, not %s', name, table.concat(quoted, ', '), vim.inspect(v)))
    return nil
  end
  return v
end

--- A list; nil when it is not there.
---@param p thread.Problems
---@param where string
---@param raw table
---@param name string
---@return any[]|nil
function M.list(p, where, raw, name)
  local v = raw[name]
  if v == nil then
    return nil
  end
  if type(v) ~= 'table' or not vim.islist(v) then
    M.bad(p, where, string.format('`%s` must be a list', name))
    return nil
  end
  return v
end

return M
