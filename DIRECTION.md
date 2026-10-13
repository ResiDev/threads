# Where thread.nvim is going

What has turned out to matter, noted on 2026-10-12 after the refactor.
DESIGN.md says how things work now; this says what to build toward.

## Goal

The goal is to move interacting with agents closer to the code. There are three aims

1. More comprehension for the user, by agents being able to interactive explain, show
2. Give the user a better way to discuss point by point rather than one giant message vs another (in typical single threaded chat)
3. More structure to the review/explore process

## Words

The model, from the top:

```
review          about a diff, or about code as it stands
└─ thread       one topic, on a chunk or on no line
   ├─ message   one turn of its conversation
   │  └─ tour   an introduction, then steps
   │     └─ step   on a chunk, or on no line
   └─ check     what the agent ran to confirm it works
chunk           lines of a file, with versions
```

| | is | holds | its state | you |
| --- | --- | --- | --- | --- |
| **review** | what Home lists | an introduction, threads, what it is about | its threads and chunks added up; open or closed | make one, add threads, go through it, close it, open it again |
| **thread** | one topic in a review | a chunk or no line, messages (the first is its introduction), checks, labels | open, or closed as fixed, won't fix or not a problem; whose move | reply, close, open again |
| **tour** | an introduction, then steps | steps | how far you have walked | walk it with `L` and `H` |
| **step** | one place in a tour | a chunk or no line, its text, messages once you reply | walked or not | reply in it, go to it |
| **message** | one turn, yours or the agent's | text, with the prose below; the agent's can carry tours | read or new | reply |
| **chunk** | lines of a file, plain code or a hunk | its anchor, its versions | accepted in its thread, for its content as it is now | accept, take back |
| **version** | one form of a chunk's code | the code, who made it | a suggestion: open, applied or declined | apply, take back, decline |
| **check** | what the agent ran to confirm it works | some text, and a bash line | none | a key opens the terminal with the line typed in, ready to run |

- **Review** has both senses: a judgement, as in a code review, and an
  overview, as in a literature review. "A review of how auth works" is a
  review too.
- **What a review is about** is a diff (uncommitted, from a base, between
  a base and a head) or code as it stands. It decides which chunks are
  hunks. A review can also come from a critique, LSP references, a grep or
  test failures.
- **A review holds what the agent picked**, not the whole diff. A hunk
  no thread names is not in it.
- **A thread you start** on a line goes in a review you pick when you
  save it: a searchable list, or a new review, which needs a title. It
  becomes a new thread there. The list, and Home, put first the review
  with the newest thread or message.
- **A closed review** leaves Home's list. Home can show the closed ones
  as well, or only them, which is where you open one again. `show.lua`
  skips them.
- **A thread's introduction is its first message**, the one you reply
  under. It is drawn apart from the conversation: centred, with no mark
  for who wrote it. A review's or a tour's introduction is text you do not
  reply to.
- **Labels** on a thread or step: title, verdict and severity, risk and
  kind.
- **A tour comes with a message.** The agent's reply carries the tour it
  answers with, and a review's thread carries its tours on its
  introduction. A thread's tours are its messages' tours, in order, and
  each is drawn under the message that brought it.
- **A chunk** is lines of a file, one or many: lines 35 to 66 of
  `run.ts`, plain code with no diff at all. Steps are on chunks, and
  notes, excerpts and links point at them. **Hunk** is git's word for a
  run of changed lines: a chunk with git's old and new versions.
- **An anchor** is how a chunk is found: its first line quoted, so it
  follows the code as it moves, and its line number to break ties.
- **Versions.** A suggestion is a version the agent proposes; applying it
  yourself accepts the chunk at that content. A fix the agent made is a
  version it applied, so the chunk comes back for you to accept. Pushing
  back adds v2 beside v1, and a declined version stays, so the agent does
  not suggest it again.
- **A check** is some text saying what the agent ran and what it got,
  and the bash line it ran. A key opens Neovim's terminal with that line
  typed in, ready to run; you press enter or do not.
- **Rounds** are the messages sent together, each snapshotting the code.
  "What changed since you last looked" and passes are built on them.

State is a characteristic of each of these, not a primitive of its own.
Three rules for it:

