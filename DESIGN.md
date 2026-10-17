# thread.nvim

An agent explains a change, or a part of the code, as a review you read
and walk in Neovim, and you talk back to it point by point. This file is
the design as decided. `design/format.ts` is the format the agent writes,
field by field, with an example. DIRECTION.md says how much of this is
built and what comes next. The words are in GLOSSARY.md, the keys in
KEYS.md.

## Why

Talking to an agent about code happens in one long chat, away from the
code, one big message answering another. thread.nvim moves it next to the
code, for three things:

1. You understand more, because the agent can show you the code as it
   explains, walk you through it in order, and draw what has a shape.
2. You can argue one point at a time. Every step, note and contract has a
   conversation of its own.
3. Reviewing and exploring get a structure: the joints of the change
   first, then the change walked, then everything else, each with a state
   you can see.

## The review

A review is one JSON file in `.threads/`. It is about a diff (a base and a
head, or your uncommitted, staged or unstaged changes) or about the code
as it stands. It holds five things, and the screen shows them in this
order:

| | what it is | who writes it |
| --- | --- | --- |
| introduction | the big picture, read first | the agent |
| contracts | what other code relies on that the change touched | the agent |
| tours | the change walked, a part at a time | the agent |
| notes | everything that is not walked: issues, decisions, questions… | both of you |
| files | every file a chunk is in, beside the rest | worked out |

Under them is the review's pool of chunks. Every place in the code it
points at is written there once, and the rest refer to it by id.

A review is open or closed. Closing it takes it off Home and out of the
code. A message of yours opens it again.

## Chunks

A chunk is lines of a file, written once in `chunks` and named by a slug
id, `parse-groups`. A step, a note, a contract and an excerpt in prose all
point at a chunk by that id, so the same lines are never copied twice,
and "what touches this" is a match on ids before it is a guess from
overlapping lines.

A chunk is found by quoting its first line (`from`) and its last (`to`;
none for one line). `line` breaks ties when a quote appears more than
once. Quoting both ends means lines added or removed inside the chunk do
not cut it short or pull in the next line, `--check` can tell the agent
when its range is wrong, and if one end is edited the other still finds
it.

`rev` says which version of the file the chunk is read from:

- `base` or `head`: the ends of the review's diff, so the agent never
  copies a hash. A removed line is `base`.
- `now`: the file as it is in your editor, unsaved edits included.
- a commit: any other version, such as "before the refactor".

## Prose

Prose is markdown plus diagrams. A tour's introduction, a step's text, a
contract's page and every message are prose. Bold, headings and lists are
drawn; other markdown shows as written. On top of markdown:

