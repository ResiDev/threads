# Writing a topic

The part of the [`threads`](SKILL.md) skill for writing a new topic.
Everything in `SKILL.md` applies too: how to explain, how to show code,
and the finish.

## A thread's first message

In this order, the parts that apply:

1. **A title**: the claim or the ask, readable with no other context
   and needing as little knowledge of the codebase as possible:
   "`reply` never clears the unread count".
2. **The lead**, everything above the first heading: what the point is,
   when it happens and what you ask, in sixty words at most. When the
   thread asks something of the user, ending on the question is often
   the clearest way to say so: they can answer from the lead alone.
3. **`## Example`**: one concrete case, what goes in and what comes
   out, so the user has the scenario in hand before the reasons.
4. **`## How`**: how the code gets to the example, assuming nothing the
   user has not shown they know. When it crosses more than one
   place, a mini-tour that follows the example: each step's title says
   what the example's values are at that point. Where a comment, the
   commit that wrote the lines or a doc says why they are so, quote it.
5. **`## The fix`** or **`## The suggestion`**: the change you propose,
   as a `diff` fence checked against the example; for a decision,
   `## The options`, each named so it can be answered yes or no.

A thread that needs more is two threads.

## The topic

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
| `explanation` | understand how something works; they mark it understood, often after putting it in their own words |
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

## Before you finish

Read each thread as the user will: from its lead and its example alone,
could they answer it? Cut what does not help them decide. Then finish
as `SKILL.md` says.