- **Whose move is worked out** from the messages, never stored. A step's
  conversation does not add up into its thread's state, but something
  waiting for you in a step still needs a sign on the thread; how it looks
  is decided with the screen.
- **Acceptance follows content.** It is keyed by the chunk's code, so a
  change brings it back. It belongs to the thread: the same hunk in two
  threads is accepted in each on its own, and once in a thread however
  many of its tours show it. Accepting never stages anything
  in git, and a review keeps its state to itself.
- **Positive is a key, negative is a message.** There is no reject on a
  chunk: what is wrong with it is a reply, and the agent needs the why.
  Declining a suggestion is the one exception, and a reason given becomes
  a message.

The shape is fixed, and what goes in it is not. The agent picks, for each
thread, which tours it has, how many and what each is called: "what
changed", "every caller", "the path to the failure". There is no template.
Common sets go in the skill as suggestions; the plugin knows none of them.
The screen draws a step by what its chunk is (a hunk, plain code, no
line), not by the tour it is in, and you can accept any chunk.

Two rules keep it small:

- **A level with one child opens as the child.** A review of one thread
  opens on the thread; a thread with only messages opens on the
  conversation. The title bar always says where you are.
- **The back and forth stops one level down.** A message can carry a tour
  and a step can carry messages, and no further.

Words that go:

- **batch**: the review is the top level, one file in `.threads/`.
- **group**, and **topic** in earlier notes here: a thread.
- **stage**: a tour with stages becomes a review with a thread per stage.
- **stop**: a step.
- **place** and **range**: a chunk, or a link to one.

Note, bubble, card, zone and Home keep their meaning in GLOSSARY.md.

## In the prose

What an introduction, a message or a step's text can hold besides words:

1. **Diagrams.** Flow, sequence and calls, every box anchored. They could
   follow the walk, marking the node you are on so the diagram works as a
   map, and show a diff's shape before and after, with the edges added
   and removed coloured.
2. **Excerpts.** Code pulled live from the file and drawn with its
   colours. A plain markdown fence is a copy that goes stale.
3. **Notes.** Highlighting from the text into the code: a line, a word on
   it, what it says. Not only on steps: any introduction or message can
   carry them.
4. **Links.** To a review, a thread, a step or code. Inline as a name you
   press, or as a row showing the line it points at. What an answer
   changed is a list of links.
5. **Examples.** A worked case: what goes in, the lines it runs, what
   comes out. They are markdown with excerpts and diagrams, nothing new to
   draw. The skill asks the agent for one wherever a point is abstract.
6. **Comparisons**, new. A way of viewing a chunk's versions, or several
   chunks side by side: side by side, as an inline diff, or flipped
   between v1, v2 and v3 in place. A comparison has no state of its own;
   the decision belongs to what it compares. A **suggestion** is a
   version of a chunk as it stands, and more than markdown:
   - `⏎` applies it, and `⏎` again takes it back;
   - it is drawn against the real code, and says so when the code has
     moved on and it no longer applies;
   - you can try it in the code, drawn into the buffer the way a review's
     hunks are, before anything is written;
   - you can edit it in a float before applying it;
   - reply on it ("why not X?") and the agent adds v2 beside v1, so the
     comparison keeps the history;
   - on a thread about a bad pattern, one suggestion per chunk, applied
     together.

   Some comparisons have nothing to apply: a hunk's old and new code, two
   instances of a pattern, an example's output on v1 and v2.

Labels (verdict, risk, kind) and checks are on a thread or a step, not
in the prose.

## Structure

The rebuild, laid out in layers. Each requires only the layers below it.

```
init            commands, keys, config
 |
surfaces        screen/ . code/ . walk . focus . page . map . compose
 |               open each other through go; redraw on store events
actions         the verbs: reply, close, accept, apply, decline, run
 |
draw/           one drawer per primitive, into a sheet
 |
prose/          the text primitives
 |
model/          the primitives and their state
 |
store/          files on disk; what you have read, walked and accepted
 |
base/  ui/      the foundations: they know nothing of reviews
```

