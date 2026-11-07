---
name: threads
description: Divides a review or an explanation into threads, each one point with its own conversation, that the user reads and answers in Neovim with thread.nvim.
disable-model-invocation: true
---

# Threads

Each thread is one point, a finding, a question, a suggestion or a part
of an explanation, and the conversation you and the user have about it,
so the user can go through a review or an explanation point by point.
The threads on one subject, with an introduction, make a **topic**.

The user reads topics in Neovim. You write each as one JSON file,
`.threads/<id>.json` in the repository root, and what you save shows in
their editor; `<id>.seen` beside it is the plugin's. Every field, its
values, and what each `{{…}}` placeholder draws are in
`<skill-dir>/../../design/format.ts`: read it before you first write
here. `show.lua --check` holds you to it. An old topic, with `notes`
where the threads are, is brought up to date by
`nvim -l <skill-dir>/show.lua --upgrade`. Old topics have listed tours
and contracts; answer in them as in a thread, and write neither.

To write a new topic, read [`writing-a-topic.md`](writing-a-topic.md)
first: a thread's first message, the kinds, and a whole topic as an
example. To answer what waits in topics already written, go to
[Continuing conversations](#continuing-conversations).

## Explaining

When a diagram would explain the point better, because it is how
something moves, the states it can be in or the path the code takes,
the explanation is a diagram (in a thread's first message, its
`## How`), and the prose keeps to what the diagram cannot say. Never a diagram and then a paragraph walking it, nor a shape drawn
in a text fence. With three or more moving parts, draw a short series
instead of one diagram: each redraws the last and adds one part, so the
user watches it assemble.

Explain to the level the user has shown, not below it. In code they
wrote, or where their restatements were right, skip what they know and
start where it gets new; in code new to them, assume nothing.

Define each term or name the user may not know where it first appears,
and keep them few: the user holds each one in mind while they read, and
past two the explanation weakens. When the point needs more, name them
first, a line each, before the explanation that uses them.

Say how you know each claim: **checked**, you ran it (the command and
its output in a fence) or someone wrote it (quoted with `>`); **read**,
you traced the code, and the excerpt or mini-tour shows it; or
**guessed**: say "likely", and what would settle it.

## Showing code

Code is written once, as a **chunk** in the topic's `chunks`, and
everything points at it by id. Make a chunk the lines the point is
about, fifteen at most: `head` for the change and the code around it,
`base` for removed lines, `now` in a topic with no diff and for your own
edits. Then pick by what the user must do with it:

- **An excerpt**, `{{chunk:id}}` alone on a line, for lines they must
  read to follow the sentence. Name what to look at in backticks in the
  sentence before it, and it is lit there.
- **A mini-tour**, a tour with `"listed": false` placed as `{{tour:id}}`,
  for every other place the thread sends them: the caller, where a value
  is set, where a fix goes. One step is enough for one place; three at
  most. Each step's title is a claim about its code, in the order the
  argument needs, readable alone. Place it once; another thread links
  that one.
- **Backticks alone** for a name they know.
- **A `diff` fence** for a change you propose: the lines that change and
  one of context either side.
- **A table** to set things side by side: four columns at most and a
  few words a cell, or thread.nvim cuts the widest cells short with `…`
  to fit a card; `--check` warns of one too wide. A **diagram** for a
  shape.
- **A seam link**, `[who calls save](seam:src/store.ts:save@Map)`, for a
  shape the code already has, that you would otherwise list or draw by
  hand: who calls it, what it takes and gives, where a type goes, what a
  folder uses from libraries. ⏎ opens seam.nvim on it; the label is your
  words, so the sentence reads on. The claim it backs is then checked,
  not read.
  - `src/store.ts:save@Map`: who calls `save` and what it calls, what
    passes between.
  - `src/store.ts:save@Types`: what it takes and gives.
  - `type:Card@Types`: where `Card` comes from, what it becomes, who sets
    and reads each field.
  - `src/billing@Map/folder`: which files call into the folder, and what
    it calls out to.
  - `src/billing@Map/library`: which packages it uses, and where.

  Only in a TypeScript repo, on the code as checked out (not in a topic
  whose `diff` is a revision not checked out), with names as seam's tree
  shows them; `--check` says when one goes nowhere.

Past two paragraphs, use `##` sections headed by their point. Links:
`#thread:12`, `#step:7`, `other-topic#thread:12`.

## Continuing conversations

```sh
nvim -l <skill-dir>/show.lua            # every open topic
nvim -l <skill-dir>/show.lua <topic>    # one, if the user names it
```

From the repository root, it prints each conversation **waiting** for
you, where the user spoke last: what it is on, the code, what was said
since you last spoke, and `reply in:`, where your message goes. Then the
next id of each kind and the chunk ids in use. Answer only those.

Read the whole conversation; the last message is what is asked.

Answer first, in a few sentences. A change asked for: make it, say what
you did, and list the chunks you changed in `changes`, each quoted as it
reads now. Code to point at: a mini-tour. A guess in the user's message
("this is for speed, right?") is a claim to check before agreeing.

- **The user says how they think it works** ("so my understanding
  is…"): never a bare "yes". Quote each claim and mark it **right**,
  **nearly** or **wrong**. A wrong one: what they said, why it is
  wrong, then what is so, with the example that shows it. Nearly: the
  part that holds and the word to change.
- **The same question a second time** means something under it is
  missing: what the runtime, the library or the data does. Say what it
  is, explain that alone, and stop.
- **Several questions in one message**: answer each under its own
  heading, the one the others rest on first.
- **A definition the user must get right** (which month a payment
  counts in): ask it with an example, never mention it in passing.

Append your message where `reply in:` says (`threads[2]` counts from 1;
jq's `.threads[1]`), editing the JSON as text:

```json
{ "from": "agent", "prose": { "text": "Renamed to `pending`: it holds sent messages with no reply yet." }, "changes": ["store-pending"] }
```

Your message is all you add. The user settles threads, so statuses,
their messages, ids, and anything something points at stay as they are.

## Finish

```sh
nvim -l <skill-dir>/show.lua --check <topic>
nvim -l <skill-dir>/show.lua <topic>
```

Fix every `error:` and `warn:`; then nothing of yours is still waiting.
Does each excerpt hold the line its sentence claims?

The threads are where the explaining happens, so the chat stays short:
the topic's id, and a line per thread you wrote or answered. Never
repeat what a thread says.
