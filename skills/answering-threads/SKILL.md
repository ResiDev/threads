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

## Standalone tours and reviews

Asked for a tour of something, not in reply to a thread: add one thread
with the next free id, **no** `file`, `"status": "open"`, titled with the
question it answers, whose one message is the overview with the `walk`. It
is a tour on its own.

Asked to review a change: set the batch's `diff` (`{ "base": "main",
"head": null }`; no head is the working tree) if it has none, then write a
standalone tour grouped by intent, every step anchored inside a hunk. The
user's review tab flags changed hunks no thread covers.

## Replies in chat

When the batch has `"reply": "chat"`, answer in the conversation, numbered
by thread id, and still append a one-line message to each thread ("answered
in chat: it guards the reload race"), with its `changes`.

## Finish

```sh
nvim -l <skill-dir>/show.lua --check
```

It checks the file parses, every anchor, note, change, stop and diagram
node resolves, every reply is in a stop that exists, and verdicts are
known. Fix what it reports and what it warns about. Then tell the user, one
line per thread, what you did, and for a walkthrough, that `<leader>hw` on
the thread (or `J` in Home) walks it.
