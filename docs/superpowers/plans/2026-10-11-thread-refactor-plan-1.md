# thread.nvim refactor, plan 1 of 2: safety net, bug fixes, shared modules

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make thread.nvim safe to restructure (one test harness, screen snapshots), fix every bug found in the review, remove the two features the owner dropped, and replace the code written several times with a few shared modules, keeping behaviour the same.

**Architecture:** Work happens on a `refactor` branch in a worktree of the thread.nvim repo, so the checkout Neovim loads keeps working. Screen snapshots (`tests/screens/*.txt`: every window's lines and extmarks, then the screen grid) pin down what thread.nvim draws; every later task must leave them unchanged unless it says otherwise. Shared modules (`text`, `look`, `sheet`, `code`, `blocks`, `float`, `hunks`, `keys`, `codediff`) each replace three or more copies and get their own unit tests.

**Tech Stack:** Lua (LuaJIT) in Neovim 0.12.5, headless `nvim -l` test scripts, git.

**Spec:** `/home/alex/.config/nvim/thread.nvim/docs/superpowers/specs/2026-10-11-thread-refactor-design.md`

**Line numbers** in this plan are from commit `c2831d0` (master when the plan was written). Earlier tasks shift them: find code by the function name given, and use the line number only as a hint.

**Plan 2** (split `home.lua`, `render.lua`, `review*.lua`, `page.lua`, `store.lua`; data-driven keys and commands; the rename; docs and lint) is outlined at the end and is written in detail once this plan has landed, because its line ranges depend on this one.

## Global Constraints

- Only files under the thread.nvim worktree change. The single exception is Task 3's one line in `/home/alex/.config/nvim/lua/plugins/thread.lua`, and only if the owner confirms it.
- thread.nvim requires nothing outside `thread`, `thread.*` and `vim.*`. The exceptions: `codediff.*`, optional and pcall-guarded, in the CodeDiff adapter (`lua/thread/git.lua` until Task 25, `lua/thread/codediff.lua` after); and home.lua's read of `package.loaded['which-key.config']`, kept by the owner. `tests/independence_spec.lua` (Task 4) enforces this.
- **Owner decisions (2026-10-11):** work in a worktree; execute subagent-driven; Task 3 runs (remove the comments.nvim dependency); Task 2 is a no-op (keep the which-key code).
- **A thread.nvim review after each phase (owner, 2026-10-11).** When Phase A, B and C are each done, the controller (not a task subagent) writes a review thread with the answering-threads skill, in the worktree's own batch (`W/.threads/`, so it reads the worktree's files), with `diff = { base = 'master' }` and `head` unset. Its hunks are the real code changes of that phase, quoted from inside each hunk, grouped by intent (one group per bug fix or per shared module, riskiest first), with `affected` only for code the phase did not touch whose meaning changed, and `tests` naming the tests that cover each group. Never put documents in as hunks to stand for code. Run `show.lua --check` from `W` and fix what it reports. The owner reads it by opening Neovim in `W`.
- Behaviour stays the same. After every task `make check` passes, and `git status tests/screens` shows no change, unless the task says which snapshots it changes and why. When it does, the commit message says so.
- Neovim 0.12.5. Use `vim.text.diff` where available (`vim.text and vim.text.diff or vim.diff`), as the code already does.
- Match the surrounding code: 2-space indent, single quotes, `require 'x'` without parentheses, `local M = {}` modules, `---` doc comments in short plain sentences (British spelling: colour, behaviour). stylua settings: column_width 160, AutoPreferSingle, call_parentheses None.
- Commit messages use a conventional prefix (`feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`) and a lower-case summary, like `git log`. **Never add a `Co-Authored-By` trailer.**
- Tests never open or drive the real `.threads/` batch in the main checkout. They work in temp repos made by `tests/helpers.lua`.
- When a function moves, update every caller and leave no alias behind (an alias is a pass-through).
- `W` below means the worktree root: `/home/alex/.config/nvim/thread.nvim/.worktrees/refactor`. Run every command from `W`.

## Review Focus

The ways a person will break this that no test covers yet, most likely first. Each has its test in the task named.

1. **Wide characters** (CJK, accents, Nerd Font icons) in titles and messages: byte columns vs display columns in `fit`, `pad`, `spread` and highlight spans. Tests: Task 17 (`fit` on CJK), Task 19 (`chunks` byte columns with `é`), Task 5 fixture (a CJK title on a Home row).
2. **A narrow editor** (70 columns): footers have to drop keys, and `fit` is asked for width 0 or less. Tests: Task 5 `home-narrow` screen, Task 17 `fit(s, 0)` and `fit(s, -3)`.
3. **A buffer with its own mapping** of a key thread.nvim maps (a dashboard's `<CR>`, a buffer's `L`): thread must take and give back the global one. Tests: Task 10.
4. **Code with tabs** in excerpts and hunks: tabs drawn as four spaces, and syntax spans skipped on such lines so they don't land in the wrong columns. Test: Task 20.
5. **No git, or git with no commit yet**: snapshots and diffs fail. thread must still save a message. Test: Task 25.

---

## Phase A: workspace, the owner's removals, the safety net

### Task 0: Worktree and baseline

**Files:** none changed in the repo; `.git/info/exclude` of thread.nvim gets one line.

- [ ] **Step 1: Keep worktrees out of git**

```bash
cd /home/alex/.config/nvim/thread.nvim
grep -qx '/.worktrees/' .git/info/exclude || echo '/.worktrees/' >> .git/info/exclude
git check-ignore -q .worktrees && echo ignored
```
Expected: `ignored`

- [ ] **Step 2: Create the worktree on a new branch**

```bash
cd /home/alex/.config/nvim/thread.nvim
git status --short   # must be empty except docs/superpowers (untracked, the plan itself)
git worktree add .worktrees/refactor -b refactor
```

- [ ] **Step 3: Baseline**

