---
name: answering-threads
description: Use when the user asks you to answer their threads, notes or questions in thread.nvim (`.threads/` in the repo), to review a change, or to turn review findings or comments into notes they can talk through with you in their editor.
---

# Answering threads

The user reads their code in Neovim with thread.nvim. Everything there is
in **reviews**, one JSON file each at `.threads/<id>.json` in the
repository root (make `.threads/` when there is none). What you write
shows in their editor as soon as you save the file. Beside each,
`<id>.seen` is the plugin's: never touch it.

A review is **an overview and its notes**. Each note is one finding, one
question or one suggestion. It opens with a **lead**, its point and what
it asks, which Notes shows under its title. Below, it carries the
reading the user needs to judge it: an excerpt, or a mini-tour of a few
steps through the code. Then the user and you talk it through in the
note.

```
review          about a diff, or about the code as it stands
├─ introduction the overview: what this is, and which notes to read first
├─ note         one finding, by kind: an issue, a decision, a suggestion,
│  │            a question, a fix, a comment; yours or the user's
│  └─ message   its first: the lead, then the reading; the rest is the
│               conversation
├─ tours        mini-tours, each placed in a note's or a message's prose
│  └─ step      a claim, on a chunk; the user can reply in it
└─ chunks       every place in the code the rest points at, each once, by id
```

The screen shows the overview, then the notes, each its row and its
lead, grouped by kind. The user opens a note to read the rest: its lead
brighter, a rule, then the reading. A mini-tour placed in it is
drawn as a walk to take, two rows: its title, then how many steps and
through which files. `j` stops on it, ⏎ walks it in the code, and Tab
shows its steps. `j` stops on an excerpt too, and ⏎ goes to its code.

There is no format number. A review written before this format does not
read: `--check` says, field by field, what each old field became. Do not
convert one unless the user asks; write a new review instead.

## Writing a note

A note opens with its lead, the reading below it, so the user can judge
it from Notes and open it only to check.

1. Title it with the claim or the ask: "`reply` never clears the unread
   count".
2. The lead: the point, when it happens, and what you ask, in two or
   three sentences ending in the question. No code. Behaviour a doc or
   spec intends is a decision, not a bug.
3. `## Why`: what someone new to this code needs to judge it. An excerpt
   for lines to read, a mini-tour for other code it names. Name in
   backticks what to look at; the excerpt lights it.
4. `## The case`: one case, what goes in and what comes out.
5. `## The fix`: a `diff` fence checked against that case, or for a
   decision `## The options`. Name each, so they answer yes or no.

## Start by listing what waits

```sh
nvim -l <skill-dir>/show.lua            # every open review
nvim -l <skill-dir>/show.lua <review>   # one, if the user names it
```

Run it from the repository root; `<review>` is a review's id, its file's
name without `.json`.

