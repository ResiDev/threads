# Where thread.nvim is going

DESIGN.md is the design as decided, and `design/format-3.ts` the format.
This file says where the code stands against them, the plan to close the
gap, and what is still open. Rewritten 2026-10-16; the history of how it
got here is at the bottom.

## Where it stands

- **Two editors in one plugin.** `lua/thread/legacy/` is the first
  version, on batches, and still the default. The rebuild (`base/` up to
  the surfaces) runs with `setup { rebuild = true }`, which is how it is
  used day to day.
- **The rebuild reads format 3 as a prototype.** Tours and notes are
  parsed into threads underneath: a note is a thread with no tours, and
  the review's tours ride on a hidden thread, id 0 (`model/three.lua`).
  Walking, replies, accepting and `show.lua` work through that carrier.
  It still reads format 2 too.
- **Built on that prototype**: the review screen with the files beside
  it and what touches what lit as you move (`model/touch.lua`); contracts
  with a page each, in the old shape (`shape` blocks, `promises`, `uses`
  with verdicts); ids per kind, `#step:7`, and `.seen` keyed the same
  way.
- **Not merged yet**: `proto/marks`, which removes marks from the plugin
  and the skill. The editor here loads `proto/notes` from its worktree,
  which is behind `master`.
- **The format moved on.** `design/format-3.ts` now has named chunks,
  prose with placed diagrams, contracts with a before and after and a
  blast radius, tours with a briefing, notes with kinds, and no labels or
  checks on steps. None of that is built.

## The plan

Bottom-up, on a branch, as the rebuild was. The new format replaces
format 2 and the prototype's format 3 outright: nothing converts old
reviews, and they are deleted. Reviews an agent writes with the new skill
are the test data for drawing, so the skill comes straight after the
model.

### 1. Land, switch, and clear the ground

- Merge `proto/marks`. Point the editor's config at `master`.
- Make the rebuild the only editor: delete `legacy/`, the `rebuild`
  option and what legacy kept alive (its colours, its smoke test, the
  `old_links` path in `model/diagram`). Every stage after this would
  otherwise have to keep the old code compiling.
- Rewrite GLOSSARY.md in the new words: review, contract, tour, step,
  note (and its kinds), chunk, prose, excerpt, briefing, dependent. Words
  that go: thread (as a part of the model), mark, label, check, group,
  carrier.

### 2. The model reads the new format

- One parse, no carrier: a review is its introduction, contracts, tours,
  notes and chunks. `model/three.lua` and threads as a model type go,
  and `thread.conversations` becomes the review's conversations: each
  step's, note's and contract's.
- The chunk pool: ids unique, every reference found (a step's, a note's,
  a contract's sides and dependents, a message's `changes`), and a
  warning for a chunk nothing points at.
- Wherever prose appears (a review's or a tour's introduction, a step,
  a contract's page, a message), the JSON holds an object, `{ "text":
  "...", "diagrams": { ... } }`, not a string, and the model reads it as
  one type.
- Rounds go: `rounds`, a message's `round`, and the snapshot taken when
  you send. A "the agent's latest answers" list needs only the `heard`
  times in `.seen`.
- Checks go: `model/check`, `draw/check` and the action that runs one.
- Notes check their kind against their status (an issue has `issue` and
  `severity`; a comment has no status).
- Contracts check `source` against `change`, and that every dependent
  but a `none` has `text`.
- Tours need their colour and introduction; colours stay distinct while
  there are sixteen or fewer, the palette's size.
- Whose move, read and walked work per conversation as now. The `.seen`
  keys from the ids change stay. Accepted moves from "per thread" to per
  review, by the chunk's content, so a chunk shared by a step and a note
  is accepted once.
- `model/touch.lua` matches chunk ids first, then overlapping lines.

### 3. Finding a chunk by both ends

- `base/anchor` finds `from`, then `to` as the first match after it,
  each by likeness when edited, `line` breaking ties.
- `rev` resolves through the review's diff: `base` and `head` to its
  ends, `now` to the buffer or the file, anything else as a commit. The
  diff stays as it is, `of` (`uncommitted`, `staged`, `unstaged`) or a
  `base` and `head`. On an uncommitted review `head` is your working
  tree, so it moves as you edit; no snapshot for now. A review with no
  diff has no `base` or `head`: its chunks are `now` or a commit.
- `--check` says when `to` is not found after `from`, and when a side is
  quoted from the wrong version.

### 4. Prose

- `{{chunk:id}}` and `{{diagram:name}}`, alone on a line, replace the
  ```` ```code ```` fence and the separate `diagram` field. `--check`
  errs on one that names nothing and warns of a diagram never placed.
