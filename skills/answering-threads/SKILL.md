---
name: answering-threads
description: Use when the user asks you to answer their threads, notes or questions in thread.nvim (`.threads/` in the repo), to review a change, or to explain code or a change as a tour they can step through in their editor.
---

# Answering threads

The user reads their code in Neovim with thread.nvim. Everything there is
in **reviews**, one JSON file each at `.threads/<id>.json` in the
repository root (make `.threads/` when there is none). What you write
shows in their editor as soon as you save the file. Beside each,
`<id>.seen` is the plugin's: never touch it.

```
review          about a diff, or about the code as it stands
├─ introduction the big picture, read first
├─ contract     what other code relies on that the change touched: a page
│               each, the contract before and after, the code that
│               depends on it; the user replies on it
├─ tour         a part of the change, walked: a briefing, then steps
│  └─ step      a claim, on a chunk or on no line; the user replies in it
├─ note         anything else, by kind: an issue, a decision, a
│  │            suggestion, a question, a fix, a comment; yours or the user's
│  └─ message   its first says what it is; the rest its conversation
└─ chunks       every place in the code the rest points at, each once, by id
```

The screen reads a review top to bottom: its introduction, its contracts
(a row each), its tours (a row each, opened in place), its notes (a row
each, grouped by kind), and its files down the right. The user walks a
tour with `L`/`H`, starting on its briefing, opens a contract's page with
`⏎`, and replies in any step, note or contract.

There is no format number. A review written before this format does not
read: `--check` says, field by field, what each old field became. Do not
convert one unless the user asks; write a new review instead.

## Start by listing what waits

```sh
nvim -l <skill-dir>/show.lua            # every open review
nvim -l <skill-dir>/show.lua <review>   # one, if the user names it
```

Run it from the repository root; `<review>` is a review's id, its file's
name without `.json`.

