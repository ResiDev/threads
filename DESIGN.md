# thread.nvim: one idea

comments.nvim and tour.nvim grew toward each other. One holds a
conversation about a line; the other tells an explanation across many lines,
in order. Each had half the other's features in a second form: anchors,
cards above the line, names that open code, a map, a picker, a checker.

thread.nvim is both, built on **one primitive: the thread**.

## The thread

A **thread** is a conversation, optionally pinned to lines of code.

- **anchored:** `file`, the line quoted verbatim in `text`, `line` as a
  tie-break, `lines` for a range. It shows as a **bubble** above its line.
- **unanchored:** it is about no line in particular. It shows as a **page**:
  the big centred float.

A thread holds **messages**, from you or the agent. A message is markdown
text, and can carry:

| Field | What it is |
| --- | --- |
| `changes` | places the agent changed for it; each shows as its hunks under the message |
| `notes` | what it says about particular lines: a number on the line, its text at the line's end or hung above it, or just a highlight |
| `diagram` | a flow, sequence or call diagram, every box anchored |
| `verdict` | bug, flaw, risk, trade-off, decision, how it works, fine; with `severity` |
| `children` | the ids of the threads it leads to, in order |

That last field is the only edge. **A message can lead to other threads.**
Everything a tour was is a shape of that:

```
thread 1   "How does auth work?"           your question, on a line
│  you:   How does auth work?
│  agent: Checked twice: who, then what.   ← children: the stages
│
├─ thread 2  "Who you are"                 no line: a page (a stage's briefing)
│  │  agent: The token is checked, the session never is.   ← children: steps
│  ├─ thread 3  router.ts:12               a line: a bubble (a tour's card)
│  └─ thread 4  verify.ts:32
│        agent: Only the key is checked.
│        you:   What about the session table?   ← a reply, like any comment
│        agent: Never read here.
│
└─ thread 5  "What you may do"
   ├─ thread 6  authz.ts:40
   └─ thread 7  cache.ts:7
```

- a **comment** is a thread you start on a line;
- a **question** is a thread you start on no line;
- an **answer** is the agent's message; it can lead to threads;
- a **stage** is an unanchored thread whose message leads to steps; its first
  message is the briefing, and its `verdict` and diagram are the stage's;
- a **step** is an anchored thread the agent started;
- a **tour** is the threads a message leads to, walked in order.

Stages are optional: a message can lead straight to steps, a three-stop walk
with no pages.

A thread has one parent at most, so the threads form a tree, and every
thread has one way back to the top: its **breadcrumb**.

## Whose move it is

Worked out from the messages, never stored:

| Status | When | Glyph |
| --- | --- | --- |
| draft | the last message is yours, unsent | `✎` |
| waiting | the last message is yours, sent | `◔` pink |
| answered | the agent answered something you said | `●` blue (new) / `○` |
| info | only the agent has spoken: an explanation | `◇` (new) / `·` |
| closed | you closed it | `✓` |

**An explanation the agent starts is not a turn you owe.** A step you never
replied to is `info`: it stays in its tour and out of your inbox. Reply to it
and it becomes a conversation like any other.

## Walking

Walking is moving through a tour, in the code or in the float. The tour you
walk is the threads under its **head**: the nearest ancestor that is
anchored, or the root. Its order is the tree read top to bottom: a stage's
page, its steps, the next stage's page, its steps.

| Key | Moves to |
| --- | --- |
| `L` / `H` | next / previous in the walk |
| `K` | the parent: from a step to its stage, from a stage to your question |
| `J` | into the first thread this one leads to |

Starting a walk sets these globally and puts back what they were when it
ends, as tour.nvim does. In the code, a step is its bubble at full size, its
notes on its lines. `<leader>hm` opens the **map** in the corner, and it
follows the walk until you close it: the question the walk started from,
every stage and step indented under it, `▸` where you are, `✓` what you have
seen, `●` where there is a conversation. It never opens on its own. A stage is a
page: the float opens, centred, with the briefing, the diagram, and the
steps listed.

In the float, `h`/`l` do the same as `H`/`L`: walk without leaving it, the
step's code drawn at the top. `⏎` on the code goes there.

A step of a tour you are not walking shows only as a sign, unless it has a
conversation or the cursor is on it: ten steps must not bury the code in
bubbles.

## Sizes of an answer

The same answer shows at three sizes:

1. **The bubble**: the agent's latest message, and a line saying where it
   leads: `▶ leads to 2 stages · 4 steps`. `<leader>hw` walks it, as `J`
   does in Home and the float.
2. **The thread** (Home or the float): the whole message, its diagram drawn,
   and its children as an outline: each stage with its verdict and steps
   under it, each step with its title and place. `j`/`k` step through them,
   `⏎` on one goes to it.
3. **The walk**: the full thing, page by page and bubble by bubble.

## Home

One screen, every thread in the batch, with tabs:

| Tab | Shows |
| --- | --- |
| inbox | every open conversation: threads with a message of yours |
| yours | where it is your move |
| agent | waiting on the agent |
| tours | every tour, by its head: answers that lead somewhere, and standalone tours |
| review | the batch's diff, file by file, and which threads explain each change |
| closed / all | |

