---
name: answering-threads
description: Use when the user asks you to answer their threads or questions in thread.nvim (`.threads/` in the repo), to review a change, or to explain code or a change as a tour they can step through in their editor.
---

# Answering threads

The user reads their code in Neovim with thread.nvim. Everything there is
in **reviews**, one JSON file each at `.threads/<id>.json` in the
repository root, in format 2. What you write shows in their editor as soon
as you save the file. Beside each, `<id>.seen` is the plugin's: never touch it.

```
review          about a diff, or about the code as it stands
└─ thread       one topic, on a chunk or on no line
   ├─ message   one turn of its conversation
   │  └─ tour   an introduction, then steps
   │     └─ step   on a chunk, or on no line
   └─ check     what you ran to confirm it works
chunk           lines of a file, found by quoting the first
```

A message of yours can carry **tours**: steps in order, each on a place in
the code or on no line. That is how you explain something across many
places. The user walks a tour with `L`/`H`, and can reply in any step.

## Start by listing what waits

```sh
nvim -l <skill-dir>/show.lua            # every open review
nvim -l <skill-dir>/show.lua <review>   # one, if the user names it
```

It prints every conversation **waiting** for you: one where the user's
message is the last. A conversation is a thread's own (`#12`) or a step's
(`#12.3`, step 3 of the thread's one tour; `#12.2.3`, step 3 of its second
tour, counting the tours of all its messages in order). With each: the code
it is on (a hunk drawn as a diff, the line marked `>`), the step and what it
says, and what was said so far. Leave everything else alone: the rest is
the user's move, or closed.

## Answer each one, at the size it needs

Read the whole conversation; the last message is what is asked now. Then
pick one of three sizes:

1. **Prose.** Most answers. A few sentences, the answer first.
2. **Prose and changes.** The user asked for a change: make it, say what
   you did in a sentence, list where in `changes`.
3. **A tour.** The explanation needs more than one place, or more than
   about 15 lines. Your message is the overview, and its `tours` hold the
   tour (below).

A reply **in a step** is about that step; the tour is context. A step's
messages carry no tours: answer in prose, with notes, an excerpt or a
diagram. If it truly needs a tour, add a message with the tour to the
thread's own `messages`, and say so in your reply in the step.

## Write the reply into the file

Append one message to the conversation's `messages`, editing the JSON as
text. A thread's are `threads[i].messages`; a step's are in its tour, in
the message that carries the tour: `messages[j].tours[k].steps[n].messages`.

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
- **Name the thread** on your first reply: set the thread's `title` (beside
  its `id`) to a few words saying what it is about: "Save should notify",
  "Why ORDER exists". Leave an existing title alone.