- Markdown tables drawn as tables, so a contract's page and a note can
  use them.

### 5. The skill and `show.lua`

- SKILL.md writes the new format: chunks first, then everything pointing
  at them; a contract's chunk side covers only its signature, a written
  side is the whole contract; dependents found by grepping the name, each
  on the line that uses it; a tour's introduction is its briefing, with a
  diagram when the steps have a shape; notes by kind.
- `show.lua` prints the next id of each kind and the chunk ids in use,
  and `--check` reads everything above.
- Two or three agents write reviews of real changes in this repository
  with only SKILL.md. Those go in `tests/reviews/`, and what they get
  wrong goes back into the skill.

### 6. Drawing and the surfaces

- **The review screen**: the introduction as prose; contracts a row each
  (`+ ~ −`, the name, `why`); tours a row each in their colour; notes as
  an index, a row each with the kind and title, grouped by kind with the
  open first, the heading counting what is open. Labels on screen name
  the kind (`step 3`, `note 12`), since numbers repeat across kinds.
- **A contract's page**: the source as a diff (`-`/`+` lines with the
  changed words lit, or two blocks when most of it changed); its prose;
  the blast radius, grouped by impact with `missed` first and each
  dependent's text under it; what touches it; the conversation.
- **The walk** opens on the tour's briefing, a float; `L` into step 1,
  `H` back to it, `J`/`K` between tours landing on briefings, and a key
  for the briefing mid-walk.
- **A step** shows the notes on its chunk, badge and title, a key away.
- **A message's changes** show their ranges, not only a first line.

### 7. Try it, then issue #1

Use it on a real change, fix what that turns up, then the rest of
[issue #1](https://github.com/ResiDev/threads/issues/1):

- **Focus**: tour.nvim's `gz`, the step's chunk lit and the rest dimmed,
  and the chunk highlighted in the file itself, not only on the screen.
- **Names in a step's text tied to its code**, replacing marks: a name in
  backticks that is in the step's chunk is underlined there with the same
  number as in the text, and lit while the cursor is on the sentence.
  Anywhere else, a key on a name shows its definition in a float.
- **Keys**: `⏎` to open often gets stuck and then nothing works, `J`
  too, since it calls the same `open`; it needs a repro first. Find
  better keys for opening. `w`/`b` move between links in text (`#step:7`
  and names in backticks) as they move between words; the walk, on `w`
  today, needs another key.

## Later

- **Versions, suggestions and comparisons.** A suggestion is a version of
  a chunk the agent proposes: `⏎` applies it, drawn against the real
  code, tried in the buffer before anything is written, edited in a
  float; pushing back adds v2 beside v1. A comparison shows versions, or
  several chunks, side by side, inline or in turn.
- **Verification beyond checks**: a check run on the base and the head,
  test results on their chunks, a browser page as text.
- **Planning with agents**, probably its own repo. Planning today is one
  long chat where decisions get lost, the problem reviews had before
  each point got its own conversation. What carries over: a conversation
  per decision, a worklist of open questions, diagrams and examples of
  the proposed shape. What differs: there is no diff, a decision has
  options with costs, decisions depend on each other, and what a plan
  decides is what a review could check the code against.

