# Glossary

The words thread.nvim's code and docs use, each for one thing.

## The model

**Review**:
What Home lists: threads about a diff, or about code as it stands. A
review in both senses, a judgement of a change or an overview of how
something works.
_Avoid_: batch

**Thread**:
One topic in a review, on a chunk or on no line, with its messages and
its tours. One you start is also called a comment, or a question when it
is on no line.
_Avoid_: group, topic, stage

**Introduction**:
What opens a review, a thread or a tour. A thread's is its first message.
_Avoid_: overview

**Tour**:
An introduction, then steps, walked in order with `L` and `H`. A thread
can have several, each named by the agent.
_Avoid_: walkthrough

**Step**:
One place in a tour: on a chunk, or on no line. A reply in it starts its
own conversation.
_Avoid_: stop, page

**Message**:
One turn in a thread or a step, yours or the agent's.

**Chunk**:
Lines of a file, one or many: plain code, or a hunk.
_Avoid_: place, range, region

**Hunk**:
A chunk a diff changed, with its old and new lines.

**Anchor**:
How a chunk is found: its file, its first line quoted, and a line number
to break ties.

**Version**:
One form of a chunk's code: as it is, as it was, or as the agent
proposes.

**Suggestion**:
A version the agent proposes, for you to apply, take back or decline.

**Check**:
What the agent ran to confirm something works: what it got, in words, and
the shell line it ran.

**Label**:
A verdict, severity, risk, kind or weight on a thread or a step.

**Round**:
The messages sent together. Starting one snapshots the code.

## State

**Accepted**:
A chunk you have gone over in a thread, for its code as it is now. A
change to the code brings it back.

**Whose move**:
Whether a conversation waits on you or on the agent, from its last
message.

## In the prose

**Note**:
A line a message or step points at, with a word on it and what it says.

**Excerpt**:
Code pulled live from a file into prose.
_Avoid_: snippet

**Link**:
A name in prose that goes to a review, a thread, a step or a chunk.

**Example**:
A worked case through the code: what goes in, the lines it runs, what
comes out.
_Avoid_: scenario

**Comparison**:
Versions of a chunk, or several chunks, shown side by side, inline or in
turn.

**Diagram**:
A flow, a sequence or a call tree, its boxes on real code.

## On screen

**Home**:
The full-screen list of reviews.

**Bubble**:
A thread drawn in the code above its first line.

**Card**:
A step drawn in the code above its chunk.

**Zone**:
The lines a thread covers; keys there act on the thread.

**Sheet**:
What a screen is built into before it is written to its buffer: lines,
highlights, marks, and who owns each line.