```
lua/thread/
  base/                 finding code
    repo.lua            the repo root, paths relative to it
    git.lua             run git, a file at a revision, snapshots, line changes
    diff.lua            a diff spec read into files and hunks
    source.lua          what a buffer holds; a file's lines as the editor has them
    anchor.lua          find a quoted line or chunk; capture one from a buffer
    match.lua  code.lua  text.lua  json.lua
    codediff.lua        the optional adapter
  ui/                   drawing
    sheet.lua  float.lua  theme.lua  look.lua  keys.lua
    hunks.lua           a chunk's versions drawn into a code buffer
    changes.lua         a diff opened in CodeDiff or Vim's diff mode
    diagram/            layout
  store/
    file.lua            read, write, watch; fires an event on change
    seen.lua            read, walked, accepted
  model/                one file per primitive: its data and its state
    review.lua  thread.lua  tour.lua  step.lua  message.lua
    chunk.lua           its anchor, located now; a hunk when the diff has it
    version.lua  check.lua  diagram.lua
    labels.lua          the labels' values
    fields.lua          reading the agent's fields, and saying what is wrong
  prose/                parse, and draw into a sheet
    init.lua            markdown, and which primitive a block is
    excerpt.lua  note.lua  link.lua  diagram.lua  comparison.lua
  draw/                 each primitive drawn the same way everywhere
    review.lua  thread.lua  tour.lua  step.lua  message.lua  chunk.lua  check.lua
    labels.lua          glyphs and badges every primitive's drawing shares
  code/                 in code buffers: placement, bubbles, cards, notes
    place.lua  bubble.lua  marks.lua  init.lua
  screen/               reviews, a review, a thread; one child opens as the child
    init.lua  keys.lua  help.lua
  walk.lua  focus.lua  page.lua  map.lua  compose.lua
  go.lua                open a primitive where it belongs
  actions.lua  config.lua  init.lua
```

| primitive | data and state | drawn by | shown in |
| --- | --- | --- | --- |
| review | `model/review` | `draw/review` | the screen: a row, then its overview |
| thread | `model/thread` | `draw/thread` | the screen, the focus float, a bubble |
| tour | `model/tour` | `draw/tour`: outline, track | the screen, the winbar, a page |
| step | `model/step` | `draw/step` | a card, a page |
| message | `model/message` | `draw/message` | the screen, the focus float, a bubble |
| chunk | `model/chunk` | `draw/chunk`: code or diff | the screen, marks in the code |
| version | `model/version` | `draw/chunk`; `ui/hunks` in the code | the screen, the code |
| check | `model/check` | `draw/check` | the screen, the focus float |
| prose | `prose/*` | `prose/*` | wherever text is drawn |

The rules that shape it are in CODING_STANDARDS.md, under Layers. What
breaks them today:

- `anchor`, `git`, `review/diff` and `refs` require `store`, mostly for
  `store.root`; `base/repo.lua` ends that.
- A thread is drawn three ways, in `home/thread.lua`,
  `review/screen/view.lua` and `render/bubble.lua`.
- `actions` requires `home`, `walk`, `map`, `page` and `render`, and
  `walk` requires `actions` back.

How that is built in Lua:

| idea | in Lua |
| --- | --- |
| a layer | a folder of modules |
| an interface | what is on a module's `M`, with its `---@class` annotations |
| private | `local` |
| a primitive | a plain table from the JSON, passed to module functions |
| talking upward | an event (`User` autocmd), or registering a function |
| the rules | a test over the `require` lines |

Where today's code goes:

| today | goes to |
| --- | --- |
| `text`, `json`, `match`, `code`, `git`, `anchor`, `review/diff` | `base/`, without their `store` requires; `text`'s prose half to `prose/`, `git`'s diff windows to `ui/` |
| `sheet`, `float`, `theme`, `look`, `keys`, `hunks`, `diagram/` | `ui/`; `look`'s labels for primitives to `draw/` |
| `store/file`, `store/seen` | `store/` |
| `tour.lua`, `review/init.lua`, `review/lines.lua`, `store.status` | `model/` |
| `blocks.lua`, `refs.lua` | `prose/` |
| `home/thread`, `home/message`, `review/screen/view` | `draw/`, merged |
| `render/` | `code/` |
| `home/`, `review/screen/` | `screen/`, merged, without the tabs |
| `menu`, `list` | gone: the screen lists reviews |

The skill's `show.lua` and checker depend on `store/`, `model/` and
`base/` only, never on drawing.

