---
name: answering-threads
description: Use when the user asks you to answer their threads, comments or questions in thread.nvim (`.threads/` in the repo), or to explain code or a change as a walkthrough they can step through in their editor.
---

# Answering threads

The user reads their code in Neovim with thread.nvim. A **thread** is a
conversation, optionally pinned to lines of code. Threads are collected in
**batches**, one JSON file each at `.threads/<id>.json` in the repository
root; `.threads/active` names the current one. What you write shows in their
editor as soon as you save the file.

A message can carry a **tour**, its `walk`: a list of stops, in order, the
way a `.tour` file lists its steps. That is how you explain something
across many places: the user walks it with `L`/`H`, and a stop becomes a
thread of its own only when they reply in it.

## Start by listing what is waiting

```sh
nvim -l <skill-dir>/show.lua            # the current batch
nvim -l <skill-dir>/show.lua <batch-id> # another one, if the user names it
```

It prints every thread **waiting** for you (the last message is the user's,
and they sent it): the lines it is on, the tour stop it is a reply in
(`in: …`, with what the stop says), and the conversation so far, plus the
**next free thread id**. Leave the
others alone: answered and info threads are the
user's move, closed ones are done.

## Answer each one, at the size it needs

Read the whole thread; the last message is what is asked now. Then pick
one of three sizes:

1. **Prose.** Most answers. A few sentences, the answer first.
2. **Prose and changes.** The user asked for a change: make it, say what you
   did in a sentence, list where in `changes`.
3. **A walkthrough.** The explanation needs more than one place, or more
   than about 15 lines. Your message is the overview, and its `walk` is the
   tour, one stop per place (below).

A thread **with no `file`** is a question about no line in particular. It
can be answered at any of the three sizes.

A thread **in a tour's stop** (it has `on`, and `in:` shows the stop) is
the user replying to that stop. Answer about that stop; the tour is
context. Never move or delete the stop it is on.

## Write the reply into the file

Append one message to the thread's `messages`, editing the JSON as text:

```json
{
  "from": "agent",
  "text": "Renamed to `pending`: it holds sent messages with no reply yet.",
  "changes": [{ "file": "lua/store.lua", "line": 212, "text": "function M.pending(batch)" }]
}
```

- **`text`**: markdown. Short paragraphs, `code` in backticks, `**bold**` for
  a point. Bubbles often show only the first line, so put the answer first.
- **`changes`**: every place you changed for this thread. Quote each line
  exactly as it now reads in `text`, give its `line`, `lines` for a block.
- **Name the thread** on your first reply: set the thread's own `title` (on
  the thread, beside `id`) to a few words saying what it is about: "Save
  should notify", "Why ORDER exists". Leave an existing title alone.
- **If your change rewrote the thread's own line**, update the thread's
  `text` and `line` to where that code is now. If you deleted it, leave it.
  A thread with `"side": "old"` quotes a removed line: leave it as it is.
- Change nothing else: not `status`, not `round`, not the user's messages,
  not ids. Never delete a thread.

## A walkthrough: a message with a tour

Your message is the **overview**: two to four sentences, the shape of the
thing and the order you will tell it in. Give it a `walk`: the stops, in
order. Stops are not threads: no ids, no status, nothing else to add.

```json
{
  "from": "agent",
  "text": "A request is checked twice: who you are, then what you may do. First the token, then the roles.",
  "walk": [
    { "stage": "Who you are", "point": "The token is checked, the session never is.", "verdict": "flaw", "severity": "high", "body": "Why, with an excerpt…" },
    { "file": "src/verify.ts", "line": 32, "text": "  const claims = jwt.verify(req.token, KEY)",
      "title": "verify trusts the token, not the session", "body": "A revoked session still passes until its token expires.",
      "notes": [ … ] },
    { "stage": "What you may do", "point": "…" },
    …
  ]
}
```

A stop is one of three kinds:

