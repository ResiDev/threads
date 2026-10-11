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
| `walk` | the tour it leads to: a list of stops, in order |

## Tours are a list on a message

**An answer can carry a tour.** Its `walk` lists the stops in order, the
way a `.tour` file lists its steps:

- a **stage**: `stage` (its title), `point`, `body`, `verdict`, diagram. A
  page, and a chapter heading: the steps after it are its own, up to the
  next stage;
- a **step**: `file`, `text`, `line`, `title`, `body`, `notes`. A card
  above its line;
- a **page**: `title` and `body`, no file.

```
thread 1   "How does auth work?"           your question, on a line
│  you:   How does auth work?
│  agent: Checked twice: who, then what.   ← walk:
│           1  stage  Who you are
│           2  step   router.ts:12
│           3  step   verify.ts:32     ← you replied here:
│           4  stage  What you may do
│           5  step   authz.ts:40
│
thread 9   on: thread 1, stop 3            a thread, on verify.ts:32
   you:   What about the session table?
   agent: Never read here.
```

**Stops are not threads.** They have no id, no status, no inbox row; they
are part of the answer. **Reply in one and it becomes a thread**, with
`on` pointing back at the stop and the stop's anchor copied, so it stays on
its line if the agent rewrites the tour. From then on it is a conversation
like any comment, drawn with the stop's words on top.

- a **comment** is a thread you start on a line;
- a **question** is a thread you start on no line;
- an **answer** is the agent's message; it can carry a tour;
- a **standalone tour** is a thread the agent starts, about no line, whose
  one message is the overview and the tour.

A reply in a stop can be answered with a tour of its own. That is the only
nesting: a tour inside a tour is walked on its own, and ending it goes back
to the outer one.

## Whose move it is

Worked out from the messages, never stored:

| Status | When | Glyph |
| --- | --- | --- |
| waiting | the last message is yours | `◔` pink |
| answered | the agent answered something you said | `●` blue (new) / `○` |
| info | only the agent has spoken: a standalone tour | `◇` (new) / `·` |
| closed | you closed it | `✓` |

**An explanation the agent starts is not a turn you owe.** A standalone tour
is `info`: in the tours tab, out of your inbox. A stop has no status at all
until you reply in it.

## Walking

Walking is going through a tour, a stop at a time, in order.

| Key | |
| --- | --- |
| `L` / `H` | next / previous stop |
| `q` | end the walk (from a tour inside a tour: back to the outer one) |

Starting a walk sets these globally and puts back what they were when it
ends, as tour.nvim does.

- **A step is shown in the code**, always in the code window: its card at
  full size above its line, with any conversation in it, and its notes on
  their lines.
- **A stage or a page opens as a page**: the float, centred, with the
  briefing, the diagram, your thread in it if you replied, and the whole
  tour as an outline, `▸` where you are. `L` from it goes on (to the code,
  for a step), `Esc` closes it and leaves you walking, `⏎` on a stop in the
  outline goes there, `r` replies in the stage.
- **The winbar says where you are** for as long as the walk lasts: the
  tour, the stage, the step, `step 3/9`, and the keys.

A stop you are not walking shows as a `▸` sign, unless the cursor is on its
line: ten steps must not bury the code in cards. `<leader>hw` on one walks
from there.

**`⏎` opens whatever card you are on**: a stop as its page (a step's page
has its code at the top), a thread in the focused float. Replying, closing
and the history are done there, so the card only lists `⏎`; `<leader>hr`
and `<leader>hd` still work but are not advertised.

**The maps.** Walking never shows one: the winbar does. `]h` / `[h` show the
batch map in the top right for three seconds, as comments.nvim does, and
`<leader>hm` keeps it open. In the focused float, stepping with `h` / `l`
shows the threads they go through in a strip under the float.

**Telling a stop from a thread.** A stop's card has a blue badge with its
place, `▶ step 3/10`, and its words have no speaker. A thread's card starts
with whose move it is and its id, `◔ 12`, and every message is labelled
`you` or `agent`. A stop you replied in has both: its words, then a plain rule,
then the conversation.

## Sizes of an answer

The same answer shows at three sizes:

1. **The bubble**: the agent's latest message, and a line saying where it
   leads: `▶ leads to 2 stages · 4 steps`. `<leader>hw` walks it.
2. **The thread** (Home or the float): the whole message, its diagram
   drawn, and its tour as an outline: each stage with its verdict and the
   steps under it, each with its place. `j`/`k` step through them, `⏎` on
   one walks from there, `J` walks it all.