### On disk

Each review is one JSON file in `.threads/`, nested like the tree:
threads hold their messages, tours and checks; tours hold steps; steps
hold their checks and their replies. Since replies live in their step,
the agent can reorder steps or add them and the replies go along. A
`format: 2` field lets the checker tell the agent when it has written the
old shape. What you have read, walked and accepted is kept beside it in a
`.seen` file only the plugin writes.

### The agent's side

The agent runs the skill's `show.lua`. It lists what is waiting for the
agent in every open review, grouped by review; naming a review narrows
it. `show.lua --check` checks what the agent wrote. There is one skill;
today's length is fine, and it should not grow much.

Links are positional: `#12` a thread, `#12.3` a step when the thread
has one tour, `#12.2.3` step 3 of tour 2, `<review>#12` a thread in
another review. Steps have no ids, one less thing for the agent to get
wrong. Walked marks are keyed by a step's chunk, or its title on no line,
so the agent reordering or retitling steps keeps them.

What counts as waiting for the agent is decided in one function in
`model/`, which `show.lua` calls, so it can be read and changed in one
place. None of it is shown in the editor.

### Building it

On a branch in a worktree, bottom-up. The first change rewrites
GLOSSARY.md in the new words, with the old ones to avoid. Then move
`base/` and `ui/` across with their tests, write `store/` and `model/`
new under the strict lint, then `draw/`, then the surfaces, then switch
over. Nothing converts today's batches; they are deleted.

The skill is rewritten straight after `model/`, before `draw/`. Reviews
an agent writes with it are the test data for `draw/` and the screen
tests.

Tests come across only when they test behaviour at a seam that still
exists, and each new layer brings its own; CODING_STANDARDS.md says what
a good one is.

The first cut is the model (review, thread, tour, step, message, chunk),
checks, and today's prose: diagrams, excerpts, notes, links. Versions,
suggestions and comparisons come after it.

The plugin never runs an agent. The files stay the interface: you ask
the agent outside Neovim, it reads and writes them.

### Stages

- **Stage 1, done 2026-10-12.** GLOSSARY.md in the new words; `base/` and
  `ui/` moved across; the layer test; the strict lint.
- **Stage 1's follow-ups, done 2026-10-13**, below.
- **Stage 2: `store/` and `model/`, done 2026-10-13**, format 2, read
  and checked once; below.
- **Stage 3: the skill and `show.lua`, done 2026-10-13**, on the
  model; below.
- **Stage 4: `prose/`.**
- **Stage 5: `draw/`.**
- **Stage 6: `actions`, `go` and the surfaces.**
- **Stage 7: the switch.** `init` on the new code, today's code deleted,
  the docs rewritten.

### Stage 1's follow-ups

A review of stage 1 (2026-10-13) found that the layer test passes because
the coupling moved, not because it went. `base/` and `ui/` require nothing
above them, but still know the shape of batches, threads, messages and
prose, and lua-language-server checks them against types declared in
`store/`. Stage 2 builds on these layers, so they are fixed first, in this
order:

1. **The layer test reads types as well as requires.** Every `---@class`
   and `---@alias` belongs to the layer of the file that declares it. A
   built layer naming a type from above it fails: in `@param`, `@return`,
   `@type`, `@field`, `@cast` or `@as`. That turns most of what follows
   into failing tests.
2. **`git`**: `snapshot(ref, message)` and `drop(prefix)`, the ref named
   by the store. `base_for`, which reads rounds, goes to `model/`. Opening
   diffs (`open_file_diff`, `open_all`, `codediff.open`) opens windows, so
   it goes to `ui/`. What stays: run, show, snapshot, hunks.
3. **`json`**: `encode(value, schema)`, the key order passed in. The
   order is format 2's, so it belongs to `model/`.
4. **`text` splits.** `width`, `fit`, `pad`, `plural`, `since` and `ago`
   stay. `wrap`, `segments`, `link_at`, `first_line` and `first_sentence`
   are prose: they move to `prose/` as they are, and stage 4 rebuilds
   them.
5. **`look` splits.** `key`, `show_key`, `hints`, `footer`, `num` and
   `track` stay. `glyph`, `who`, `label`, `dots`, `verdict_of`,
   `kind_badge` and `risk` label primitives: they move to `draw/` as they
   are.