- **A step**: on a line, `file` and `text` (the line, verbatim) and `line`
  (`lines` for a block). It shows as a card above that line. Its `title` is
  a **claim** about the code there ("verify trusts the token, not the
  session"), never a topic. Its `body` says why, in a sentence or three.
  Its **notes** are the evidence, on the lines that prove it.
- **A stage**: `stage` (its title, a claim), `point` (one sentence a
  newcomer could repeat), `body`, and `verdict` when it judges something.
  It shows as a full page: the briefing. Quote the few lines the argument
  rests on as excerpts. The steps after it are its own, up to the next
  stage. A stage never has a `file`.
- **A page**: `title` and `body`, no `file`: one idea in many places,
  shown as a page.

Any stop can carry a `diagram`.

Use stages when the explanation has chapters (3–7 stages of 1–5 steps);
for three or four places, go straight to steps. Order them as an
argument, not a file listing: each comes where the one before made it the
next question.

**Notes** sit on a step (or a message), each on one line: the line quoted
in `text` with its `line`, what it says in `note`, a word to pick out in
`mark`, and `file` only when it is not the step's own file. A note with no `note`
just highlights its line. Two to five per step:

```json
"notes": [
  { "line": 32, "text": "  const claims = jwt.verify(req.token, KEY)", "mark": "KEY", "note": "the only check" },
  { "line": 35, "text": "  return claims", "note": "never looks at the session table" }
]
```

**Excerpts** pull code into a page or a message: a ` ```code ` fence holding
one JSON anchor, `lines` how many (default 6, at most 15):

````md
```code
{ "file": "src/verify.ts", "text": "export function verify(req) {", "lines": 6 }
```
````

**Diagrams**, when the point is a shape: `diagram` on a message or a stop. Never
draw ASCII yourself. Kinds: `flow` (`nodes` with `id`, `label`, optional
anchor; `edges` with `from`, `to`, optional `label`; `direction` `down` or
`right`), `sequence` (`participants`, `messages` in order), `calls` (a
`root` with nested `children`). A node that is real code gets `file` and
`text`, verbatim.

**Verdicts**: `bug`, `flaw`, `risk`, `trade-off`, `decision`, `how it
works`, `fine`, with `severity` (`high`, `medium`, `low`) when it matters.

Write for someone who was not in the conversation: define a term the first
time it appears, give abstract things a concrete case, say what you checked
when a claim rests on running something.

## Standalone tours

Asked for a tour of something, not in reply to a thread: add one thread
with the next free id, **no** `file`, `"status": "open"`, titled with the
question it answers, whose one message is the overview with the `walk`. It
is a tour on its own.

## Reviews

Asked to review a change, write a **review**: a thread like a standalone
tour (no `file`, titled `Review: …`), whose one message is the overview and
carries `review` instead of `walk`. The user reads it on its own screen,
group by group, each hunk drawn as a diff, accepting or asking about each
hunk or any line of it, removed lines too; then walks the hunks in the code
with the removed lines drawn above. An accepted hunk comes back when its
code changes.

```json
{
  "from": "agent",
  "text": "Two things changed: tours learnt to resume, and the cache moved. The resume first: it is what users will notice.",
  "diagram": { "kind": "flow", "nodes": [], "edges": [] },
  "review": {
    "diff": { "of": "uncommitted" },
    "groups": [
      {
        "title": "Walking a tour again picks up where you left off",
        "kind": "feat",
        "risk": "medium",
        "risk_why": "the .seen file gains a field older versions drop",
        "body": "Why these hunks changed, once for all of them. Excerpts welcome.",
        "hunks": [
          { "file": "lua/walk.lua", "text": "    if furthest > 0 and first then", "line": 321, "note": "Starts on the stop after the furthest one you saw, so a tour you finished starts again from the first." },
          { "file": "lua/store.lua", "text": "function M.visit(batch, owner, n)", "line": 574 }
        ],
        "affected": [{ "file": "lua/map.lua", "text": "local function collect_walk(batch)", "line": 90, "note": "The map reads the same visited marks to tick stops off. It ignores the new `furthest` field, so it still ticks every stop you saw: right, but worth a look if the map should show where you will resume." }],
        "tests": [{ "file": "tests/smoke.lua", "text": "eq(walk.state().n, 2, 'picks up where you left off')", "line": 321, "note": "Walks two stops, ends the walk, starts it again and checks it is on stop 2. It never finishes a tour, so starting over after the last stop is not tested." }]
      }
    ]
  }
}
```

- **`diff`**: what is reviewed. `{ "of": "uncommitted" }` (everything
  since the last commit), `"staged"` or `"unstaged"`; or `{ "base":
  "main" }` (to the working tree), or `{ "base": "a1b2c3", "head":
  "d4e5f6" }`. Use the batch's `diff` when it has one: it is what the user
  asked for. New files git does not track count, when the new side is the
  working tree.
- **A group is one intent**, not one file: a feature, a fix, a rename done
  in nine places. Its `body` explains **all its hunks at once**; a hunk's
  `note` is only for what is particular to it. Order groups riskiest first.
- **`hunks`** name the hunks of the diff the group is about, each by
  quoting **any line inside the hunk** as an anchor. A hunk that only
  removes lines: quote a removed line with `"side": "old"`. **A hunk can be
  in more than one group** when it serves both.
- **`kind`**, as a commit prefix: `feat`, `fix`, `refactor`, `perf`,
  `test`, `docs`, `chore`, `style`.
- **`risk`**, always: `low`, `medium` or `high`, and `risk_why` unless it
  is low. Risk is how bad it is if this is wrong and how hard to undo: a
  file format, a public interface, data written to disk, a behaviour users
  rely on, or something people may disagree with are higher; a local
  refactor with tests is low.
- **`affected`**: code the change does not touch but changes the meaning
  of: callers of a changed function, readers of a changed format. The user
  steps through these apart from the hunks, so name only what is worth
  looking at.
- **`tests`**: the tests that cover the group. A group with none that
  needs some: say so in its body.
- **Every affected place and test has a `note`, and so does a hunk with
  anything particular to say.** The note is what the user reads first: it
  is the heading above that code on the review screen, its line in Home,
  and the card when they walk it in the code. It is read **on its own**,
  not after the group's body or the item before it, so it never says
  "the same", "see above" or just names the thing. A sentence or two:
  - a hunk: what this hunk does that the group's body does not say;
  - an affected place: **how it depends on the change** (it calls the
    changed function, reads the changed field) **and what that means for
    it**: still right and why, now wrong, or what to check;
  - a test: **what it checks**, and which part of the change that covers;
    what it leaves untested, when that matters.
- Leave out hunks too obvious to explain (a typo, an import for a change
  in a group); the user accepts those one at a time. Everything else
  belongs in a group.
- Link other threads with `#12` (or `#12.3`, stop 3 of its tour) in any
  text; the user opens them with Enter.

### Threads in a review

The user asks about a review where they read it:

- **A reply in a group, a hunk, an affected place or a test** is a thread
  with `on`, like a reply in a tour's stop: answer about that one.
- **A thread on one line of a hunk** has `review`, the review's thread id.
  On a removed line it also has `"side": "old"`: its `text` is the line as
  it was, and `line` its number in the old side of the diff. The code has
  no such line now; answer about what removing it did.

`show.lua` prints the hunk either is about as a diff, the line marked `>`.

**When one asks for a change, make it**: that is how a review gets fixed.
Answer with `changes`, as for any thread: under your reply the user sees
each place you list, and goes to it with Enter, so list every place you
changed. The hunk comes back for them to accept again. Then keep the review
true to the code:

- If your change rewrote the line a hunk of the review quotes, quote it as
  it reads now (`text`, `line`); `--check` says when a quote no longer
  finds its hunk.
- A hunk your change adds goes at the end of its group's `hunks`, with a
  `note`. Never reorder or remove a group's hunks: replies are tied to them.
- A thread on a removed line keeps its quote, even if you put the line back.

## Replies in chat

When the batch has `"reply": "chat"`, answer in the conversation, numbered
by thread id, and still append a one-line message to each thread ("answered
in chat: it guards the reload race"), with its `changes`.

## Finish

```sh
nvim -l <skill-dir>/show.lua --check
```

It checks the file parses, every anchor, note, change, stop and diagram
node resolves, every reply is in a stop that exists, verdicts are known,
and for a review that every hunk you name is in the diff; it warns about
hunks no group explains. Fix what it reports and what it warns about. Then tell the user, one
line per thread, what you did, and for a walkthrough, that `<leader>hw` on
the thread (or `J` in Home) walks it.