```bash
cd /home/alex/.config/nvim/thread.nvim/.worktrees/refactor && make check
```
Expected: `8 tests, 0 failed` and `thread smoke: ok` (the smoke test prints `-- INSERT --` noise too; that's fine).

---

### Task 1: Remove `:Thread import`, and the node anchors it brought

The owner dropped importing tour.nvim `.tour` files. `symbol` and `pattern` anchors on diagram nodes only ever came from imported tours, and thread follows neither properly: page.lua ignores them, and home.lua runs a regex search for `symbol`. They go too.

**Files:**
- Delete: `lua/thread/import.lua`
- Modify: `plugin/thread.lua` (desc string, the `import` branch of `complete`)
- Modify: `lua/thread/init.lua` (`M.commands.import`)
- Modify: `lua/thread/config.lua` (`tours` option and its comment)
- Modify: `lua/thread/home.lua` (`M.draw_tours` empty text, ~1453; the `node.symbol` search in the ⏎ handler, ~2643)
- Modify: `lua/thread/diagram/init.lua` (`ANCHOR_FIELDS`, ~23, and any message listing them)
- Modify: `tests/smoke.lua` (the import section, lines 281-302, and the review comment at 329-330)
- Modify: `README.md:57-58`, `DESIGN.md` ("Tours that already exist", 325-334)

- [ ] **Step 1: Replace the smoke test's import with a tour the agent writes**

In `tests/smoke.lua`, replace lines 281-302 (from `-- Import a tour:` through `eq(#require('thread.tour').tours(batch), 2, 'two tours now')`) with:

```lua
-- A standalone tour the agent writes: a stage, then a step with a note.
batch = store.active()
local sid = store.next_id(batch)
batch.data.threads[#batch.data.threads + 1] = {
  id = sid,
  title = 'Writing to the store',
  status = 'open',
  messages = { {
    from = 'agent',
    text = 'Where writes go.',
    walk = {
      { stage = 'Writes go straight in', point = 'set has no cache.', verdict = 'fine', body = 'Nothing to keep in step.' },
      {
        file = 'store.lua',
        line = 8,
        text = 'function M.set(store, key, value)',
        body = 'The whole of set.',
        notes = { { line = 9, text = '  store[key] = value', note = 'the write' } },
      },
    },
  } },
}
store.save(batch)
local root_thread = store.find(store.active(), sid)
-- A file git does not track: the review below finds it unexplained.
vim.fn.writefile({ 'scratch' }, root .. '/notes.txt')
batch = store.active()
eq(#require('thread.tour').tours(batch), 2, 'two tours now')
```

and change the comment at the start of the review section (was "untracked files nothing explains (the new file, the tour imported above)") to:

```lua
-- Review: the uncommitted work, one group explaining one change, and
-- untracked files nothing explains (extra.lua, notes.txt).
```

Also change the file's header comment: drop ", import a tour" from line 4.

- [ ] **Step 2: Run the smoke test: still passes before anything is deleted**

Run: `make smoke`
Expected: `thread smoke: ok`

- [ ] **Step 3: Delete import and every reference to it**

```bash
git rm -q lua/thread/import.lua
```

`lua/thread/init.lua`: delete the whole `import = function(cmd) ... end,` entry of `M.commands`.

`plugin/thread.lua`: in `desc`, remove `import, ` from the list. Replace the `complete` function with:

```lua
  complete = function(arg, line)
    if line:match '^%S*%s+%S+%s' then
      return {}
    end
    return vim.tbl_filter(function(name)
      return name:find(arg, 1, true) == 1
    end, vim.tbl_keys(require('thread').commands))
  end,
```

`lua/thread/config.lua`: delete the two lines

```lua
  -- Where `:Thread import` finds tours.
  tours = '.tours',
```

`lua/thread/home.lua`, in `M.draw_tours`: change the empty-state text to

```lua
    P.hl(P.add '  No tours yet. An answer that walks you through the code is one.', 0, -1, 'ThreadMeta')
```

`lua/thread/home.lua`, in the ⏎ handler's diagram branch: delete

```lua
        if node.symbol and not node.text then
          vim.fn.search('\\<' .. node.symbol:gsub('^.*[.:]', '') .. '\\>', 'w')
        end
```

`lua/thread/diagram/init.lua`: set `local ANCHOR_FIELDS = { 'text', 'line' }`, then read `validate_node` and every error message that names the anchor fields, and make them name only `text` and `line`. A node that still has `symbol` or `pattern` must fail validation with a message that names the field. Add this test to `tests/spec.lua` (before its final report lines):

```lua
test('diagram: a node anchored by symbol is refused', function()
  local d, err = require('thread.diagram').validate { kind = 'flow', nodes = { { id = 'a', label = 'x', file = 'a.lua', symbol = 'M.get' } }, edges = {} }
  eq(d, nil, 'refused')
  eq(type(err) == 'string' and err:find('symbol', 1, true) ~= nil, true, 'the message names the field: ' .. tostring(err))
end)
```

Run `make test` before changing `diagram/init.lua` and see this test fail; then make the change and see it pass.

- [ ] **Step 4: Docs**

`README.md`: delete the sentence "plus `import <tour>` to read a tour.nvim `.tour` file in as threads." (lines 57-58), keeping "`:Thread` takes the same as subcommands."

`DESIGN.md`: delete the section "## Tours that already exist" (lines 325-334), and add this paragraph at the end of "## Tours are a list on a message", before "## Whose move it is":

```markdown
Excerpts in any message, stage or step (` ```code ` fences holding an
anchor: `file`, `text`, `line`, `lines`) are drawn as the code they point
at, in the page and the thread.
```

- [ ] **Step 5: Check nothing still names it**

Run: `grep -rn "import\b\|\.tours\|config.options.tours\|node.symbol" lua plugin README.md DESIGN.md | grep -v "^lua/thread/diagram" `
Expected: no output other than unrelated prose (e.g. SKILL.md's "an import for a change" is fine).

- [ ] **Step 6: Full check and commit**

Run: `make check`
Expected: `9 tests, 0 failed`, `thread smoke: ok`

```bash
git add -A && git commit -m "refactor: drop :Thread import and the symbol and pattern node anchors it brought"
```

---

### Task 2: which-key (no change: owner decided to keep it)

`make_buf` in home.lua appends `thread-home` to `package.loaded['which-key.config'].disable.ft` when which-key is loaded, so `g` on Home doesn't wait for which-key. The owner chose to keep this (2026-10-11). It loads no which-key code; it only reads which-key's table if it is already loaded. Nothing to do in this task. Task 4's independence spec allows exactly this read in `lua/thread/home.lua`, and plan 2 carries the allowance to wherever `make_buf` ends up.

---

### Task 3: The config's dependency on comments.nvim

**Confirmed by the owner (2026-10-11): "remove it, I don't want any dependencies on comments."** They were told the consequence: comments.nvim's `<CR>` does not fall back to an earlier mapping (off a comment it sends a plain Enter), thread.nvim's does. Without `dependencies = { 'comments.nvim' }` the two load in no fixed order, and when comments.nvim loads second, `<CR>` on a thread no longer focuses it while both plugins are installed. Do not change comments.nvim or its config to work around this.

**Files:**
- Modify: `/home/alex/.config/nvim/lua/plugins/thread.lua` (outside the worktree; the config repo)

- [ ] **Step 1: Remove the dependency and the comment above it**

The file becomes:

```lua
return {
  {
    -- The prototype that combines comments and tours, from the local checkout.
    dir = vim.fn.stdpath 'config' .. '/thread.nvim',
    name = 'thread.nvim',
    event = 'VeryLazy',
    cmd = 'Thread',
    opts = {},
  },
}
```

- [ ] **Step 2: Commit in the config repo**

```bash
cd /home/alex/.config/nvim && git add lua/plugins/thread.lua && git commit -m "chore: thread.nvim no longer loads after comments.nvim"
```

---

### Task 4: One test harness

Today `tests/spec.lua` and `tests/smoke.lua` each define their own `fail`/`eq`/`press`/repo setup. This task adds a runner, shared helpers, a spec that enforces thread's independence, and moves the unit tests onto them.

**Files:**
- Create: `tests/runner.lua`, `tests/helpers.lua`, `tests/run.lua`, `tests/independence_spec.lua`
- Move: `tests/spec.lua` → `tests/model_spec.lua`
- Modify: `tests/minimal_init.lua`, `tests/smoke.lua`, `Makefile`

**Interfaces:**
- Produces `tests.runner`: `R.test(name, fn)`, `R.eq(actual, expected, what)`, `R.ok(value, what) -> value`, `R.count`, `R.failures`.
- Produces `tests.helpers` (`H`): `H.root` (plugin root), `H.sh(cwd, cmd) -> stdout`, `H.git(cwd, args) -> stdout`, `H.repo(files) -> root` (cds there), `H.batch(threads, data) -> batch`, `H.press(keys)`, `H.type_in(text)`, `H.settle(ms)`, `H.screen() -> string[]`, `H.on_screen(text) -> row, line`, `H.must_see(text, what)`, `H.freeze_time(iso) -> restore()`, `H.reset()`.
- Every later task's spec files use these.

- [ ] **Step 1: The runner**

`tests/runner.lua`:

```lua
--- The test runner: `test(name, fn)`, `eq` and `ok`. `tests/run.lua` runs
--- every tests/*_spec.lua with it in one Neovim; `make test`.

local R = { count = 0, failures = 0 }

---@param name string
---@param fn fun()
function R.test(name, fn)
  R.count = R.count + 1
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then
    R.failures = R.failures + 1
    io.stderr:write('FAIL ' .. name .. ':\n' .. tostring(err) .. '\n')
  end
end

function R.eq(actual, expected, what)
  if not vim.deep_equal(actual, expected) then
    error(string.format('%s: expected %s, got %s', what or 'value', vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

function R.ok(value, what)
  if not value then
    error(what or 'expected a true value', 2)
  end
  return value
end

return R
```

`tests/run.lua`:

```lua
-- Every tests/*_spec.lua, in one Neovim. `SPEC=name make test` runs the
-- files whose path contains `name`.

local R = require 'tests.runner'
local here = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h')
for _, path in ipairs(vim.fn.glob(here .. '/*_spec.lua', false, true)) do
  if not vim.env.SPEC or path:find(vim.env.SPEC, 1, true) then
    dofile(path)
  end
end
io.stdout:write(string.format('%d tests, %d failed\n', R.count, R.failures))
vim.cmd(R.failures > 0 and 'cquit 1' or 'qa!')
```

`tests/minimal_init.lua` becomes:

```lua
local here = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.runtimepath:prepend(here)
package.path = here .. '/?.lua;' .. package.path
vim.g.mapleader = ' '
vim.cmd('runtime plugin/thread.lua')
```

- [ ] **Step 2: The helpers**

`tests/helpers.lua`:

```lua
--- What the tests share: a git repository to work in, keys pressed the way
--- a person presses them, the screen as text, and time held still.

local H = {}

H.root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')

-- Commits the same every run, the plugin's snapshots included.
for k, v in pairs {
  GIT_AUTHOR_NAME = 't',
  GIT_AUTHOR_EMAIL = 't@t',
  GIT_COMMITTER_NAME = 't',
  GIT_COMMITTER_EMAIL = 't@t',
  GIT_AUTHOR_DATE = '2026-10-11T12:00:00Z',
  GIT_COMMITTER_DATE = '2026-10-11T12:00:00Z',
} do
  vim.env[k] = v
end

--- Run `cmd` in `cwd`; its output, or an error with its stderr.
---@param cwd string
---@param cmd string[]
---@return string
function H.sh(cwd, cmd)
  local out = vim.system(cmd, { cwd = cwd, text = true }):wait()
  if out.code ~= 0 then
    error(table.concat(cmd, ' ') .. ': ' .. (out.stderr or ''), 2)
  end
  return out.stdout or ''
end

---@param cwd string
---@param args string[]
---@return string
function H.git(cwd, args)
  return H.sh(cwd, vim.list_extend({ 'git' }, args))
end

--- A new git repository holding `files` (path -> lines), committed. The
--- editor's cwd moves there.
---@param files table<string, string[]>
---@return string root
function H.repo(files)
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, 'p')
  for path, lines in pairs(files) do
    vim.fn.mkdir(vim.fs.dirname(root .. '/' .. path), 'p')
    vim.fn.writefile(lines, root .. '/' .. path)
  end
  H.git(root, { 'init', '-q' })
  H.git(root, { 'add', '.' })
  H.git(root, { 'commit', '-qm', 'init' })
  vim.cmd('cd ' .. vim.fn.fnameescape(root))
  return root
end

--- The current batch, holding `threads` and any other fields in `data`,
--- saved the way the plugin saves it.
---@param threads table[]
---@param data table|nil
---@return table batch
function H.batch(threads, data)
  require('thread').ensure()
  local store = require 'thread.store'
  local batch = store.active(true)
  batch.data.threads = threads
  for k, v in pairs(data or {}) do
    batch.data[k] = v
  end
  store.save(batch)
  return store.active()
end

function H.press(keys)
  vim.api.nvim_feedkeys(vim.keycode(keys), 'xt', false)
end

function H.type_in(text)
  H.press('i' .. text .. '<Esc>')
end

function H.settle(ms)
  vim.wait(ms or 60, function()
    return false
  end)
end

--- The screen, a string a row.
---@return string[]
function H.screen()
  vim.cmd 'redraw'
  local rows = {}
  for r = 1, vim.o.lines do
    local line = {}
    for c = 1, vim.o.columns do
      line[#line + 1] = vim.fn.screenstring(r, c)
    end
    rows[r] = table.concat(line)
  end
  return rows
end

---@return integer|nil row, string|nil line
function H.on_screen(text)
  for r, line in ipairs(H.screen()) do
    if line:find(text, 1, true) then
      return r, line
    end
  end
end

function H.must_see(text, what)
  if not H.on_screen(text) then
    error(what .. ': expected to see ' .. vim.inspect(text) .. ' on screen:\n' .. table.concat(H.screen(), '\n'), 2)
  end
end

--- os.time() and os.date() without a time say `iso` from now on.
---@param iso string  `2026-10-11T12:00:00`
---@return fun() restore
function H.freeze_time(iso)
  local real_time, real_date = os.time, os.date
  local y, mo, d, h, mi, s = iso:match '(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)'
  local now = real_time { year = y, month = mo, day = d, hour = h, min = mi, sec = s }
  os.time = function(t)
    return t and real_time(t) or now
  end
  os.date = function(f, t)
    return real_date(f, t or now)
  end
  return function()
    os.time, os.date = real_time, real_date
  end
end

--- No walk, no floats, no buffers: a clean slate between tests.
function H.reset()
  pcall(function()
    if require('thread.walk').state() then
      require('thread.walk').stop()
    end
  end)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative ~= '' then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  vim.cmd 'silent! only'
  vim.cmd 'silent! %bwipe!'
end

return H
```

- [ ] **Step 3: Move the unit tests onto the runner**

```bash
git mv tests/spec.lua tests/model_spec.lua
```

In `tests/model_spec.lua`: replace the header comment and the local `failures, count`, `test` and `eq` definitions (lines 1-16) with

```lua
-- Tours, statuses, the text helpers and diagrams, without a window.

local R = require 'tests.runner'
local test, eq = R.test, R.eq
```

and delete the last five lines (the `io.stdout:write(... tests, ... failed)` report, the `cquit`, and `qa!`).

- [ ] **Step 4: The independence spec**

`tests/independence_spec.lua`:

```lua
-- thread.nvim stands alone: it requires only its own modules and Neovim's.
-- The one exception is the optional CodeDiff adapter.

local R = require 'tests.runner'
local H = require 'tests.helpers'

-- File -> module prefixes it may require besides thread's and vim's.
local ALLOWED = {
  ['lua/thread/git.lua'] = { 'codediff.' },
  -- Reads which-key's table, if loaded, to keep it off Home. Kept by the
  -- owner's decision; it loads nothing.
  ['lua/thread/home.lua'] = { 'which-key.config' },
}

local function required(line)
  local out = {}
  for name in line:gmatch "require%s*%(?%s*['\"]([^'\"]+)['\"]" do
    out[#out + 1] = name
  end
  for name in line:gmatch "pcall%(%s*require%s*,%s*['\"]([^'\"]+)['\"]" do
    out[#out + 1] = name
  end
  for name in line:gmatch "package%.loaded%[%s*['\"]([^'\"]+)['\"]" do
    out[#out + 1] = name
  end
  return out
end

R.test('thread.nvim requires no other plugin', function()
  for _, path in ipairs(vim.fn.globpath(H.root, 'lua/**/*.lua', false, true)) do
    local rel = path:sub(#H.root + 2)
    for n, line in ipairs(vim.fn.readfile(path)) do
      if not line:match '^%s*%-%-' then
        for _, name in ipairs(required(line)) do
          local fine = name == 'thread' or name:match '^thread%.' or name:match '^vim%.'
          for _, prefix in ipairs(ALLOWED[rel] or {}) do
            fine = fine or name:sub(1, #prefix) == prefix
          end
          R.ok(fine, string.format('%s:%d requires %s', rel, n, name))
        end
      end
    end
  end
end)
```

- [ ] **Step 5: The smoke test on the helpers**

In `tests/smoke.lua`:
- add `local H = require 'tests.helpers'` after the header comment;
- delete the local `sh`, `press`, `type_in`, `settle`, `screen`, `on_screen` and `must_see` functions, and replace the fixture setup (from `local plugin = vim.fn.getcwd()` through `vim.cmd('cd ' .. vim.fn.fnameescape(root))`) with:

```lua
local plugin = H.root
local root = H.repo {
  ['store.lua'] = {
    'local M = {}',
    '',
    'function M.get(store, key)',
    '  local cache = {}',
    '  return store[key]',
    'end',
    '',
    'function M.set(store, key, value)',
    '  store[key] = value',
    'end',
    '',
    'return M',
  },
  ['main.lua'] = { 'local store = require "store"', 'store.set({}, "a", 1)' },
}
local press, type_in, settle, on_screen = H.press, H.type_in, H.settle, H.on_screen
local function must_see(text, what)
  if not on_screen(text) then
    fail(what .. ': expected to see ' .. vim.inspect(text) .. ' on screen:\n' .. table.concat(H.screen(), '\n'))
  end
end
```

Keep `fail`, `eq`, the `notes`/`heard` capture and everything else as they are.

- [ ] **Step 6: Makefile**

```make
NVIM ?= nvim

.PHONY: test smoke check

# Unit tests: every tests/*_spec.lua. SPEC=name runs only those matching.
test:
	@$(NVIM) --headless --clean -u tests/minimal_init.lua -l tests/run.lua

# End to end: a thread, a tour walked, a review, the skill's checker.
smoke:
	@$(NVIM) --headless --clean -u tests/minimal_init.lua -l tests/smoke.lua

check: test smoke
```

- [ ] **Step 7: Run everything**

Run: `make check`
Expected: `10 tests, 0 failed` (9 moved + independence), `thread smoke: ok`.

Then break it on purpose to see the independence spec bite: add `local x = require 'telescope'` as the last line of `lua/thread/config.lua`, run `make test`, expect `FAIL thread.nvim requires no other plugin ... lua/thread/config.lua:76 requires telescope`, then remove the line.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "test: one runner and shared helpers, and a spec that keeps thread.nvim standalone"
```

---

### Task 5: Screen snapshots

Every screen thread.nvim draws, written as text: each window (float size and title/footer chunks, buffer lines, extmarks with their highlights, virt_text and virt_lines), then the screen grid. Compared with `tests/screens/<name>.txt`. This is what lets later tasks prove they changed nothing.

**Files:**
- Create: `tests/screens.lua`, `tests/screens/*.txt` (generated)
- Modify: `Makefile`, `.gitignore` (create it if missing)

**Interfaces:**
- Consumes: `tests.helpers` (Task 4).
- Produces: `make screens` (check) and `UPDATE=1 make screens` (write). Later tasks run `make check`, which includes it.

- [ ] **Step 1: Write `tests/screens.lua`**

```lua
-- Every screen thread.nvim draws, as text: each window (a float's size,
-- title and footer; the buffer's lines; its extmarks), then the screen
-- itself. Compared with tests/screens/<name>.txt, so a change to what you
-- see fails. `make screens` checks; `UPDATE=1 make screens` writes them.

local H = require 'tests.helpers'

local dir = H.root .. '/tests/screens'
local update = vim.env.UPDATE == '1'
local failures = {}
local diff = vim.text and vim.text.diff or vim.diff

vim.o.columns, vim.o.lines = 120, 40
vim.o.signcolumn = 'yes:2'
vim.notify = function() end
H.freeze_time '2026-10-11T12:00:00'

----------------------------------------------------------------------
-- The fixture: a repository, work in progress, and a batch written out
----------------------------------------------------------------------

local root = H.repo {
  ['store.lua'] = {
    'local M = {}',
    '',
    'function M.get(store, key)',
    '  local cache = {}',
    '  return store[key]',
    'end',
    '',
    'function M.set(store, key, value)',
    '  store[key] = value',
    'end',
    '',
    'return M',
  },
  ['main.lua'] = { 'local store = require "store"', 'store.set({}, "a", 1)' },
}
vim.fn.writefile({ '/.threads/' }, root .. '/.git/info/exclude')
local head = vim.trim(H.git(root, { 'rev-parse', 'HEAD' }))
-- What the review and thread 3's change read: a changed line, and a file
-- git does not track.
vim.fn.writefile({ 'local store = require "store"', 'store.set({}, "a", 2)' }, root .. '/main.lua')
vim.fn.writefile({ 'return 1' }, root .. '/extra.lua')

local data = {
  title = 'Screens',
  reply = 'inline',
  rounds = { { sent = '2026-10-11T11:00:00', snapshot = head } },
  threads = {
    {
      id = 1,
      title = 'How get works',
      file = 'store.lua',
      line = 3,
      text = 'function M.get(store, key)',
      status = 'open',
      messages = {
        { from = 'you', round = 1, text = 'How does get work?' },
        {
          from = 'agent',
          at = '2026-10-11T11:30:00',
          text = 'It reads the store. **One stage**, three steps. See #3.',
          verdict = 'how it works',
          diagram = {
            kind = 'flow',
            nodes = { { id = 'a', label = 'M.get', file = 'store.lua', text = 'function M.get(store, key)' }, { id = 'b', label = 'store' } },
            edges = { { from = 'a', to = 'b', label = 'reads' } },
          },
          walk = {
            { stage = 'Reading is a lookup', point = 'get never writes.', body = '```code\n{ "file": "store.lua", "text": "  return store[key]", "lines": 2 }\n```' },
            {
              file = 'store.lua',
              line = 4,
              text = '  local cache = {}',
              title = 'the cache is thrown away',
              body = 'A new table each call.',
              notes = { { line = 4, text = '  local cache = {}', note = 'new every call', mark = 'cache' } },
            },
            { file = 'store.lua', line = 9, text = '  store[key] = value', title = 'set writes straight through', body = 'No cache to update.' },
            { file = 'store.lua', line = 30, text = '  gone()', title = 'a step whose line went', body = 'It moved.' },
          },
        },
      },
    },
    {
      id = 2,
      on = { thread = 1, step = 2 },
      file = 'store.lua',
      line = 4,
      text = '  local cache = {}',
      status = 'open',
      messages = { { from = 'you', round = 1, text = 'Should the cache move to the module?' } },
    },
    {
      id = 3,
      title = 'Who else reads it · 誰が読む',
      status = 'open',
      messages = {
        { from = 'you', round = 1, text = 'What else reads the store?' },
        { from = 'agent', at = '2026-10-11T11:45:00', text = '`main.lua` does, once.', changes = { { file = 'main.lua', line = 2, text = 'store.set({}, "a", 2)' } } },
      },
    },
    {
      id = 4,
      file = 'main.lua',
      line = 1,
      text = 'local store = require "store"',
      status = 'closed',
      messages = { { from = 'you', round = 1, text = 'Rename it?' }, { from = 'agent', at = '2026-10-11T11:10:00', text = 'Done.' } },
    },
    {
      id = 5,
      title = 'Writing to the store',
      status = 'open',
      messages = { {
        from = 'agent',
        at = '2026-10-11T11:50:00',
        text = 'Where writes go.',
        walk = {
          { stage = 'Writes go straight in', point = 'set has no cache.', verdict = 'fine', body = 'Nothing to keep in step.' },
          { file = 'store.lua', line = 8, text = 'function M.set(store, key, value)', body = 'The whole of set.' },
        },
      } },
    },
    {
      id = 6,
      title = 'Review: the value',
      status = 'open',
      messages = { {
        from = 'agent',
        at = '2026-10-11T11:55:00',
        text = 'One change, and a new file.',
        review = {
          diff = { of = 'uncommitted' },
          groups = { {
            title = 'the value is 2 now',
            kind = 'fix',
            risk = 'high',
            risk_why = 'callers read it',
            body = 'It was 1.',
            hunks = { { file = 'main.lua', text = 'store.set({}, "a", 2)', line = 2, note = 'the new value' } },
            affected = { { file = 'store.lua', text = 'function M.set(store, key, value)', line = 8, note = 'what it calls' } },
          } },
        },
      } },
    },
  },
}
vim.fn.mkdir(root .. '/.threads', 'p')
vim.fn.writefile(vim.split(require('thread.json').encode(data), '\n'), root .. '/.threads/screens.json')
vim.fn.writefile({ 'screens' }, root .. '/.threads/active')
-- The batches menu says how long ago each file changed.
vim.uv.fs_utime(root .. '/.threads/screens.json', os.time() - 600, os.time() - 600)

----------------------------------------------------------------------
-- Writing a screen out
----------------------------------------------------------------------

local function hl_name(h)
  if type(h) == 'table' then
    return table.concat(vim.tbl_map(tostring, h), '+')
  end
  return h == nil and '' or tostring(h)
end

local function chunks(list)
  if type(list) ~= 'table' then
    return tostring(list)
  end
  local out = {}
  for _, c in ipairs(list) do
    out[#out + 1] = '[' .. tostring(c[1]) .. '|' .. hl_name(c[2]) .. ']'
  end
  return table.concat(out)
end

local function ns_name(id)
  for name, n in pairs(vim.api.nvim_get_namespaces()) do
    if n == id then
      return name
    end
  end
  return tostring(id)
end

local FIELDS = { 'hl_group', 'line_hl_group', 'number_hl_group', 'sign_text', 'sign_hl_group', 'virt_text_pos', 'virt_text_win_col', 'priority', 'hl_eol', 'virt_lines_above' }

local function mark_lines(m)
  local d = m[4]
  local parts = { ns_name(d.ns_id), m[2] .. ':' .. m[3] }
  if d.end_row then
    parts[#parts + 1] = 'to ' .. d.end_row .. ':' .. tostring(d.end_col)
  end
  for _, k in ipairs(FIELDS) do
    if d[k] ~= nil then
      parts[#parts + 1] = k .. '=' .. hl_name(d[k])
    end
  end
  if d.virt_text then
    parts[#parts + 1] = 'vt=' .. chunks(d.virt_text)
  end
  local out = { table.concat(parts, ' ') }
  for _, vl in ipairs(d.virt_lines or {}) do
    out[#out + 1] = '    vl ' .. chunks(vl)
  end
  return out
end

local function window(win)
  local c = vim.api.nvim_win_get_config(win)
  local buf = vim.api.nvim_win_get_buf(win)
  local out = {}
  if c.relative ~= '' then
    out[#out + 1] = string.format('== float %dx%d at %s,%s z%s', c.width, c.height, tostring(c.row), tostring(c.col), tostring(c.zindex))
    if c.title then
      out[#out + 1] = 'title ' .. chunks(c.title)
    end
    if c.footer then
      out[#out + 1] = 'footer ' .. chunks(c.footer)
    end
  else
    out[#out + 1] = string.format('== window %dx%d', vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win))
  end
  out[#out + 1] = 'buffer ' .. (vim.bo[buf].filetype ~= '' and vim.bo[buf].filetype or '-') .. ' ' .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':t')
  local bar = vim.wo[win].winbar
  if bar ~= '' then
    out[#out + 1] = 'winbar ' .. (bar:find('thread.walk', 1, true) and require('thread.walk').bar() or bar)
  end
  out[#out + 1] = 'cursor ' .. table.concat(vim.api.nvim_win_get_cursor(win), ':')
  for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    out[#out + 1] = string.format('%3d|%s', i, l)
  end
  -- Highlights sorted, so the order they were made in does not matter;
  -- marks that draw something in the order Neovim keeps them.
  local hls, drawn = {}, {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
    local d = m[4]
    if d.virt_text or d.virt_lines or d.sign_text then
      vim.list_extend(drawn, mark_lines(m))
    else
      hls[#hls + 1] = mark_lines(m)[1]
    end
  end
  table.sort(hls)
  vim.list_extend(out, hls)
  vim.list_extend(out, drawn)
  return out
end

local function order(a, b)
  local ca, cb = vim.api.nvim_win_get_config(a), vim.api.nvim_win_get_config(b)
  local fa, fb = ca.relative ~= '', cb.relative ~= ''
  if fa ~= fb then
    return not fa
  end
  if (ca.zindex or 0) ~= (cb.zindex or 0) then
    return (ca.zindex or 0) < (cb.zindex or 0)
  end
  local pa, pb = vim.api.nvim_win_get_position(a), vim.api.nvim_win_get_position(b)
  if pa[1] ~= pb[1] then
    return pa[1] < pb[1]
  end
  return pa[2] < pb[2]
end

local function capture(name)
  H.settle()
  local wins = vim.api.nvim_tabpage_list_wins(0)
  table.sort(wins, order)
  local out = {}
  for _, w in ipairs(wins) do
    vim.list_extend(out, window(w))
  end
  out[#out + 1] = '== screen'
  for _, row in ipairs(H.screen()) do
    out[#out + 1] = (row:gsub('%s+$', ''))
  end
  for i, l in ipairs(out) do
    out[i] = (l:gsub(vim.pesc(root), '<root>'))
  end
  local path = dir .. '/' .. name .. '.txt'
  if update then
    vim.fn.mkdir(dir, 'p')
    vim.fn.writefile(out, path)
    return
  end
  local want = vim.fn.filereadable(path) == 1 and vim.fn.readfile(path) or {}
  if vim.deep_equal(want, out) then
    os.remove(path .. '.actual')
  else
    vim.fn.writefile(out, path .. '.actual')
    failures[#failures + 1] = '--- ' .. name .. '\n' .. diff(table.concat(want, '\n') .. '\n', table.concat(out, '\n') .. '\n')
  end
end

----------------------------------------------------------------------
-- The screens
----------------------------------------------------------------------

require('thread').setup {}
local store = require 'thread.store'
local render = require 'thread.render'
local home = require 'thread.home'
local page = require 'thread.page'
local walk = require 'thread.walk'
local rpage = require 'thread.review_page'

vim.cmd.edit 'store.lua'
local code_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(code_win, { 3, 0 })
render.refresh()
capture 'code-bubbles'
render.toggle()
capture 'code-one-line'
render.toggle()

home.open()
capture 'home-threads'
H.press 'o'
capture 'home-threads-open'
H.press '2'
capture 'home-tours'
H.press '3'
capture 'home-review'
H.press '4'
capture 'home-closed'
H.press '1'
H.press '?'
capture 'home-help'
H.press 'q'
home.close()

home.focus { comment = store.find(store.active(), 1) }
capture 'focus-float'
home.close()

page.open(5, 0)
capture 'page-overview'
page.close()
page.open(1, 1)
capture 'page-stage'
H.press 'M'
capture 'page-stage-outline'
H.press 'M'
page.close()
page.open(1, 4)
capture 'page-step-gone'
page.close()

vim.api.nvim_set_current_win(code_win)
walk.start(1, 2)
capture 'walk-step'
walk.stop()

require('thread.map').pin()
capture 'map-batch'
require('thread.map').close()

require('thread.menu').open()
capture 'menu'
H.press 'q'

rpage.open { owner = 6 }
capture 'review-groups'
H.press 'j'
H.press '<CR>'
capture 'review-group'
H.press 'o'
capture 'review-hunk-open'
H.press 'o'
H.press '<CR>'
capture 'review-walk-hunk'
walk.stop()
rpage.close()

vim.cmd.edit(root .. '/main.lua')
render.toggle_drawn(3)
capture 'code-changes-drawn'
render.toggle_drawn(3)

vim.o.columns = 70
home.open()
capture 'home-narrow'
home.close()
vim.o.columns = 120

if #failures > 0 then
  io.stderr:write('screens changed; the new ones are in tests/screens/*.actual\n' .. table.concat(failures, '\n') .. '\n')
  vim.cmd 'cquit 1'
end
io.stdout:write(update and 'screens: written\n' or 'screens: ok\n')
vim.cmd 'qa!'
```

- [ ] **Step 2: Makefile and .gitignore**

Add to the `Makefile` (and to `.PHONY`):

```make
# Every screen as text, against tests/screens/. UPDATE=1 writes them anew.
screens:
	@UPDATE=$(UPDATE) $(NVIM) --headless --clean -u tests/minimal_init.lua -l tests/screens.lua
```

and make `check: test screens smoke`. Add `tests/screens/*.actual` to `.gitignore`.

- [ ] **Step 3: Write the snapshots and read every one**

Run: `UPDATE=1 make screens`
Expected: `screens: written`, and 23 files in `tests/screens/`.

Open each file and check its screen section shows what its name says: `home-tours` shows the tours tab, `walk-step` shows the step's card above line 4 with `① new every call`, `review-walk-hunk` has a `vl` line holding `store.set({}, "a", 1)`, `page-step-gone` says the line moved or went, `home-help` shows the help, `menu` the batches list, and so on. If an entry point does not do what the sequence assumes (for example `q` doesn't close the help), change the sequence so each screen is what its name says, and say so in the commit message. If a screen captures an error message instead of the screen, that's a bug to report, not to snapshot.

