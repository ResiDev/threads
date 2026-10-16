# Glossary

The words thread.nvim's code and docs use, each for one thing.

## The model

**Review**:
What Home lists: a judgement of a change, or an overview of how
something works, about a diff or about the code as it stands. Its
introduction, its contracts, its tours and its notes, and the chunks they
point at.
_Avoid_: batch

**Introduction**:
What opens a review: the big picture, read first. A tour's is its
briefing.
_Avoid_: overview

**Contract**:
Something code depends on that the change added, changed or removed: a
function's signature, a type, a behaviour. Its source, the contract as it
was and as it is; its prose; its dependents; its conversation.

**Source**:
A contract's sides: the chunk of its signature, or the contract written
out whole, before and after.

**Dependent**:
Code that uses a contract, a chunk on the line that uses it, with its
impact: how far the change reached it (`none`, `adapted`, `reworked`,
`missed`) and what it had to do.

**Blast radius**:
A contract's dependents, grouped by impact, the furthest first.

**Tour**:
A briefing, then steps, walked in order with `L` and `H`. Its colour tells
it apart on screen.
_Avoid_: walkthrough

**Briefing**:
A tour's introduction: what its steps are for, read before the first,
with a diagram when they have a shape.

**Step**:
One place in a tour, with a claim for its title: on a chunk, or on no
line; one on no line is drawn as its page. Its own conversation.
_Avoid_: stop

**Note**:
Something said about the change, on a chunk or on no line: an `issue`
(a bug, a flaw or a risk, with a severity), a `decision`, a `question`, a
`suggestion`, a `fix`, or a `comment`. Each kind has its own statuses; a
comment has none. One you start is a comment on lines, a question on
none.
_Avoid_: thread

**Message**:
One turn in a conversation, yours or the agent's. The agent's can name
the chunks it changed.

**Conversation**:
The messages of a step, a note or a contract. Each has its own whose
move.
_Avoid_: discussion, thread

**Chunk**:
Lines of a file, written once in a review and pointed at by id: its
first line and its last quoted, the line it was on, and the version it
is read at (`base`, `head`, `now`, or a commit).
_Avoid_: place, range, region

**Hunk**:
A run of lines a diff changed, with its old and new lines.

**Anchor**:
Lines you picked in the code, as a note of yours is started on them:
their file, first and last line, and version.

**Version**:
One form of a chunk's code: as it is, as it was, or as the agent
proposes.

**Suggestion**:
A note proposing a change; later, a version of a chunk to apply, take
back or decline.

## State

**Accepted**:
A chunk you have gone over, for its code as it is now. A change to the
code brings it back.

**Whose move**:
Whether a conversation waits on you or on the agent, from its last
message. Nobody's when only the agent has spoken, or its note is
settled.

**Settled**:
A note with a status other than `open`.

**Read**:
A message of the agent's you have seen.

**Walked**:
A step you have been to.

## In the prose

**Prose**:
Text the agent writes, with its diagrams by name: a review's
introduction, a briefing, a step's text, a contract's page, a message.
`{{chunk:id}}` alone on a line puts an excerpt there, `{{diagram:name}}`
a diagram.

**Excerpt**:
A chunk's code pulled live into prose.
_Avoid_: snippet

**Link**:
`#step:7`, `#note:12`, `#contract:3`, or another review's
`review-id#note:2`: goes to that conversation.

**Name**:
A name in backticks that may point at code, found where it is defined.

**Example**:
A worked case through the code: what goes in, the lines it runs, what
comes out.
_Avoid_: scenario

**Comparison**:
Versions of a chunk, or several chunks, shown side by side, inline or in
turn.

**Diagram**:
A flow, a sequence or a call tree, its boxes on chunks.

## On screen

**Home**:
The full-screen list of reviews.

**Overview**:
A review on the screen: its introduction, its contracts, its tours and
its notes, its files beside.

**Bubble**:
A note drawn in the code above its first line.

**Card**:
A step drawn in the code above its chunk.

**Zone**:
The lines a note or a step covers; keys there act on it.

**Sheet**:
What a screen is built into before it is written to its buffer: lines,
highlights, marks, and who owns each line.
