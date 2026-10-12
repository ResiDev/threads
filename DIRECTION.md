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
   ├─ tour      an introduction, then steps
   │  └─ step   on a chunk, or on no line
   ├─ check     what the agent ran to confirm it works
   └─ message   one turn of its conversation
chunk           lines of a file, with versions
```

| | is | holds | its state | you |
| --- | --- | --- | --- | --- |
| **review** | what Home lists | an introduction, threads, what it is about | its threads and chunks added up; open or closed | make one, add threads, go through it, close it, open it again |
| **thread** | one topic in a review | a chunk or no line, messages (the first is its introduction), tours, checks, labels | open, or closed as fixed, won't fix or not a problem; whose move | reply, close, open again |
| **tour** | an introduction, then steps | steps | how far you have walked | walk it with `L` and `H` |
| **step** | one place in a tour | a chunk or no line, its text, messages once you reply | walked or not | reply in it, go to it |
| **message** | one turn, yours or the agent's | text, with the prose below | read or new | reply |
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
- **Labels** on a thread or step: title, verdict and severity, risk, kind
  and weight.
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
    git.lua             run git, a file at a revision, snapshots
    diff.lua            a diff spec read into files and hunks
    anchor.lua          find a quoted line or chunk; capture one from a buffer
    match.lua  code.lua  text.lua  json.lua
    codediff.lua        the optional adapter
  ui/                   drawing
    sheet.lua  float.lua  theme.lua  look.lua  keys.lua
    hunks.lua           a chunk's versions drawn into a code buffer
    diagram/            layout
  store/
    file.lua            read, write, watch; fires an event on change
    seen.lua            read, walked, accepted
  model/                one file per primitive: its data and its state
    review.lua  thread.lua  tour.lua  step.lua  message.lua
    chunk.lua           its anchor, located now; a hunk when the diff has it
    version.lua  check.lua
  prose/                parse, and draw into a sheet
    init.lua            markdown, and which primitive a block is
    excerpt.lua  note.lua  link.lua  diagram.lua  comparison.lua
  draw/                 each primitive drawn the same way everywhere
    review.lua  thread.lua  tour.lua  step.lua  message.lua  chunk.lua  check.lua
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
| `text`, `json`, `match`, `code`, `git`, `anchor`, `review/diff` | `base/`, without their `store` requires |
| `sheet`, `float`, `theme`, `look`, `keys`, `hunks`, `diagram/` | `ui/`; `look` gives `tour.track` to `draw/tour` |
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
wrong. Walked marks are keyed by a step's content, as acceptance is, so
reordering steps keeps them.

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