- [ ] **Step 4: Prove they are stable**

Run: `make screens && make screens`
Expected: `screens: ok` twice. If a screen differs between runs (a time, a temp path, a SHA), find where it comes from and pin it in the fixture (the clock is frozen, git dates are fixed by `tests/helpers.lua`, the root is replaced by `<root>`). Never loosen the comparison.

- [ ] **Step 5: Full check and commit**

Run: `make check` → `10 tests, 0 failed`, `screens: ok`, `thread smoke: ok`.

```bash
git add -A && git commit -m "test: screen snapshots of everything thread.nvim draws"
```

---

## Phase B: bug fixes

Every task: write the failing test, run it and see it fail for the reason given, fix, see it pass, run `make check`. If the fix changes a screen, run `UPDATE=1 make screens`, read `git diff tests/screens`, and keep only the change the fix explains.

### Task 6: `a` in Home's review tab does nothing

The loop at the end of `KEYS` (home.lua ~2725) makes a list of keys do nothing, and `'a'` is in it, so it overwrites `KEYS.a` (~2473). Home's help and the review tab's hints advertise `a`.

**Files:**
- Create: `tests/home_spec.lua`
- Modify: `lua/thread/home.lua` (the no-op key list)

- [ ] **Step 1: Failing test**

`tests/home_spec.lua`:

```lua
-- Home: keys that act on the row you are on.

local R = require 'tests.runner'
local H = require 'tests.helpers'

R.test('home: a in the review tab accepts the group you are on', function()
  H.reset()
  local root = H.repo { ['main.lua'] = { 'local x = 1' } }
  vim.fn.writefile({ 'local x = 2' }, root .. '/main.lua')
  H.batch { {
    id = 1,
    title = 'Review',
    status = 'open',
    messages = { {
      from = 'agent',
      text = 'One change.',
      review = {
        diff = { of = 'uncommitted' },
        groups = { { title = 'two now', kind = 'fix', risk = 'low', body = 'b', hunks = { { file = 'main.lua', text = 'local x = 2', line = 1 } } } },
      },
    } },
  } }
  local store, review, home = require 'thread.store', require 'thread.review', require 'thread.home'
  review.invalidate()
  home.open { view = 'review' }
  H.settle()
  H.press 'j' -- from the review's row to its group's
  H.settle()
  H.press 'a'
  H.settle()
  local owner = store.find(store.active(), 1)
  local group = review.work(review.of(owner)).groups[1]
  R.eq(review.state(store.active(), 1, group), 'accepted', 'the group is accepted')
  home.close()
end)
```

Run: `SPEC=home make test`
Expected: `FAIL home: a in the review tab accepts ...: the group is accepted: expected "accepted", got "open"`. If it fails another way (the row after `j` isn't the group), look at `home-review.txt` to see the rows and adjust the presses until the only reason left is the no-op `a`.

- [ ] **Step 2: Fix**

In home.lua, remove `'a', ` from the list in `for _, lhs in ipairs { '5', '6', ... } do KEYS[lhs] = function() end end`. Keep `'A'`.

- [ ] **Step 3: Pass, check, commit**

Run: `SPEC=home make test` → `1 tests, 0 failed`. Run: `make check` → all pass, screens unchanged.

```bash
git add -A && git commit -m "fix: a in Home's review tab accepts again; the no-op keys took it"
```

---

### Task 7: The diff reader drops lines that start with `-- ` or `++ `

`parse` in review.lua (~158-221) skips any line starting `--- ` and takes any line starting `+++ ` as a file header, even inside a hunk. A removed Lua comment (`-- note`) reads `--- note` in the diff and is lost; so is an added line `++ x`. Counts, the drawn old lines and the accept-by-content key go wrong.

**Files:**
- Create: `tests/review_spec.lua`
- Modify: `lua/thread/review.lua` (`parse`)

- [ ] **Step 1: Failing test**

`tests/review_spec.lua`:

```lua
-- Reviews: the diff read from git, grouped, accepted.

local R = require 'tests.runner'
local H = require 'tests.helpers'

R.test('review: a removed line starting -- and an added one starting ++ are kept', function()
  H.reset()
  local root = H.repo { ['a.lua'] = { 'local x = 1', '-- old note', 'return x' } }
  vim.fn.writefile({ 'local x = 1', '++ new', 'return x' }, root .. '/a.lua')
  local review = require 'thread.review'
  review.invalidate()
  local f = review.file(review.spec { of = 'uncommitted' }, 'a.lua')
  R.eq({ f.add, f.del }, { 1, 1 }, 'a line each way')
  local part = f.hunks[1].parts[1]
  R.eq(part.old, { '-- old note' }, 'the removed line')
  R.eq(part.new, { '++ new' }, 'the added line')
end)
```

Run: `SPEC=review make test` → FAIL on `a line each way` (`{0, 0}` or `{1, 0}`).

- [ ] **Step 2: Fix: read exactly as many lines as the hunk header says**

In `parse`, add `local left_old, left_new = 0, 0` next to `local files, f, parts`. Make the first branch of the loop consume hunk lines while the header's counts last, so file headers are only looked for between hunks:

```lua
  for line in (out .. '\n'):gmatch '(.-)\n' do
    if part and (left_old > 0 or left_new > 0) then
      -- Inside a hunk: its header said how many lines of each side follow.
      local c = line:sub(1, 1)
      if c == '-' and left_old > 0 then
        part.old[#part.old + 1] = line:sub(2)
        f.del = f.del + 1
        left_old = left_old - 1
      elseif c == '+' and left_new > 0 then
        part.new[#part.new + 1] = line:sub(2)
        f.add = f.add + 1
        left_new = left_new - 1
      end
      -- `\ No newline at end of file` and the like: skipped.
    elseif line:match '^diff %-%-git ' then
```

Keep the existing `diff --git`, `+++ `, `new file mode`, `deleted file mode`, `Binary files` and `@@ ` branches as they are, add `left_old, left_new = part.old_count, part.new_count` at the end of the `@@ ` branch, and delete the two old branches that read `-` and `+` lines (`elseif part and line:sub(1, 1) == '-' and not line:match '^%-%-%- ' then ...` and `elseif part and line:sub(1, 1) == '+' then ...`).

- [ ] **Step 3: Pass, check, commit**

Run: `SPEC=review make test` → pass. Run: `make check` → all pass, screens unchanged.

```bash
git add -A && git commit -m "fix: read a hunk's lines by its header's counts, so -- and ++ lines are not taken for headers"
```

---

### Task 8: `git.show` keeps stale contents for `HEAD`, the index and branches

`git.show` (git.lua ~86-107) caches `rev:file` forever because "a commit's files never change". But reviews ask for `HEAD`, the index (`''`) and branch names, which move. After `git add` or a commit, reviews read the old file.

**Files:**
- Create: `tests/git_spec.lua`
- Modify: `lua/thread/git.lua` (`show`, new `forget`), `lua/thread/review.lua` (`invalidate`)

**Interfaces:**
- Produces: `git.forget()` — drops what was read at revisions that move. `review.invalidate()` calls it.

- [ ] **Step 1: Failing tests**

`tests/git_spec.lua`:

```lua
-- git: files at a revision, hunks, snapshots.

local R = require 'tests.runner'
local H = require 'tests.helpers'

R.test('git.show: HEAD and the index are read again once the code changes', function()
  H.reset()
  local root = H.repo { ['a.lua'] = { 'one' } }
  local git, review = require 'thread.git', require 'thread.review'
  R.eq(git.show('HEAD', 'a.lua'), { 'one' }, 'HEAD')
  R.eq(git.show('', 'a.lua'), { 'one' }, 'the index')
  vim.fn.writefile({ 'two' }, root .. '/a.lua')
  H.git(root, { 'add', 'a.lua' })
  review.invalidate()
  R.eq(git.show('', 'a.lua'), { 'two' }, 'the index after git add')
  H.git(root, { 'commit', '-qm', 'two' })
  review.invalidate()
  R.eq(git.show('HEAD', 'a.lua'), { 'two' }, 'HEAD after a commit')
end)

R.test('git.show: a commit by its sha is read once', function()
  H.reset()
  local root = H.repo { ['a.lua'] = { 'one' } }
  local git = require 'thread.git'
  local sha = vim.trim(H.git(root, { 'rev-parse', 'HEAD' }))
  R.eq(git.show(sha, 'a.lua'), { 'one' }, 'first read')
  local real, calls = vim.system, 0
  vim.system = function(...)
    calls = calls + 1
    return real(...)
  end
  git.show(sha, 'a.lua')
  require('thread.review').invalidate()
  git.show(sha, 'a.lua')
  vim.system = real
  R.eq(calls, 0, 'never read again')
end)
```

Run: `SPEC=git make test` → the first test fails at `the index after git add` (got `{ 'one' }`).

- [ ] **Step 2: Fix**

Replace `shown` and `M.show` in git.lua with:

```lua
local shown = {} -- sha:file -> lines|false; a commit's files never change
local moving = {} -- rev:file -> lines|false, for revisions that move: HEAD, the index, a branch

--- Forget what was read at revisions that move: the code changed.
function M.forget()
  moving = {}
end

--- A file as it was at a revision, or nil if it did not exist.
---@param rev string  a sha, a ref, or '' for the index
---@param file string
---@return string[]|nil
function M.show(rev, file)
  local key = rev .. ':' .. file
  local cache = (#rev == 40 and rev:match '^%x+$') and shown or moving
  if cache[key] == nil then
    local out = vim.system({ 'git', '-C', store.root(), 'show', key }, { text = true }):wait()
    if out.code == 0 then
      local lines = vim.split(out.stdout, '\n', { plain = true })
      if lines[#lines] == '' then
        lines[#lines] = nil
      end
      cache[key] = lines
    else
      cache[key] = false
    end
  end
  return cache[key] or nil
end
```

In review.lua `M.invalidate`, add `require('thread.git').forget()` as its first line.

- [ ] **Step 3: Pass, check, commit**

Run: `SPEC=git make test` → `2 tests, 0 failed`. Run: `make check` → all pass, screens unchanged.

```bash
git add -A && git commit -m "fix: re-read HEAD, the index and branches after the code changes; only a sha is cached for good"
```

---

### Task 9: Saving reorders review and diagram keys, and turns their empty lists into `{}`

json.lua's `ORDER` has none of the keys a review or a diagram uses, and `LISTS` none of their lists, so a save reshuffles them and writes `"tests": []` back as `"tests": {}`.

**Files:**
- Create: `tests/json_spec.lua`
- Modify: `lua/thread/json.lua` (`ORDER`, `LISTS`)

- [ ] **Step 1: Failing tests**

`tests/json_spec.lua`:

```lua
-- The batch file's JSON: a fixed key order, lists kept lists.

local R = require 'tests.runner'
local json = require 'thread.json'

R.test('json: empty review and diagram lists stay lists', function()
  local v = {
    review = { groups = { { title = 'g', hunks = {}, affected = {}, tests = {} } } },
    diagram = { kind = 'flow', nodes = {}, edges = {} },
  }
  local again = json.encode(json.decode(json.encode(v)))
  for _, key in ipairs { 'hunks', 'affected', 'tests', 'nodes', 'edges' } do
    R.ok(again:find('"' .. key .. '": []', 1, true), key .. ' stays []:\n' .. again)
  end
end)

R.test('json: a review reads top to bottom', function()
  local s = json.encode {
    review = {
      groups = { { tests = {}, affected = {}, hunks = { { note = 'n', text = 'x', line = 1, file = 'a' } }, body = 'b', risk_why = 'w', risk = 'low', kind = 'fix', title = 'g' } },
      diff = { of = 'uncommitted' },
    },
  }
  local seen = {}
  for key in s:gmatch '"([%w_]+)":' do
    seen[#seen + 1] = key
  end
  R.eq(seen, { 'review', 'diff', 'of', 'groups', 'title', 'kind', 'risk', 'risk_why', 'body', 'hunks', 'file', 'line', 'text', 'note', 'affected', 'tests' }, 'key order')
end)
```

Run: `SPEC=json make test` → both fail.

- [ ] **Step 2: Fix**

Set `ORDER` and `LISTS` to the following. A group reads the way a person reads it (title, kind, risk, why, body, then its lists); `kind` sits right after `title`, which a diagram doesn't have, so a diagram's `kind` still comes first.

```lua
for i, key in ipairs {
  'id', 'stage', 'title', 'kind', 'direction', 'risk', 'risk_why',
  'on', 'thread', 'step', 'point', 'reply',
  'diff', 'of', 'base', 'head', 'rounds', 'sent', 'snapshot', 'threads',
  'from', 'round', 'at', 'file', 'rev', 'line', 'lines', 'text', 'mark', 'note',
  'status', 'verdict', 'severity', 'body', 'messages', 'notes', 'changes', 'diagram', 'walk',
  'review', 'groups', 'hunks', 'affected', 'tests',
  'participants', 'nodes', 'edges', 'label', 'to', 'side', 'dashed', 'children',
} do
  ORDER[key] = i
end

--- Keys that hold lists, so an empty one is written `[]` rather than `{}`.
local LISTS = {
  threads = true, rounds = true, messages = true, changes = true, notes = true, walk = true,
  groups = true, hunks = true, affected = true, tests = true, participants = true, nodes = true, edges = true, children = true,
}
```

With this, the test's review comes out `review, diff, of, groups, title, kind, risk, risk_why, body, hunks, file, line, text, note, affected, tests`.

Then check nothing is missing: `grep -n "fail('%s\.\|\.risk_why\|\.affected\|\.tests\|\.participants\|\.children\|\.dashed\|\.direction" lua/thread/review.lua lua/thread/diagram/*.lua` lists the fields a review or a diagram reads. Add any key it finds that is not above (at the end of `ORDER`), and a list-valued one to `LISTS` too.

- [ ] **Step 3: Pass, check, commit**

Run: `SPEC=json make test` → pass. Run: `make check` → all pass. Screens should not change, since key order is never drawn; if one does, find out why before going on.

```bash
git add -A && git commit -m "fix: keep review and diagram keys in a fixed order and their empty lists as []"
```

---

### Task 10: Keys taken from the buffer instead of the global mapping

Two places save the mapping a key had before thread.nvim mapped it, with `vim.fn.maparg(lhs, 'n', false, true)`, which returns the current buffer's own mapping when it has one:

- `init.lua` `on_comment` (~133-165): at `VeryLazy` the current buffer may be a dashboard with its own `<CR>`. thread then calls that dead dashboard callback for Enter anywhere off a thread.
- `walk.lua` `set_keys` (~60-70): when the current buffer has its own `L`, it saves `false`, then on stop deletes the global `L` and never puts the user's back.

**Files:**
- Create: `lua/thread/keys.lua`, `tests/keys_spec.lua`
- Modify: `lua/thread/init.lua` (`on_comment`), `lua/thread/walk.lua` (`set_keys`)

**Interfaces:**
- Produces: `keys.global(lhs) -> table|nil` — the global normal-mode mapping of `lhs` as `maparg(..., true)` gives it, ignoring any buffer's own. Task 24 adds the rest of `keys`.

- [ ] **Step 1: Failing tests**

`tests/keys_spec.lua`:

```lua
-- Keys thread.nvim lays over yours: the global mapping is the one kept,
-- whatever the current buffer maps.

local R = require 'tests.runner'
local H = require 'tests.helpers'

R.test('walk: a buffer of its own L does not cost you your global L', function()
  H.reset()
  H.repo { ['a.lua'] = { 'x' } }
  vim.keymap.set('n', 'L', '<Cmd>let g:thread_test_L = "global"<CR>', { desc = 'mine' })
  vim.cmd.edit 'a.lua'
  vim.keymap.set('n', 'L', '<Cmd>let g:thread_test_L = "buffer"<CR>', { buffer = 0 })
  H.batch { { id = 1, title = 't', status = 'open', messages = { { from = 'agent', text = 'x', walk = { { file = 'a.lua', line = 1, text = 'x', body = 'b' } } } } } }
  local walk = require 'thread.walk'
  walk.start(1, 1)
  H.settle()
  walk.stop()
  H.settle()
  local g = require('thread.keys').global 'L'
  R.eq(g and g.desc, 'mine', 'the global L is back')
  R.eq(vim.fn.maparg('L', 'n', false, true).buffer, 1, 'and the buffer has its own')
  vim.keymap.del('n', 'L')
  vim.keymap.del('n', 'L', { buffer = 0 })
end)

R.test("Enter off a thread does what the global Enter did, not a buffer's", function()
  H.reset()
  H.repo { ['a.lua'] = { 'x' } }
  pcall(vim.keymap.del, 'n', '<CR>')
  vim.keymap.set('n', '<CR>', function()
    vim.g.thread_test_enter = 'global'
  end, { desc = 'global enter' })
  local dashboard = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(dashboard)
  vim.keymap.set('n', '<CR>', function()
    vim.g.thread_test_enter = 'dashboard'
  end, { buffer = dashboard })
  -- Set up afresh while the "dashboard" is current, as at VeryLazy.
  package.loaded['thread'] = nil
  require('thread').setup {}
  vim.cmd.edit 'a.lua'
  vim.g.thread_test_enter = nil
  H.press '<CR>'
  H.settle()
  R.eq(vim.g.thread_test_enter, 'global', 'the global Enter ran')
end)
```

Run: `SPEC=keys make test` → both fail. The second fails on `the global Enter ran` (got "dashboard"). The first calls `thread.keys`, which Step 2 creates, so until then it fails on the missing module; create the module with Step 2's code, leave walk.lua alone, run again, and see it fail on `the global L is back` (got nil). That is the bug.

- [ ] **Step 2: `keys.global`**

`lua/thread/keys.lua`:

```lua
--- Keys thread.nvim lays over yours, and gives back.

local M = {}

--- The global normal-mode mapping of `lhs`, as maparg() gives it, ignoring
--- any mapping the current buffer has of its own.
---@param lhs string
---@return table|nil
function M.global(lhs)
  local want = vim.keycode(lhs)
  for _, m in ipairs(vim.api.nvim_get_keymap 'n') do
    if vim.keycode(m.lhs) == want then
      return m
    end
  end
end

return M
```

- [ ] **Step 3: Use it**

`init.lua` `on_comment`: replace `local old = vim.fn.maparg(lhs, 'n', false, true)` with `local old = require('thread.keys').global(lhs)`.

`walk.lua` `set_keys`: replace the two lines

```lua
    local old = vim.fn.maparg(k.lhs, 'n', false, true)
    W.saved[k.lhs] = (old and old.lhs and old.buffer ~= 1) and old or false
```

with

```lua
    W.saved[k.lhs] = keys.global(k.lhs) or false
```

and add `local keys = require 'thread.keys'` to walk.lua's requires.

Check that `vim.fn.mapset('n', false, old)` in `restore_keys` accepts what `nvim_get_keymap` returns (the first test proves it). If it doesn't, convert in `keys.global` by returning `vim.fn.maparg(m.lhs, 'n', false, true)` evaluated with no buffer mapping in the way: `vim.api.nvim_buf_call(<a scratch buffer>, ...)`.

- [ ] **Step 4: Pass, check, commit**

Run: `SPEC=keys make test` → pass. Run: `make check` → all pass, screens unchanged.

```bash
git add -A && git commit -m "fix: remember the global mapping a key had, not the current buffer's"
```

---

### Task 11: A function call is taken for a function

Dimming (`render.lua` `scope`, ~1085) and the code shown under a thread (`home.lua` `scope`, ~355) climb the syntax tree to the first node whose type contains `function`, `method`, `class`, `impl` or `struct`. Lua's `function_call` (and Java's `method_invocation`) match, so a thread on a call dims everything but the call.

