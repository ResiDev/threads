# Tours that walk seam

Status: an idea, 2026-11-02. Nothing built, nothing mocked.

## The idea

Tours are the most useful thing thread has found: a card on the lines it
talks about, one claim a step, walked at your own pace in your own
editor. So keep the tour and widen where a step can stand.

Today a step, a note and an excerpt each point at a **place**, and the
only kind of place is a chunk: lines of a file. Add a second kind, a
**seam place**: a name, the seam view to show it in (its code, its
types, its map), and what is opened or lit there. A tour then walks
places of either kind, and nothing else about tours changes.

Seam keeps to facts from the LSP and treesitter. The agent's words stay
in thread and are drawn beside seam's facts, never inside its model, so
what was checked and what is claimed never mix.

## The place

```ts
type Place = ChunkId | SeamPlace;

interface SeamPlace {
  /** The name, and where it is, as seam resolves it. */
  name: Line;
  file: Line;
  line: number;
  view: "code" | "types" | "map";
  /** Types opened and names lit: what the step needs seen. */
  open?: Line[];
}
```

A step's `chunk` becomes a `place`. A note can stand on one too.

## How a step is drawn

- **On a chunk**: as today, a card above its lines in your file.
- **On seam's code**: a card above the line in seam's copy of the code,
  at the row seam drew that file line on. To mock.
- **On types and on the map**: no line to sit on, so the step is a
  **footer** on the page. Two footers: the step's, which stays while you
  move, and seam's own foot, which tells what is under the cursor.

`L` and `H` drive seam: each step goes to its name in its view, as `J`
does, with what it opens opened. `gb` goes back to where you were before
the walk took you there.

## What falls out of it

- **Asking from seam**: a note started on a seam place, a key away
  wherever seam shows a name, as a note on a line is today. The answer
  can be a step on that same place, put into the tour where you asked.
- **Detours**: mini-tours placed in a step's text, as prose places them
  today.
- **Paths seam works out** (a value's uses, a function's callers): a way
  for the agent to choose places, not part of the format.

## What seam needs to give

- An entry taking a name, a file, a line and a view, split from
  `here()`, which reads the cursor (also in `threads.md`).
- The row its code copy draws a file line on.
- Room for a second footer on the Types and Map pages, and a way for
  thread to fill it. The code screen has no foot (decided 2026-11-02),
  so steps there use the card.

`show.lua --check` resolves a seam place through seam's index, and warns
when seam is not there to.

## Later

- **Claims checked live**: a step carries a treesitter or seam query,
  run each time it is drawn, and says when its claim no longer holds.

## Open

- The two footers: which sits above, how tall each is, and what the
  step's shows (its title, its text, a key to reply).
- How a footer says which thing on the page it is about: lighting what
  its `open` names may be enough.
- A review with seam places read where seam is not installed, or on a
  repo it does not cover (thread's own Lua): the place drawn as its file
  and line, as a chunk.
- Mocks to make, on a real TypeScript repo: a tour of four steps, one
  each on your file, seam's code, a type and the map; and a note asked
  from seam, answered as a step.