- **If your change rewrote the line a chunk quotes** (the thread's, or a
  step's), quote it as it reads now. A chunk with `"side": "old"` quotes a
  removed line: leave it.
- Change nothing else: not `status`, `rounds`, a message's `round` or `at`,
  the user's messages, ids. Never delete a thread, a tour or a step: the
  user's replies are inside them.

## Chunks, notes, excerpts, diagrams, links

A **chunk** is lines of a file: `file`, `line`, and `text`, its first line
quoted verbatim, which is how it is found as the code moves (`line` breaks
ties). `lines` for more than one; `rev` to read the file at a commit;
`"side": "old"` for a line the review's diff removed, with `line` its
number in the old side.

**Notes** sit on a message or a step, each a chunk on one line with what
it says in `note` and a word to pick out in `mark`. A note with no `note`
just highlights its line. Two to five:

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
Never draw ASCII yourself. Kinds: `flow` (`nodes` with `id` and `label`;
`edges` with `from`, `to`, optional `label` and `dashed`; `direction`
`down` or `right`), `sequence` (`participants` with `id` and `label`,
`messages` in order with `from`, `to`, `label`, optional `reply`), `calls`
(a `root` with nested `children`). A node that is real code gets `file`,
`text` verbatim and `line` (and `"side": "old"` for a removed line); that
is the only link a node has.

**Links** in any text: `#12` a thread, `#12.3` or `#12.2.3` a step,
`other-review#12` a thread in another review. The user opens them with
Enter.

Write for someone who was not in the conversation: define a term the
first time it appears, and give an abstract point a worked case (what goes
in, the lines it runs, what comes out).

## Labels and checks

**Labels** go on a thread or a step:

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

**Checks** go on a thread or a step: what you ran to confirm something
works, so the user can run it too. Add one whenever a claim rests on
running something:

```json
"checks": [{ "text": "Walked two steps, ended, walked again: it starts on step 2.", "run": "make test SPEC=walk" }]
```

`text` says what you ran and what you got; `run` is the line as typed in a
shell. A key opens it in a terminal, ready to run.

## Tours

A tour is `title`, an optional `introduction`, and `steps`. A step has:

- `title`: a **claim** about the code there ("verify trusts the token, not
  the session"), never a topic;
- `text`: why, in a sentence or three. It is read **on its own**, so it
  never says "the same", "see above" or just names the thing;
- `chunk`, the code it is on; with none, the step is a page, for one idea
  in many places;
- optionally `notes` (the evidence, on the lines that prove it), a
  `diagram`, labels and `checks`;
- `messages`: `[]`. The user's replies go there.

Order steps as an argument, not a file listing: each comes where the one
before made it the next question. You pick which tours a thread has, how
many and what each is called. Some that work: "What changed", "Every
caller", "Tests", "The path to the failure", "How a request flows".

## Writing a review

Asked to review a change, or for a tour of something ("how does auth
work?"), write a new review: a new file `.threads/<id>.json`, its id the
title in lowercase words joined by `-`, one no file has yet.

```json
{
  "format": 2,
  "title": "Tours pick up where you left off",
  "diff": { "base": "main" },
  "introduction": "Two things changed: tours resume, and the cache moved. The resume first: users will notice it.",
  "threads": [
    {
      "id": 1,
      "title": "Walking a tour again resumes it",
      "kind": "feat",
      "risk": "medium",
      "risk_why": "the .seen file gains a field older versions drop",
      "messages": [
        {
          "from": "agent",
          "text": "Why these hunks changed, once for all of them. Excerpts welcome.",
          "tours": [
            {
              "title": "What changed",
              "steps": [
                {
                  "title": "A tour you walked starts after the furthest step you saw",
                  "text": "So a tour you finished starts again from the first.",
                  "chunk": { "file": "lua/walk.lua", "line": 321, "text": "    if furthest > 0 and first then" },
                  "messages": []
                }
              ]
            },
            {
              "title": "Every caller",
              "steps": [
                {
                  "title": "The map still ticks every step you saw",
                  "text": "It reads the same walked marks and ignores `furthest`: right, but worth a look if it should show where you will resume.",
                  "chunk": { "file": "lua/map.lua", "line": 90, "text": "local function collect_walk(r)" },
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

- **`diff`**: what is reviewed. `{ "of": "uncommitted" }` (everything since
  the last commit), `"staged"` or `"unstaged"`; `{ "base": "main" }` (to
  the working tree); `{ "base": "a1b2c3", "head": "d4e5f6" }`. No `diff`:
  the review is about the code as it stands, as a tour of auth is. New
  files git does not track count, when the new side is the working tree.
- **Between a base and a head**, the code is read at the head: give every
  chunk on the diff `"rev"`, the head as `diff` writes it. Prefer a diff
  that ends at the working tree, where chunks need no `rev`.
- **`introduction`**: the overview, two to four sentences: the shape of
  the change and the order you tell it in.
- **A thread is one intent**, not one file: a feature, a fix, a rename
  done in nine places. Ids from 1; riskiest first. Its first message is its
  introduction: why its code changed, said once for all of it. Its tours
  walk the code: its hunks, the code that depends on them, its tests.
- **A step on a hunk** quotes **any line inside the hunk**, and shows the
  whole hunk as a diff. A hunk that only removes lines: quote a removed
  line with `"side": "old"`. A hunk can be in more than one thread when it
  serves both. The step's `text` says what this hunk does that the
  thread's introduction does not.
- **A step on code the change did not touch** (a caller, a reader of a
  changed format) says how it depends on the change, and what that means
  for it: still right and why, now wrong, or what to check.
- **A step on a test** says what it checks, which part of the change that
  covers, and what it leaves untested when that matters. A thread with no
  tests that needs some says so.
- A review holds what you pick: a hunk in no step is not in it, and the
  user never sees it. Leave out only what needs no look (a typo, an import
  for a change shown elsewhere). `--check` lists what you left out.

For a tour of something, not a change: a review with no `diff`, a thread
per question, each with one message whose tour answers it.

## Finish

```sh
nvim -l <skill-dir>/show.lua --check <review>
```

It reads the file as the editor does: every field, then every chunk, note,
last change and diagram node of an open thread against the code. An
`error:` means the editor will not show the review: fix every one, and
what it warns about. A `note:` lists hunks of the diff in no thread or
step. Then tell the user, one line per conversation, what you did; for a
new review, its id, and that Home lists it.