A tour row says how big it is (`2 stages · 6 steps`) and how much you have
seen. A step you replied to shows in the inbox under its file, with the tour
it belongs to beside it.

## Review

A batch can carry a `diff` (`base`, `head`; no head is the working tree).
The review tab lists the changed files with their size, and for each hunk
the threads anchored inside it. A file with a hunk no thread covers is
flagged `⚠`: a change nobody explained. `⏎` opens the file's diff (CodeDiff,
or a `:diffthis` split), `v` marks it viewed. A review the agent writes is a
standalone tour grouped by intent, every step anchored in a hunk; your
comments on the diff are threads, and the agent's fixes come back as
changes.

## The batch file

One JSON file per batch, `.threads/<id>.json`, the current one named in
`.threads/active`. The agent edits it as text.

```json
{
  "title": "Auth cleanup",
  "reply": "inline",
  "diff": { "base": "main", "head": null },
  "rounds": [{ "sent": "2026-10-11T14:03:00", "snapshot": "4f1c…" }],
  "threads": [
    {
      "id": 1,
      "title": "How auth works",
      "file": "src/auth.ts",
      "line": 42,
      "text": "export function authorise(req) {",
      "status": "open",
      "messages": [
        { "from": "you", "round": 1, "text": "How does a request get authorised?" },
        {
          "from": "agent",
          "text": "Checked twice: who you are, then what you may do.",
          "verdict": "how it works",
          "diagram": { "kind": "flow", "nodes": [], "edges": [] },
          "children": [2, 5]
        }
      ]
    },
    {
      "id": 4,
      "title": "verify trusts the token, not the session",
      "file": "src/verify.ts",
      "line": 32,
      "text": "  const claims = jwt.verify(req.token, KEY)",
      "status": "open",
      "messages": [
        {
          "from": "agent",
          "text": "A revoked session still passes until its token expires.",
          "notes": [{ "line": 32, "text": "  const claims = jwt.verify(req.token, KEY)", "mark": "KEY", "note": "the only check" }]
        }
      ]
    }
  ]
}
```

Seen state lives beside it in `.threads/<id>.seen`, which only the plugin
writes.

## Tours that already exist

A `.tour` file reads in as threads: `:Thread import <name>` turns it into a
standalone tour in the current batch. The overview becomes the root page,
each stage a page with its briefing, each step a thread with its description
as the agent's message and its comments and notes as notes. Excerpts in a
description (` ```code ` fences holding an anchor) are drawn as the code
they point at, in the page and the thread. A tour's `diff` becomes the
batch's.

## The agent

One skill, `answering-threads`, for every kind of thread. An answer is one
of three sizes, and the agent picks:

- **prose**: a reply, a few sentences, the answer first;
- **prose and changes**: it changed code, and lists where;
- **a walkthrough**: the explanation needs more than one place. The message
  is the overview and leads to steps, or to stages with steps, each a new
  thread with its own message, notes and diagram.

It also answers replies inside steps, and can write a standalone tour or a
review as a new parentless thread. `show.lua` lists what is waiting, and
`show.lua --check` checks the file: every anchor, note, change and diagram
node resolves, every child exists and has one parent.

## Keys

Under `<leader>h` by default, every one changeable or `false`:

| Key | |
| --- | --- |
| `<leader>hh` | Home |
| `<leader>hc` | comment on the line or the selection |
| `<leader>ha` | ask a question about no line |
| `<leader>ho` | focus the thread under the cursor (also `⏎` on its lines) |
| `<leader>hr` / `<leader>hd` | reply to it / close it |
| `<leader>hm` | the map, kept open |
| `<leader>hb` | the batches |
| `<leader>hs` | send: seal the drafts into a round and snapshot the tree |
| `<leader>ht` / `<leader>hx` | bubbles at their size or one line / hide them |
| `<leader>hw` | walk the tour the cursor's thread is in, or leads to |
| `<leader>hq` | stop walking |
| `<leader>hz` | dim everything but the thread you are on |
| `<leader>hg` | draw the thread's changes into the code |
| `]h` / `[h` | next / previous thread that is your move; `]H` / `[H` any open one |
| `+` / `-` on a thread's lines | more or less of it |
| `L` `H` `K` `J` while walking | next, previous, up, into |

## Decisions

- **The file is the interface.** The plugin never talks to the agent.
- **Status is derived.** If the agent forgets a field, the status is still
  right.
- **One edge.** Children on messages, not siblings or routes: a tour is
  whatever a message leads to, so a reply can lead somewhere too.
- **A tree, not a graph.** One parent each, so there is always a way back.
  Messages may still mention other threads in their text.
- **Quiet by default.** Explanations are not inbox items, and steps are not
  bubbles until you walk them or talk in them.
- **Styling follows comments.nvim**: bubbles on the buffer's own background,
  blue for your move, pink for the agent's; tour's verdict badges and
  diagram colours join it.