It prints every conversation **waiting** for you: one where the user's
message is the last. A conversation is a note's, a step's or a
contract's, each known by its link, its kind and its id: `#note:12`,
`#step:7`, `#contract:3`. With each: what it is on (the note's kind and
status, the step and what it says, the contract's sides), the code (a
hunk drawn as a diff, the chunk's lines marked `>`), what was said since
you last spoke (a note's first message too), and where to write your
reply, as `reply in:`. For each review it also prints the **next id** of
each kind and the **chunk ids in use**, by file.

Leave everything else alone: the rest is the user's move, or settled. A
`cannot read <id>` line is a review the editor cannot show either: if you
wrote it, `--check <id>` says what to fix; if not, leave it alone.

Older reviews have listed tours and contracts. Answer in them as in a
note; do not add new ones.

## Answer each one, at the size it needs

Read the whole conversation in the file; the last message is what is
asked now. Then pick one of three sizes:

1. **Prose.** Most answers. A few sentences, the answer first.
2. **Prose and changes.** The user asked for a change: make it, say what
   you did in a sentence, list the chunks you changed in `changes`.
3. **Prose and a mini-tour.** The answer points at code. Add a
   mini-tour (below) and place it in your reply: "How it is read:" and
   `{{tour:4}}` on the next line.

A reply **in a step** is about that step; its tour is context.

## Write the reply into the file

Append one message to the conversation's `messages`, editing the JSON as
text, in place: a note's are `notes[i].messages`, a step's
`tours[k].steps[n].messages`, a contract's `contracts[i].messages` (add
the list if it has none). `show.lua` prints which, counting from 1:
`notes[2]` is the second note (`.notes[1]` in jq, which counts from 0).

```json
{
  "from": "agent",
  "prose": { "text": "Renamed to `pending`: it holds sent messages with no reply yet." },
  "changes": ["store-pending"]
}
```

- **`prose`**: an object, `{ "text": "..." }`, never a bare string, with
  `diagrams` beside the text when it needs one, written as Prose,
  excerpts, mini-tours says. A row often shows only the first line, so
  put the answer first.
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

## Notes

A note has:

- `id`: a number no other note of the review has, from 1. Number them in
  the order to read them, the one that matters most first;
- `kind`, and a `status` of that kind's, `open` when you write it:

  | kind | it asks the user to | statuses |
  | --- | --- | --- |
  | `issue` | fix it or dismiss it | open, fixed, won't fix, not a problem |
  | `decision` | agree with a choice the code makes, or push back | open, agreed, reversed |
  | `suggestion` | take it or not | open, taken, declined |
  | `question` | answer it | open, answered |
  | `fix` | check what you changed | open, checked |
  | `comment` | read it | none: a comment has no `status` |

  Only an issue has `issue` and `severity`, and it must have both.
  `issue` is `bug`, wrong now, with a case that shows it; `flaw`, it
  works but costs something (an edge case it gets wrong, a misleading
  count, a missing check); or `risk`, right now but likely to break (an
  assumption nothing checks, code no test covers). `severity` is `low`,
  `medium` or `high`: how bad it is if this is wrong, and how hard to
  undo. A file format, a public interface, data on disk and a behaviour
  users rely on are higher;
- `title`: the claim or the ask, readable alone;
- `chunk`, the place it is about, when there is one; else none. With a
  mini-tour, the place a fix would go. The note's row shows where it is;
  its excerpt or mini-tour shows the code;
- `messages`: at least one. Its first, from you, is the note, written as
  Writing a note says. The user's replies follow.

A **decision** lists everything the choice keeps or loses before it
offers options, so the user chooses knowing all of it. A **fix** you
propose says the edge case it turns on ("when `head` is `top`, the
indices are as before"), and its `diff` fence leaves no lines out.

What you ran to confirm something goes in the prose: the command, and
what it gave, in a fence. A throwaway script the user will not have: say
in a sentence what it did, then its output. A note the user wrote is
theirs: answer it, and leave its kind, title and status as they are.

## Mini-tours

A **mini-tour** takes the user to the code a note rests on: how a bug
happens, where a value comes from, what a fix touches. It is one of the
review's `tours` with `"listed": false`, placed in prose with
`{{tour:2}}`, its `id`, alone on a line. The prose around it is its
briefing, so it has no `introduction` or `colour`.

**Code the prose refers to gets a mini-tour.** Whenever the note names
code the user would have to go and find (a caller, where a value is
set, the function a fix goes in), place a mini-tour to it, even of one
step, rather than naming it in backticks. It is drawn as two rows, so it
costs nothing until walked, and the walk carries what the prose would
otherwise have to say: each step's text, on its code.

**Three steps at most**; past three it is warned of. Each step is a
**claim** about the code it is on, in the order the argument needs:
each comes where the one before made it the next question. A step is
read on its own, so its `text` never says "the same" or "see above".

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

and in the note: `"The unread count on Home stays at its old total after you reply. Shall I clear it in `reply`?\n\n## Why\n\n{{tour:4}}"`

- `id`: a number no other tour of the review has, from 1. Its steps'
  ids are numbers no other step has, in any tour, from 1. `show.lua`
  prints the next of each;
- `title`: what the walk shows, as a claim;
- each step: `id`, `title`, `chunk`, `messages: []`, and `text`: a
  sentence on what to see in its code, naming it in backticks, which
  lights it there. Titles are plain text: no backticks.

Place each mini-tour once, in the note it explains; another note that
needs the same path links that note. To choose:

- **An excerpt** for the lines the claim rests on, which the user must
  read to follow the sentence.
- **A mini-tour** for every other place the note sends them: a chain of
  causes, the caller, where a value is set, where a fix goes. One step
  is enough for one place.
- **Backticks alone** for a name the user knows, or one said in passing
  that they need not look at.

A note can have both: an excerpt for the lines to read, a mini-tour for
the path around them.

## Chunks

A **chunk** is lines of a file, written once in the review's `chunks`
and pointed at by its `id` from everywhere else: a note's `chunk`, a
step's, a diagram node's, a message's `changes`, and `{{chunk:id}}` in
prose. **Write the chunks first**, then everything that points at them.
Two things on the same lines share one chunk.

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
- How much: the lines the point is about, not the function around them.
  An excerpt shows fifteen lines at most, so a chunk of a few to fifteen
  lines is enough.

## Prose, excerpts, diagrams, links

Wherever prose goes (the overview, a step's `text`, every message) the
JSON holds an object, `{ "text": "...", "diagrams": { ... } }`.

Bold, *italic*, headings, lists, tables, `>` quotes and ``` fences are
drawn; other markdown shows as written. A command's output goes in a
fence.

**Write it to be read at a glance**, then line by line:

- **The claim first.** The prose's first sentence, and each paragraph's,
  says what is true or what changed; the rest backs it.
- **More than two paragraphs: `##` sections**, each heading naming its
  point: "It costs a half-true comment" over "Costs". An excerpt, a
  mini-tour, a table, a diagram or a fence is not a paragraph; it goes
  in the section whose point it shows. Each section is a stop for `j`
  and `k`.
- **A note's first message is its lead, then its sections.** The lead
  is everything above the first heading: text alone, sixty words at
  most, ending in the question. Below it, those that apply, in this
  order: `## Why`, `## The case`, `## The fix` (`## The options` for a
  decision). A comment or a fix asks nothing, so its lead need not. A
  note that needs more is two notes.
- **One idea a sentence**, its subject and verb early.
- **A table for a comparison**: two things set against the same
  properties, a row a property.
- **Bold** a phrase that is a point, *italic* a word the sentence leans
  on, and a `>` quote for words taken from the code, a comment or the
  user.
- **Define a term** the first time it appears.

## The tools for showing code

A note explains with these, so the user reads the code it means, not a
name they have to go and find.

**An excerpt** shows one place: `{{chunk:id}}` alone on a line, the
chunk's lines read from the file each time it is drawn, fifteen rows at
most.

- **It shows what the change did.** A chunk on a hunk of the diff draws
  its added lines marked `+`. When the chunk holds everything a part of
  the diff put in place of some lines, those lines show above, marked
  `-`. So a chunk on a changed signature shows it before and after, and
  one inside a rewritten block shows only its `+` lines. A chunk all of
  whose lines are new is plain, its place saying `added`. A chunk at
  `base` marks its removed lines `-`. A chunk at `now` or on unchanged
  code is plain.
- **It lights what you name.** Names the text puts in backticks since
  the last excerpt or mini-tour are lit where they stand in the next
  excerpt. Name what the user should look at in the sentence that
  introduces it: "`restore` closes the screen but never calls `stop`:".
  A call is found by its name, `stop()` as `stop`.

**A mini-tour** shows a path through several places (Mini-tours, above).

**A `diff` fence** shows a change you propose: lines starting `-` and
`+` are washed as a diff. Write the few lines that change and a line of
context either side, not a whole patch.

````markdown
I would stop the walk before going back:

```diff
   if not s.walk then
+    walk.stop()
     go.close 'screen'
```
````

**A diagram** shows a shape (below). **A table** sets two things against
the same properties.

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

Any node that is real code gets `"chunk"`, the id of one of the review's
chunks. Labels are plain text: no markdown, no links.

**Links** name what they go to and its `id`: `#note:12` a note,
`#step:7` a step; `other-review#note:12` in another review. Notes and
steps count their own ids, so `#step:3` and `#note:3` are two things.
The user opens them with Enter. A name in backticks is code, and links
to where the repo defines it. Use backticks for a key, a command or a
name the user knows; code they need to read, show.

## Writing a review

Asked to review a change, or to turn findings or comments into notes,
write a new review: a new file `.threads/<id>.json`. Its id is its title in
lowercase, each run of anything but letters and digits made one `-`,
cut to 40 characters, with no `-` at either end, and `-2`, `-3` added
when a file has it already.

With findings in hand (a code review, PR comments, the user's list),
each becomes a note. Check each against the code first, then:

- **Confirmed**: keep its kind and severity, and add the reading it
  rests on.
- **Partly right**: say what holds, then correct the rest, naming where
  the finding came from: "The review says only insert mode clears it;
  `keep` does too."
- **Not reproduced**: a `question`, saying what you tried and asking for
  the case that shows it.
- **"Intended?"**: a `decision` when the code, a doc or a spec shows the
  choice was deliberate; quote it.

Evidence in two places that are not a path (the code and the spec that
pins it) is two excerpts, or a mini-tour whose step titles say what
each shows.

Write it in this order:

1. **`diff`**, so `--check` can list the hunks.
2. **`chunks`**: every place you will point at, each once.
3. **`tours`**: the mini-tours the notes need.
4. **`notes`**, the one that matters most first.
5. **`introduction`** last: two or three sentences on what the change
   does and which notes to read first, by link (`#note:1`). Say what you
   left out and why.

Run `show.lua --check <id>` after the chunks: every chunk then warns
that nothing points at it, which only lists what is still to write; read
it for errors in the chunks themselves. Run it again at the end, where it
should warn of nothing.

```json
{
  "title": "Replying leaves the unread count stale",
  "diff": { "base": "main" },
  "introduction": {
    "text": "The change lets you reply from Home. Read #note:1 first: Home's unread count is wrong after every reply. #note:2 asks whether a reply should reopen a closed note."
  },
  "tours": [
    {
      "id": 1,
      "title": "How the unread count goes stale",
      "listed": false,
      "steps": [
        { "id": 1, "title": "seen.mark sets the count when you open a note", "chunk": "seen-mark", "messages": [] },
        { "id": 2, "title": "reply writes the message but never touches .seen", "text": { "text": "So the count still holds the total from when you opened it." }, "chunk": "reply", "messages": [] },
        { "id": 3, "title": "Home reads the stale count", "chunk": "home-count", "messages": [] }
      ]
    }
  ],
  "notes": [
    {
      "id": 1,
      "kind": "issue",
      "issue": "bug",
      "severity": "medium",
      "status": "open",
      "title": "Home's unread count is wrong after you reply",
      "chunk": "reply",
      "messages": [
        {
          "from": "agent",
          "prose": {
            "text": "Home shows a note as unread after you reply to it from Home. Shall I mark it read at the end of `reply`?\n\n## Why\n\nThe count is set when you open a note, and the new reply path skips it:\n\n{{tour:1}}\n\n## The case\n\nOpen a note with 3 messages, reply from Home: Home says 1 unread, though you wrote it.\n\n## The fix\n\n```diff\n   store.write(r, n, text)\n+  seen.mark(r, n)\n end\n```"
          }
        }
      ]
    },
    {
      "id": 2,
      "kind": "question",
      "status": "open",
      "title": "Should a reply reopen a closed note?",
      "chunk": "reply",
      "messages": [
        {
          "from": "agent",
          "prose": {
            "text": "A reply to a closed note leaves it closed, so the agent never sees it in `show.lua`. Should a reply reopen it, as a message reopens a closed review?\n\n## Why\n\n`reply` writes the message and leaves `status` alone:\n\n{{chunk:reply}}"
          }
        }
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

The file's keys can come in any order; the plugin writes `chunks` last
when it saves.

- **`diff`**: what is reviewed. `{ "of": "uncommitted" }` (everything
  since the last commit), `"staged"` or `"unstaged"`; `{ "base": "main" }`
  (to the working tree); `{ "base": "a1b2c3", "head": "d4e5f6" }`. No
  `diff`: the review is about the code as it stands. New files git does
  not track count, when the new side is the working tree. Review what
  the user named; with nothing named, prefer a diff that ends at the
  working tree.
- **`status`**: leave it out; a review is open until the user closes it.
- A review holds what has a note. `--check` lists, as `note:` lines, the
  hunks no note or step is on; that is fine. It is the user's list of
  what you did not raise.

## Finish

```sh
nvim -l <skill-dir>/show.lua --check <review>
nvim -l <skill-dir>/show.lua <review>
```

`--check` reads the file as the editor does: every field, then every
chunk against the code (`from` found, `to` after it, read at the right
end of the diff), every `{{chunk:id}}`, `{{tour:id}}` and
`{{diagram:name}}`, every diagram node, every id pointed at, and every
link in what you wrote. It warns of an excerpt that lights nothing the
text before it named, which usually means the excerpt does not hold what
the sentence claims, and of a `diff` fence that leaves lines out. For
each open note it warns of a lead that is missing, longer than sixty
words, or asks nothing when its kind asks. An
`error:` is something the editor cannot show: fix every one, and every
`warn:`. Then `show.lua <review>` should list nothing of yours still
waiting.

`--check` reads only a little of your prose. Before you tell the user,
read each note as they will: can they judge it and reply from the note
alone? Does each excerpt hold the line its sentence claims? Cut what
does not help them decide.

Then tell the user, one line per conversation, what you did; for a new
review, its id, and that Home lists it.
