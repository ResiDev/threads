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
`missed`) and what it had to do. A contract's page calls them its
callers, and shows each one's code as the change left it.

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
a diagram, `{{tour:2}}` a tour, `{{contract:3}}` a contract.

**Excerpt**:
A chunk's code pulled live into prose.
_Avoid_: snippet

**Link**:
`#step:7`, `#note:12`, `#contract:3`, or another review's
`review-id#note:2`: goes to that conversation.

**Name**:
A name in backticks that may point at code, found where it is defined.

**Highlight**:
A name a step's text puts in backticks that stands whole in the step's
chunk. Numbered in the order the text first names it, the number after
the name in the text and at the right of each line it is on. While
walking, one may be the current one: lit strongly, its lines washed, its
sentence in the text lit. Derived, never written.

**Example**:
A worked case through the code: what goes in, the lines it runs, what
comes out.
_Avoid_: scenario

**Comparison**:
Versions of a chunk, or several chunks, shown side by side, inline or in
turn.

**Diagram**:
A flow, a sequence or a call tree, its boxes on chunks.

**Unlisted tour**:
A tour with `"listed": false`: not a row in the review's tours, seen only
where prose places it, `{{tour:2}}`; a short walk that explains
something, three steps as a rule, the prose around it its briefing.
Tab turns it: its steps' titles, then their text with where each is,
then their code.
_Avoid_: inline tour

**Inline contract**:
One of the review's contracts drawn in prose, under a `── contract`
label. Tab turns it: as it is, what changed marked, then against as it
was, then one row. `c` goes to it, ⏎ opens its page.

**Fold**:
How much a tour or a contract placed in prose shows, which Tab turns through.

## On screen

**Place**:
Where the screen is: Home, one of a review's tabs, or a page under
them, a contract's, a note's, a step's or a tour's briefing. `K` goes
up from it: a tab to Home, a briefing to Tours, another page to the tab
it was opened from.
_Avoid_: depth

**Home**:
The full-screen list of reviews.

**Tab**:
One of the four ways a review is on the screen, Overview, Contracts,
Tours and Notes, which `H` and `L` go between.
_Avoid_: section

**View**:
How a contract's page shows its change and its callers' code, which Tab
cycles and the page keeps from one contract to the next: split, as it
was then as it is; side, the two beside each other; as it is, the new
form alone, a bar in the margin where a line changed (blue) or was added
(green).

**Overview**:
A review's first tab: its introduction, then the review at a glance, a
mark for each contract, step and note and what of them needs you.

**Files beside**:
A review's files down the right of Contracts and Tours, in a window wide
enough: where the contract under the cursor reaches, or which tours walk
each file.
_Avoid_: sidebar

**Bubble**:
A note drawn in the code above its first line.

**Card**:
A step drawn in the code above its chunk.

**Zone**:
The lines a note or a step covers; keys there act on it.

**Dim**:
While walking, the code but the step's chunk washed quiet, so the chunk
reads first.
_Avoid_: focus, which is a note opened over the code

**Sheet**:
What a screen is built into before it is written to its buffer: lines,
highlights, marks, and who owns each line.
