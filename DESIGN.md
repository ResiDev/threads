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
| `review` | a diff, explained in groups: read on its own screen, walked in the code (see Review) |

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
like any other thread, drawn with the stop's words on top.

- a **comment** is a thread you start on a line;
- a **question** is a thread you start on no line;
- an **answer** is the agent's message; it can carry a tour;
- a **standalone tour** is a thread the agent starts, about no line, whose
  one message is the overview and the tour.

A reply in a stop can be answered with a tour of its own. That is the only
nesting: a tour inside a tour is walked on its own, and ending it goes back
to the outer one.

Excerpts in any message, stage or step (` ```code ` fences holding an
anchor: `file`, `text`, `line`, `lines`) are drawn as the code they point
at, in the page and the thread.

## Whose move it is

Worked out from the messages, never stored:

| Status | When | Glyph |
| --- | --- | --- |
| waiting | the last message is yours: the agent's move | `󱡯` pink |
| answered | the agent answered something you said: your move | `󰇮` deep blue (new) / `󰗯` |
| info | only the agent has spoken: a standalone tour | `󰍍` light cyan (new) / `󰦂` |
| closed | you closed it | `󰗡` |

The shape says whose move it is, and is never a person or robot, which
mark who wrote a message: an envelope for yours (sealed is new, open is
read), an envelope on its way for the agent's, a map for a tour, nobody's,
and a check once closed. With `ui.icons = false`: `●` `○` `◔` `◇` `·` `✓`.

**An explanation the agent starts is not a turn you owe.** A standalone tour
is `info`: in the tours tab, out of your inbox. A stop has no status at all
until you reply in it.

## Walking

Walking is going through a tour, a stop at a time, in order.

| Key | |
| --- | --- |
| `L` / `H` | next / previous stop |
| `r` | reply in the stop you are on (on the overview: in the thread) |
| `M` | the whole tour: in a page, its outline; in the code, the map |
| `K` | walking a review: back to its screen, on the hunk you were on |
| `q` | end the walk (from a tour inside a tour: back to the outer one) |

**Walking a tour again picks up where you left off**: at the first stop you
have not been to after the furthest you got. `<leader>hw` on a stop, or `⏎`
on a stop in an outline, still walks from that stop.

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
  tour, the stage, the step, the tour's track, `step 3/9`, and the keys.
  The track is the tour's shape: a cell per stop, a gap where each stage
  starts, filled up to where you are, `▰▰▰ ▰▰▱ ▱▱▱▱`. The card you are
  on and the page show it beside their count too. A tour of more than 24
  stops gets an even bar of 12 cells instead.
- **A step whose line moved or went** opens as a page instead, saying so
  and quoting the line it was on, and `L` goes on from there.

A stop you are not walking shows as a `▸` sign, and as one line when the
cursor is on its line (`Tab` shows it whole): ten steps must not bury the code
in cards. While you walk a tour, the other tours' stops are hidden and every other
thread folds to one line.
`<leader>hw` on one walks from there.

**`⏎` opens whatever card you are on**: a stop as its page (a step's page
has its code at the top), a thread in the focused float. Replying, closing
and the history are done there, so the card only lists `⏎`; `<leader>hr`
and `<leader>hd` still work but are not advertised.

**The maps.** Walking never shows one: the winbar does. `]h` / `[h` show the
batch map in the top right for three seconds, as comments.nvim does, and
`<leader>hm` keeps it open. In the focused float, stepping with `h` / `l`
shows the threads they go through in a strip under the float.

**Telling a stop from a thread.** Tours are light cyan, conversations deep
blue (pink while the agent works on them). A stop's card has a light cyan
border and badge with its place, `▶ step 3/10`, its words have no speaker,
and its sign is `▸`. A thread's card starts with whose move it is and its
id, `◔ 12`, and its sign is `▎`. A stop you replied in is both: its
border and sign are between the tour's cyan and the conversation's blue
(pink while the agent has it), with the tour's badge and `▸`; its words,
then a plain rule, then the conversation.

**Conversations read like a chat**: the agent's messages on the left, yours
set in towards the right. Every message is marked with a shape as well as a
colour, so you never need the colours to tell who spoke: `󰀄` you, `󰚩` the
agent, lit while unread (`ui.icons = false`: `●` you, `▲` the agent, `△`
unread). A row's strip of shapes is its last five messages. In the float
each message says when it was written: yours as you saved it, the agent's
as it first showed up (noted in the `.seen` file, so the agent never has to
write a time). A stop's own words run across the middle, above
the conversation.

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
| threads | every open conversation, grouped by whose turn it is (`g` groups by file or round instead) |
| tours | every thread that leads to a tour: answers, and standalone tours; `⏎` walks one from the start, `J` from where you left off |
| review | every review: its groups, how risky, how much you have accepted; `d` picks a diff to review |
| closed | |

Under its row, the thread the cursor is on shows its last message; `l`
shows more, `o` all of it. Threads on no line are grouped as **general**.

A tour row says how big it is (`2 stages · 6 steps`), how many stops you
have been to, and how many have a conversation. A stop you replied in shows
in the threads tab under its file, with the tour it is in beside it.

## Review

**A review is a diff, explained in groups.** The agent writes it as a
thread about no line whose message carries `review`: the `diff` it is
about, and the changes in it grouped by what they are for.

- **A group is one intent**, explained once for all its hunks: its
  `title`, `kind` (a commit's prefix: feat, fix, refactor, perf, test,
  docs, chore, style), `risk` (low, medium, high, with `risk_why`), `body`
  and diagram. A hunk is named by any line inside it, and can be in more
  than one group.
- **Three lists per group**: the `hunks` it changed, the code it
  `affected` without changing (callers, readers of a format), and the
  `tests` that cover it.
- **What nothing explains** is gathered last, as its own group: usually
  changes too small to need words.

The diff can be `uncommitted`, `staged`, `unstaged`, from a `base` to the
working tree, or between a `base` and a `head`. It is read with `git
diff`, and untracked files count as added when the new side is the working
tree. It is read again on every save and a few seconds after, so the
agent's edits show.

**A review has two levels.** Unlike a tour, it is not walked page by
page: you read it on its own screen, then go into the code.

- **The screen** fills the editor. First the groups: the overview, then a
  line per group, with whether it is accepted, its risk, kind and size.
  `⏎` on a group opens it: what it is for, then each of its hunks as a
  diff, then the code it affects and its tests. `j`/`k` go from one item
  to the next (the overview, a group, a hunk), and every key acts on the
  item you are on. `o` lets the cursor into an item, to read it as text;
  `o` or `Esc` again goes back to moving by items.
- **The code**: `⏎` on a hunk walks the group's hunks in the code, the
  removed lines drawn above the added ones, washed; `L` goes on into the
  next group's. The track counts the group's hunks. `K` comes back to the
  screen, on the hunk you were on. `⏎` on an affected line or a test walks
  that list instead. `q` ends the walk.

| On the screen | |
| --- | --- |
| `j` / `k` | the next / previous item |
| `⏎` / `J` | into it: a group opens; a hunk is walked in the code from there; an affected line or a test, that list |
| `K` | out: from a group to the groups, from the groups to Home's review tab |
| `o` | open the item: a hunk shown whole, the cursor let in to read it; `o` or `Esc` closes it |
| `a` | accept the hunk, or on a group all of its hunks; again takes it back. An accepted hunk has a green bar down its side |
| `r` | reply on the item: a thread on the hunk, the group, the line |
| `L` / `H` | the next / previous group |
| `q` | close |

Each group's line says its size (lines added and removed, hunks), how
many hunks you have accepted, and its conversations by whose move.

**Accepting** is a hunk at a time, by its content: the same change stays
accepted as it moves, and a hunk that changes is new to look at. A group
is accepted when all its hunks are, `◑` when some are, and when it was
accepted whole and then its code changed, it says **changed since you
accepted it**.

**A thread on a review brings its diff.** A reply in a group or hunk, or a
thread started while the diff is drawn, belongs to the review: going to it
from anywhere draws the review's diff into the code. `<leader>hg` on one
hides or shows it.

**Where a change came from.** A hunk the agent changed for a thread says so
on the review's screen, `from #12`. `#12` in any message links to thread 12,
and `#12.3` to stop 3 of its tour; `⏎` opens it.

Home's review tab lists the reviews, with how much is accepted, and under
each its groups: accepted, risk, kind, title and size. `⏎` opens the
screen, `J` walks the hunks from where you left off, and `d` picks the
diff to review and saves it in the batch's `diff`, where the agent looks.

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
| `Tab` on a thread's lines | one line, or whole (`zone.more`/`less` give a message at a time) |
| `S-Tab` where cards stack | the next card on that line to the top |
| `L` `H` `q` while walking | next stop, previous stop, end the walk |

## How the code is laid out

Each file does one thing; the folders hold the big ones in parts. The words
are in GLOSSARY.md.

- **The batch.** `store/` keeps batches: `file.lua` on disk (the cache, the
  active batch, the watcher), `seen.lua` what you have read, walked and
  accepted, `init.lua` the threads and messages, and is the one way in.
  `json.lua` writes the file in a fixed key order. `anchor.lua` and
  `match.lua` find where a quoted line is now; `refs.lua` where a name in
  an answer points.
- **What is worked out from it.** `tour.lua` turns a message's `walk` into
  stops. `review/diff.lua` reads a diff from git, `review/init.lua` works a
  review out of it (groups, accepting, its walk). `git.lua` takes
  snapshots, shows a file at a revision and opens diffs; `codediff.lua` is
  everything it knows about CodeDiff. `code.lua` reads code with
  treesitter: its colours, the function around a line.
- **Drawing.** `text.lua` measures, fits and wraps text; `look.lua` decides
  how things are marked (glyphs, badges, keys as hints). A screen is built
  into a `sheet.lua` and written into its buffer in one go; `blocks.lua`
  holds what screens share (prose with excerpts, numbered code, a diagram,
  a conversation); `float.lua` opens and sizes the windows; `hunks.lua`
  draws changes into code; `diagram/` lays diagrams out (`diagram/flow/`
  a file per stage: ranks, routes, labels).
- **The code view.** `render/` draws threads into code buffers: `place.lua`
  where they sit and which one the cursor is on, `bubble.lua` a bubble or
  card, `marks.lua` notes, changes and dimming, `init.lua` the rest.
  `actions.lua` is what you can do to a thread; `walk.lua` walks a tour;
  `keys.lua` lays keys over yours and gives them back.
- **Screens.** `home/` is Home: `model.lua` what it shows, `tabs.lua` the
  tabs, `thread.lua` an open thread, `message.lua` one of its messages,
  `single.lua` the float a thread is
  focused in, `keys.lua`, `reply.lua`, `help.lua`, `init.lua` the window.
  `page.lua` is a stop's page, `review/screen/` a review's screen (`view.lua`
  what it shows, `init.lua` its keys),
  `map.lua` the map, `menu.lua` and `list.lua` the batches, `compose.lua`
  the float you write in.
- **Setup.** `init.lua` holds the commands and keys as lists; `config.lua`
  the defaults; `theme.lua` the colours.

Tests: `make check` runs the unit tests (`tests/*_spec.lua`), the screen
snapshots (`tests/screens/`, every screen as text; `UPDATE=1 make screens`
writes them anew) and an end-to-end smoke test.

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
  deep blue for your move, pink while the agent works on it. Tours, their
  cards, notes and the winbar are light cyan, so a tour and a conversation
  never look alike; tour's verdict badges
  and diagram colours join them.