**Files:**
- Create: `lua/thread/code.lua`, `tests/code_spec.lua`
- Modify: `lua/thread/render.lua` (`scope`), `lua/thread/home.lua` (`scope`)

**Interfaces:**
- Produces: `code.enclosing(root, lo, hi) -> lo|nil, hi|nil` — the 1-based line range of the function, method, class, impl or struct around lines `lo..hi` of the tree whose root node is `root`. Task 20 adds more to `code`.

- [ ] **Step 1: Failing test**

`tests/code_spec.lua`:

```lua
-- Code: the scope around a line, syntax colours, code rows on a sheet.

local R = require 'tests.runner'

local function tree(lines, lang)
  return vim.treesitter.get_string_parser(table.concat(lines, '\n'), lang):parse()[1]:root()
end

R.test('code.enclosing: a call is not a scope', function()
  local root = tree({ 'local function outer()', '  print(1)', '  helper(', '    2', '  )', 'end' }, 'lua')
  R.eq({ require('thread.code').enclosing(root, 4, 4) }, { 1, 6 }, 'the function around the call')
end)

R.test('code.enclosing: nothing around top-level code', function()
  local root = tree({ 'local x = 1', 'print(x)' }, 'lua')
  R.eq({ require('thread.code').enclosing(root, 2, 2) }, {}, 'no scope')
end)
```

Run: `SPEC=code make test` → fails (no module). Write `enclosing` with the old test (`ty:find 'function' or ...`) first and see the first test fail with `{ 3, 5 }`; that is the bug.

- [ ] **Step 2: Fix**

`lua/thread/code.lua`:

```lua
--- Code drawn outside its buffer: the scope around a line, and (Task 20)
--- syntax colours and rows of code on a sheet.

local M = {}

--- Whether a syntax node holds a body of code: a function, method, class,
--- impl or struct, and not a call of one.
local function holds_code(ty)
  if ty:find 'call' or ty:find 'invocation' then
    return false
  end
  return ty:find 'function' or ty:find 'method' or ty:find 'class' or ty:find 'impl' or ty:find 'struct'
end

--- The lines (1-based) of the function, method or class around lines
--- `lo`..`hi` of the tree under `root`; nothing when there is none.
---@param root TSNode
---@param lo integer
---@param hi integer
---@return integer|nil, integer|nil
function M.enclosing(root, lo, hi)
  local node = root:named_descendant_for_range(lo - 1, 0, hi - 1, 0)
  while node do
    if holds_code(node:type()) then
      local sr, _, er, ec = node:range()
      return sr + 1, ec == 0 and er or er + 1
    end
    node = node:parent()
  end
end

return M
```

In `render.lua` `scope`, replace the `local node = ...` line and the `while node do ... end` loop with:

```lua
    local slo, shi = root and require('thread.code').enclosing(root, lo, hi)
    if slo then
      return slo, shi
    end
```

In `home.lua` `scope`, replace the `local node = trees[1]:root()...` line and its `while` loop with:

```lua
    local slo, shi = require('thread.code').enclosing(trees[1]:root(), t.line, t.to)
    if slo then
      lo, hi = slo, shi
    end
```

- [ ] **Step 3: Pass, check, commit**

Run: `make check` → all pass. Screens unchanged (the fixture's threads sit on functions, not calls).

```bash
git add -A && git commit -m "fix: a function call is not the scope a thread is in"
```

---

### Task 12: `home.open { focus = ... }` on an open Home ignores `focus`

`M.open` (home.lua ~3043) only re-picks when `opts.view` is given, so `focus` without `view` is dropped when Home is already open.

**Files:**
- Modify: `lua/thread/home.lua` (`M.open`), `tests/home_spec.lua`

- [ ] **Step 1: Failing test** (append to `tests/home_spec.lua`)

```lua
R.test('home.open: focus moves the cursor to that thread when Home is already open', function()
  H.reset()
  H.repo { ['a.lua'] = { 'x', 'y' } }
  H.batch {
    { id = 1, file = 'a.lua', line = 1, text = 'x', status = 'open', messages = { { from = 'you', text = 'one' } } },
    { id = 2, file = 'a.lua', line = 2, text = 'y', status = 'open', messages = { { from = 'you', text = 'two' } } },
  }
  local home = require 'thread.home'
  home.open()
  H.settle()
  home.open { focus = 2 }
  H.settle()
  R.eq(home._state().focus, 2, 'focused')
  home.close()
end)
```

Run: `SPEC=home make test` → fails with `focused: expected 2, got 1`.

- [ ] **Step 2: Fix**

In `M.open`, change

```lua
    if opts.view then
      pick()
      draw()
    end
```

to

```lua
    if opts.view or opts.focus then
      pick()
      draw()
    end
```

- [ ] **Step 3: Pass, check, commit**

```bash
make check
git add -A && git commit -m "fix: home.open moves to the thread asked for when Home is already open"
```

---

### Task 13: Deleting a batch leaves its seen file and its snapshots

`store.delete` (~266) removes `<id>.json` and `active`, but not `<id>.seen`, nor the snapshot refs `refs/threads/<id>/<round>` git.snapshot made, which keep their objects alive forever.

**Files:**
- Create: `tests/store_spec.lua`
- Modify: `lua/thread/store.lua` (`delete`), `lua/thread/git.lua` (new `drop`)

**Interfaces:**
- Produces: `git.drop(batch_id)` — deletes every ref under `refs/threads/<batch_id>/`.

- [ ] **Step 1: Failing test**

`tests/store_spec.lua`:

```lua
-- The batch files: saving, loading, deleting.

local R = require 'tests.runner'
local H = require 'tests.helpers'

R.test('store.delete removes the batch, its seen file and its snapshots', function()
  H.reset()
  local root = H.repo { ['a.lua'] = { 'x' } }
  require('thread').ensure()
  local store = require 'thread.store'
  local batch = store.new 'gone'
  local t = store.add(batch, nil, 'a question')
  store.mark_seen(batch, t)
  local seen = store.dir() .. '/' .. batch.id .. '.seen'
  R.ok(vim.trim(H.git(root, { 'for-each-ref', 'refs/threads/' .. batch.id .. '/' })) ~= '', 'a snapshot ref to start with')
  R.ok(vim.uv.fs_stat(seen), 'a seen file to start with')
  store.delete(batch.id)
  R.eq(vim.trim(H.git(root, { 'for-each-ref', 'refs/threads/' .. batch.id .. '/' })), '', 'its refs are gone')
  R.eq(vim.uv.fs_stat(seen), nil, 'its seen file is gone')
end)
```

Run: `SPEC=store make test` → fails at `its refs are gone`.

- [ ] **Step 2: Fix**

In git.lua, after `M.snapshot`:

```lua
--- Delete a batch's snapshots: every ref under refs/threads/<id>/.
---@param id string
function M.drop(id)
  local out = git { 'for-each-ref', '--format=%(refname)', 'refs/threads/' .. id .. '/' } or ''
  for ref in out:gmatch '[^\n]+' do
    git { 'update-ref', '-d', ref }
  end
end
```

In store.lua `M.delete`, after `os.remove(M.dir() .. '/' .. id .. '.json')`:

```lua
  os.remove(M.dir() .. '/' .. id .. '.seen')
  require('thread.git').drop(id)
```

(`seen_path` takes a batch; use the path directly here.)

- [ ] **Step 3: Pass, check, commit**

```bash
make check
git add -A && git commit -m "fix: deleting a batch deletes its seen file and its snapshot refs"
```

---

### Task 14: `segments` changes the row it reads, and an unreadable code fence vanishes

Two bugs in render.lua's text code:
- `M.segments` (~143) flips `line.bold` on the row it is given, so drawing the same rows twice gives different chunks (model_spec deep-copies around it).
- `M.wrap` (~62) drops a ` ```code ` fence whose body is not a JSON anchor with a `file`: the text is lost without a word.

**Files:**
- Create: `tests/text_spec.lua`
- Modify: `lua/thread/render.lua` (`wrap`, `segments`)

- [ ] **Step 1: Failing tests**

`tests/text_spec.lua`:

```lua
-- Text: widths, fitting, wrapping prose, chunks.

local R = require 'tests.runner'

R.test('segments leaves the row it reads alone', function()
  local render = require 'thread.render'
  local row = render.wrap('**bold** and on', 40)[1]
  local before = vim.deepcopy(row)
  local first = render.segments(row)
  R.eq(row, before, 'row unchanged')
  R.eq(render.segments(row), first, 'the same chunks twice')
end)

R.test('wrap: a code fence that is not an anchor shows as code', function()
  local rows = require('thread.render').wrap('see\n\n```code\nnot json\n```', 40)
  local texts = vim.tbl_map(function(r)
    return r.text
  end, rows)
  R.ok(vim.tbl_contains(texts, 'not json'), 'the fence body is shown: ' .. vim.inspect(texts))
end)
```

Run: `SPEC=text make test` → both fail.

- [ ] **Step 2: Fix**

`segments`: at the top of the function add `local bold = line.bold`, and inside `prose` use and flip `bold` instead of `line.bold` (three places: the two `line.bold and 'ThreadPoint' or 'ThreadText'` and `line.bold = not line.bold`).

`wrap`: where the closing fence of an excerpt is handled, emit the excerpt's lines as code rows when they don't decode to an anchor:

```lua
      elseif not fenced and excerpt then
        local ok, a = pcall(vim.json.decode, table.concat(excerpt, '\n'))
        if ok and type(a) == 'table' and a.file then
          out[#out + 1] = { text = '▤ ' .. a.file .. (a.line and (':' .. a.line) or ''), code = true, excerpt = a }
        else
          -- Not an anchor: show what it says rather than nothing.
          for _, l in ipairs(excerpt) do
            out[#out + 1] = { text = l, code = true }
          end
        end
        excerpt = nil
```

Cut each such line at `width` the same way the function cuts other fenced code (read how the `elseif fenced then` branch does it and do the same).

In `tests/model_spec.lua`, `'wrap: bold runs and excerpts'`: `render.segments(vim.deepcopy(rows[1]))` can now be `render.segments(rows[1])`.

- [ ] **Step 3: Pass, check, commit**

Run: `make check` → all pass; screens unchanged.

```bash
git add -A && git commit -m "fix: segments no longer flips its row's bold, and a code fence that is not an anchor shows as code"
```

---

### Task 15: A thread's changes draw the same removed lines twice

`paint_changes` (render.lua ~1173) draws, for each change of the message, every hunk in its file that overlaps it. Two changes near one hunk draw its removed lines twice.

**Files:**
- Create: `tests/render_spec.lua`
- Modify: `lua/thread/render.lua` (`paint_changes`)

- [ ] **Step 1: Failing test**

`tests/render_spec.lua`:

```lua
-- Drawing in the code: bubbles, notes, changes.

local R = require 'tests.runner'
local H = require 'tests.helpers'

R.test("changes: a hunk two changes overlap is drawn once", function()
  H.reset()
  local root = H.repo { ['a.lua'] = { 'one', 'two', 'three', 'four' } }
  require('thread').ensure()
  local store, render = require 'thread.store', require 'thread.render'
  local batch = store.active(true)
  local t = store.add(batch, { file = 'a.lua', line = 2, text = 'two' }, 'change these') -- round 1: a snapshot
  vim.fn.writefile({ 'one', 'TWO', 'THREE', 'four' }, root .. '/a.lua')
  batch = store.active()
  t = store.find(batch, t.id)
  t.messages[#t.messages + 1] = {
    from = 'agent',
    text = 'done',
    changes = { { file = 'a.lua', line = 2, text = 'TWO' }, { file = 'a.lua', line = 3, text = 'THREE' } },
  }
  store.save(batch)
  vim.cmd.edit(root .. '/a.lua')
  render.toggle_drawn(t.id)
  local drawn = 0
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, render.ns, 0, -1, { details = true })) do
    for _, vl in ipairs(m[4].virt_lines or {}) do
      if (vl[1] and vl[1][1] or ''):find('^two') then
        drawn = drawn + 1
      end
    end
  end
  R.eq(drawn, 1, 'the removed "two" drawn once')
  render.toggle_drawn(t.id)
end)
```

Check `store.add`'s signature before running (`grep -n "^function M.add" lua/thread/store.lua`) and pass the anchor the way it takes it. Run: `SPEC=render make test` → `expected 1, got 2`.

- [ ] **Step 2: Fix**

In `paint_changes`, keep a set of hunks already drawn for the buffer, keyed by `h.old_start .. ':' .. h.new_start`, declared before the loop over the messages' changes, and skip a hunk already in it.

- [ ] **Step 3: Pass, check, commit**

Run: `make check` → all pass; screens unchanged (the fixture's change has one hunk).

```bash
git add -A && git commit -m "fix: draw each hunk of a thread's changes once"
```

---

### Task 16: Going to a thread fails from a modified buffer, or when another plugin's autocmd throws

`actions.jump` (~162) opens the thread's file with `vim.cmd.edit`, which refuses when the current buffer is modified and `hidden` is off, and passes on any error from another plugin's `FileType`/`BufReadPost` autocmd.

**Files:**
- Create: `tests/actions_spec.lua`
- Modify: `lua/thread/actions.lua` (`jump`)

- [ ] **Step 1: Failing test**

`tests/actions_spec.lua`:

```lua
-- Actions on threads: going to one, closing, the changes.

local R = require 'tests.runner'
local H = require 'tests.helpers'

R.test('jump: goes to the thread from a modified buffer, hidden off', function()
  H.reset()
  local root = H.repo { ['a.lua'] = { 'x' }, ['b.lua'] = { 'one', 'two' } }
  H.batch { { id = 1, file = 'b.lua', line = 2, text = 'two', status = 'open', messages = { { from = 'you', text = 'here' } } } }
  vim.o.hidden = false
  vim.cmd.edit 'a.lua'
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'changed' })
  local ok = pcall(require('thread.actions').jump, require('thread.store').find(require('thread.store').active(), 1))
  vim.o.hidden = true
  R.ok(ok, 'no error')
  R.eq(vim.fn.expand '%:t', 'b.lua', 'in the thread file')
  R.eq(vim.api.nvim_win_get_cursor(0)[1], 2, 'on its line')
