-- The screen pinned, for a change that should change nothing a person
-- sees: shots' review driven through every place, wide and narrow, its
-- text after each step compared with a run recorded before. `make pin`;
-- PIN=base records the run to compare with, at the commit checked out,
-- which every later run reads the review's code at too. Each step's text
-- is OUT/run/<size>/NN.txt (OUT: $TMPDIR/thread-pin); a run that differs
-- prints the diff and fails.

local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local env = vim.env
local OUT = (env.OUT or ((env.TMPDIR or '/tmp') .. '/thread-pin'))
local BASE, RUN = OUT .. '/base', OUT .. '/run'
local SIZES = { '150x44', '96x44' }

-- Home, each tab both ways round, each page and back, the walk and its
-- briefing over the code, and help here and there.
-- stylua: ignore
local STEPS = {
  ':Thread', '?', 'q', 'K', '?', 'q', '<Tab>', '<CR>',
  'L', 'L', 'L', 'L', 'H', 'H', 'H',
  'j', '<CR>', 'L', 'H', '?', 'q', 'K',
  'L', 'j', '<CR>', 'j', '?', 'q', 'H', '<CR>', 'K', '<CR>', 'j', 'p', 'K',
  'L', 'L', 'L', '<CR>', 'L', 'H', '?', 'q', 'K', 'j',
  'H', 'H', 't', 'B', 'j', '?', 'q', 'L', 'H', 'p', 'K',
  'L', 'L', '<CR>', 'j', 'j', '<CR>', 'U', 'K', 'q',
}

---@param cmd string[]
---@param extra table<string, string>|nil
---@return string
local function run(cmd, extra)
  local r = vim.system(cmd, { text = true, env = extra }):wait()
  assert(r.code == 0, table.concat(cmd, ' ') .. ': ' .. (r.stderr or '') .. (r.stdout or ''))
  return r.stdout or ''
end

-- What differs from run to run with nothing on the screen changed: when
-- :Thread debug ran and the commit it was loaded from, left out; the ids
-- Neovim gave the marks, counted on from the run's first, and where
-- thread.nvim was loaded from, which a key's source says.
local VARIES = { '^thread debug, %d', '^loaded: ' }

---@param path string
---@return string[]
local function read(path)
  local out = {} ---@type string[]
  for _, line in ipairs(vim.fn.readfile(path)) do
    local keep = true
    for _, pat in ipairs(VARIES) do
      keep = keep and not line:find(pat)
    end
    if keep then
      out[#out + 1] = (line:gsub('( mark )%d+', '%1#'):gsub(' at %S+(/lua/thread/)', ' at <root>%1'))
    end
  end
  return out
end

local record = env.PIN == 'base'
local rev = record and vim.trim(run { 'git', '-C', root, 'rev-parse', 'HEAD' }) or (vim.uv.fs_stat(BASE .. '/rev') and vim.fn.readfile(BASE .. '/rev')[1])
if not rev then
  io.stderr:write 'pin: nothing recorded to compare with; PIN=base make pin first\n'
  os.exit(1)
end

local function drive()
  vim.fn.delete(RUN, 'rf')
  run({ 'nvim', '--headless', '--clean', '-l', root .. '/tests/shots.lua' }, {
    OUT = OUT,
    NAME = 'run',
    REV = rev,
    PICTURES = env.PICTURES or '0',
    STEPS = table.concat(STEPS, ';'),
  })
end

drive()
if record then
  vim.fn.delete(BASE, 'rf')
  run { 'cp', '-a', RUN, BASE }
  vim.fn.writefile({ rev }, BASE .. '/rev')
  io.stdout:write(string.format('pin: %d steps at %s, recorded in %s\n', #STEPS + 1, rev:sub(1, 7), BASE))
  vim.cmd 'qa!'
end

-- The walk's float over the code lands a row or two apart from run to
-- run, the same code or not: a screen differs only if it does in each of
-- TRIES runs.
local TRIES = 4
local left = {} ---@type table<string, string>  each screen differing so far, its diff
for _, size in ipairs(SIZES) do
  for n = 0, #STEPS do
    left[string.format('%s/%02d.txt', size, n)] = ''
  end
end
for try = 1, TRIES do
  if try > 1 then
    drive()
  end
  for name in pairs(left) do
    local was, now = read(BASE .. '/' .. name), read(RUN .. '/' .. name)
    local d = vim.text.diff(table.concat(was, '\n') .. '\n', table.concat(now, '\n') .. '\n', { ctxlen = 1 })
    left[name] = d ~= '' and d or nil
  end
  if next(left) == nil then
    break
  end
end
local names = vim.tbl_keys(left)
table.sort(names)
for _, name in ipairs(names) do
  io.stdout:write('--- ' .. name .. '\n' .. left[name])
end
io.stdout:write(string.format('pin: %d of %d screens differ from %s\n', #names, 2 * (#STEPS + 1), BASE))
if #names > 0 then
  os.exit(1)
end
vim.cmd 'qa!'
