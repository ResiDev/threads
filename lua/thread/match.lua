--- Quoted text -> the line it now lives on, plus how sure we are.
---
--- The anchor an agent can always get right is the line it was looking at,
--- copied verbatim. Everything hard about that anchor is here: the code moves,
--- gets reindented, gains an argument, and the quoted text has to find it again
--- without ever confidently landing somewhere wrong.
---
--- Taken from tour.nvim, unchanged but for this line. Pure Lua: no Neovim
--- API, no filesystem; `find` takes the text, the lines and two knobs.

local M = {}

--- Below this ratio there is no plausible candidate and we say so rather than
--- moving the cursor. Not a confidence threshold -- confidence is reported as a
--- number and coloured by the caller -- but a floor under "did we find it at
--- all". A deleted line otherwise resolves to whatever the least-bad line in the
--- file happens to be.
M.FLOOR = 0.6

--- Bound on the strings fed to the distance matrix. The comparison is O(n*m),
--- and a minified bundle on one 200kB line would otherwise stall the editor.
--- Past this length the prefix decides it, which is ample for source code.
local MAX_LEN = 512

--- Trim the ends and collapse internal runs of whitespace.
---
--- Reindentation and reformatting are the changes a line is most likely to
--- survive while still being *the same line*, so a match here still counts as
--- exact: it reports 1.0 and the caller shows no drift warning.
---@param s string
---@return string
local function normalise(s)
  return (s:gsub('%s+', ' '):gsub('^ ', ''):gsub(' $', ''))
end

--- Levenshtein distance, two rows rather than a full matrix.
---@param a string
---@param b string
---@return integer
local function distance(a, b)
  if #a > MAX_LEN then
    a = a:sub(1, MAX_LEN)
  end
  if #b > MAX_LEN then
    b = b:sub(1, MAX_LEN)
  end

  local la, lb = #a, #b
  if la == 0 then
    return lb
  end
  if lb == 0 then
    return la
  end

  local prev, cur = {}, {}
  for j = 0, lb do
    prev[j] = j
  end

  for i = 1, la do
    cur[0] = i
    local ai = a:byte(i)
    for j = 1, lb do
      local sub = prev[j - 1] + (ai == b:byte(j) and 0 or 1)
      local del = prev[j] + 1
      local ins = cur[j - 1] + 1
      local best = del < ins and del or ins
      cur[j] = best < sub and best or sub
    end
    prev, cur = cur, prev
  end

  return prev[lb]
end

--- Similarity of two strings, 0 (nothing in common) to 1 (identical).
---@param a string
---@param b string
---@return number
local function ratio(a, b)
  local longest = math.max(#a, #b)
  if longest == 0 then
    return 1
  end
  return 1 - (distance(a, b) / longest)
end

--- Of several equally good candidates, the one nearest `hint`.
---
--- The agent knows the line number it was reading, so a step carrying both
--- `text` and `line` turns the ambiguous case -- a quoted line that occurs three
--- times in the file -- into a certain one. Without a hint the first match wins,
--- which is the rule `pattern` already documents.
---@param candidates integer[]
---@param hint integer|nil
---@return integer
local function pick(candidates, hint)
  if not hint then
    return candidates[1]
  end
  local best, best_gap = candidates[1], math.huge
  for _, lnum in ipairs(candidates) do
    local gap = math.abs(lnum - hint)
    if gap < best_gap then
      best, best_gap = lnum, gap
    end
  end
  return best
end

---@class thread.Match
---@field line integer      1-indexed
---@field confidence number 0..1; 1 means exact or whitespace-only difference

--- Find the line `text` came from.
---
--- Three rungs, cheapest first: the line verbatim, the line ignoring
--- whitespace, then the closest line by edit distance. The first two report 1.0
--- and cost a string compare each; the third only runs when both have failed,
--- over the one file the step names.
---
---@param text string          the line as the tour author saw it
---@param lines string[]        the file's lines now
---@param opts { hint: integer|nil, floor: number|nil }|nil
---@return thread.Match|nil, string|nil
function M.find(text, lines, opts)
  if type(text) ~= 'string' or text == '' then
    return nil, 'text must be a non-empty string'
  end
  if type(lines) ~= 'table' or #lines == 0 then
    return nil, string.format('no line matching this text in the file: %q', text)
  end

  opts = opts or {}
  local hint = opts.hint
  local floor = opts.floor or M.FLOOR

  local exact = {}
  for lnum, line in ipairs(lines) do
    if line == text then
      exact[#exact + 1] = lnum
    end
  end
  if #exact > 0 then
    return { line = pick(exact, hint), confidence = 1 }, nil
  end

  local wanted = normalise(text)
  local loose = {}
  for lnum, line in ipairs(lines) do
    if normalise(line) == wanted then
      loose[#loose + 1] = lnum
    end
  end
  if #loose > 0 then
    return { line = pick(loose, hint), confidence = 1 }, nil
  end

  -- Fuzzy. The distance between two strings is at least the difference in their
  -- lengths, and the ratio divides by the longer of the two -- so a candidate
  -- can only reach `floor` if that length difference is within (1 - floor) of
  -- the longer string. Most lines are rejected on that arithmetic alone and
  -- never reach the matrix, which is what keeps this cheap on a large file.
  local scored, best_score = {}, 0
  for lnum, line in ipairs(lines) do
    local candidate = normalise(line)
    local longest = math.max(#candidate, #wanted)
    if math.abs(#candidate - #wanted) <= longest * (1 - floor) then
      local score = ratio(wanted, candidate)
      if score > best_score + 1e-9 then
        scored, best_score = { lnum }, score
      elseif score > best_score - 1e-9 then
        scored[#scored + 1] = lnum
      end
    end
  end

  if best_score < floor or #scored == 0 then
    return nil, string.format('no line matching this text in the file: %q', text)
  end

  return { line = pick(scored, hint), confidence = best_score }, nil
end

return M
