# thread.nvim refactor: design

Date: 2026-10-11. Agreed in conversation with the owner after a read of the
whole plugin.

## Scope

- Only thread.nvim changes. tour.nvim and comments.nvim are separate
  plugins, designed to be independent, and are not touched. The owner's
  Neovim config is not touched either, with one exception: the
  `dependencies = { 'comments.nvim' }` line in `lua/plugins/thread.lua`
  (see Decisions).
- thread.nvim must not load code from any other plugin. Today it loads
  none from tour.nvim or comments.nvim; its copies of `match.lua` and
  `diagram/*` are its own and stay. The one exception is the optional
  CodeDiff integration, which stays but moves behind one adapter module.

## Decisions

| Question | Decision |
| --- | --- |
| CodeDiff (word-level diff colours, `:CodeDiff` to open changes) | Keep, optional, behind one module `thread/codediff.lua`; everything works without it |
| `:Thread import` of tour.nvim `.tour` files | Remove: `import.lua`, the subcommand and its completion, `config.tours`, the smoke-test section, the docs. `symbol` and `pattern` anchors on diagram nodes came in with imported tours and go too |
| home.lua editing which-key's loaded config | Keep (owner, 2026-10-11): it loads nothing, only reads which-key's table if loaded, so `g` on Home doesn't wait for which-key. The independence test allows exactly this |
| `dependencies = { 'comments.nvim' }` in the config's `lua/plugins/thread.lua` | Remove (owner: "I don't want any dependencies on comments"), knowing Enter on a thread may stop working while comments.nvim is also installed and loads second |
| How to work | In a git worktree on a `refactor` branch; plan executed subagent-driven |

## What the refactor must do

The owner approved these strategies (numbering from the review):

- **B. A safety net first.** One test harness (runner, helpers, a fixture
  git repo), screen snapshots of everything thread.nvim draws, and small
  commits.
- **C. Shared modules** for the code that is written several times:
  `text` (fit, pad, width, wrap, ago, ...), `sheet` (lines, highlights,
  items, written to a buffer), `code` (syntax-lit code rows, the scope
  around a line), `blocks` (prose with excerpts, diagrams, conversations),
  `float` (scratch floats), `hunks` (removed lines drawn into the code),
  `keys` (keymaps laid over the user's and given back), one `git` module
  plus the `codediff` adapter.
- **D. Split the big files** where they really vary: `home.lua` (3128) into
  `home/` with views, parts and two surfaces; `render.lua` (1537) into
  `render/`; `review.lua` + `review_page.lua` (1747) into `review/`;
  `page.lua` built on the shared modules; `store.lua` into persistence,
  seen state and the domain.
- **E. Patterns everywhere.** One owner per piece of state; draw
  functions return data and it is written once; events instead of
  require-inside-function loops; one table instead of parallel lists of
  keys, hints, help and commands; finish the rename from comments.nvim
  (`comment`, `t.c`) to thread's words, with a GLOSSARY.md.
- **Fix every bug found** (list in plan 1).

Behaviour stays the same except where a bug fix changes it. The screen
snapshots are how that is checked.

## Target layout (end of plan 2)

```
lua/thread/
  init.lua            setup, the command table, global keys, autocmds
  config.lua
  text.lua            width, fit, pad, plural, first_line, first_sentence, ago, wrap, segments, link_at
  look.lua            glyphs, labels, badges, verdicts, key hints as chunks
  sheet.lua           lines + highlights + marks + items, written to a buffer
  blocks.lua          prose (with excerpts), diagrams, conversations, on a sheet
  code.lua            syntax spans, the enclosing scope, code rows on a sheet
  float.lua           scratch floats: window, keys, when they close
  hunks.lua           removed lines and washes drawn into a code buffer
  keys.lua            global lookup, an overlay that gives keys back, zone keys
  json.lua  match.lua  anchor.lua  refs.lua  tour.lua  theme.lua
  git.lua             one runner, show, snapshot, diff parsing, refs
  codediff.lua        the optional CodeDiff adapter, and nothing else of CodeDiff anywhere
  store/              init (domain), file (persistence), seen
  review/             diff, init, accept, screen
  render/             init, place, bubble, marks
  home/               init, model, frame, views/{threads,tours,review}, thread, parts, inside, single, reply, keys, help
  page.lua  walk.lua  map.lua  menu.lua  compose.lua  actions.lua
  diagram/*
```
