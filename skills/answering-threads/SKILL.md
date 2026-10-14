---
name: answering-threads
description: Use when the user asks you to answer their threads, notes or questions in thread.nvim (`.threads/` in the repo), to review a change, or to explain code or a change as a tour they can step through in their editor.
---

# Answering threads

The user reads their code in Neovim with thread.nvim. Everything there is
in **reviews**, one JSON file each at `.threads/<id>.json` in the
repository root, in format 3. What you write shows in their editor as soon
as you save the file. Beside each, `<id>.seen` is the plugin's: never touch it.

```
review          about a diff, or about the code as it stands
├─ contract     what other code relies on that the change touched
├─ tour         a part of the change, walked: an introduction, then steps
│  └─ step      on a chunk, or on no line; the user replies in it
└─ note         anything else: a finding, a question, a decision, a diagram,
   │            and the user's own comments
   └─ message   its first is what it says; the rest its conversation
chunk           lines of a file, found by quoting the first
```

The screen reads a review top to bottom: its introduction, its contracts,
its tours (a row each, opened in place), its notes, each drawn whole, and
its files down the right. The user walks a tour with `L`/`H`, and replies
in any step or note.

Older reviews are in format 2, with `threads` (and `groups`) where format 3
has tours and notes: answer in them as they are, and write every new
review in format 3.

## Start by listing what waits

```sh
nvim -l <skill-dir>/show.lua            # every open review
nvim -l <skill-dir>/show.lua <review>   # one, if the user names it
```

It prints every conversation **waiting** for you: one where the user's
message is the last. In format 3 a conversation is a step's or a note's,
each known by its id: `#7`. With each: the code it is on (a hunk drawn as
a diff, the line marked `>`), the step and what it says, what was said
so far, and where to write your reply. Leave everything else alone: the
rest is the user's move, or closed. A `cannot read <id>` line is a review
the editor cannot show either: if you wrote it, `--check <id>` says what
to fix; if not, leave it alone.

## Answer each one, at the size it needs

Read the whole conversation; the last message is what is asked now. Then
pick one of three sizes:

1. **Prose.** Most answers. A few sentences, the answer first.
2. **Prose and changes.** The user asked for a change: make it, say what
   you did in a sentence, list where in `changes`.
3. **Prose and a tour.** The explanation needs more than one place, or
   more than about 15 lines. Add a tour to the review's `tours` (below),
   its steps' ids the next free ones, and link its first step from your
   reply: "Walk #23 for how it is read."

A reply **in a step** is about that step; the tour is context. A note's
or a step's messages carry no tours: answer in prose, with marks, an
excerpt or a diagram.

## Write the reply into the file

Append one message to the conversation's `messages`, editing the JSON as
text: a step's are `tours[k].steps[n].messages`, a note's
`notes[i].messages`. `show.lua` prints which, as `reply in:`.

```json
{
  "from": "agent",
  "text": "Renamed to `pending`: it holds sent messages with no reply yet.",
  "changes": [{ "file": "lua/store.lua", "line": 212, "text": "function M.pending(r)" }]
}
```

- **`text`**: markdown. Short paragraphs, `code` in backticks, `**bold**`
  for a point. Bubbles often show only the first line, so put the answer
  first.
- **`changes`**: every place you changed for this conversation, each a
  chunk quoting its first line as it reads now.
- **Name a note** on your first reply when the user started it: set its
  `title` (beside its `id`) to a few words saying what it is about: "Save
  should notify", "Why ORDER exists". Leave an existing title alone.
