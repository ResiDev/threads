---
name: answering-threads
description: Use when the user asks you to answer their threads, notes or questions in thread.nvim (`.threads/` in the repo), to review a change, or to turn review findings or comments into notes they can talk through with you in their editor.
---

# Answering threads

The user reads their code in Neovim with thread.nvim. Everything there is
in **reviews**, one JSON file each at `.threads/<id>.json` in the
repository root; what you write shows in their editor when you save.
`<id>.seen` beside it is the plugin's.

A review is **an overview and its notes**. Each note is one finding,
question or suggestion, and a conversation you and the user have in it.
Every field, its values, and what each `{{…}}` placeholder draws are in
`<skill-dir>/../../design/format.ts`: read it before you first write
here. `show.lua --check` holds you to it. Old reviews have listed tours
and contracts; answer in them as in a note, and write neither.

## Writing a note

The user judges a note from its lead and opens it only to check. Its
first message runs in this order, using the sections that apply:

1. **The title**: the claim or the ask, readable alone: "`reply` never
   clears the unread count".
2. **The lead**, all above the first heading: the point, when it happens,
   and what you ask, in words, sixty at most, ending in the question.
3. **`## Example`**: a single one, what goes in and what comes out, so
   the reader has it in hand before the reasons.
4. **`## How`**: how the code comes to that example, for someone new
   to it, the code as the subject: "`reply` calls `store.write` and
   never `seen.mark`". Where a comment, the commit that wrote the lines
   or a doc says why they are so, quote it.
5. **`## The fix`**: a `diff` fence checked against the example; for a
   decision, `## The options`, each named so they answer yes or no.

A note that needs more is two notes.

When the point is how something moves, the states it can be in, or which
path the code takes, `## How` is a diagram: the diagram carries it, and
the prose keeps what a diagram cannot say. Never a diagram and then a
paragraph walking it, nor a shape drawn in a text fence.

A name the user may not know is said what it is where it first
appears. Two in a message is easy to hold; when the point needs more,
name them first, a line each, before the explanation that uses them,
or ask whether the note is two.

**Say how you know each claim.** *Checked*: you ran it (command and
output in a fence) or someone wrote it (quoted with `>`). *Read*: you
traced the code, and the excerpt or mini-tour shows it. *Guessed*: say
"likely", and what would settle it.

## Showing code

Code is written once, as a **chunk** in the review's `chunks`, and
everything points at it by id. Make a chunk the lines the point is
about, fifteen at most: `head` for the change and the code around it,
`base` for removed lines, `now` in a review with no diff and for your own
edits. Then pick by what the user must do with it:

- **An excerpt**, `{{chunk:id}}` alone on a line, for lines they must
  read to follow the sentence. Name what to look at in backticks in the
  sentence before it, and it is lit there.
- **A mini-tour**, a tour with `"listed": false` placed as `{{tour:id}}`,
  for every other place the note sends them: the caller, where a value
  is set, where a fix goes. One step is enough for one place; three at
  most. Each step's title is a claim about its code, in the order the
  argument needs, readable alone. Place it once; another note links
  that one.
- **Backticks alone** for a name they know.
- **A `diff` fence** for a change you propose: the lines that change and
  one of context either side.
- **A table** to set two things side by side, a **diagram** for a shape.

Past two paragraphs, use `##` sections headed by their point. Links:
`#note:12`, `#step:7`, `other-review#note:12`.

## Answering what waits

```sh
nvim -l <skill-dir>/show.lua            # every open review
nvim -l <skill-dir>/show.lua <review>   # one, if the user names it
```

From the repository root, it prints each conversation **waiting** for
you, where the user spoke last: what it is on, the code, what was said
since you last spoke, and `reply in:`, where your message goes. Then the
next id of each kind and the chunk ids in use. Answer only those.

Read the whole conversation; the last message is what is asked. Answer
first, in a few sentences. A change asked for: make it, say what you
did, and list the chunks you changed in `changes`, each quoted as it
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

Append your message where `reply in:` says (`notes[2]` counts from 1;
jq's `.notes[1]`), editing the JSON as text:

```json
{ "from": "agent", "prose": { "text": "Renamed to `pending`: it holds sent messages with no reply yet." }, "changes": ["store-pending"] }
```

Your message is all you add. The user settles notes, so statuses, their
messages, ids, and anything something points at stay as they are.

## Writing a review

Asked to review a change, or to turn findings into notes, write
`.threads/<id>.json`, its id the title in lowercase with each run of
other characters one `-`, cut to 40, `-2` added when taken. With nothing
named, review a `diff` that ends at the working tree.

Each finding becomes a note, checked against the code first: confirmed,
add the reading; partly right, say what holds and correct the rest;
not reproduced, a `question` saying what you tried.

Past a dozen notes in one go the user is likely overloaded, and the
minor ones bury the rest. Before writing more, ask whether some are
better as a line each in the introduction, under what you left out,
for the user to ask for as a note.

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
the notes (the one that matters most first, as note 1), and last the
`introduction`: two or three sentences on what the change does, which
notes to read first, and what you left out and why.

```json
{
  "title": "Replying leaves the unread count stale",
  "diff": { "base": "main" },
  "introduction": { "text": "The change lets you reply from Home. Read #note:1 first: Home's unread count is wrong after every reply." },
  "tours": [
    {
      "id": 1, "title": "How the unread count goes stale", "listed": false,
      "steps": [
        { "id": 1, "title": "seen.mark sets the count when you open a note", "chunk": "seen-mark", "messages": [] },
        { "id": 2, "title": "reply writes the message but never touches .seen", "chunk": "reply", "messages": [] },
        { "id": 3, "title": "Home reads the stale count", "chunk": "home-count", "messages": [] }
      ]
    }
  ],
  "notes": [
    {
      "id": 1, "kind": "issue", "issue": "bug", "severity": "medium", "status": "open",
      "title": "Home's unread count is wrong after you reply", "chunk": "reply",
      "messages": [
        { "from": "agent", "prose": { "text": "Home shows a note as unread after you reply to it from Home. Shall I mark it read at the end of `reply`?\n\n## Example\n\nOpen a note with 3 messages, reply from Home: Home says 1 unread, though you wrote it.\n\n## How\n\nThe count is set when you open a note, and the new reply path skips it:\n\n{{tour:1}}\n\n## The fix\n\n```diff\n   store.write(r, n, text)\n+  seen.mark(r, n)\n end\n```" } }
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
nvim -l <skill-dir>/show.lua --check <review>
nvim -l <skill-dir>/show.lua <review>
```

Fix every `error:` and `warn:`; then nothing of yours is still waiting.
Read each note as the user will: from its lead and its example alone, could
they answer yes or no? Does each excerpt hold the line its sentence
claims? Cut what does not help them decide. Then tell the user, a line
per conversation, what you did, and a new review's id.
