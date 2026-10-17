-- Reviews as an agent might get them wrong: H.world's, which has a thing
-- of every kind, changed at random, written as JSON and read back as a
-- file is. Each must be read or refused with what is wrong, never fail;
-- each that reads is drawn by every drawer at a random width and put in
-- a buffer, and none fails or draws a row wider than it. Not in check: a failure is a
-- review to look at, and its regression goes in a spec. `make fuzz`; the
-- variables:
--
--   COUNT  how many reviews (default 5000)
--   SEED   where the randomness starts (default 1), so a run is the same
--          each time; another finds other reviews
--   OUT    where each failure's review is written (default
--          $TMPDIR/thread-fuzz), NN.json

local H = require 'tests.helpers'
local D = require 'tests.drawn'

local json = require 'thread.base.json'
local review = require 'thread.model.review'

local env = vim.env
local COUNT = tonumber(env.COUNT) or 5000
local SEED = tonumber(env.SEED) or 1
local OUT = env.OUT or ((env.TMPDIR or '/tmp') .. '/thread-fuzz')

-- Narrower than this, a drawer may cut nothing more and run over: the
-- narrowest a review is drawn at.
local NARROW = 40

-- What goes in place of a value: of every JSON type, ids pointing at
-- nothing, and text that is long, wide, blank or not one line.
local VALUES = {
  0,
  -1,
  1.5,
  true,
  '',
  'x',
  '#note:999',
  '#step:1',
  '#chunk:nope',
  '{{diagram:none}}',
  '| a | b |\n|---|---|\n| 1 | 2 |',
  '\t\n\r',
  'a\tb',
  '\r',
  '\27[31mred',
  'a\u{200b}b',
  string.rep('w', 400),
  string.rep('é', 300),
  vim.NIL,
  {},
  { 1 },
  { vim.NIL, { kind = 'flow' } },
}

-- What goes in front of a string.
local TEXTS = vim.tbl_filter(function(v)
  return type(v) == 'string'
end, VALUES)

--- Every place in `t`, as the keys that lead there, in an order that is
--- the same each run: `pairs` has none.
---@param t table
---@param at any[]
---@param into any[][]
---@return any[][]
local function places(t, at, into)
  local keys = vim.tbl_keys(t)
  table.sort(keys, function(a, b)
    return tostring(a) < tostring(b)
  end)
  for _, k in ipairs(keys) do
    local here = vim.list_extend(vim.deepcopy(at), { k })
    into[#into + 1] = here
    if type(t[k]) == 'table' then
      places(t[k], here, into)
    end
  end
  return into
end

--- `raw` with one to three places changed: gone, given another value, or
--- a string with another put in front, which reads more often and so is
--- drawn more.
---@param raw table
---@param all any[][]
---@return table
local function changed(raw, all)
  local t = vim.deepcopy(raw)
  for _ = 1, math.random(3) do
    local at = all[math.random(#all)]
    local holder = t
    for i = 1, #at - 1 do
      holder = type(holder) == 'table' and holder[at[i]] or nil
    end
    local key = at[#at]
    -- Only where the key still fits: a change before may have put a value
    -- where this place was, and a list with a name in it is no JSON.
    local list = type(holder) == 'table' and vim.islist(holder) and next(holder) ~= nil
    if type(holder) == 'table' and (type(key) == 'number') == list then
      local was = holder[key]
      local how = math.random(4)
      if how == 1 and list then
        table.remove(holder, key)
      elseif how == 1 then
        holder[key] = nil
      elseif how >= 3 and type(was) == 'string' then
        holder[key] = TEXTS[math.random(#TEXTS)] .. was
      else
        holder[key] = vim.deepcopy(VALUES[math.random(#VALUES)])
      end
    end
  end
  return t
end

--- What went wrong, the same each time it does: the first line, its path
--- in the repository and not the machine.
---@param err any
---@return string
local function said(err)
  return (tostring(err):gsub('\n.*', ''):gsub('^[^:]*/(lua/)', '%1'))
end

H.mute()
H.reset()
vim.fn.delete(OUT, 'rf')
vim.fn.mkdir(OUT, 'p')
math.randomseed(SEED)

local failures, seen = 0, {} ---@type integer, table<string, true>

--- Write a failure down, once for each `kind` of it: the same fault
--- found again says nothing new.
---@param i integer
---@param kind string
---@param what string
---@param text string  the review, as written
local function failed(i, kind, what, text)
  if seen[kind] then
    return
  end
  seen[kind] = true
  failures = failures + 1
  local file = string.format('%s/%02d.json', OUT, failures)
  vim.fn.writefile(vim.split(text, '\n'), file)
  io.stdout:write(string.format('review %d: %s\n  %s\n', i, what, file))
end

local buf, ns = vim.api.nvim_create_buf(false, true), vim.api.nvim_create_namespace 'thread-fuzz'
local read, refused = 0, 0
D.plainly(function()
  H.world()
  local raw = assert(json.decode(table.concat(vim.fn.readfile '.threads/screens.json', '\n')))
  local all = places(raw, {}, {})
  for i = 1, COUNT do
    -- As a file is: written, and read back.
    local text = json.encode(changed(raw, all))
    local ok, r = pcall(function()
      return (review.parse(json.decode(text), 'screens'))
    end)
    if not ok then
      failed(i, said(r), 'reading it failed: ' .. said(r), text)
    elseif not r then
      refused = refused + 1
    else
      read = read + 1
      local width = math.random(NARROW, 180)
      local drew, lines, P = pcall(D.drawn, r, width)
      -- Into a buffer, as a screen puts it: Neovim takes no row with a
      -- line break in it.
      local put, err = drew, nil
      if drew then
        put, err = pcall(P.apply, buf, ns)
      end
      if not drew then
        failed(i, said(lines), 'drawing it failed: ' .. said(lines), text)
      elseif not put then
        failed(i, said(err), 'putting it in a buffer failed: ' .. said(err), text)
      else
        local over = D.wide(lines, width)
        if #over > 0 then
          failed(i, 'wide', string.format('a row past %d columns: %s', width, vim.inspect(over[1])), text)
        end
      end
    end
  end
end)

io.stdout:write(string.format('fuzz: seed %d, %d reviews: %d read and drawn, %d refused, %d failures\n', SEED, COUNT, read, refused, failures))
vim.cmd(failures > 0 and 'cquit 1' or 'qa!')
