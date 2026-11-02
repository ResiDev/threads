# Threads are the primitive

Status: an idea, 2026-10-29. The branch `notes-first` is the first step.

## The idea

A thread is one point and its conversation: an issue, a question, a
decision. It is a note in the format today. The conversation per point
is what is most interesting, so everything centres on threads:

- **Contracts and tours stop being parts of their own.** What they gave
  becomes something a thread places in its prose.
- **Explaining happens inside a thread.** To explain something, the
  agent writes a thread with as many tours as it needs.
- **Planning too.** A plan is threads, one per decision.

So the work is giving threads the primitives they need to cover
everything.

## The problem

There is one problem to solve: the agent gives the user enough context
to understand the point, and no more, prose above all.

Too little, and the user cannot judge the point without reading the
code themselves. Too much, and the point takes longer to read than the
code it explains.

## What we know so far

From the test on `notes-first` (a review of `d2d64a5..7e990b1`, 6 notes,
read by an agent new to the code):

- Enough context: the reader judged all 6 notes correctly from the note
  alone.
- Too much prose: each note took 2 to 5 minutes, at 1,100 to 2,100
  characters. The aim was one minute.
- What helped was what was shown, not said: mini-tours, output before
  and after, excerpts that light the names the text uses, fixes as
  `diff` fences.

So a primitive earns its place when it replaces prose with something
seen.

## Measuring it, to hill climb

The aim is the least reading for which the point is understood. That
needs two measures: what reading a thread cost, and whether the reply
shows the point was understood. Time alone rewards notes that are short
and wrong.

- **Cost, from use.** `.seen` already keeps, by name, what you read and
  when each message showed up, and only the plugin writes it. It could
  also keep when a thread was opened and closed, the time on it with
  idle gaps cut, and when you first replied.
- **Understanding, from the reply.** Your first reply is the evidence.
  An agent sorts it: decided (yes, no, a fix), pushed back with a
  reason, or asked for context ("where is this?", "what calls it?"). The
  last means the thread gave too little. Messages until it is settled
  count too.
- **A loop that does not wait for you.** A fixed set of findings, each
  with what the reader must come away knowing: the claim, when it
  happens, the fix. One agent writes the threads with the skill, a
  fresh one answers from the thread alone, and the score is the answers
  right and the words it took. Change the skill or a primitive, run it
  again.
- **Use keeps the loop honest.** An agent reader is not you: what you
  take time over or ask about, while the loop's score rises, says where
  it is wrong.

## Open

- Which primitives are missing. Candidates: a signature before and
  after with who depends on it (what a contract gave), and what a plan's
  decision needs (options and their costs).
- seam.nvim for the types, on TypeScript repos, never required. First a
  key on a name in a note (in backticks, or lit in an excerpt with its
  chunk's file and line) opening seam on it: its types, calls or page,
  `gf` back. seam needs an entry taking a name, file and line, split
  from `here()`, which reads the cursor. Then, mocked before it is
  built, seam's takes and gives and the declarations of those types
  drawn in the note, so the agent writes none of it. Tours that walk
  seam's views: `thread-seam.md`.
- Whether a tour is worth keeping when it belongs to no point: a walk
  through a change before there is any opinion about it.

## Not this

The branch `thread-documents` (2026-10-19, `design/plan.md` there) also
used the word thread, for the opposite idea: a thread is a file holding
reviews, plans and explains as documents, with contracts and tours as
parts of their own. Here a thread is the point, not the file.