It prints every conversation **waiting** for you: one where the user's
message is the last. A conversation is a step's, a note's or a
contract's, each known by its link, its kind and its id: `#step:7`,
`#note:12`, `#contract:3`. With each: what it is on (the step and what
it says, the note's kind and status, the contract's sides), the code (a
hunk drawn as a diff, the chunk's lines marked `>`), what was said since
you last spoke (a note's first message too), and where to write your
reply, as `reply in:`. For each review it also prints the **next id** of
each kind and the **chunk ids in use**, by file.

Leave everything else alone: the rest is the user's move, or settled. A
`cannot read <id>` line is a review the editor cannot show either: if you
wrote it, `--check <id>` says what to fix; if not, leave it alone.

## Answer each one, at the size it needs

Read the whole conversation in the file; the last message is what is
asked now. Then pick one of three sizes:

1. **Prose.** Most answers. A few sentences, the answer first.
2. **Prose and changes.** The user asked for a change: make it, say what
   you did in a sentence, list the chunks you changed in `changes`.
3. **Prose and a tour.** The explanation needs more than one place, or
   more than about 15 lines. Add an unlisted tour to the review's
   `tours` (below), its id and its steps' ids the next free ones, and
   place it in your reply with `{{tour:4}}`: "How it is read:" and the
   tour on the next line.

A reply **in a step** is about that step; the tour is context. A reply on
a contract that shows its page was wrong (a dependent's `impact`, its
`prose`, a side) changes the page too, and says so.

## Write the reply into the file

Append one message to the conversation's `messages`, editing the JSON as
text, in place: a step's are `tours[k].steps[n].messages`, a note's
`notes[i].messages`, a contract's `contracts[i].messages` (add the list if
it has none). `show.lua` prints which, counting from 1: `tours[2]` is the
second tour (`.tours[1]` in jq, which counts from 0).

```json
{
  "from": "agent",
  "prose": { "text": "Renamed to `pending`: it holds sent messages with no reply yet." },
  "changes": ["store-pending"]
}
```

- **`prose`**: an object, `{ "text": "..." }`, never a bare string, with
  `diagrams` beside the text when it needs one. Markdown: short
  paragraphs, `code` in backticks, `**bold**` for a point. A row often
  shows only the first line, so put the answer first.
- **`changes`**: the chunks you changed for this conversation, by id.
  Add a chunk to the review's `chunks` for each place first, quoting it
  as it reads now (`"rev": "now"`, or `"head"` when the review's diff
  ends at the working tree), then list its id. Only your messages have
  `changes`. In a review between two commits, your change is in the
  working tree, past its diff, so its chunks are at `now`.
- **No `at`**: the plugin notes when your message first showed up. The
  user's messages have theirs.
- **If your change rewrote a line a chunk quotes**, quote it as it reads
  now: a chunk at `now`, or at `head` of a diff that ends at the working
  tree, reads your edits. A chunk at `base` or at a commit never moves:
  leave it.
- Change nothing else: not `status`, not the user's messages, not an id.
  Only the user settles a note. Never delete a tour, a step, a note or a
  chunk something points at: the user's replies are inside them.

## Chunks

A **chunk** is lines of a file, written once in the review's `chunks`
and pointed at by its `id` from everywhere else: a step's `chunk`, a
note's, a contract's sides and dependents, a diagram node's, a message's
`changes`, and `{{chunk:id}}` in prose. **Write the chunks first**, then
everything that points at them. Two things on the same lines share one
chunk. Chunks whose lines overlap touch too: a note on one line inside a
step's chunk shows in that step as it is walked.

```json
{ "id": "parse-groups", "file": "lua/review.lua", "line": 143, "from": "local function parse_groups(p, raw)", "to": "end", "rev": "head" }
```

- `id`: a slug, letters, digits, `-`, `_` and `.`, saying what the lines
  are: `parse-groups`, `keys-hl`. Each chunk has its own; `show.lua`
  lists those in use.
- `from`: its first line, verbatim, indentation and all; `to`: its last,
  verbatim, the first line after `from` that reads so. No `to`: one line.
  Quoting both ends keeps the range right as lines are added inside it.
- `line`: where `from` is, from 1. Every chunk has one, though it only
  breaks ties when `from` appears more than once.
- `rev`: which version it is read from. `head` and `base` are the ends of
  the review's diff, so a chunk on a change is `head`, and a line the
  diff removed is `base`. `now` is the file as it is in the editor; any
  other value is a commit, short or full. Code the change did not touch
  is `head` too, in a review with a diff. A review with no `diff` has no
  `base` or `head`: its chunks are `now` or a commit.
- How much: the lines what points at it is about, not the hunk around
  them. A step on a long hunk shows the hunk's rows around its chunk, so
  a chunk of a few to twenty lines is enough; a contract's dependent is
  the one line that uses it.

## Prose, excerpts, diagrams, links

Wherever prose goes (the review's introduction, a tour's briefing, a
step's `text`, a contract's `prose`, every message) the JSON holds an
object, `{ "text": "...", "diagrams": { ... } }`.

**The text explains.** What a step or a message has to say about its
code goes in its `text`, naming the code in backticks: "`verify` checks
the token against `KEY` and never looks at the session table." Nothing is
drawn on the lines themselves, so say it where it is read. Bold,
headings, lists, tables and ``` fences are drawn; other markdown shows
as written. A command's output goes in a fence.

**Excerpts** show code inside prose: `{{chunk:id}}` alone on a line, the
chunk's lines read from the file each time it is drawn, fifteen at most:
past that, a row says how many more, so keep an excerpt's chunk short.
An excerpt quotes code: it adds no file to the review and is not
something the review is about.

**Diagrams**, when the point is a shape. Never draw ASCII yourself. A
diagram goes in the prose's `diagrams`, by a name (letters, digits, `-`,
`_`, `.`), and is placed in its text with `{{diagram:name}}` alone on a
line. Write the diagram first, then the text that says what it shows. Its
`kind` is one of:

- `flow`: `nodes`, each `{ "id", "label" }`, a label of one line or
  more; `edges`, each `{ "from", "to" }` by node id, with an optional
  `"label"` and `"dashed": true`; `"direction"`, `"down"` (the default)
  or `"right"`.
- `sequence`: `participants`, each `{ "id", "label" }`, a label of one
  line; `messages` in order, each `{ "from", "to", "label" }` by
  participant id, with `"reply": true` for an answer.
- `calls`: `"root"`, a node `{ "label", "children": [ ...nodes ] }`, at
  most 32 deep; a node's `id` is optional.

Any node, a participant too, that is real code gets `"chunk"`, the id of
one of the review's chunks; that is the only link a node has. Labels are
plain text: no markdown, no links.

```json
{
  "text": "`w` asks `.seen` how far you got, and the walk starts after it:\n\n{{diagram:resume}}",
  "diagrams": {
    "resume": {
      "kind": "flow",
      "direction": "right",
      "nodes": [
        { "id": "key", "label": "w", "chunk": "keys-w" },
        { "id": "start", "label": "walk.start", "chunk": "walk-start" },
        { "id": "resume", "label": "after the furthest step", "chunk": "resume" }
      ],
      "edges": [{ "from": "key", "to": "start" }, { "from": "start", "to": "resume", "label": "walked before" }]
    }
  }
}
```

**Tours in prose** explain by walking: when a point is a path through
the code (how a bug happens, where a value comes from, what a fix
touches), place a short tour where you make the point, not prose that
names five places. Write it in the review's `tours` with
`"listed": false` (Tours, below) and place it with `{{tour:2}}`, its
`id`, alone on a line. **Keep it short: three steps as a rule**; past
three it is warned of, and a walk that long is one to list. The prose
around it is its briefing, so it needs no `introduction` or `colour`.
The user turns it with Tab (the titles alone, then each step's text and
where it is, then its code inline), goes to it with `t`, and walks it
with `⏎`, a step's card in the code at a time, `q` back where they read
it. A listed tour can be placed too.

```json
"tours": [
  {
    "id": 4,
    "title": "How the unread count goes stale",
    "listed": false,
    "steps": [
      { "id": 21, "title": "seen.mark sets the count when you open a note", "chunk": "seen-mark", "messages": [] },
      { "id": 22, "title": "reply writes the message but never touches .seen", "text": { "text": "So the count still holds the old total." }, "chunk": "reply", "messages": [] },
      { "id": 23, "title": "Home reads the stale count", "chunk": "home-count", "messages": [] }
    ]
  }
]
```

and in the note: `"The count goes stale because nothing clears it on a reply:\n\n{{tour:4}}\n\nClearing it in `reply` fixes all three."`

**Contracts in prose**: `{{contract:3}}` alone on a line draws the
contract there: its name and why, then as it was and as it is; Tab turns
it to one row, and its page lists what placed it. Where prose leans on
a contract (a note about what a change costs callers, an answer about
how two parts meet), place it rather than only linking it, so the reader
sees the joint without leaving. A contract placed this way is one of the
review's `contracts`, written there once.

**Links** in any text name what they go to and its `id`: `#step:7` the
step whose `id` is 7, `#note:12` a note, `#contract:3` a contract, drawn
as the contract's name; `other-review#note:12` in another review. Steps,
notes and contracts each count their own ids, so `#step:3` and `#note:3`
are two things. The user opens them with Enter. A link in backticks is
code, not a link.

Write for someone who was not in the conversation: define a term the
first time it appears, and give an abstract point a worked case (what goes
in, the lines it runs, what comes out).

## Contracts

A **contract** is something other code relies on that the change
touched: a function's signature, a JSON field, a table, an endpoint, a
key, a behaviour callers count on. Not what happens inside a function.

Contracts are how a reader comes to know the codebase, not only the
change: a tour shows what this change did, a contract what the rest of
the code counts on, and that stays true after the change is merged. So
be generous with them. Anything the change touched that code outside
its own file relies on is a contract, however small the change to it:
a reader skips a contract they did not need in a second, and one left
out is a joint they never see. Each is a row in the review and a page
of its own:

- `id`: a number no other contract of the review has, from 1;
- `name` as it reads in the code (`review.grouped(r)`), or a behaviour in
  a few words (`Tab on a heading`); `kind` in your own words (`function`,
  `JSON field`, `table`, `key`);
- `why`: one sentence on what changed in it, shown on its row in the
  review's list;
- **`source`**: the contract itself, as it was and as it is. `change` is
  `added` (only `after`), `removed` (only `before`) or `changed` (both).
  Each side is either:
  - **a chunk's id**, where the code holds the contract in one place.
    The chunk covers **only the contract**: a function's signature, not
    its body; a struct's fields, not the code that fills them. `before`
    reads at `base`, `after` at `head`. The page draws the two as a diff.
  - **written out**, `{ "lang": "ts", "text": "..." }`, where no one
    place holds it: a table built by several migrations, a JSON format
    the code only reads, a behaviour. `lang` is what a markdown fence
    takes (`ts`, `lua`, `json`; `text` for a behaviour said in words).
    Written out means **the whole contract**, every field of what its
    `name` names, not the part that changed: so name it as narrowly as
    callers rely on it ("Ids in a review", not "the review format").

  A signature the change left as it was, over a body that now does
  something else, is a behaviour: write both sides out, saying what a
  caller could count on before and can now.
- **`prose`**: the page, as long as it needs: why it changed, what it was
  for before, what the change costs callers, what to watch, with a
  diagram where the contract has a shape. Say what a reader cannot see in
  the source.
- **`dependents`**, its blast radius: the code that depends on it. **Find
  them by grepping for the name** (`git grep -n 'grouped('`) before you
  write them, so the list is complete, tests too, and give each a chunk
  **on the line that uses the contract**, not the start of the function
  around it, shared with whatever else is on that line. A use the change
  rewrote is that line at `head`; one it removed with the contract, at
  `base`. Each has an `impact`:
  - `none`: still right as it was; `text` is optional;
  - `adapted`: a small edit to follow it;
  - `reworked`: it had to change how it works;
  - `missed`: it needs a change the diff did not make. That is also an
    issue: give it a note of kind `issue` on the same chunk, one for
    each such dependent; `--check` warns of one that has none.

  Every impact but `none` says in `text` what it had to do and what it
  cost. For an added contract, new code written to use it is `none`;
  old code changed to use it is `adapted` or `reworked`.
- `messages`: the user's replies go here; leave it out until there are
  some.

The screen works out which tours, notes and files touch each contract
from their chunks, so point steps at the same chunks where they meet.

## Tours

The review's listed tours walk the change, each a part of it named for
what it is about ("Placing threads in each buffer", "Requoting threads
that moved"), in the order to read them, riskiest first. An unlisted
tour, `"listed": false`, is a short walk that explains something, seen
only where prose places it (Tours in prose, above). A tour is:

- `id`: a number no other tour of the review has, from 1 (`show.lua`
  prints the next); `{{tour:2}}` places it in prose;
- `title`: what its steps are about together, never a kind of step: not
  "What changed", "Every caller" or "Tests". A test goes in the tour of
  the code it tests, a caller with the change it depends on;
- `listed`: leave it out for a tour of the review; `false` for one only
  prose places, which then needs no `introduction` or `colour`;
- **`introduction`: its briefing**, the first stop of its walk: what its
  steps show and how they fit, read before the evidence. When the steps
  have a shape (a call chain, a pipeline, a before and after), draw it:
  a diagram whose nodes are the steps' chunks;
- `colour`: `orange`, `yellow`, `lime`, `teal`, `sky`, `blue`, `violet`,
  `pink`, `rose`, `amber`, `green`, `mint`, `cyan`, `indigo`, `purple` or
  `magenta`, a different one from the review's other tours. The first
  eight are the furthest apart: use them first. It marks the tour's files
  beside it, so the reader sees what goes with what;
- `steps`, at least one, in the order to walk them.

A step has:

- `id`: a number no other step of the review has, in any tour, from 1
  (`show.lua` prints the next). Links name steps by it, so it never
  changes, is never used again, and a new step can go anywhere;
- `title`: a **claim** about the code there ("verify trusts the token,
  not the session"), never a topic;
- `text`: why, in a sentence or three, the code it means named in
  backticks, and an excerpt where other code needs showing. It is read
  **on its own**, so it never says "the same", "see above" or just names
  the thing;
- `chunk`, the code it is on; with none, the step is a page, for one idea
  in many places, and needs its `text`;
- `messages`: `[]`. The user's replies go there.

Steps carry no labels: a problem in a step's code is a note on the same
chunk, and the step shows it as it is walked. Order steps as an argument,
not a file listing: each comes where the one before made it the next
question. A change has a few tours of several steps each: three to eight
tours of three to ten steps reads well, as a guide, not a rule. Many
tours of one step are notes, or one tour.

## Notes

Notes are where everything that does not walk goes, at the bottom of the
review, a row each, grouped by kind. A note has:

- `id`: a number no other note of the review has, from 1;
- `kind`, and a `status` of that kind's, `open` when you write it:

  | kind | it asks the reader to | statuses |
  | --- | --- | --- |
  | `issue` | fix it or dismiss it | open, fixed, won't fix, not a problem |
  | `decision` | agree or push back | open, agreed, reversed |
  | `suggestion` | take it or not | open, taken, declined |
  | `question` | answer it | open, answered |
  | `fix` | check what you changed | open, checked |
  | `comment` | read it | none: a comment has no `status` |

  Only an issue has `issue` and `severity`, and it must have both.
  `issue` is `bug`, wrong now, with a case that shows it; `flaw`, it
  works but costs something (an edge case it gets wrong, a misleading
  count, a missing check); or `risk`, right now but likely to break (an
  assumption nothing checks, code no test covers). `severity` is `low`,
  `medium` or `high`. Severity is how bad
  it is if this is wrong and how hard to undo: a file format, a public
  interface, data on disk, a behaviour users rely on are higher;
- `title`: what it says, in a few words; an issue's is the claim
  ("show.lua cuts a long hunk from its top");
- `chunk`, when it is about one place; else none;
- `messages`: at least one. Its first, from you, is what it says: prose
  with excerpts, links to steps (`#step:4`) and contracts
  (`#contract:1`), a diagram, `changes` as any message of yours has. The
  user's replies follow.

A step says what the code there does; a note says what you think of it.
When a step finds a problem, the step keeps its claim and an issue on the
same chunk says the problem and links the step. What you ran to confirm
something goes in the prose: the command, and what it gave, in a fence.
A throwaway script the user will not have: say in a sentence what it
did, then its output. A note the
user wrote is theirs: answer it, and leave its kind, title and status as
they are.

## Writing a review

Asked to review a change, or for a tour of something ("how does auth
work?"), write a new review: a new file `.threads/<id>.json`. Its id is
its title in lowercase, each run of anything but letters and digits made
one `-`, cut to 40 characters, with no `-` at either end, and `-2`, `-3`
added when a file has it already. Write it in this order:

1. **`diff`**, so `--check` can list the hunks.
2. **`chunks`**: every place you will point at, each once.
3. **`contracts`**, their sides and dependents on those chunks.
4. **`tours`** and their steps on those chunks.
5. **`notes`**.
6. **`introduction`** last, now that you know the shape.

Run `show.lua --check <id>` after the chunks: every chunk then warns
that nothing points at it, which only lists what is still to write; read
it for errors in the chunks themselves. Run it again at the end, where it
should warn of nothing.

```json
{
  "title": "Tours pick up where you left off",
  "diff": { "base": "main" },
  "introduction": {
    "text": "A walk now starts after the furthest step you saw, not at the top. `walk.start` takes where to start (#contract:1), and `.seen` keeps it per tour (#contract:2). The resume first: users will notice it."
  },
  "contracts": [
    {
      "id": 1,
      "name": "walk.start(r, tour, from)",
      "kind": "function",
      "source": { "change": "changed", "before": "walk-start-old", "after": "walk-start" },
      "why": "It starts a walk where it is told, not always at step 1.",
      "prose": { "text": "`from` is the step to start on; none starts at the first, as before, so a caller that passes nothing is unchanged." },
      "dependents": [
        { "chunk": "keys-w", "impact": "adapted", "text": "`w` passes the furthest step walked: one argument more." },
        { "chunk": "map-walked", "impact": "none" }
      ]
    },
    {
      "id": 2,
      "name": "furthest",
      "kind": "field in .seen",
      "source": {
        "change": "added",
        "after": { "lang": "ts", "text": "interface Seen {\n  walked: Record<string, true>;\n  furthest: Record<string, number>; // tour -> its furthest step, 0 when none\n}" }
      },
      "why": "A walk starts again after it.",
      "prose": { "text": "Old `.seen` files have no `furthest`: they read as 0, so those tours start at the top once, as before." }
    }
  ],
  "tours": [
    {
      "id": 1,
      "title": "Where a walk starts again",
      "colour": "sky",
      "introduction": {
        "text": "`w` asks `.seen` how far you got, and the walk starts after it:\n\n{{diagram:resume}}\n\nThe map reads the same marks and ignores `furthest`.",
        "diagrams": {
          "resume": {
            "kind": "flow",
            "direction": "right",
            "nodes": [
              { "id": "key", "label": "w", "chunk": "keys-w" },
              { "id": "start", "label": "walk.start", "chunk": "walk-start" },
              { "id": "resume", "label": "after the furthest step", "chunk": "resume" }
            ],
            "edges": [{ "from": "key", "to": "start" }, { "from": "start", "to": "resume", "label": "walked before" }]
          }
        }
      },
      "steps": [
        {
          "id": 1,
          "title": "A tour you walked starts after the furthest step you saw",
          "text": { "text": "So a tour you finished starts again from the first: `furthest` past the last step wraps to 0." },
          "chunk": "resume",
          "messages": []
        },
        {
          "id": 2,
          "title": "The map still ticks every step you saw",
          "text": { "text": "`collect_walk` reads the walked marks only, so it never shows where `w` will land." },
          "chunk": "map-walked",
          "messages": []
        }
      ]
    }
  ],
  "notes": [
    {
      "id": 1,
      "kind": "issue",
      "issue": "flaw",
      "severity": "low",
      "status": "open",
      "title": "The map does not show where a walk resumes",
      "chunk": "map-walked",
      "messages": [
        { "from": "agent", "prose": { "text": "The map ticks what you saw (#step:2) but not where `w` will take you: worth a mark from #contract:2." } }
      ]
    },
    {
      "id": 2,
      "kind": "question",
      "status": "open",
      "title": "Should a finished tour start at its briefing?",
      "messages": [
        { "from": "agent", "prose": { "text": "Today it starts on step 1. Starting on the briefing would show what the tour is about again; which do you want?" } }
      ]
    }
  ],
  "chunks": [
    { "id": "walk-start-old", "file": "lua/walk.lua", "line": 318, "from": "function M.start(r, tour)", "rev": "base" },
    { "id": "walk-start", "file": "lua/walk.lua", "line": 318, "from": "function M.start(r, tour, from)", "rev": "head" },
    { "id": "resume", "file": "lua/walk.lua", "line": 321, "from": "    if furthest > 0 and first then", "to": "    end", "rev": "head" },
    { "id": "keys-w", "file": "lua/keys.lua", "line": 55, "from": "  walk.start(r, tour, seen.furthest(r, tour))", "rev": "head" },
    { "id": "map-walked", "file": "lua/map.lua", "line": 92, "from": "    if walked[step.name] then", "rev": "head" }
  ]
}
```

The file's keys can come in any order; the plugin writes `chunks` last
when it saves.

- **`diff`**: what is reviewed. `{ "of": "uncommitted" }` (everything
  since the last commit), `"staged"` or `"unstaged"`; `{ "base": "main" }`
  (to the working tree); `{ "base": "a1b2c3", "head": "d4e5f6" }`. No
  `diff`: the review is about the code as it stands, as a tour of auth
  is. New files git does not track count, when the new side is the
  working tree. Review what the user named; with nothing named, prefer
  a diff that ends at the working tree.
- **`introduction`**: the overview, two to five sentences: the shape of
  the change and the order the tours tell it in. Link the contracts it
  rests on, `#contract:1`, so the overview ties to the list under it.
- **`status`**: leave it out; a review is open until the user closes it.
- **A hunk** is a run of changed lines: git's changes with no context,
  joined when one starts six or fewer lines after the last ended, so a
  file rewritten end to end is one hunk. A chunk is on every hunk its
  lines overlap, read at the end it is read at. `--check` lists every
  hunk no step, note or contract (its sides and dependents too) is on:
  run it once the file has its `diff`, to see them all.
- **A step on a hunk** has a chunk on lines inside the hunk, at `head`
  (at `base` for a hunk that only removes lines; a `head` chunk shows
  the lines removed among the ones it is on), and shows the hunk as a
  diff. A hunk can be in more than one tour when it serves both. The
  step's `text` says what this hunk does that the briefing does not.
- **A step on code the change did not touch** (a caller, a reader of a
  changed format) says how it depends on the change, and what that means
  for it: still right and why, now wrong, or what to check. It is often a
  contract's dependent too: give both the same chunk.
- **A step on a test** says what it checks, which part of the change that
  covers, and what it leaves untested when that matters. A tour with no
  tests that needs some gets an issue saying so, a `risk`.
- A review holds what you pick: a hunk in no step is not in it, and the
  user never sees it. Leave out only what needs no look: a typo, an
  import or a comment for a change shown elsewhere, docs that say again
  what a step's code shows. Say in the introduction what you left out and
  why; `--check` lists those hunks each time, and that is fine.

For a tour of something, not a change: a review with no `diff`, its
chunks at `now`, a tour per question, and notes for what does not walk.

## Finish

```sh
nvim -l <skill-dir>/show.lua --check <review>
nvim -l <skill-dir>/show.lua <review>
```

`--check` reads the file as the editor does: every field, then every
chunk against the code (`from` found, `to` after it, read at the right
end of the diff), every `{{chunk:id}}` and `{{diagram:name}}`, every
diagram node, every id pointed at, and every link in what you wrote. An
`error:` is something the editor cannot show: fix every one, and every
`warn:`. A `note:` lists hunks of the diff on no step, note or contract:
put each in the review, or mean to leave it out. Then `show.lua <review>` should list nothing of yours
still waiting.

Then tell the user, one line per conversation, what you did; for a new
review, its id, and that Home lists it.