6. **`diff` takes a typed spec** and never reads a file's `diff` field;
   reading it, and the errors written for the agent, go to `model/`. `gen`
   goes private behind `diff.changed()`. Its autocmd moves into
   `diff.watch()`, which `init` calls, so requiring it does nothing.
7. **`tour`'s derived cache goes.** It is one loop over tens of threads,
   and `review.work` is cached already; `tour` then no longer requires
   `base/diff`. The review said the cache depends only on the batch; it
   depends on the code too, through `step_of` for a reply in a review's
   hunk. Dropping it is still right.
8. **`anchor` splits.** `base/source.lua` says what file and revision a
   buffer holds, and gives a file's lines as the editor sees them
   (`of_buf`, `belongs`, `lines_of`). `anchor.lua` says where a quote is
   now (`locate`, `capture`, `finder`), and `locate` takes `{ text, line
   }`. `diff` then requires `source`, not `anchor`.
9. **Hunks follow the glossary.** git's `thread.Hunk` becomes
   `thread.LineChange`, `thread.DiffPart` extends it, and `ui/hunks` draws
   `DiffPart`s, so `DrawnHunk` goes. `thread.DiffHunk` is the glossary's
   hunk.
10. **`ui/diagram` lays out a diagram it is given.** Checking one the
    agent wrote, with errors meant for it, goes to `model/` with the rest
    of the file. The review missed this one.
11. **The test tooling.** `tests/layers.lua` names its layers (`built =
    'ui'`, no bare indexes) and gives `of_path` and `built_paths`, used by
    both `independence_spec` and `tests/lint.lua`. The lint checks that
    every function on `M` in a built layer has its `@param`s and
    `@return`: lua-language-server passes a function with none at all
    (`text.pad`, `text.segments`, `codediff.open`, `theme.blend`,
    `look.key`, `diagram.is_linked`).
12. `show.lua` drops the copy it made so that `anchor.locate` would skip
    removed lines; it no longer looks for them.

Left as it is: `ui/diagram/flow/init.lua` is 630 lines, over the 600-line
warning, as it came across.

### Stage 2: `store/` and `model/`, done 2026-10-13

Today's code above the foundations is in `lua/thread/legacy/`, at the
same paths beneath it, and the types it declares are `thread.legacy.*`,
so the model's names are free. It runs on its own store until the
switch. The new layers are at their real paths, and `built` is `model`.

**`store/` knows no primitives.**
- `file.lua` reads and writes review files by id, and keeps no cache: a
  read decodes afresh. It remembers each file's time as it last wrote it
  or told of it, so the watcher tells only of what changed under it.
  Every change fires `User ThreadChanged` with `{ id }`; `fire` is there
  for `seen.lua` too. There is no current review: `.threads/active` is
  gone.