| written | becomes |
| --- | --- |
| `#step:7`, `#note:12` | a link to that step or note; `other-review#note:12` is in another review |
| `#contract:3` | the contract's name, linking to its page |
| `` `name` `` | code, and a link to where the name is defined when it is found; `` `name` (file.lua:37) `` pins it |
| `{{chunk:id}}` alone on a line | an excerpt: the chunk's lines, read from the file each time it is drawn |
| `{{diagram:name}}` alone on a line | the diagram `diagrams[name]`, drawn there |
| any other ``` fence | code, drawn as written |

Diagrams (a flow, a sequence or a call tree) sit beside the text by name
and are placed in it with `{{diagram:name}}`. The agent writes them
before the text, so the prose can describe what the diagram shows rather
than the diagram being drawn to fit the prose. Keeping them out of the
string also keeps them out of JSON escaping: a bad quote inside a diagram
breaks only the diagram, not the whole file.

An excerpt is a quotation, not something the review is about. It draws
the code and goes to it on `⏎`, but it adds no file to the files list and
cannot be accepted.

## Contracts

A contract is something other code relies on that the change touched: a
function's signature, a JSON field, a table, an endpoint, a key, a
behaviour callers count on. What happens inside a function is not one.
Each is a row in the review's list and a page of its own.

- **The contract itself, before and after.** `source` has an `after` when
  it was added, a `before` when removed, both when changed, and the
  `change` that says which. Each side is a chunk where the code holds the
  contract in one place (only the signature lines, not the body), read at
  `base` and `head`; or written out whole, as code, where no one place
  does: a table built by several migrations, a JSON format the code only
  reads. Written out means the whole thing. The screen finds what
  changed.
- **The page shows the two sides as a diff.** A signature that changed by
  one word shows as one `-` line and one `+` line with that word lit; one
  that mostly changed shows as two blocks.
- **The blast radius.** `dependents` lists the code that depends on the
  contract, each chunk on the line that uses it, with how far the change
  reached it: `none`, `adapted` (a small edit to follow it), `reworked`
  (it had to change how it works) or `missed` (it needs a change the diff
  did not make, which is also an issue note). Every impact but `none`
  says in `text` what it had to do and what it cost.
- **Prose** says why it changed and what it costs, with a diagram where
  the contract has a shape. `why` is the one sentence on what changed in
  it that the review's list shows.
- **A conversation**, as everything has.

The agent finds dependents by grepping for the contract's name before it
writes them, so the list is complete.

## Tours and steps

A tour is a part of the change, named for what it is about, never for a
kind of step ("Tests", "Callers"). It has a colour the agent picks, so a
tour keeps its colour when the agent adds or reorders tours, and the
files it touches are marked in it.

**Walking a tour starts on its briefing**, its introduction: a float with
what its steps show and how they fit, often a diagram, and its steps
listed. `L` goes into step 1 in the code and `H` from step 1 comes back
to it. `J` and `K` move to the next and previous tour, landing on its
briefing, and `B` brings the current one back mid-walk. This is tour.nvim's stage briefing, which made
sure you read the point before the evidence.

A step is a claim about the code at its chunk, never a topic. It has a
title, its prose and a conversation. A step on no chunk is a page, for
one idea in many places. Steps carry no labels: an issue about a step's
code is a note on the same chunk, and the step shows that note's badge
and title as you walk it.

## Notes

A note is anything that is not walked, on a chunk or on no line. Its
first message says what it is and the rest are its conversation. Each
kind asks something different of you and has its own statuses:

| kind | asks you to | status |
| --- | --- | --- |
| `issue` (a bug, flaw or risk, with a severity) | fix it or dismiss it | open, fixed, won't fix, not a problem |
| `decision` | agree or push back | open, agreed, reversed |
| `suggestion` | take it or not | open, taken, declined |
| `question` | answer it | open, answered |
| `fix` | check what the agent changed | open, checked |
| `comment` | read it | none |

Either of you can write any kind. A comment of yours waits on the agent
because its last message is yours; one of the agent's waits on nobody.

Notes sit at the bottom of the review, so they are also met where they
apply: a note on a step's chunk shows on the step as you walk. At the
bottom they are an index, one row each (kind, severity, title), grouped
by kind with the open ones first, and the notes' heading counts what is
open: `notes · 9 · open: 3 issues · 1 question`. A kind's settled notes
fold into one row until it is opened.

## Conversations and state

A message is yours or the agent's, with its prose. The agent's can list
the chunks it changed in answer. Yours has the time you wrote it, which
the plugin sets.

State is worked out or kept by the plugin, never written by the agent:

- **Whose move** comes from the last message of each conversation. The
  agent's skill asks the same function what waits on it.
- **What you have read, walked and accepted, and when each of the
  agent's messages first appeared**, live in `<review>.seen` beside the
  review. Only the plugin writes it. The agent rewrites the review file
  whenever it answers, and it would drop or mangle state it does not own;
  two programs writing one file lose each other's changes.
- **Ids.** Steps, notes and contracts each count their own ids from 1,
  never changed and never reused. The agent writes them (`show.lua`
  prints the next of each); a note you write takes the next note id.
  Prose links them as `#step:7`, and `.seen` keys them the same way:
  `step:7`, `note:12:2` for note 12's second message. A message is known
  by its place in its conversation, since conversations only grow at the
  end.
- **Accepted** follows a chunk's content. A change to the lines brings it
  back to accept.

Two rules from the start still hold. Positive is a key and negative is a
message: there is no reject, because the agent needs the why. And the
file is the interface: the plugin never runs the agent.

## On screen

- **The review screen** is a main column and the files beside it. The
  column is the introduction, the contracts (a row each, cut to the first
  few), the tours (a row each, `Tab` opens one in place with its steps'
  code) and the notes list. The files stay in view as you scroll, and
  light up for what the cursor is on, a contract's or a tour's.
- **A contract's page** opens with `⏎`; `L` and `H` go between contracts.
- **A walk** opens the tour's briefing, then shows each step's card above
  its chunk in the code, the winbar saying where you are.
- **The code** shows every open review's steps and notes in the buffers
  you have open: a sign on their lines, and above the one the cursor is
  on its bubble or card; `]h` to the next thing that wants you.
- **Home** lists the reviews.

Every surface shares the same keys for moving: `j`/`k` items, `J`/`K`
levels, `H`/`L` sideways, `Tab` folds, `o` reads. KEYS.md has them all.

## The agent

One skill, `answering-threads`, writes reviews and answers what waits.
Its `show.lua` lists what waits on the agent in every open review and
prints the next ids. `show.lua --check` reads a review the way the editor
does and reports what is wrong: a chunk not found, a range whose `to` is
missing, an id pointed at that does not exist, a link that goes nowhere.

## How the code is laid out

In layers, each requiring only those below it. CODING_STANDARDS.md has
the rules and a test enforces them.

```
init            commands, keys, config
surfaces        screen/  code/  walk  map  compose, opening each other through go
actions         the verbs: reply, start a note, settle, accept
draw/           one drawer per thing on screen, into a sheet
prose/          markdown, links, excerpts, diagrams in text
model/          the review's parts and their state; checking what the agent wrote
store/          files on disk; .seen
base/  ui/      finding code, git, diffs; windows, sheets, layout
```
