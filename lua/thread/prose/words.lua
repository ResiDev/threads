--- Two versions of a line, word by word: how much of it changed, its
--- words that changed lit on each side, and in two runs of lines which
--- line each became, so the words lit are those of one line changed.

local M = {}

-- More of a line changed than this, and it is not that line changed but
-- another; more of a contract, and its sides are drawn as two blocks.
M.MOSTLY = 0.6

-- Lines a side at most that are paired one by one with what they became.
M.PAIRS = 40

-- A run of text as tokens: words, spaces, and each other character.
---@param s string
---@return string[]
local function tokens(s)
  local out, i = {}, 1 ---@type string[], integer
  while i <= #s do
    local _, e = s:find('^[%w_]+', i)
    if not e then
      _, e = s:find('^%s+', i)
    end
    if not e then
      local b = s:byte(i)
      e = i + (b >= 0xF0 and 3 or b >= 0xE0 and 2 or b >= 0xC0 and 1 or 0)
    end
    out[#out + 1] = s:sub(i, e)
    i = e + 1
  end
  return out
end

--- How many tokens two runs keep in common from each place on, by a
--- longest common run: `L[i][j]` for `A` from `i` and `B` from `j`.
---@param A string[]
---@param B string[]
---@return integer[][]
local function common(A, B)
  local L = {} ---@type integer[][]
  for i = #A + 1, 1, -1 do
    L[i] = {}
    for j = #B + 1, 1, -1 do
      if i > #A or j > #B then
        L[i][j] = 0
      elseif A[i] == B[j] then
        L[i][j] = L[i + 1][j + 1] + 1
      else
        L[i][j] = math.max(L[i + 1][j], L[i][j + 1])
      end
    end
  end
  return L
end

--- How much of a line changed, from 0 to 1: its tokens the other version
--- does not keep. A signature is one line, so counting lines alone would
--- call any change to it most of it.
---@param a string
---@param b string
---@return number
function M.share(a, b)
  local A, B = tokens(a), tokens(b)
  local most = math.max(#A, #B)
  return most == 0 and 0 or 1 - common(A, B)[1][1] / most
end

--- Two versions of a line, each as chunks, what the other has not lit:
--- the tokens either side kept in common by a longest common run.
---@param a string
---@param b string
---@return thread.Chunks before, thread.Chunks after
function M.marked(a, b)
  local A, B = tokens(a), tokens(b)
  local L = common(A, B)
  -- Each side's tokens, and whether each changed.
  local xs, ys = {}, {} ---@type { [1]: string, [2]: boolean }[], { [1]: string, [2]: boolean }[]
  local i, j = 1, 1
  while i <= #A or j <= #B do
    if i <= #A and j <= #B and A[i] == B[j] then
      xs[#xs + 1], ys[#ys + 1] = { A[i], false }, { B[j], false }
      i, j = i + 1, j + 1
    elseif j <= #B and (i > #A or L[i][j + 1] >= L[i + 1][j]) then
      ys[#ys + 1], j = { B[j], true }, j + 1
    else
      xs[#xs + 1], i = { A[i], true }, i + 1
    end
  end
  ---@param list { [1]: string, [2]: boolean }[]
  ---@param hl string
  ---@return thread.Chunks
  local function lit(list, hl)
    local out = {} ---@type thread.Chunks
    for k, t in ipairs(list) do
      -- Space that moved is not a word that changed: lit only between two
      -- that did.
      local on = t[2] and (not t[1]:find '^%s+$' or (list[k - 1] and list[k - 1][2] and list[k + 1] and list[k + 1][2]))
      local want = on and hl or 'ThreadCode'
      local last = out[#out]
      if last and last[2] == want then
        last[1] = last[1] .. t[1]
      else
        out[#out + 1] = { t[1], want }
      end
    end
    return out
  end
  local x, y = lit(xs, 'ThreadDiffDeleteWord'), lit(ys, 'ThreadDiffAddWord')
  return x, y
end

--- Which line each removed line became: the pairs, in order, of lines
--- like enough to be one line changed, as many as can be and the most
--- alike of those; a line too unlike any is left alone, so its words are
--- not lit against another's. Runs past `M.PAIRS` lines a side pair
--- nothing.
---@param olds string[]
---@param news string[]
---@return table<integer, integer>
function M.pair(olds, news)
  local out = {} ---@type table<integer, integer>
  if #olds == 0 or #news == 0 or #olds > M.PAIRS or #news > M.PAIRS then
    return out
  end
  -- best[i][k]: the pairs from olds[i] and news[k] on, counted with how
  -- alike they are, each pair worth more than any likeness.
  local best, like = {}, {} ---@type number[][], number[][]
  for i = #olds + 1, 1, -1 do
    best[i], like[i] = {}, {}
    for k = #news + 1, 1, -1 do
      if i > #olds or k > #news then
        best[i][k] = 0
      else
        local share = M.share(olds[i], news[k])
        like[i][k] = share <= M.MOSTLY and (2 - share) or nil
        best[i][k] = math.max(best[i + 1][k], best[i][k + 1], like[i][k] and like[i][k] + best[i + 1][k + 1] or 0)
      end
    end
  end
  local i, k = 1, 1
  while i <= #olds and k <= #news do
    if like[i][k] and best[i][k] == like[i][k] + best[i + 1][k + 1] then
      out[i], i, k = k, i + 1, k + 1
    elseif best[i][k] == best[i + 1][k] then
      i = i + 1
    else
      k = k + 1
    end
  end
  return out
end

--- A run of removed lines and the run that replaced it, set in rows: a
--- line beside the one it became, those paired with none side by side as
--- they come. `paired` says a row's two are alike.
---@param olds string[]
---@param news string[]
---@return { a: integer|nil, b: integer|nil, paired: boolean|nil }[]
function M.aligned(olds, news)
  local p = M.pair(olds, news)
  local rows, A, B, j = {}, {}, {}, 1 ---@type { a: integer|nil, b: integer|nil, paired: boolean|nil }[], integer[], integer[], integer
  local function flush()
    for t = 1, math.max(#A, #B) do
      rows[#rows + 1] = { a = A[t], b = B[t] }
    end
    A, B = {}, {}
  end
  for i = 1, #olds do
    local k = p[i]
    if k then
      while j < k do
        B[#B + 1], j = j, j + 1
      end
      flush()
      rows[#rows + 1], j = { a = i, b = k, paired = true }, k + 1
    else
      A[#A + 1] = i
    end
  end
  while j <= #news do
    B[#B + 1], j = j, j + 1
  end
  flush()
  return rows
end

return M