- **If your change rewrote the line a chunk quotes** (a note's, or a
  step's), quote it as it reads now. A chunk with `"side": "old"` quotes a
  removed line: leave it.
- You may add `checks` to the step or note you answer in, and change its
  labels when your answer changes the judgement (say so in the text).
- Change nothing else: not `status`, `rounds`, a message's `round` or `at`,
  the user's messages, ids. Never delete a tour, a step or a note: the
  user's replies are inside them.

## Chunks, marks, excerpts, diagrams, links

A **chunk** is lines of a file: `file`, `line`, and `text`, its first line
quoted verbatim, which is how it is found as the code moves (`line` breaks
ties). `lines` for more than one; `rev` to read the file at a commit;
`"side": "old"` for a line the review's diff removed, with `line` its
number in the old side.

**Marks**, a message's or a step's `notes` field, each a chunk on one line
with what it says in `note` and a word to pick out in `mark`. A mark with
no `note` just highlights its line. Two to five on a step that has any:

```json
"notes": [
  { "file": "src/verify.ts", "line": 32, "text": "  const claims = jwt.verify(req.token, KEY)", "mark": "KEY", "note": "the only check" },
  { "file": "src/verify.ts", "line": 35, "text": "  return claims", "note": "never looks at the session table" }
]
```

**Excerpts** pull code into any text: a ` ```code ` fence holding one
chunk, `lines` how many (default 6, at most 15):

````md
```code
{ "file": "src/verify.ts", "text": "export function verify(req) {", "line": 30, "lines": 6 }
```
````

**Diagrams**, when the point is a shape: `diagram` on a message or a step.
Never draw ASCII yourself. Its `kind` is one of: `flow` (`nodes` with `id` and `label`;
`edges` with `from`, `to`, optional `label` and `dashed`; `direction`
`down` or `right`), `sequence` (`participants` with `id` and `label`,
`messages` in order with `from`, `to`, `label`, optional `reply`), `calls`
(a `root` with nested `children`). A node that is real code gets `file`,
`text` verbatim and `line` (and `"side": "old"` for a removed line); that
is the only link a node has.

**Links** in any text: `#7` the step or note whose `id` is 7,
`other-review#7` in another review. The user opens them with Enter. A
`#7` in backticks is code, not a link. (In a format 2 review, `#12` is a
thread and `#12.3` its step with `id` 3.) `[[id]]` names one of the
review's contracts, drawn as its name.

Write for someone who was not in the conversation: define a term the
first time it appears, and give an abstract point a worked case (what goes
in, the lines it runs, what comes out).

## Labels and checks

**Labels** go on a step or a note:

- `verdict` when it judges: `bug`, `flaw`, `risk`, `trade-off`,
  `decision`, `how it works`, `fine`; with `severity` (`low`, `medium`,
  `high`) when it matters.
- `risk`: `low`, `medium` or `high`, and `risk_why` unless it is low. Risk
  is how bad it is if this is wrong and how hard to undo: a file format, a
  public interface, data written to disk, a behaviour users rely on, or
  something people may disagree with are higher; a local refactor with
  tests is low.
- `kind`, as a commit prefix: `feat`, `fix`, `refactor`, `perf`, `test`,
  `docs`, `chore`, `style`.

**Checks** go on a step or a note: what you ran to confirm something
works, so the user can run it too. Add one whenever a claim rests on
running something:

```json
"checks": [{ "text": "Walked two steps, ended, walked again: it starts on step 2.", "run": "make test SPEC=walk" }]
```

`text` says what you ran and what you got; `run` is the line as typed in a
shell at the repository root. A key opens it in a terminal there, ready to
run.

## Tours

The review's tours walk the change, each a part of it named for what it is
about ("Placing threads in each buffer", "Painting cards", "Requoting
threads that moved"), in the order to read them, riskiest first. A tour is:

- `title`: what its steps are about together, never a kind of step:
  not "What changed", "Every caller" or "Tests". A test goes in the tour
  of the code it tests, a caller with the change it depends on;
- `introduction`: one sentence on what its steps show, read under its
  title before its steps;
- `colour`: `orange`, `yellow`, `lime`, `teal`, `sky`, `blue`, `violet` or
  `pink`, a different one from the review's other tours. It marks the
  tour's files beside it, so the reader sees what goes with what;
- `steps`, in the order to walk them.

A step has:

- `id`: a number no other step or note of the review has: steps and notes
  share one run of ids, from 1 (`show.lua` prints the next). Links name
  steps by it, so it never changes, and a new step can go anywhere in
  its tour;
- `title`: a **claim** about the code there ("verify trusts the token, not
  the session"), never a topic;
- `text`: why, in a sentence or three. It is read **on its own**, so it
  never says "the same", "see above" or just names the thing;
- `chunk`, the code it is on; with none, the step is a page, for one idea
  in many places;
- optionally `notes` (marks: the evidence, on the lines that prove it), a
  `diagram`, labels and `checks`;
- `messages`: `[]`. The user's replies go there.

Order steps as an argument, not a file listing: each comes where the one
before made it the next question. A change has a few tours of several
steps each: three to eight tours of three to ten steps reads well. Many
tours of one step are notes, or one tour.

## Notes

Notes are where everything that does not walk goes, at the bottom of the
review, each drawn whole: a finding, a question for the user, a decision
and what it traded away, a diagram of the whole change, a worked example,
what you ran. This is the place to be inventive: any primitive goes in a
note. A note has:

- `id`: from the same run as the steps';
- `title`: what it says, in a few words; a finding's title is the claim
  ("show.lua cuts a long hunk from its top");
- `chunk`, when it is about one place; else none;
- labels: a finding has `verdict` and `severity`;
- `messages`: its first, from you, is what it says: `text` with excerpts,
  links to steps (`#4`) and `[[contracts]]`, and `notes` (marks), a
  `diagram`, `changes` as any message has. The user's replies follow;
- `checks`, when it rests on running something.

A step says what the code there does; a note says what you think of it.
When a step finds a problem, the step keeps its claim and a note on the
same chunk says the problem, with its verdict, and links the step. The
user can close a note (fixed, won't fix, not a problem); a tour stays.

## Writing a review

Asked to review a change, or for a tour of something ("how does auth
work?"), write a new review: a new file `.threads/<id>.json`. Its id is
its title in lowercase, each run of anything but letters and digits made
one `-`, cut to 40 characters, with no `-` at either end, and `-2`, `-3`
added when a file has it already.

```json
{
  "format": 3,
  "title": "Tours pick up where you left off",
  "diff": { "base": "main" },
  "introduction": "Two things changed: tours resume, and the cache moved. A walk now keeps [[furthest]], and the map reads it beside the walked marks. The resume first: users will notice it.",
  "contracts": [
    {
      "id": "furthest",
      "name": "seen.furthest",
      "kind": "field in .seen",
      "change": "added",
      "after": "the furthest step walked, per tour",
      "why": "A walk starts again after it.",
      "at": { "file": "lua/store/seen.lua", "line": 40, "text": "  furthest = furthest," },
      "uses": [{ "file": "lua/walk.lua", "line": 321, "text": "    if furthest > 0 and first then" }]
    }
  ],
  "tours": [
    {
      "title": "Where a walk starts again",
      "colour": "sky",
      "introduction": "The walk keeps the furthest step you saw, and the map reads the same marks.",
      "steps": [
        {
          "id": 1,
          "title": "A tour you walked starts after the furthest step you saw",
          "text": "So a tour you finished starts again from the first.",
          "chunk": { "file": "lua/walk.lua", "line": 321, "text": "    if furthest > 0 and first then" },
          "kind": "feat",
          "checks": [{ "text": "Walked two steps, ended, walked again: on step 2.", "run": "make test SPEC=walk" }],
          "messages": []
        },
        {
          "id": 2,
          "title": "The map still ticks every step you saw",
          "text": "It reads the same walked marks and ignores `furthest`.",
          "chunk": { "file": "lua/map.lua", "line": 90, "text": "local function collect_walk(r)" },
          "messages": []
        }
      ]
    }
  ],
  "notes": [
    {
      "id": 3,
      "title": "The map does not show where a walk resumes",
      "chunk": { "file": "lua/map.lua", "line": 90, "text": "local function collect_walk(r)" },
      "verdict": "flaw",
      "severity": "low",
      "messages": [
        {
          "from": "agent",
          "text": "The map ticks what you saw (#2) but not where `L` will take you: worth a mark on [[furthest]]'s step."
        }
      ]
    }
  ]
}
```

- **`diff`**: what is reviewed. `{ "of": "uncommitted" }` (everything since
  the last commit), `"staged"` or `"unstaged"`; `{ "base": "main" }` (to
  the working tree); `{ "base": "a1b2c3", "head": "d4e5f6" }`. No `diff`:
  the review is about the code as it stands, as a tour of auth is. New
  files git does not track count, when the new side is the working tree.
- **Between a base and a head**, the code is read at the head: give every
  chunk on the diff `"rev"`, the head as `diff` writes it. Prefer a diff
  that ends at the working tree, where chunks need no `rev`.
- **`introduction`**: the overview, two to five sentences: the shape of
  the change and the order the tours tell it in. Name the contracts it
  rests on with `[[id]]`, so the overview ties to the list under it.
- **`contracts`**: what other code relies on that the change touched,
  each once: a function's signature, a JSON field, a table, an endpoint,
  a key, a behaviour callers count on. Not what happens inside a
  function. `id` (letters, digits, `-`), `name` as it reads in the code,
  `kind` in your own words, `change` (`added`, `changed`, `removed`,
  `relied on`), `before` and `after` (a signature, a shape, a sentence;
  added has no `before`, removed no `after`), `why` in a sentence, the
  chunk it is defined `at`, and the chunks that `uses` it. The screen
  works out which tours, notes and files touch each from these chunks,
  so point them at lines your steps are on. Most changes have three to
  ten; list the ones a reader needs to see how the parts fit.
- **`tours`** walk the change: its hunks, the code that depends on them
  and its tests, by what they are about (above).
- **`notes`**: what you found and what you think: every problem, each its
  own note with its verdict; what you would ask the author; a decision
  and its alternative; a diagram or worked example of the whole. A review
  with nothing to say past its tours has none.
- **A hunk** is a run of changed lines: git's changes with no context,
  joined when six or fewer lines apart, so a file rewritten end to end is
  one hunk. `--check` lists every hunk no step or note is on: run it once
  the file has its `diff`, to see them all.
- **A step on a hunk** quotes **any line inside the hunk**, and shows the
  hunk as a diff. A hunk that only removes lines: quote a removed line
  with `"side": "old"`. A hunk can be in more than one tour when it serves
  both. The step's `text` says what this hunk does that the tour's
  introduction does not.
- **A step on code the change did not touch** (a caller, a reader of a
  changed format) says how it depends on the change, and what that means
  for it: still right and why, now wrong, or what to check.
- **A step on a test** says what it checks, which part of the change that
  covers, and what it leaves untested when that matters. A tour with no
  tests that needs some gets a note saying so.
- A review holds what you pick: a hunk in no step is not in it, and the
  user never sees it. Leave out only what needs no look: a typo, an
  import or a comment for a change shown elsewhere, docs that say again
  what a step's code shows. `--check` lists what you left out.

For a tour of something, not a change: a review with no `diff`, a tour per
question, and notes for what does not walk.

## Finish

```sh
nvim -l <skill-dir>/show.lua --check <review>
```

It reads the file as the editor does: every field, then every chunk, mark,
last change, diagram node and excerpt of every step and open note against
the code, and every link in what you wrote. An `error:` is something the
editor cannot show: the review, or the chunk it names.
Fix every one, and what it warns about. A `note:` lists hunks of the diff
in no step or note. Then tell the user, one line per conversation, what
you did; for a new review, its id, and that Home lists it.