end)
```

Run: `SPEC=actions make test` → fails (`no error`: E37).

- [ ] **Step 2: Fix**

In actions.lua add, above `M.jump`:

```lua
--- Show `path` in the current window, reusing its buffer if it has one.
--- Not `:edit`: that refuses on a modified buffer when 'hidden' is off,
--- and passes on any error another plugin's autocmd throws.
---@param path string
---@return integer|nil bufnr
local function show_file(path)
  local buf = vim.fn.bufadd(path)
  if not vim.api.nvim_buf_is_loaded(buf) then
    pcall(vim.fn.bufload, buf)
  end
  if not vim.api.nvim_buf_is_loaded(buf) then
    return nil
  end
  vim.bo[buf].buflisted = true
  pcall(vim.api.nvim_win_set_buf, 0, buf)
  return vim.api.nvim_get_current_buf() == buf and buf or nil
end
```

and in `jump` replace `vim.cmd.edit(vim.fn.fnameescape(path))` with

```lua
    if not show_file(path) then
      notify(string.format('could not open %s', comment.file), vim.log.levels.WARN)
      return false
    end
```

`bufload` doesn't fire `FileType` the way `:edit` does in all cases: after `nvim_win_set_buf`, check the buffer got its filetype (`vim.bo[buf].filetype ~= ''` for a `.lua` file). If it didn't, run `vim.api.nvim_buf_call(buf, function() pcall(vim.cmd, 'filetype detect') end)` once after loading, and add `R.eq(vim.bo.filetype, 'lua', 'its filetype')` to the test.

- [ ] **Step 3: Pass, check, commit**

Run: `make check` → all pass. Screens unchanged.

```bash
git add -A && git commit -m "fix: go to a thread without :edit, so a modified buffer or another plugin's autocmd can't stop it"
```

---

## Phase C: shared modules

Each task moves code that exists in several places into one module, with unit tests at the module's interface. **Each must leave `tests/screens` unchanged** (except Task 23, which says what it changes), so run `make check` after each call site you move, not only at the end. If two copies behave differently, keep each caller's output by passing an option, and list the differences in the commit message. If keeping the output would take more than an option, stop and report instead of changing what the user sees.

### Task 17: `text.lua`: widths, fitting, wrapping, time

**Files:**
- Create: `lua/thread/text.lua`
- Modify: every file that defines or calls the functions below; `tests/text_spec.lua`, `tests/model_spec.lua`, `tests/smoke.lua`

**Interfaces:**
- Produces `thread.text`:
  - `text.width(s) -> integer` (display columns; `vim.fn.strdisplaywidth`)
  - `text.fit(s, w) -> string` (cut to `w` columns with `…`; `''` when `w <= 0`)
  - `text.pad(s, w) -> string` (spaces after `s` up to `w` columns)
  - `text.plural(n, one, many) -> string`
  - `text.first_line(s) -> string`
  - `text.first_sentence(s) -> string`
  - `text.ago(stamp) -> string|nil` (ISO time to `just now`, `12m ago`, `3h ago`, `2d ago`)
  - `text.since(secs) -> string` (the same words for a number of seconds)
  - `text.wrap(s, width) -> row[]`, `text.segments(row) -> chunk[]`, `text.link_at(s, col) -> id|nil, stop|nil`
- `render.follow_link` stays in render (it navigates).

- [ ] **Step 1: Tests first**

Append to `tests/text_spec.lua`, and change its two existing tests from `require('thread.render')` to `require('thread.text')`:

```lua
local H = require 'tests.helpers'
local text = require 'thread.text'

R.test('fit: cuts by display width and never loops', function()
  R.eq(text.fit('hello', 0), '', 'no room')
  R.eq(text.fit('hello', -3), '', 'less than none')
  R.eq(text.fit('hello', 5), 'hello', 'fits')
  R.eq(text.fit('hello', 4), 'hel…', 'cut')
  R.eq(text.fit('日本語です', 5), '日本…', 'wide characters take two columns')
  R.eq(text.width(text.fit('日本語です', 4)), 3, 'never a half character')
end)

R.test('pad and plural', function()
  R.eq(text.pad('é', 3), 'é  ', 'pads by columns, not bytes')
  R.eq(text.plural(1, 'line'), '1 line')
  R.eq(text.plural(2, 'line'), '2 lines')
  R.eq(text.plural(2, 'match', 'matches'), '2 matches')
end)

R.test('ago and since', function()
  local restore = H.freeze_time '2026-10-11T12:00:00'
  R.eq(text.ago '2026-10-11T11:59:30', 'just now')
  R.eq(text.ago '2026-10-11T11:48:00', '12m ago')
  R.eq(text.ago '2026-10-11T09:00:00', '3h ago')
  R.eq(text.ago '2026-10-08T12:00:00', '3d ago')
  R.eq(text.ago 'not a time', nil)
  R.eq(text.since(30), 'just now')
  R.eq(text.since(7200), '2h ago')
  restore()
end)

R.test('first_sentence drops fences and markup', function()
  R.eq(text.first_sentence 'It reads `the store`. Then more.', 'It reads the store.')
  R.eq(text.first_sentence '```code\n{}\n```\nOnly line', 'Only line')
end)
```

Move the `'wrap: bold runs and excerpts'` test from `model_spec.lua` into `text_spec.lua` (using `text.wrap`/`text.segments`).

Run: `SPEC=text make test` → fails (no module).

- [ ] **Step 2: Create `text.lua` by moving code**

- `wrap`, `segments`, `link_at`: move `M.wrap`, `M.segments` and `M.link_at` from render.lua verbatim (with Task 14's fixes).
- `fit`: home.lua's binary-search `fit` (~89-107) verbatim. It handles `w <= 0` and wide characters; the copies in render.lua (~228), page.lua (~51, loops forever at `w <= 0`), review_page.lua (~60, returns `''` for `w == 1` where home returns `'…'`), map.lua (~42, loops forever at `w <= 0`) and walk.lua (~134) all go. Note the `w == 1` difference in the commit message.
- `pad`: home.lua ~109. `first_line`: home.lua ~113 (render.lua ~242 is the same). `plural`: review_page.lua ~74.
- `first_sentence`: tour.lua ~48.
- `ago` and `since`: from render.lua `M.ago` (~594) and menu.lua `ago` (~9), the thresholds written once:

```lua
--- How long `secs` seconds is, as `just now`, `12m ago`, `3h ago`, `2d ago`.
---@param secs number
---@return string
function M.since(secs)
  if secs < 90 then
    return 'just now'
  elseif secs < 5400 then
    return math.floor(secs / 60 + 0.5) .. 'm ago'
  elseif secs < 129600 then
    return math.floor(secs / 3600 + 0.5) .. 'h ago'
  end
  return math.floor(secs / 86400 + 0.5) .. 'd ago'
end

--- How long ago an ISO time was, in words; nil when it is not one.
---@param stamp string|nil
---@return string|nil
function M.ago(stamp)
  local y, mo, d, h, mi, s = (stamp or ''):match '(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)'
  if not y then
    return nil
  end
  return M.since(os.time() - os.time { year = y, month = mo, day = d, hour = h, min = mi, sec = s })
end
```

menu.lua's `ago(ns)` becomes `text.since(os.time() - math.floor(ns / 1e9))`.

- `width`: `M.width = vim.fn.strdisplaywidth`; replace the `local width_of = vim.fn.strdisplaywidth` lines with `local width_of = text.width` only where it reads better; otherwise call `text.width`.

- [ ] **Step 3: Move every caller**

Find them all: `grep -rn "render\.\(wrap\|segments\|link_at\|ago\)\|local function \(fit\|pad\|first_line\|plural\|first_sentence\|ago\)\b\|title_of\b" lua tests skills`. Make each use `text.*`. Delete home.lua's `local ago = render.ago` and its `title_of` (it only calls `store.title`; call that). `tests/smoke.lua` line 123 uses `require('thread.render').ago`: make it `require('thread.text').ago`.

- [ ] **Step 4: Check and commit**

Run: `make check` → all pass, screens unchanged.
Run: `grep -rn "local function fit\|local function pad\|local function ago\|local function first_sentence\|local function plural" lua` → no output.

```bash
git add -A && git commit -m "refactor: one text module for widths, fitting, wrapping and times"
```

---

### Task 18: `look.lua`: how threads are marked, and keys as hints

render.lua exports a dozen functions that decide how things look (`glyph`, `who`, `label`, `side`, `dots`, `kind_badge`, `risk`, `verdict_of`, `key`, `show_key`, `NUMS`, `TRACK`/`progress`), used by home, page, review_page, map and walk only through render. And five places turn a list of `{ key, what it does }` into chunks, each its own way: `render.hint_chunks` (~518), `page.keys_footer` (~291, drops keys to fit), `review_page.footer` (~547), home's `key_hints` (~331), `footer` and `single_footer`.

**Files:**
- Create: `lua/thread/look.lua`, `tests/look_spec.lua`
- Modify: render.lua, home.lua, page.lua, review_page.lua, map.lua, walk.lua, tests that call the moved functions

**Interfaces:**
- Produces `thread.look`: `glyph`, `who`, `label`, `side`, `dots`, `DOTS`, `DOTS_WIDTH`, `kind_badge`, `risk`, `verdict_of`, `NUMS`, `key`, `show_key`, `TRACK`, `progress` (same signatures as in render.lua), and:

```lua
--- Keys and what they do, as chunks: `key label` pairs with `sep` between,
--- after `lead`. With `room`, keys named in `drop` go, in that order, until
--- the rest fit.
---@param list ({ [1]: string|false|nil, [2]: string }|{})[]  a key (as typed, false: unmapped) and what it does; empty entries are skipped
---@param opts { lead: string|nil, sep: string|nil, trail: string|nil, room: integer|nil, drop: string[]|nil, key_hl: string|nil, label_hl: string|nil, show: boolean|nil }|nil
---@return { [1]: string, [2]: string|nil }[]
function M.hints(list, opts)
```

`show = true` writes keys through `show_key` (so `<CR>` shows as `⏎`). Defaults: `lead = ''`, `sep = '  '`, `trail = ''`, `key_hl = 'ThreadKey'`, `label_hl = 'ThreadKeyLabel'`.

- [ ] **Step 1: Tests first**

`tests/look_spec.lua`:

```lua
-- How things look: glyphs, badges, keys as hints.

local R = require 'tests.runner'
local look = require 'thread.look'

R.test('hints: key and label pairs', function()
  R.eq(look.hints({ { 'j', 'down' }, {}, { false, 'never' }, { 'k', 'up' } }, { lead = ' ', sep = '  ' }), {
    { ' ' },
    { 'j', 'ThreadKey' },
    { ' down', 'ThreadKeyLabel' },
    { '  ' },
    { 'k', 'ThreadKey' },
    { ' up', 'ThreadKeyLabel' },
  })
end)

R.test('hints: keys dropped in order until they fit', function()
  local list = { { 'h/l', 'threads' }, { 'L', 'next' }, { '<Esc>', 'close' } }
  local out = look.hints(list, { room = 14, drop = { '<Esc>', 'h/l' }, show = true })
  local text = table.concat(vim.tbl_map(function(c)
    return c[1]
  end, out))
  R.eq(text, 'h/l threads  L next', 'Esc went first and that was enough')
end)