3. **The walk**: the full thing, page by page and card by card.

## Home

One screen, every thread in the batch, with tabs:

| Tab | Shows |
| --- | --- |
| inbox | every open conversation: threads with a message of yours |
| yours | where it is your move |
| agent | waiting on the agent |
| tours | every thread that leads to a tour: answers, and standalone tours |
| review | the batch's diff, file by file, and which threads explain each change |
| closed / all | |

A tour row says how big it is (`2 stages · 6 steps`), how many stops you
have been to, and how many have a conversation. A stop you replied in shows
in the inbox under its file, with the tour it is in beside it.

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
          "walk": [
            { "stage": "Who you are", "point": "The token is checked, the session never is.", "verdict": "flaw" },
            {
              "file": "src/verify.ts",
              "line": 32,
              "text": "  const claims = jwt.verify(req.token, KEY)",
              "title": "verify trusts the token, not the session",
              "body": "A revoked session still passes until its token expires.",
              "notes": [{ "line": 32, "text": "  const claims = jwt.verify(req.token, KEY)", "mark": "KEY", "note": "the only check" }]
            }
          ]
        }
      ]
    },
    {
      "id": 2,
      "on": { "thread": 1, "step": 2 },
      "file": "src/verify.ts",
      "line": 32,
      "text": "  const claims = jwt.verify(req.token, KEY)",
      "status": "open",
      "messages": [{ "from": "you", "round": 2, "text": "What about the session table?" }]
    }
  ]
}
```

Seen state lives beside it in `.threads/<id>.seen`, which only the plugin
writes: how many messages of each thread you have read, and which stops of
each tour you have been to.

## Tours that already exist

A `.tour` file reads in nearly as it is: `:Thread import <name>` turns it
into a standalone tour in the current batch, one thread whose message is
the overview and whose `walk` is the steps: stages keep their point,
verdict and diagram, each step's description becomes its `body` and its
comments and notes its notes. Excerpts in a
description (` ```code ` fences holding an anchor) are drawn as the code
they point at, in the page and the thread. A tour's `diff` becomes the
batch's.

## The agent

One skill, `answering-threads`, for every kind of thread. An answer is one
of three sizes, and the agent picks:

- **prose**: a reply, a few sentences, the answer first;
- **prose and changes**: it changed code, and lists where;
- **a walkthrough**: the explanation needs more than one place. The message
  is the overview and carries the tour: steps, or stages with steps.

It also answers replies in stops (with the stop shown as context), and can
write a standalone tour or a review as a new thread about no line.
`show.lua` lists what is waiting, and `show.lua --check` checks the file:
every anchor, note, change, stop and diagram node resolves, and every reply
is in a stop that exists.

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
| `<leader>ht` / `<leader>hx` | bubbles at their size or one line / hide them |
| `<leader>hw` | walk the tour the cursor's thread leads to, or is in |
| `<leader>hq` | stop walking |
| `<leader>hz` | dim everything but the thread you are on |
| `<leader>hg` | draw the thread's changes into the code |
| `]h` / `[h` | next / previous thread that is your move; `]H` / `[H` any open one |
| `+` / `-` on a thread's lines | more or less of it |
| `L` `H` `q` while walking | next stop, previous stop, end the walk |

## Decisions

- **The file is the interface.** The plugin never talks to the agent.
- **No draft, no send.** A message goes to the agent as you save it; you
  then ask the agent to answer. The first message after everything was
  answered starts a new round and snapshots the code, so the agent's
  changes show against what you were looking at. A send step only earns
  its keep once something can wake the agent up, such as an MCP hook.
- **Status is derived.** If the agent forgets a field, the status is still
  right.
- **One kind of conversation, not one kind of storage.** Everything can be
  replied to, but a stop is only a thread once someone does. An earlier
  version made every stage and step a thread joined by `children`; every
  step then carried status, read state and an inbox place it did not need,
  and walking a tree (up, into, heads) was hard to follow.
- **A tour is a list.** `L`, `H` and `q`; the winbar says where you are.
- **Quiet by default.** Explanations are not inbox items, and stops are not
  cards until you walk to them or reply.
- **Styling follows comments.nvim**: bubbles on the buffer's own background,
  blue for your move, pink while the agent works on it. Tour cards and notes
  are blue too, strong enough to stand off the code; tour's verdict badges
  and diagram colours join them.
