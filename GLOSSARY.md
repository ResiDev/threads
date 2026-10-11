# Glossary

The words thread.nvim's code and docs use, each for one thing.

- **batch**: a set of threads, one JSON file in `.threads/`. One is active.
- **thread**: a conversation, on lines of code or on none. A thread you
  start on a line is also called a comment, one on no line a question.
- **message**: one turn in a thread, yours or the agent's.
- **round**: the messages sent together, from the first one after
  everything was answered. Starting one snapshots the code.
- **anchor**: where a thread, step or note sits: a file, a quoted line, a
  line number to break ties.
- **tour**: the list of stops a message's `walk` holds; **walking** it is
  going through them with `L` and `H`.
- **stop**: one item of a tour. A **stage** is a chapter, shown as a page;
  a **step** is on a line, shown as a card; a **page** is on no line.
- **note**: a line a step or message points at, numbered, with a word on it.
- **review**: a message whose `review` groups the hunks of a diff.
- **group**: one intent in a review, with its hunks, the code it affects
  and its tests.
- **hunk**: a run of changed lines in a diff.
- **bubble**: a thread drawn in the code above its first line.
- **card**: a step drawn the same way, until someone replies in it.
- **zone**: the lines a thread covers; keys there act on the thread.
- **Home**: the full-screen list of a batch's threads, in tabs.
- **sheet**: what a screen is built into before it is written to its
  buffer: lines, highlights, marks, who owns each line.
