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

## Writing a thread

Its first message has, in this order, the parts that apply:

1. **A title**: the claim or the ask, readable with no other context
   and needing as little knowledge of the codebase as possible:
   "`reply` never clears the unread count".
2. **The lead**, everything above the first heading: what the point is,
   when it happens and what you ask, in sixty words at most. When the
   thread asks something of the user, ending on the question is often
   the clearest way to say so: they can answer from the lead alone.
3. **`## Example`**: one concrete case, what goes in and what comes
   out, so the user has the scenario in hand before the reasons.
4. **`## How`**: how the code gets to the example, for someone new to
   it; assume nothing about the codebase. When it crosses more than one
   place, a mini-tour that follows the example: each step's title says
   what the example's values are at that point. Where a comment, the
   commit that wrote the lines or a doc says why they are so, quote it.
5. **`## The fix`** or **`## The suggestion`**: the change you propose,
   as a `diff` fence checked against the example; for a decision,
   `## The options`, each named so it can be answered yes or no.

A thread that needs more is two threads.

When a diagram would explain the point better, because it is how
something moves, the states it can be in or the path the code takes,
`## How` is a diagram, and the prose keeps to what the diagram cannot
say. Never a diagram and then a paragraph walking it, nor a shape drawn
in a text fence.

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
- **A table** to set two things side by side, a **diagram** for a shape.

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

## Writing a topic

Asked to review a change, to explain some code, or to turn findings
into threads, write `.threads/<id>.json`, its id the title in lowercase
with each run of other characters one `-`, cut to 40, `-2` added when
taken. With nothing named, review a `diff` that ends at the working
tree.

Each finding becomes a thread, checked against the code first:
confirmed, add the reading; partly right, say what holds and correct
the rest; not reproduced, a `question` saying what you tried.

Past a dozen threads in one go the user is likely overloaded, and the
minor ones bury the rest. Before writing more, ask whether they belong
in a topic of their own, or as a line each in the introduction, under
what you left out, for the user to ask for as a thread.

| kind | asks the user to |
| --- | --- |
| `issue` | fix it or dismiss it: a `bug` wrong now, with an example; a `flaw` that works but costs something; a `risk` likely to break |
| `decision` | agree with a choice someone wrote down as deliberate (quote it), knowing all it keeps and loses; with only the code to go on, it is a `question` |
| `suggestion` | take it or not |
| `question` | answer it |
| `fix` | check what you changed |
| `comment` | read it |

An issue's `severity` is how bad it is if wrong and how hard to undo: a
file format, a public interface or data on disk is higher.

Write in this order: `diff`, `chunks` (then `--check`: it lists errors
in them, and warns of each that nothing points at yet), the mini-tours,
the threads (the one that matters most first, as `#thread:1`), and last
the `introduction`: two or three sentences on what the change does,
which threads to read first, and what you left out and why.

```json
{
  "title": "Replying leaves the unread count stale",
  "diff": { "base": "main" },
  "introduction": { "text": "The change lets you reply from Home. Read #thread:1 first: Home's unread count is wrong after every reply." },
  "tours": [
    {
      "id": 1, "title": "How the unread count goes stale", "listed": false,
      "steps": [
        { "id": 1, "title": "Opening a thread with 3 messages: seen.mark sets its count to 0", "chunk": "seen-mark", "messages": [] },
        { "id": 2, "title": "Replying from Home: reply writes message 4 and leaves the count at 0", "chunk": "reply", "messages": [] },
        { "id": 3, "title": "Home counts 1 unread: message 4, which you wrote", "chunk": "home-count", "messages": [] }
      ]
    }
  ],
  "threads": [
    {
      "id": 1, "kind": "issue", "issue": "bug", "severity": "medium", "status": "open",
      "title": "Home's unread count is wrong after you reply", "chunk": "reply",
      "messages": [
        { "from": "agent", "prose": { "text": "Home shows a thread as unread after you reply to it from Home. Shall I mark it read at the end of `reply`?\n\n## Example\n\nOpen a thread with 3 messages, reply from Home: Home says 1 unread, though you wrote it.\n\n## How\n\nThe count is set when you open a thread, and the new reply path skips it:\n\n{{tour:1}}\n\n## The fix\n\n```diff\n   store.write(r, n, text)\n+  seen.mark(r, n)\n end\n```" } }
      ]
    }
  ],
  "chunks": [
    { "id": "seen-mark", "file": "lua/seen.lua", "line": 40, "from": "function M.mark(r, n)", "to": "end", "rev": "head" },
    { "id": "reply", "file": "lua/home.lua", "line": 88, "from": "local function reply(r, n, text)", "to": "end", "rev": "head" },
    { "id": "home-count", "file": "lua/home.lua", "line": 31, "from": "  local unread = seen.unread(r, n)", "rev": "head" }
  ]
}
```

## Finish

```sh
nvim -l <skill-dir>/show.lua --check <topic>
nvim -l <skill-dir>/show.lua <topic>
```

Fix every `error:` and `warn:`; then nothing of yours is still waiting.
Read each thread as the user will: from its lead and its example alone,
could they answer it? Does each excerpt hold the line its sentence
claims? Cut what does not help them decide.

The threads are where the explaining happens, so the chat stays short:
the topic's id, and a line per thread you wrote or answered. Never
repeat what a thread says.
