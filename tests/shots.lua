-- Pictures of the review screen, every tab, wide and narrow, to look at
-- after a change to how it draws. `make shots`; NAME=<dir> (default
-- `now`) under OUT (default $TMPDIR/thread-shots); REV=<commit> the
-- repository at that commit, not HEAD; STEPS others than these.
--
-- The review is tests/reviews/ids-counted-per-kind-links-that-name-it,
-- which has contracts of every impact, four tours and notes of every
-- kind. It holds no conversations and nothing walked, so what a person
-- would have done is added here: a question the agent answered, a note
-- you replied to, a decision agreed, a step answered, a contract asked
-- about, a tour walked whole and one partly, and when the agent's
-- messages came.

local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local env = vim.env
local OUT = (env.OUT or ((env.TMPDIR or '/tmp') .. '/thread-shots')) .. '/' .. (env.NAME or 'now')
local ID = 'ids-counted-per-kind-links-that-name-it'

---@param cmd string[]
---@param extra table<string, string>|nil
local function run(cmd, extra)
  local r = vim.system(cmd, { text = true, env = extra }):wait()
  assert(r.code == 0, table.concat(cmd, ' ') .. ': ' .. (r.stderr or ''))
  return r.stdout or ''
end

--- A local time `hours` ago, as the format writes one.
---@param hours number
---@return string
local function ago(hours)
  return os.date('%Y-%m-%dT%H:%M:%S', os.time() - math.floor(hours * 3600)) --[[@as string]]
end

---@param from 'you'|'agent'
---@param text string
---@param hours number|nil  yours: when you wrote it
local function say(from, text, hours)
  return { from = from, at = hours and ago(hours) or nil, prose = { text = text } }
end

vim.fn.delete(OUT, 'rf')
local repo = OUT .. '/repo'
run { 'git', 'clone', '-q', '--shared', root, repo }
if env.REV then
  run { 'git', '-C', repo, 'checkout', '-q', env.REV }
end
vim.fn.mkdir(repo .. '/.threads', 'p')
vim.fn.writefile({ '/.threads/' }, repo .. '/.git/info/exclude', 'a')

local r = vim.json.decode(table.concat(vim.fn.readfile(root .. '/tests/reviews/' .. ID .. '.json'), '\n'))
local notes = {} ---@type table<integer, table>
for _, n in ipairs(r.notes) do
  notes[n.id] = n
end
local steps = {} ---@type table<integer, table>
for _, x in ipairs(r.tours) do
  for _, s in ipairs(x.steps) do
    steps[s.id] = s
  end
end
vim.list_extend(notes[9].messages, {
  say('you', 'Would a renumbered contract break links in other reviews, or only in this one?', 20),
  say(
    'agent',
    'Only in this one: another review links a contract as `review-id#contract:3`, by its own id, and ids are never reused. `--check` can say so in the warning.'
  ),
})
table.insert(notes[4].messages, say('you', 'Is the skill the only place that still teaches them?', 1))
notes[10].status = 'agreed'
vim.list_extend(notes[10].messages, { say('you', 'Agreed: the name is what a reader looks for.', 30), say('agent', 'Kept as it is.') })
steps[1].messages = {
  say('you', 'Does an old review with a bare #3 still open?', 26),
  say('agent', 'It opens, and `--check` warns once per link; nothing is rewritten.'),
}
-- A conversation on a contract, link.follow's, the agent's answer new.
for _, c in ipairs(r.contracts) do
  if c.id == 3 then
    c.messages = {
      say('you', 'So a bare `#7` that resolves opens without a word in the editor? The warning only reaches `--check`.', 3),
      say(
        'agent',
        'Yes. `go.lua` drops `why` when there is a target, so the user lands where the link goes. Only a `#7` that both a step and a note have stops there, because it returns no target.'
      ),
    }
  end
end
vim.fn.writefile({ vim.json.encode(r) }, repo .. '/.threads/' .. ID .. '.json')

local heard, read = {}, {} ---@type table<string, string>, table<string, integer>
for _, n in ipairs(r.notes) do
  for i, m in ipairs(n.messages) do
    if m.from == 'agent' then
      heard['note:' .. n.id .. ':' .. i] = ago(i == 1 and 4 or 2)
    end
  end
end
heard['step:1:2'] = ago(2)
heard['contract:3:2'] = ago(2)
-- Read: the notes looked at already, the first message of the
-- question, and what you wrote.
for _, id in ipairs { 2, 3, 5, 6, 7, 11, 12, 13 } do
  read['note:' .. id] = #notes[id].messages
end
read['note:9'], read['note:4'], read['note:10'] = 2, 2, 3
read['contract:3'] = 1
local walked = {} ---@type table<string, true>
for _, id in ipairs { 1, 2, 23, 24, 25, 26, 27, 31, 28 } do
  walked['step:' .. id] = true
end
local seen = { read = read, walked = walked, accepted = vim.empty_dict(), heard = heard }
vim.fn.writefile({ vim.json.encode(seen) }, repo .. '/.threads/' .. ID .. '.seen')

-- Each tab, then a note further down, the briefing of the tour under
-- the cursor on Tours, and the contracts' was and is.
local STEPS = table.concat({ ':Thread', 'L', 'L', 'L', 'j', 'H', '<CR>', 'K', 'H', 'j' }, ';')
for _, size in ipairs { '150x44', '96x44' } do
  local out = OUT .. '/' .. size
  local colors = env.COLORS or 'tokyonight-night'
  run(
    { 'nvim', '--headless', '--clean', '-l', root .. '/tests/view.lua' },
    { REPO = repo, SIZE = size, OUT = out, STEPS = env.STEPS or STEPS, COLORS = colors }
  )
  io.stdout:write(out .. '\n')
end
vim.cmd 'qa!'