R.test('verdict badge', function()
  local v = look.verdict_of { messages = { { from = 'agent', text = 'x', verdict = 'risk', severity = 'low' } } }
  R.eq(v.text, 'RISK · low', 'text')
  R.eq(v.hl, 'ThreadVerdictWarn', 'colour')
end)
```

Move `'verdict badge'` out of `model_spec.lua` (it is this one). Run: `SPEC=look make test` → fails.

- [ ] **Step 2: Move the look functions**

Move them from render.lua to look.lua verbatim, with the tables they use (`VERDICT_HL`, `KIND_HL`, `RISK`, `SIGN` if only these use it, `NUMS`, `DOTS`, `TRACK`). render.lua requires look for what it still needs. Every caller of `render.glyph`, `render.verdict_of`, ... uses `look.*` (grep `render\.\(glyph\|who\|label\|side\|dots\|DOTS\|kind_badge\|risk\|verdict_of\|NUMS\|key\|show_key\|TRACK\|progress\)`).

- [ ] **Step 3: One way to turn keys into hints**

Write `look.hints` and move the five call sites to it one at a time, running `make screens` after each:
1. `page.keys_footer`: becomes its key list plus `look.hints(list, { lead = ' ', sep = '', trail = '  ', room = ..., drop = { 'Esc', 'h/l', w.map, '⏎' }, show = true })`. Read the old code for exactly where the spaces went (it put two spaces after each label) and set `sep`/`trail` so the footer comes out the same.
2. `review_page.footer`.
3. `render.hint_chunks` (the bubble's hints).
4. home's `footer` and `single_footer`.
5. home's `key_hints(P, row, col, keys, right)`: it writes into the sheet directly, aligned to `right`. Make it compute `local chunks = look.hints(keys, { sep = '   ' })`, then lay them out at the column it does now. Fix the fragile `P.hls[#P.hls - 2][4]` in the tab bar (~1791), which assumes `key_hints` makes exactly four highlights: have the tab bar find the highlight it wants by its group, or build its chunks itself.

- [ ] **Step 4: Check and commit**

Run: `make check` → all pass, screens unchanged.

```bash
git add -A && git commit -m "refactor: look.lua for glyphs, badges and key hints, one way to show keys"
```

---

### Task 19: `sheet.lua`: what a screen is built into, and drawn from

Three builders (`page.builder` ~63, `review_page.builder` ~82, home's `page()` ~312) collect lines and `{ row, start, end, group }` highlights, and six places write them to a buffer (home's draw ~1923, page `finish` ~389, review_page `draw` ~609, map ~272, ui.lua `redraw` ~56, home's help ~2332).

**Files:**
- Create: `lua/thread/sheet.lua`, `tests/sheet_spec.lua`
- Modify: home.lua, page.lua, review_page.lua, map.lua, ui.lua

**Interfaces:**
- Produces `thread.sheet`:
  - `sheet.new(opts) -> P` with `opts.indent` (default 0). `P.lines`, `P.hls`, `P.marks`, `P.owner` (line, 1-based, to its owner), `P.items`.
  - `P.add(text, owner) -> row` (0-based), `P.hl(row, s, e, group, opts)` (`e < 0`: to the line's end), `P.mark(row, col, extmark_opts)`, `P.chunks(chunks, indent, owner) -> row`, `P.spread(chunks, right, width) -> row`, `P.rule(label, width)`, `P.item(it)` / `P.done()` (sets `it.first`/`it.last`, 1-based).
  - `sheet.apply(P, buf, ns, opts)`: lines (modifiable toggled around them; `opts.modifiable` says what it is left as, default false), then highlights clamped to their line (`opts.priority` for those that don't set one; `hl_eol` ones run to the next line's start, as home does), then marks.
  - `sheet.text(P) -> string[]` for tests.
- The builders keep their dot-call style (`P.add(...)`, not `P:add(...)`), so call sites only change where the builder is made and where it is written out.

- [ ] **Step 1: Tests first**

`tests/sheet_spec.lua`:

```lua
-- Sheets: lines with their highlights, then into a buffer.

local R = require 'tests.runner'
local sheet = require 'thread.sheet'

local function find(marks, group)
  for _, m in ipairs(marks) do
    if m[4].hl_group == group then
      return m
    end
  end
end

R.test('chunks: one line, byte columns, the indent first', function()
  local P = sheet.new { indent = 2 }
  R.eq(P.chunks { { 'ab', 'A' }, { ' ' }, { 'é', 'B' } }, 0, 'row')
  R.eq(P.lines, { '  ab é' })
  R.eq(P.hls, { { 0, 2, 4, 'A' }, { 0, 5, 7, 'B' } }, 'é is two bytes')
  R.eq(P.chunks({ { 'x', 'C' } }, 0, 'owner'), 1, 'own indent')
  R.eq(P.owner[2], 'owner', 'owned')
end)

R.test('spread: the last chunk against the right edge', function()
  local P = sheet.new { indent = 1 }
  P.spread({ { 'left' } }, { 'right', 'R' }, 12)
  R.eq(P.lines, { ' left   right' })
end)

R.test('items span the rows added while open', function()
  local P = sheet.new()
  P.add 'before'
  local it = { kind = 'group' }
  P.item(it)
  P.add 'one'
  P.add 'two'
  P.done()
  R.eq({ it.first, it.last }, { 2, 3 })
end)

R.test('apply: highlights clamped to their line, priorities kept', function()
  local P = sheet.new()
  P.add 'short'
  P.hl(0, 2, 99, 'X')
  P.hl(0, 0, -1, 'Y', { priority = 50 })
  P.mark(0, 0, { virt_text = { { 'v', 'V' } }, virt_text_pos = 'eol' })
  local buf = vim.api.nvim_create_buf(false, true)
  local ns = vim.api.nvim_create_namespace 'test.sheet'
  sheet.apply(P, buf, ns, { priority = 15 })
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  R.eq({ find(marks, 'X')[4].end_col, find(marks, 'X')[4].priority }, { 5, 15 }, 'X')
  R.eq({ find(marks, 'Y')[4].end_col, find(marks, 'Y')[4].priority }, { 5, 50 }, 'Y')
  R.eq(#marks, 3, 'and the mark')
  R.eq(vim.bo[buf].modifiable, false, 'left read-only')
  vim.api.nvim_buf_delete(buf, { force = true })
end)
```

Run: `SPEC=sheet make test` → fails.

- [ ] **Step 2: Write `sheet.lua`**

```lua
--- What a screen is built into before it is drawn: its lines, the
--- highlights and marks on them, which thread owns each line, and items
--- that span rows. `sheet.apply` writes it into a buffer.

local M = {}

local width_of = vim.fn.strdisplaywidth

---@class thread.Sheet
---@field lines string[]
---@field hls table[]    { row, start, end (-1: the line's end), group, opts|nil }
---@field marks table[]  { row, col, extmark opts }
---@field owner table<integer, any>  line (1-based) -> its owner
---@field items table[]  each with `first` and `last` rows, 1-based

---@param opts { indent: integer|nil }|nil
---@return thread.Sheet
function M.new(opts)
  local indent = opts and opts.indent or 0
  local P = { lines = {}, hls = {}, marks = {}, owner = {}, items = {} }
  function P.add(text, owner)
    P.lines[#P.lines + 1] = text
    P.owner[#P.lines] = owner
    return #P.lines - 1
  end
  function P.hl(row, s, e, group, hl_opts)
    P.hls[#P.hls + 1] = { row, s, e, group, hl_opts }
  end
  function P.mark(row, col, mark_opts)
    P.marks[#P.marks + 1] = { row, col, mark_opts }
  end
  --- Chunks of { text, hl } as one line, after `pad` spaces (the sheet's
  --- indent unless given).
  function P.chunks(chunks, pad, owner)
    local text = string.rep(' ', pad or indent)
    local spans = {}
    for _, c in ipairs(chunks) do
      spans[#spans + 1] = { #text, #text + #c[1], c[2] }
      text = text .. c[1]
    end
    local row = P.add(text, owner)
    for _, sp in ipairs(spans) do
      if sp[3] then
        P.hl(row, sp[1], sp[2], sp[3])
      end
    end
    return row
  end
  --- Chunks on the left, and `right` pushed to the right edge of `width`.
  function P.spread(chunks, right, width)
    local used = indent
    for _, c in ipairs(chunks) do
      used = used + width_of(c[1])
    end
    if right then
      chunks[#chunks + 1] = { string.rep(' ', math.max(2, width + indent - used - width_of(right[1]))) .. right[1], right[2] }
    end
    return P.chunks(chunks)
  end
  function P.rule(label, width)
    P.add ''
    return P.chunks { { '── ' .. label .. ' ', 'ThreadCrumb' }, { string.rep('─', math.max(2, width - width_of(label) - 4)), 'ThreadTabRule' } }
  end
  --- Start an item at the next row; `P.done()` ends it.
  function P.item(it)
    it.first = #P.lines + 1
    P.items[#P.items + 1] = it
    P.open = it
  end
  function P.done()
    if P.open then
      P.open.last = math.max(P.open.first, #P.lines)
      P.open = nil
    end
  end
  return P
end

--- Write `P` into `buf`: its lines, then its highlights (each clamped to
--- its line) and marks in `ns`.
---@param P thread.Sheet
---@param buf integer
---@param ns integer
---@param opts { priority: integer|nil, modifiable: boolean|nil }|nil
function M.apply(P, buf, ns, opts)
  opts = opts or {}
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, P.lines)
  vim.bo[buf].modifiable = opts.modifiable == true
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(P.hls) do
    local len = #(P.lines[h[1] + 1] or '')
    local o = vim.tbl_extend('force', { end_col = (h[3] < 0 or h[3] > len) and len or h[3], hl_group = h[4], priority = opts.priority }, h[5] or {})
    if o.hl_eol then
      o.end_row, o.end_col = h[1] + 1, 0
    end
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, h[1], math.min(h[2], len), o)
  end
  for _, m in ipairs(P.marks) do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, m[1], m[2], m[3])
  end
end

---@param P thread.Sheet
---@return string[]
function M.text(P)
  return vim.deepcopy(P.lines)
end

return M
```

- [ ] **Step 3: Move the builders and the writers, one file at a time**

Run `make screens` after each:
1. page.lua: `builder()` → `sheet.new { indent = PAD }`; `finish`'s lines-and-highlights part → `sheet.apply(P, S.buf, ns)`. (page sets no priority: pass none.)
2. review_page.lua: `builder()` → `sheet.new { indent = PAD }` (its `P.chunks(chunks, indent)` already matches); the write in `draw` → `sheet.apply`.
3. home.lua: `page()` → `sheet.new()`; the write in `draw` → `sheet.apply(P, buf, ns, { priority = 15, modifiable = S.reply ~= nil })` followed by `vim.bo[buf].modified = false`. Replace home's four hand-written chunks-to-row loops (~736-749, 858-869, 1045-1054, 1213-1223) with `P.chunks(chunks, indent, owner)` where they produce the same text and highlights.
4. home's help float (~2332), map.lua (~272), ui.lua `redraw` (~56): their writes → `sheet.apply`. ui.lua's `render()` callers (menu.lua) return `{ lines, hls, items, title }`; let menu build a sheet and return it as the same table shape, or have ui.lua take a sheet. Keep the list's behaviour (the cursor stays on the same item).

If one site's highlights come out with a different priority than before, pass the old one through `opts.priority` or the highlight's own opts.

- [ ] **Step 4: Check and commit**

Run: `make check` → all pass, screens unchanged.
Run: `grep -rn "local function builder\|local function page()\|nvim_buf_set_lines(.*P.lines" lua` → no output.

```bash
git add -A && git commit -m "refactor: sheet.lua builds every screen and writes it to its buffer"
```

---

### Task 20: `code.lua`: syntax colours and rows of code, in one place

The numbered, syntax-lit code row is written nine times (home `draw_code.code_row` ~454, `draw_excerpt` ~580, `draw_change.row` ~653, `draw_quoted` ~708; page `prose` ~108 and `draw_code` ~151; review_page `prose` ~153 and `draw_hunk` ~270). `home.syntax` (~273) lives in Home, so page.lua and review_page.lua require the 3,128-line Home to colour code. `home.scope`'s cache (~354) is keyed by the file's whole text and never emptied.

**Files:**
- Modify: `lua/thread/code.lua`, `tests/code_spec.lua`, home.lua, page.lua, review_page.lua, render.lua (`scope`)

**Interfaces:**
- Consumes: `code.enclosing` (Task 11), `sheet` (Task 19).
- Produces in `thread.code`:
  - `code.syntax(lines, file) -> table<integer, {s, e, group}[]>` (moved from home, same result)
  - `code.scope(lines, file, lo, hi) -> lo, hi` (the function around `lo..hi`, else a dozen lines either side, as home's `scope` does), cached by file and text hash, at most 32 entries
  - `code.row(P, r, opts) -> row, code_col` — one line of code on a sheet:

```lua
---@class thread.CodeRow
---@field num integer|nil    its line number; nil leaves the four columns blank (a removed line)
---@field sign string|nil    '+', '-' or ' ' in a diff gutter; nil: no gutter
---@field text string        the code; tabs are drawn as four spaces
---@field spans table[]|nil  its syntax spans; none on a line with a tab, whose columns would be off
---@field num_hl string|nil  the number's highlight, LineNr by default

--- A line of code on a sheet: `opts.indent` spaces, the number in four
--- columns, then two spaces, or ' <sign> ' in a diff, then the code.
---@param P thread.Sheet
---@param r thread.CodeRow
---@param opts { indent: integer, owner: any|nil, span_opts: table|nil, num_opts: table|nil }
---@return integer row  0-based
---@return integer code_col  the byte column the code starts at
function M.row(P, r, opts)
  local prefix = string.rep(' ', opts.indent) .. (r.num and string.format('%4d', r.num) or '    ') .. (r.sign and (' ' .. r.sign .. ' ') or '  ')
  local row = P.add(prefix .. r.text:gsub('\t', '    '), opts.owner)
  P.hl(row, opts.indent, opts.indent + 4, r.num_hl or 'LineNr', opts.num_opts)
  if not r.text:find '\t' then
    for _, s in ipairs(r.spans or {}) do
      P.hl(row, #prefix + s[1], #prefix + s[2], s[3], opts.span_opts)
    end
  end
  return row, #prefix
end
```

  - `code.lines(P, lines, opts) -> first, last` — plain numbered lines from line `opts.from` of `opts.file`, coloured: `for i, l in ipairs(lines) do code.row(P, { num = opts.from + i - 1, text = l, spans = spans[i], num_hl = opts.num_hl and opts.num_hl(opts.from + i - 1) }, opts) end`.
- The callers keep their own extra highlights (washes, note marks, the lit line) after `code.row`, using the `row` and `code_col` it returns.

- [ ] **Step 1: Tests first** (append to `tests/code_spec.lua`)

```lua
local sheet = require 'thread.sheet'
local code = require 'thread.code'

R.test('code.row: number, gutter, code', function()
  local P = sheet.new()
  local row, col = code.row(P, { num = 7, text = 'local x', spans = { { 0, 5, '@keyword.lua' } } }, { indent = 2 })
  R.eq({ row, col }, { 0, 8 })
  R.eq(P.lines, { '     7  local x' })
  R.eq(P.hls, { { 0, 2, 6, 'LineNr' }, { 0, 8, 13, '@keyword.lua' } })
end)

R.test('code.row: a diff gutter, a removed line', function()
  local P = sheet.new()
  code.row(P, { sign = '-', text = 'old' }, { indent = 0 })
  R.eq(P.lines, { '     - old' })
end)

R.test('code.row: tabs drawn as four spaces, and no spans on that line', function()
  local P = sheet.new()
  code.row(P, { num = 1, text = '\treturn x', spans = { { 1, 7, '@keyword.lua' } } }, { indent = 0 })
  R.eq(P.lines, { '   1      return x' })
  R.eq(#P.hls, 1, 'only the number')
end)

R.test('code.syntax: spans for Lua', function()
  local spans = code.syntax({ 'local x = 1' }, 'a.lua')
  R.ok(spans[1] and #spans[1] > 0, 'some spans')
  R.eq(code.syntax({ 'x' }, 'a.unknown-ext'), {}, 'none for a file it cannot parse')
end)

R.test('code.scope: the function around, else a dozen lines either side', function()
  local lines = { 'local function f()', '  return 1', 'end' }
  R.eq({ code.scope(lines, 'a.lua', 2, 2) }, { 1, 3 })
  local flat = {}
  for i = 1, 40 do
    flat[i] = 'x = ' .. i
  end
  R.eq({ code.scope(flat, 'a.lua', 20, 20) }, { 8, 32 })
end)
```

Run: `SPEC=code make test` → the new ones fail.

- [ ] **Step 2: Move `syntax` and `scope`, write `row` and `lines`**

Move `syntax` from home.lua verbatim. Move home's `scope` and turn it into `code.scope(lines, file, lo, hi)` (it took a Home thread `t`; it needs `t.lines`, `t.c.file`, `t.line`, `t.to`). Its cache: key `file .. ':' .. vim.fn.sha256(table.concat(lines, '\n'))`, holding the per-range results; when it holds 32 files, empty it. render.lua's `scope(bufnr, lo, hi)` works on a buffer's parser, not a string: leave its parser part, it already uses `code.enclosing` (Task 11).

- [ ] **Step 3: Move the nine code-row sites, one at a time, `make screens` after each**

page and review_page first (`prose` excerpts → `code.lines`; `draw_code` and `draw_hunk` → `code.row` plus their own extra highlights), then home's four. Afterwards neither page.lua nor review_page.lua requires `thread.home` for colours: `grep -n "thread.home').syntax" lua` → no output.

- [ ] **Step 4: Check and commit**

Run: `make check` → all pass, screens unchanged.

```bash
git add -A && git commit -m "refactor: code.lua colours and draws rows of code for every screen"
```

---

### Task 21: `blocks.lua`: prose with excerpts, diagrams, conversations

page.lua and review_page.lua each have `prose` (byte-identical), `draw_diagram` and `draw_talk`, and home.lua has `draw_quoted` and `draw_diagram`. They are the same blocks drawn onto a sheet.

**Files:**
- Create: `lua/thread/blocks.lua`, `tests/blocks_spec.lua`
- Modify: page.lua, review_page.lua, home.lua (where its output stays the same)

**Interfaces:**
- Consumes: `text`, `look`, `sheet`, `code`, `anchor`, `diagram`, `store`.
- Produces `thread.blocks`:
  - `blocks.prose(P, s, width, opts)` — wrapped text, `code` and **bold** picked out, excerpts (` ```code ` fences) drawn as the code they point at (a `file:line` heading, then up to 15 lines), or a broken line (`▤ file · its line is gone`). `opts.indent` for the code rows (default the sheet's own indent).
  - `blocks.diagram(P, raw, width, opts) -> { first: integer, drawn: table }|nil` — validated and drawn, trailing spaces stripped from each row; an invalid one draws `diagram: <why>` in `ThreadBroken` and returns nil; with `opts.degraded`, a note when the layout had to fall back.
  - `blocks.talk(P, batch, thread, width, opts)` — the conversation as chat rows: the agent's on the left with its label and time on the right, yours set in (`look.chat`/`render.chat`). `opts.head = 'rule'` (page: a rule saying `your thread here · <glyph> <status>`) or `'line'` (review_page: a glyph line); `opts.gap` puts a blank line between messages (page does, review_page doesn't). It does not mark the thread seen; the caller does, as each does now.

- [ ] **Step 1: Tests first**

`tests/blocks_spec.lua`:

```lua
-- Blocks on a sheet: prose with excerpts, diagrams, conversations.

local R = require 'tests.runner'
local H = require 'tests.helpers'
local sheet, blocks = require 'thread.sheet', require 'thread.blocks'

R.test('prose: an excerpt is drawn as the code it points at', function()
  H.reset()
  H.repo { ['a.lua'] = { 'local M = {}', 'function M.f()', '  return 1', 'end' } }
  local P = sheet.new { indent = 2 }
  blocks.prose(P, 'Look:\n\n```code\n{ "file": "a.lua", "text": "  return 1", "lines": 2 }\n```', 40)
  R.eq(sheet.text(P), { '  Look:', '', '  a.lua:3', '     3    return 1', '     4  end' })
end)

R.test('prose: an excerpt whose line went says so', function()
  H.reset()
  H.repo { ['a.lua'] = { 'x' } }
  local P = sheet.new { indent = 2 }
  blocks.prose(P, '```code\n{ "file": "a.lua", "text": "gone" }\n```', 40)
  R.eq(sheet.text(P), { '  ▤ a.lua · its line is gone' })
end)

R.test('diagram: an invalid one says why', function()
  local P = sheet.new()
  R.eq(blocks.diagram(P, { kind = 'nope' }, 40), nil, 'nothing drawn')
  R.ok(sheet.text(P)[1]:find('^diagram: '), 'says why')
end)
```

Before writing `blocks.lua`, check the expected text in the first two tests against what page.lua draws today (`prose` with PAD 2): the blank line after "Look:" comes from `wrap` keeping the paragraph break; correct the expectation if the current code draws it differently, because the current output is the truth. Run: `SPEC=blocks make test` → fails (no module).

- [ ] **Step 2: Write `blocks.lua` from the copies**

`prose` and `diagram` from page.lua (`prose` ~93, `draw_diagram` ~181; review_page's are the same but for the `degraded` note); page's `draw_diagram` also records `S.diagram = { first, drawn }` for ⏎ on a box: `blocks.diagram` returns that, and page stores it. `talk` from page's `draw_talk` (~257) and review_page's (~184), their differences as options.

- [ ] **Step 3: Move the callers, `make screens` after each**

page.lua, then review_page.lua, then home.lua's `draw_quoted` and `draw_diagram` where the output stays the same. Home draws with its own indent and owner per line; if a home block cannot come out the same through `blocks`, leave it for plan 2 (Home's split) and say so in the commit message.

- [ ] **Step 4: Check and commit**

Run: `make check` → all pass, screens unchanged.

```bash
git add -A && git commit -m "refactor: blocks.lua draws prose, diagrams and conversations for page, review and Home"
```

---

### Task 22: `float.lua`: one way to open the floats screens are drawn in

page.lua (~509-585), review_page.lua (~859-945), ui.lua (~17-31) and Home's help (~2334) each create a scratch buffer, open a float, set buffer keys and decide when it closes. page keeps itself open only when the window you went to has filetype `markdown`, which is compose.lua's choice of filetype: a coupling nobody would guess.

**Files:**
- Create: `lua/thread/float.lua`, `tests/float_spec.lua`
- Modify: page.lua, review_page.lua, ui.lua, home.lua (help), compose.lua

**Interfaces:**
- Produces `thread.float`:

```lua
---@class thread.FloatOpts
---@field ft string|nil       the buffer's filetype
---@field config table        nvim_open_win's config; relative = 'editor', style = 'minimal' and border = 'rounded' unless given
---@field wo table|nil        window options to set
---@field keys table<string, function>|nil  buffer keys, nowait
---@field leave 'close'|'stay'|fun(to: integer): boolean|nil  when you leave it: close it (default), keep it, or close it if the function says so, given the window you went to
---@field enter boolean|nil   focus it (default true)

---@class thread.Float
---@field win integer
---@field buf integer
---@field is_open fun(): boolean
---@field close fun()
---@field map fun(lhs: string|false|nil, fn: function)

---@param opts thread.FloatOpts
---@return thread.Float
function M.open(opts)
```

- Produces `compose.is(win) -> boolean`: whether `win` is a compose float. compose.lua sets `vim.w[win].thread_compose = true` on the window it opens.

- [ ] **Step 1: Tests first**

`tests/float_spec.lua`:

```lua
-- Floats: opened, keyed, closed when you leave them unless told otherwise.

local R = require 'tests.runner'
local H = require 'tests.helpers'
local float = require 'thread.float'

local CONFIG = { row = 1, col = 1, width = 20, height = 3 }

R.test('float: q closes it when asked, and leaving closes it by default', function()
  H.reset()
  local closed = false
  local f = float.open { ft = 'thread-test', config = CONFIG, keys = { q = function()
    closed = true
  end } }
  R.eq(vim.bo[f.buf].filetype, 'thread-test')
  H.press 'q'
  R.ok(closed, 'q ran')
  vim.cmd 'wincmd p'
  H.settle()
  R.eq(f.is_open(), false, 'leaving closed it')
end)

R.test('float: leave = stay keeps it open', function()
  H.reset()
  local f = float.open { config = CONFIG, leave = 'stay' }
  vim.cmd 'wincmd p'
  H.settle()
  R.ok(f.is_open(), 'still open')
  f.close()
end)

R.test('float: leave as a function decides by the window you went to', function()
  H.reset()
  local f = float.open { config = CONFIG, leave = function(to)
    return not vim.w[to].keep_me
  end }
  local other = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), true, { relative = 'editor', row = 10, col = 10, width = 5, height = 1 })
  vim.w[other].keep_me = true
  H.settle()
  R.ok(f.is_open(), 'kept open for that window')
  vim.api.nvim_win_close(other, true)
  f.close()
end)
```

Run: `SPEC=float make test` → fails.

- [ ] **Step 2: Write `float.lua`**

```lua
--- The floats screens are drawn in: a scratch buffer, the window, its
--- keys, and when it closes.

local M = {}

---@param opts thread.FloatOpts
---@return thread.Float
function M.open(opts)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  if opts.ft then
    vim.bo[buf].filetype = opts.ft
  end
  local config = vim.tbl_extend('keep', opts.config, { relative = 'editor', style = 'minimal', border = 'rounded' })
  local win = vim.api.nvim_open_win(buf, opts.enter ~= false, config)
  for k, v in pairs(opts.wo or {}) do
    vim.wo[win][k] = v
  end
  local F = { win = win, buf = buf }
  function F.is_open()
    return vim.api.nvim_win_is_valid(win)
  end
  function F.close()
    if F.is_open() then
      vim.api.nvim_win_close(win, true)
    end
  end
  function F.map(lhs, fn)
    if lhs then
      vim.keymap.set('n', lhs, fn, { buffer = buf, nowait = true })
    end
  end
  for lhs, fn in pairs(opts.keys or {}) do
    F.map(lhs, fn)
  end
  local leave = opts.leave or 'close'
  if leave ~= 'stay' then
    vim.api.nvim_create_autocmd('WinLeave', {
      buffer = buf,
      callback = function()
        vim.schedule(function()
          local to = vim.api.nvim_get_current_win()
          if F.is_open() and to ~= win and (leave == 'close' or leave(to)) then
            F.close()
          end
        end)
      end,
    })
  end
  return F
end

return M
```

- [ ] **Step 3: Move the four floats, `make check` after each**

1. compose.lua: after `nvim_open_win`, `vim.w[win].thread_compose = true`; add `function M.is(win) return vim.api.nvim_win_is_valid(win) and vim.w[win].thread_compose == true end`.
2. page.lua `M.open`: `float.open { ft = 'thread-page', config = {...as now...}, wo = { wrap = false, cursorline = true, winhighlight = ... }, keys = {...}, leave = function(to) return not require('thread.compose').is(to) end }`. `S.win`/`S.buf` come from it; `M.close` uses it.
3. review_page.lua `M.open`: its float with `leave = 'stay'` (it never closed on leave).
4. ui.lua: its float with `leave = 'close'` (it closed once on leave; closing is idempotent).
5. Home's help float.

Home's own two windows (full screen and the focus float) move in plan 2, with Home's surfaces.

- [ ] **Step 4: Check and commit**

Run: `make check` → all pass, screens unchanged. Run: `grep -n "filetype ~= 'markdown'" lua` → no output.

```bash
git add -A && git commit -m "refactor: float.lua opens every screen's float; page knows the compose float by asking compose"
```

---

### Task 23: `hunks.lua`: removed lines drawn into the code

`render.paint_changes` (~1173) and `review.paint` (~734) both hang removed lines above where they were as `virt_lines` and wash the added ones. They differ: paint_changes pads with 200 spaces and uses `DiffAdd`/`DiffDelete` (or CodeDiff's names); review.paint pads to the window's width, uses `ThreadDiffAdd`/`ThreadDiffDelete`, and places a deletion at the end of the file more carefully.

**Files:**
- Create: `lua/thread/hunks.lua`, `tests/hunks_spec.lua`
- Modify: render.lua (`paint_changes`), review.lua (`paint`)

**Interfaces:**
- Produces `thread.hunks`:

```lua
---@class thread.PaintHunk
---@field old_start integer
---@field old_count integer
---@field new_start integer  with new_count 0, the line the removal follows
---@field new_count integer
---@field old string[]       the removed lines

--- Each hunk's removed lines hung above where they were, padded to the
--- window's width, and its added lines washed. A hunk listed twice is
--- drawn once.
---@param bufnr integer
---@param ns integer
---@param list thread.PaintHunk[]
---@param opts { add: string, del: string }
function M.paint(bufnr, ns, list, opts)
```

- This task changes one snapshot: in `code-changes-drawn`, the removed line's padding goes from 200 spaces to the window's width. The `== screen` section must not change. Say so in the commit message.

- [ ] **Step 1: Tests first**

`tests/hunks_spec.lua`:

```lua
-- Hunks drawn into a code buffer.

local R = require 'tests.runner'
local H = require 'tests.helpers'
local hunks = require 'thread.hunks'

local function setup(lines)
  H.reset()
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf, vim.api.nvim_create_namespace 'test.hunks'
end

local function virt(buf, ns)
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    for _, vl in ipairs(m[4].virt_lines or {}) do
      out[#out + 1] = { m[2], vim.trim(vl[1][1]), m[4].virt_lines_above }
    end
  end
  return out
end

R.test('a changed line: the old one above the new, the new one washed', function()
  local buf, ns = setup { 'a', 'B', 'c' }
  hunks.paint(buf, ns, { { old_start = 2, old_count = 1, new_start = 2, new_count = 1, old = { 'b' } } }, { add = 'Add', del = 'Del' })
  R.eq(virt(buf, ns), { { 1, 'b', true } })
  local washed = false
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    washed = washed or (m[4].hl_group == 'Add' and m[2] == 1)
  end
  R.ok(washed, 'B washed')
end)

R.test('a deletion at the end of the file hangs below the last line', function()
  local buf, ns = setup { 'a', 'b' }
  hunks.paint(buf, ns, { { old_start = 3, old_count = 1, new_start = 2, new_count = 0, old = { 'c' } } }, { add = 'Add', del = 'Del' })
  R.eq(virt(buf, ns), { { 1, 'c', false } })
end)

R.test('a hunk listed twice is drawn once', function()
  local buf, ns = setup { 'a', 'B', 'c' }
  local h = { old_start = 2, old_count = 1, new_start = 2, new_count = 1, old = { 'b' } }
  hunks.paint(buf, ns, { h, vim.deepcopy(h) }, { add = 'Add', del = 'Del' })
  R.eq(#virt(buf, ns), 1)
end)

R.test('tabs in removed lines are drawn as four spaces', function()
  local buf, ns = setup { 'x' }
  hunks.paint(buf, ns, { { old_start = 1, old_count = 1, new_start = 1, new_count = 1, old = { '\tb' } } }, { add = 'Add', del = 'Del' })
  local m = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  for _, x in ipairs(m) do
    if x[4].virt_lines then
      R.eq(x[4].virt_lines[1][1][1]:sub(1, 5), '    b')
    end
  end
end)
```

Run: `SPEC=hunks make test` → fails.

- [ ] **Step 2: Write `hunks.paint`** from review.paint's inner loop (its row and `above` rules, its padding to the window's width), with the drawn-once set from Task 15 (keyed `old_start:new_start`).

- [ ] **Step 3: Use it from both**

review.paint builds its list from `f.hunks[*].parts` (each part has `old_start`, `old_count`, `new_start`, `new_count`, `old`) and calls `hunks.paint(bufnr, ns, list, { add = 'ThreadDiffAdd', del = 'ThreadDiffDelete' })`. paint_changes builds its list from the hunks that overlap a change (each with `old = vim.list_slice(old, h.old_start, h.old_start + h.old_count - 1)`) and calls it with `{ add = words and 'CodeDiffLineInsert' or 'DiffAdd', del = words and 'CodeDiffLineDelete' or 'DiffDelete' }` (Task 25 moves those names into the CodeDiff adapter). Task 15's set in paint_changes goes; hunks.paint does it now.

- [ ] **Step 4: Check and commit**

Run: `make check`. `make screens` fails on `code-changes-drawn` only, in its `vl` padding. Check the `== screen` section of `tests/screens/code-changes-drawn.txt.actual` equals the old one, then `UPDATE=1 make screens` and `git diff --stat tests/screens` (one file).

```bash
git add -A && git commit -m "refactor: hunks.lua draws removed lines into the code for reviews and a thread's changes

code-changes-drawn: removed lines are padded to the window's width, not
200 spaces; the screen is the same."
```

---

### Task 24: `keys.lua`: the walk's overlay and the zone keys

walk.lua's `set_keys`, `cover` and `restore_keys` (~60-112) lay the walk's keys over the user's and give them back; init.lua's `on_comment` (~133-165) maps keys that act on a thread and otherwise do what they did. Both move into `keys`.

**Files:**
- Modify: `lua/thread/keys.lua`, `tests/keys_spec.lua`, walk.lua, init.lua

**Interfaces:**
- Consumes: `keys.global` (Task 10).
- Produces in `thread.keys`:

```lua
--- Lay `specs` over the global mappings now, remembering each one replaced.
---@param specs { lhs: string, fn: function, desc: string }[]
---@return thread.Overlay  with :cover(buf) and :restore()
function M.overlay(specs)

--- `lhs` acts on the thread under the cursor when `opts.here()` says so, and
--- does what it did before anywhere else: the global mapping it replaced,
--- else the key's own meaning.
---@param lhs string|false|nil
---@param opts { here: fun(): boolean, run: fun(), desc: string }
function M.zone(lhs, opts)
```

- [ ] **Step 1: Tests first** (append to `tests/keys_spec.lua`)

```lua
local keys = require 'thread.keys'

R.test('overlay: laid over the global and a buffer, then all given back', function()
  H.reset()
  vim.keymap.set('n', 'Q', '<Cmd>let g:thread_test_q = "mine"<CR>', { desc = 'mine' })
  local buf = vim.api.nvim_get_current_buf()
  vim.keymap.set('n', 'Q', '<Cmd>let g:thread_test_q = "buffer"<CR>', { buffer = buf, desc = 'buffer' })
  local o = keys.overlay { { lhs = 'Q', fn = function()
    vim.g.thread_test_q = 'walk'
  end, desc = 'walk' } }
  o:cover(buf)
  H.press 'Q'
  R.eq(vim.g.thread_test_q, 'walk', 'ours while it lasts, even over the buffer')
  o:restore()
  H.press 'Q'
  R.eq(vim.g.thread_test_q, 'buffer', 'the buffer has its own back')
  R.eq(keys.global('Q').desc, 'mine', 'and the global one is back')
  vim.keymap.del('n', 'Q', { buffer = buf })
  vim.keymap.del('n', 'Q')
end)

R.test('zone: on a thread it runs, elsewhere it falls back', function()
  H.reset()
  vim.keymap.set('n', 'Z', function()
    vim.g.thread_test_z = 'before'
  end, { desc = 'before' })
  local here = false
  keys.zone('Z', { here = function()
    return here
  end, run = function()
    vim.g.thread_test_z = 'thread'
  end, desc = 'test' })
  H.press 'Z'
  H.settle()
  R.eq(vim.g.thread_test_z, 'before', 'off a thread')
  here = true
  H.press 'Z'
  H.settle()
  R.eq(vim.g.thread_test_z, 'thread', 'on one')
  vim.keymap.del('n', 'Z')
end)
```

Run: `SPEC=keys make test` → the new ones fail.

- [ ] **Step 2: Write `overlay` and `zone`**

`overlay` from walk.lua's three functions, as an object:

```lua
local Overlay = {}
Overlay.__index = Overlay

function M.overlay(specs)
  local o = setmetatable({ specs = specs, saved = {}, bufs = {} }, Overlay)
  for _, s in ipairs(specs) do
    o.saved[s.lhs] = M.global(s.lhs) or false
    vim.keymap.set('n', s.lhs, s.fn, { desc = s.desc })
  end
  return o
end

--- The same keys on `buf`: a buffer's own mapping wins over a global one
--- (the snacks dashboard's `L` opens Lazy).
function Overlay:cover(buf)
  if self.bufs[buf] or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local saved = {}
  for _, s in ipairs(self.specs) do
    local old = vim.api.nvim_buf_call(buf, function()
      return vim.fn.maparg(s.lhs, 'n', false, true)
    end)
    saved[s.lhs] = (old and old.buffer == 1) and old or false
    vim.keymap.set('n', s.lhs, s.fn, { buffer = buf, desc = s.desc })
  end
  self.bufs[buf] = saved
end

--- Every key back as it was.
function Overlay:restore()
  for lhs, old in pairs(self.saved) do
    pcall(vim.keymap.del, 'n', lhs)
    if old then
      pcall(vim.fn.mapset, 'n', false, old)
    end
  end
  for buf, saved in pairs(self.bufs) do
    if vim.api.nvim_buf_is_valid(buf) then
      for lhs, old in pairs(saved) do
        pcall(vim.keymap.del, 'n', lhs, { buffer = buf })
        if old then
          vim.api.nvim_buf_call(buf, function()
            pcall(vim.fn.mapset, 'n', false, old)
          end)
        end
      end
    end
  end
  self.saved, self.bufs = {}, {}
end
```

`zone` from init.lua's `on_comment`, keeping its `zone_before` table as a module-level `before` in keys.lua (so a second `setup()` falls back to what was there before thread, not to thread's own mapping):

```lua
local before = {} -- lhs -> the mapping a zone key replaced, kept across setup calls

function M.zone(lhs, opts)
  if not lhs then
    return
  end
  local old = M.global(lhs)
  if old and (old.desc or ''):find '^Thread: ' then
    old = before[lhs]
  end
  before[lhs] = old
  local function fallback()
    if old and old.callback then
      if old.expr == 1 then
        return old.callback()
      end
      vim.schedule(old.callback)
      return ''
    elseif old and old.rhs and old.rhs ~= '' then
      return vim.keycode(old.rhs)
    end
    return vim.keycode(lhs)
  end
  vim.keymap.set('n', lhs, function()
    if not opts.here() then
      return fallback()
    end
    vim.schedule(opts.run)
    return ''
  end, { expr = true, desc = 'Thread: ' .. opts.desc })
end
```

- [ ] **Step 3: Use them**

walk.lua: `W.saved`/`W.bufs` become `W.keys = keys.overlay(specs)` (specs from `walk_keys()`: `{ lhs = k.lhs, fn = k.fn, desc = 'Thread walk: ' .. k.action }`), `cover(buf)` becomes `W.keys:cover(buf)`, `restore_keys(w)` becomes `if w and w.keys then w.keys:restore() end`. Keep the guard that a walk sets its keys once, and nested walks (`W.outer`).

init.lua: `on_comment(lhs, fn, desc)` becomes

```lua
  local function on_comment(lhs, fn, desc)
    keys.zone(lhs, {
      here = function()
        local render = require 'thread.render'
        return vim.bo.buftype == '' and render.visible() and render.at_cursor() ~= nil
      end,
      run = fn,
      desc = desc,
    })
  end
```

(check what `render.at_cursor()` returns and keep the old condition's meaning exactly), and `zone_before` goes.

- [ ] **Step 4: Check and commit**

Run: `make check` → all pass, screens unchanged; Task 10's tests still pass.

```bash
git add -A && git commit -m "refactor: keys.lua lays the walk's keys over yours and gives them back, and maps the zone keys"
```

---

### Task 25: One git module, and CodeDiff behind one adapter

git is run four ways (git.lua's `git` ~18, review.lua's `git` ~119, `vim.system` in `git.show`, and elsewhere: `grep -rn "vim.system({ 'git'" lua`). review.lua parses `git diff` itself (`parse` ~158, `untracked` ~222). CodeDiff's engine, highlight names and commands are spread over git.lua (~131-273), render.lua (~1191) and home.lua (~647).

**Files:**
- Create: `lua/thread/codediff.lua`
- Modify: git.lua, review.lua, render.lua, home.lua, anything else running git; `tests/git_spec.lua`, `tests/independence_spec.lua`

**Interfaces:**
- Produces in `thread.git`:
  - `git.run(args, opts) -> stdout|nil, err|nil` — git in the repository root; `opts.env` for extra environment.
  - `git.diff(args, opts) -> file[]` — `git diff -U0` with `args`, read into `{ file, status, add, del, parts = { { old_start, old_count, new_start, new_count, old, new } } }`; `opts.untracked` adds untracked files as added. (Moved from review.lua's `parse`, with Task 7's fix, and `untracked`.)
  - unchanged: `show`, `forget`, `hunks`, `word_hunks`, `snapshot`, `drop`, `base_for`, `open_file_diff`, `open_all`.
- Produces `thread.codediff`, the only module that touches CodeDiff:
  - `codediff.engine() -> table|nil` (nil when not installed, not built, or `ui.diff = 'builtin'`)
  - `codediff.word_hunks(old, new) -> hunks|nil` (nil: use the built-in diff)
  - `codediff.available() -> boolean` (`:CodeDiff` exists and `ui.diff ~= 'builtin'`)
  - `codediff.open_file(base) -> boolean`, `codediff.open_all(base) -> boolean` (false: not available, the caller falls back)
  - `codediff.HL = { add = 'CodeDiffLineInsert', del = 'CodeDiffLineDelete', word_add = 'CodeDiffCharInsert', word_del = 'CodeDiffCharDelete' }`
- review.lua keeps grouping parts into hunks (`hunk_of`, the `GAP` joining).

- [ ] **Step 1: Tests first** (append to `tests/git_spec.lua`)

```lua
R.test('git.diff: files and their parts, untracked files as added', function()
  H.reset()
  local root = H.repo { ['a.lua'] = { 'one', 'two' } }
  vim.fn.writefile({ 'one', 'TWO' }, root .. '/a.lua')
  vim.fn.writefile({ 'new' }, root .. '/b.lua')
  local files = require('thread.git').diff({ 'HEAD' }, { untracked = true })
  table.sort(files, function(x, y)
    return x.file < y.file
  end)
  R.eq(vim.tbl_map(function(f)
    return { f.file, f.status, f.add, f.del }
  end, files), { { 'a.lua', 'modified', 1, 1 }, { 'b.lua', 'added', 1, 0 } })
  R.eq({ files[1].parts[1].old, files[1].parts[1].new }, { { 'two' }, { 'TWO' } })
end)

R.test('git.run: outside a repository, nil and why', function()
  H.reset()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  vim.cmd('cd ' .. vim.fn.fnameescape(dir))
  local out, err = require('thread.git').run { 'rev-parse', 'HEAD' }
  R.eq(out, nil, 'no output')
  R.ok(type(err) == 'string' and err ~= '', 'a reason')
end)

R.test('a message saves outside git, with no snapshot', function()
  H.reset()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, 'p')
  vim.cmd('cd ' .. vim.fn.fnameescape(dir))
  require('thread').ensure()
  local store = require 'thread.store'
  local t = store.add(store.active(true), nil, 'no git here')
  R.eq(store.find(store.active(), t.id).messages[1].text, 'no git here', 'saved')
end)

R.test('codediff: not installed, so nothing, and the built-in diff is used', function()
  local codediff = require 'thread.codediff'
  R.eq(codediff.engine(), nil, 'no engine in a bare Neovim')
  R.eq(codediff.available(), false, 'no :CodeDiff')
  local hunks, words = require('thread.git').word_hunks({ 'a' }, { 'b' })
  R.eq({ #hunks, words }, { 1, false }, 'the built-in diff, by lines')
end)
```

Run: `SPEC=git make test` → the new ones fail (no `git.diff`, no `git.run`, no `codediff`); the "outside git" one may already pass: keep it, it pins Review Focus 5.

- [ ] **Step 2: `git.run` and `git.diff`**

Rename git.lua's local `git` to `M.run` (keep a `local git = M.run` only if it makes the file read better; there must be one implementation). Make `git.show` use it. Replace review.lua's local `git` with `require('thread.git').run`, and every other `vim.system({ 'git'` in `lua/thread` except `store.root`'s `rev-parse --show-toplevel` (git.lua requires store; store can't require git without a loop).

Move `parse` (minus the part that groups parts into hunks) and `untracked` into git.lua as `M.diff(args, opts)`. In review.lua, `M.files(spec)` calls `git.diff(args, { untracked = spec.worktree })` and turns each file's `parts` into `hunks` with `hunk_of` and the `GAP` joining, as `flush` did.

- [ ] **Step 3: `codediff.lua`**

Move `engine` (~134-157), the CodeDiff half of `word_hunks` (~164-201), `has_codediff` (~203) and the `CodeDiff` branches of `open_file_diff` and `open_all` from git.lua into codediff.lua. git.lua's `word_hunks` becomes "`codediff.word_hunks(old, new)` or the built-in hunks"; `open_file_diff`/`open_all` call `codediff.open_file(base)`/`codediff.open_all(base)` first and fall back as now. render.lua's and home.lua's `'CodeDiffLineInsert'`-style literals become `codediff.HL.*`. In `tests/independence_spec.lua`, change the `git.lua` entry of `ALLOWED` to `['lua/thread/codediff.lua'] = { 'codediff.' }` and keep the `home.lua` which-key entry.

- [ ] **Step 4: Check and commit**

Run: `make check` → all pass, screens unchanged. Run: `grep -rn "codediff\.\|CodeDiff" lua --include=*.lua | grep -v "^lua/thread/codediff.lua" | grep -v "codediff')\|codediff.HL\|codediff.word_hunks\|codediff.open_\|codediff.available\|^\S*:\s*--"` → no output.

```bash
git add -A && git commit -m "refactor: one way to run git and read a diff, and CodeDiff behind codediff.lua"
```

---

### Task 26: Plan 1 done: report and hand back

- [ ] **Step 1: Full check, twice**

Run: `make check && make check` → all green both times.

- [ ] **Step 2: Report the numbers**

```bash
git diff --stat master...refactor | tail -1
wc -l lua/thread/*.lua lua/thread/diagram/*.lua | tail -1
git -C /home/alex/.config/nvim/thread.nvim show master:lua/thread/home.lua | wc -l; wc -l lua/thread/home.lua
```

Report to the owner: lines before and after, per file for the five biggest; tests before (8 unit + smoke) and after; every bug fixed with its commit; every snapshot that changed and why (only Task 23's padding, plus any a bug fix explained).

- [ ] **Step 3: Finish the branch**

Use superpowers:finishing-a-development-branch. The owner decides between merging `refactor` into `master` now (the checkout Neovim loads picks it up) or keeping the branch until plan 2 is done.

---

## Plan 2 (outline; written in detail after plan 1 lands)

Each line is a task with its own tests at the new module's interface and `make check` (screens unchanged) after each.

1. **`review/`**: `review/diff.lua` (spec, files, lines; reading the diff stops happening inside a paint: the cache refresh moves out of `review.files`, which today runs git on a cursor move), `review/init.lua` (of, find, work, walk, group_of, said, origins), `review/accept.lua`, the paint into the code via `hunks`; `review_page.lua` becomes `review/screen.lua` on sheet, blocks and float.
2. **`render/`**: `render/init.lua` (paint orchestration, lifecycle, toggles), `render/place.lua` (locate, covering, track, at_cursor, cycle; owns `active`), `render/bubble.lua` (bubble, line_bubble, levels), `render/marks.lua` (notes, changes via hunks, dimming via `code`). Each piece of state has exactly one owner. `render.follow_link` moves to actions.
3. **`page.lua`** as a pure `build(state) -> sheet` plus keys, so its content is tested without a window, the way tour.nvim's briefing is.
4. **Home, model**: `home/model.lua` (GROUPS, matches, collect, delta, neighbours; one per-draw cache of each file's lines instead of three).
5. **Home, views**: threads, tours and review tabs as `{ name, count, draw, keys }`, replacing ten `FILTERS[S.filter].view ==` checks and the `TABS = #FILTERS - 1` arithmetic; review keys (`J`, `a`, `d`, `r`, `c`) move into the review view; the diff picker moves into review.
6. **Home, parts**: `PARTS[kind] = { hints, activate }` for code, message, excerpt, change, diagram and stop, replacing the 85-line ⏎ handler and the 50-line hint chain; a diagram node is followed by one function shared with page.
7. **Home, frame and surfaces**: `layout() -> frame` (rows, owners, items, refs, focused) written once, so ⏎ no longer draws twice and j/k no longer recompute every diff; full screen and focus float as two surfaces on `float`, replacing ~40 `S.single` checks; `INDENT`/`LABEL`/`TEXT_COL` become per-session; VimResized bound to the window's life.
8. **Home, the rest**: `inside.lua`, `single.lua`, `reply.lua`, `keys.lua` (one table: key, handler, hint, help line, generating the keymaps, footers and `?` help), `help.lua`; the dead code listed in the review (`S.dirty`, unused params, redundant draws, `layout(false)` twice, `S.order` reset three times, misplaced doc comments).
9. **`store/`**: `store/file.lua` (root, dir, read/write, exclude, load/save/list/new/delete/active, watch, notify), `store/seen.lua` (the seen file: hear, when, unseen, seen_count, mark_seen, visit, visited), `store/init.lua` (the domain: status, title, add, reply, find, accept...), same public interface.
10. **Commands and keys as data**: `init.lua`'s command table, global keys and `:Thread` completion from one list; `plugin/thread.lua` thin.
11. **The rename**: `thread.Comment` → `thread.Thread`, `comment` params → `thread`, Home's `t.c` → `t.thread`; a GLOSSARY.md (thread, message, stop, stage, step, page, walk, tour, batch, round, review, group, hunk, zone, bubble, card, sheet); DESIGN.md gets a "How the code is laid out" section.
12. **The skill's `show.lua`** requires the plugin's `store`, `tour`, `anchor` and `match` instead of re-implementing status, title, `lines_of`, `walk_of` and an exact matcher that disagrees with the plugin's fuzzy one; the checker moves to `check.lua`; `--dir` for a non-default batch directory.
13. **Lint in `make check`**: `lua-language-server --check` (unused locals, globals) and `stylua --check`, with a `.luarc.json` and `.stylua.toml` in the repo; a warning for any file over 600 lines.

---

## Pre-flight findings for the tasks not yet done (2026-10-11)

Tasks 0-4 and 6-16 are done on `refactor`. A read of this plan against the code found these faults in the tasks still to do. Fix each one as you reach its task.

- **Task 5:** thread 3 in the fixture holds the `changes` but has no `file`, so it is never placed and `toggle_drawn(3)` draws nothing. Put the `changes` on anchored thread 4 and call `toggle_drawn(4)`. The claims at Task 23 (its snapshot change) and Task 26 follow from this. The script writes 22 snapshot files, not 23. Keep the store.lua/main.lua fixture in one place (`H.fixture`), shared by the smoke test and the screens.
- **Task 17:** render's and home's `first_line` differ (backticks, trimming). `text.first_line` holds what they share; the backtick step stays with the caller that has it. walk's `fit` counts characters, not columns: moving it to `text.fit` is a wide-character fix, so name it in the commit. Don't write `local width_of = text.width` (that's an alias); call `text.width`. The grep must cover `first_line`.
- **Task 18:** test 2's `room = 14` contradicts its expectation. Use `room = 24`, with width counted in display columns. `look.hints` needs `sep_hl` and a per-label trail to reproduce today's footers (page and review_page put `'  '` in the label chunk; home ends with `{' '}`; render highlights its separator; `key_hints` starts the label highlight after the space). Drop the `<CR>`→⏎ claim. Snapshots must not change.
- **Task 19:** `sheet.apply` must skip nil groups and empty spans, and `P.chunks` must skip empty chunks, as map.lua and home do today.
- **Task 20:** `code.enclosing` and `code.lua` exist already (Task 11). The Files list must match the steps. State that home's `M.syntax` export is deleted and its callers moved.
- **Task 21:** the blank line is drawn as `'  '`, not `''`. The sheet needs a `P.indent`. Use `render.chat`; `look.chat` doesn't exist.
- **Task 22:** `FloatOpts` needs `map(lhs, fn, opts)` (review_page's j/k are expr maps) and `on_close` (help's `done()`).
- **Task 23:** the tabs test passes when nothing is drawn. Assert the number of virt-line marks.
- **Task 24:** after restoring, set `w.keys = nil`, or an outer walk resumed after an inner one loses its keys. `keys.lua` exists already (Task 10, `keys.global`). init.lua must require it.
- **Task 25:** `git.run` must return raw stdout, with callers trimming: today's trimming breaks `git show` (line 1's indent, trailing blank lines). No `local git = M.run` alias. anchor.lua's `parse_codediff` moves into `codediff.lua`. `store.exclude` requires git lazily.