- `seen.lua` keeps, by key: messages read per conversation (`12`, or
  `12/<step>` for a step's), steps walked and chunks accepted per
  thread, and when each of the agent's messages was heard. Walked is per
  thread, not per tour, since a step's key is unique in its thread. The
  first time a review is heard, what is in it gets its file's time;
  saving a review hears it, so the agent's next messages get theirs.
  Reading, walking and accepting fire; hearing does not.

**`model/`**: a file per primitive, and two that serve them.
`fields.lua` reads the agent's fields and words the problems (`thread
12, message 1, tour 1, step 2, chunk: ...`), with where each field of
the old shape went. `labels.lua` holds the labels' values.
- Each primitive's `parse` checks in place: the table decoded is the
  one returned, with the lists it always has filled in (a review's
  `rounds` and `threads`, a thread's `messages`, a step's `messages`).
  The ones it may not have (`notes`, `changes`, `tours`, `checks`) stay
  out of the file when there are none.
- Errors stop a review being read; warnings (the agent's thread with no
  title, a risk with no why, a step with no text) do not. A field a
  primitive does not name is an error.
- `review.read(id)` holds what it read until the file's time changes:
  the same table until then. `review.save` writes it back without its
  `id`, which is the file's name. `review.list()` gives the reviews
  newest message first, and apart, those that cannot be read, with why.
- A message's tours are parsed by its thread, so a step's messages are
  refused any. That is how the back and forth stops one level down, and
  it keeps the requires a tree.
- `thread.conversations(t)`: its own, then each step's, in order.
  `thread.move(c)`; `thread.waiting(r)`, the one function; `unread` and
  `mark_read`. `step.key` (its chunk, or its title on no line),
  `step.walked`, `tour.walked`, `tour.next`.
- Rounds are in `review.lua`. `review.add` (a thread of yours) and
  `review.reply` (in any conversation; it opens a closed thread) send a
  message: it joins the round still waiting, or starts one with a
  snapshot at `refs/threads/<id>/<n>`. Neither saves; the action does.
  `review.base_for(r, c, i)`.
- `chunk.spec(about)`, `chunk.locate(c, spec)`, `chunk.code`,
  `chunk.key` (its hunk's key, or a hash of its code), `chunk.accepted`
  and `chunk.accept`.
- `review.unfound(r)`: every chunk, note, last change and diagram node
  of an open thread that is not in the code now, for `show.lua --check`.

Left for later:
- The guards in `base/` that contradict their types (`anchor.locate`'s
  `type(a.text)`, `anchor.finder`'s `type(a.file)`) stay until the
  switch: legacy still hands them data nothing has checked.
- A message's `round` is not checked against the rounds there are.
- `version.lua` comes with suggestions, after the first cut.
- `prose/init.lua` and `draw/labels.lua`, moved ahead in stage 1, are
  required by legacy. Stages 4 and 5 rebuild them without breaking it,
  or first copy what legacy needs into `legacy/`.

Stage 2's follow-ups, from its review, done 2026-10-13:
- A step is known by its chunk, or by its title when it is on no line,
  so the agent retitling it keeps it walked and its replies read. A
  later step of the thread on the same chunk is told apart by its place
  among them.
- A message you send opens a closed review again, as it opens a closed
  thread: `show.lua` skips closed reviews, and in one every reply
  started a round.
- Where a removed line sits is `diff.removed` in `base/`, which legacy's
  `old_place` and `chunk.locate` both call.
- Legacy's store does not load a file with a `format`, so today's Home
  does not list a format 2 review as a batch.

**Format 2**, as a sketch:

```json
{
  "format": 2,
  "title": "Tours pick up where you left off",
  "diff": { "base": "main" },
  "status": "open",
  "introduction": "Two things changed: tours resume, and the cache moved.",
  "rounds": [{ "sent": "2026-10-13T10:00:00", "snapshot": "a1b2c3d" }],
  "threads": [
    {
      "id": 1,
      "title": "Walking a tour again resumes it",
      "chunk": { "file": "lua/walk.lua", "line": 321, "text": "    if furthest > 0 and first then" },
      "status": "open",
      "kind": "feat",
      "risk": "medium",
      "risk_why": "the .seen file gains a field older versions drop",
      "messages": [
        {
          "from": "agent",
          "text": "Why it changed, with excerpts and notes.",
          "tours": [
            {
              "title": "Every caller",
              "introduction": "Three places read the walked marks.",
              "steps": [
                {
                  "title": "The map ticks every stop you saw",
                  "text": "It ignores `furthest`, which is right.",
                  "chunk": { "file": "lua/map.lua", "line": 90, "text": "local function collect_walk(batch)" },
                  "messages": []
                }
              ]
            }
          ]
        }
      ],
      "checks": [{ "text": "Walked two steps, ended, walked again: on step 2.", "run": "make test SPEC=walk" }]
    }
  ]
}
```

- No `diff`: the review is about code as it stands. A diff is `of`
  `unstaged`, `staged` or `uncommitted`, or from a `base` to a `head`.
- A review's `status` is `open` or `closed`. A thread's `status` is `open`, `fixed`, `won't fix` or `not a problem`.
- Labels sit on a thread or a step: `verdict` and `severity`, `risk` and
  `risk_why`, `kind`.
- A message has `from`, `text`, and may have `notes`, `diagram`, `changes`
  (links to the code it changed) and, for yours, `round` and `at`. The
  agent's may have `tours`.
- A step has a `title` and may have `text`, a `chunk`, `notes`, a
  `diagram`, labels, `checks` and `messages`. On no line it has no
  `chunk`, and is drawn as a page.
- A chunk is `file`, `line`, `text` (its first line, quoted), and may
  have `lines`, `rev`, or `side: "old"` for a line the diff removed. A
  note is a chunk with a `note` and a `mark`.
- The next thread id is the highest in the file plus one.

### Stage 3: the skill and `show.lua`, done 2026-10-13

The skill writes format 2, and `show.lua` asks the model. The installed
skill links to `master`'s copy, so this goes live at the switch.

**`show.lua`** requires `store/`, `model/` and `base/` only, which the
layer test now holds for every script in `skills/`.
- With no review named, it lists what `thread.waiting(r)` gives for
  each open review, the newest file first; naming one narrows it, and
  says when it is closed. Each conversation has its link
  (`thread.link(c)`: `#12`, `#12.3`, `#12.2.3`), where it is, its code (a
  hunk drawn as a diff, the chunk's lines marked), the step and what it
  says, the messages, and the link of each tour's first step. A review
  that cannot be read is one line, with its first error.
- It writes nothing. It reads with `review.parse`, not `review.read`,
  because reading hears the agent's messages, and when they were first
  heard is the editor's to note.
- `--check [review]`: the problems of `review.parse`, errors and
  warnings, then `review.unfound(r)`; with no review named, every one.
  It fails on any error. A `note:` lists the hunks no thread or step is
  on (`review.left_out(r)`): a review holds what the agent picked, so it
  is not a warning.
- `review.unfound` warns of a chunk found only by likeness: a quote that
  no line reads now.

**Decided:**
- A diagram's node links to code only (`file`, `text`, `line`, `side`).
  `step` and `stage` are refused; legacy passes `old_links` to
  `model/diagram.validate` until the switch.
- Between a `base` and a `head`, a chunk is read at the head only when
  its `rev` says so, so the skill asks for `rev` on chunks in such a
  review, and prefers diffs that end at the working tree.
- Untracked files leave out `.threads/`: the agent may write the first
  review before the plugin has kept the folder out of git, and the
  review's own file was a hunk of its diff.
- `make smoke` no longer runs the skill; `tests/skill_spec.lua` runs
  `show.lua` as the agent does.
- SKILL.md keeps today's length and sizes of answer. Groups became
  threads, a group's hunks, affected code and tests became its tours,
  suggested by name ("What changed", "Every caller", "Tests"), and the
  notes on them became each step's text, read on its own.

Left for later:
- `--check` does not read the excerpts and links in text: `prose/`
  parses them, in stage 4, and `show.lua` may then require it.
- A message's `round` is still not checked against the rounds there are.

## Verification

A review should show that what was built works. thread.nvim validates
nothing itself: the agent has the shell and the browser. The review
carries what the agent ran, as a check on the thread it backs, and a key
gives you the same line in a terminal to run yourself.

Later, maybe: the same check on the review's base and head, test results
on their chunks, a browser's page as text, screenshots.

## Separately: design and planning with agents

A different idea, probably its own repo. What the review taught may carry
over to working out a design or a plan with an agent, before any code is
written.

Planning with an agent today is one long chat or one long document. The
agent proposes, you push back point after point, and decisions get lost in
the scroll. That is the problem reviews had before each point got its own
thread.

What may carry over:

- **A conversation per decision.** A plan's threads are its decisions and
  open questions, each with the whole argument about it in one place.
- **A worklist.** Every question decided, deferred or dropped, so none is
  skipped before building starts.
- **The prose.** Diagrams of the proposed shape, examples that walk the
  design through a concrete case before it exists, comparisons of the
  options, and tours of the code it will change.

What is different:

- **Nothing to diff yet.** The thing discussed is decisions, not code.
  Code shows as context: what exists, and what the plan will touch. A
  review of a plan made from its markdown as hunks was tried on
  2026-10-11, and it was the wrong way round.
- **Options.** A decision has its options side by side, each with its
  cost, then the one chosen and why.
- **Decisions depend on each other.** Changing one reopens others.
- **It feeds the review.** What a plan decides is what the change was
  for, the axis a review is missing. A review could check the code against
  it.

Open: where it lives, in Neovim or somewhere else, and whether decisions
end up as records in the repo, like ADRs.
