# Keys

Which key does what, on every surface. A few keys mean the same thing
wherever they are; a new surface uses them for those things and nothing
else, and finds other keys for what is its own.

## The keys every surface shares

| Key         | Means                                                         |
| ----------- | ------------------------------------------------------------- |
| `j` / `k`   | down / up an item: a review, a tour, a step, a note, a file, a chunk |
| `J` / `K`   | down / up a level: into what is under the cursor, back out    |
| `⏎`         | the same as `J`                                               |
| `L` / `H`   | sideways: the next / previous note, contract, or step in a walk |
| `Tab`       | fold or unfold what you are looking at                        |
| `o`         | open an item to read it line by line; `o` again closes it      |
| `q`         | close the surface; `Esc` too, or back out of what it is doing |

- **`j` and `k` move by items, not lines.** Lines are for reading, which
  `o` lets you into; there `j` and `k` are the editor's again.
- **`J` goes down, `K` goes up.** Never a walk, a section or anything else.
  `-` and `<BS>` also go up on the screen, for those used to them.
- **`L` and `H` stay at the same level.** From a note to the next note,
  from a step to the next step; never in or out. A walk's briefing is
  the step before the first.
- **`Tab` folds, `o` reads.** `Tab` changes how much of the whole view
  is shown and leaves the cursor where it was; `o` shows one item whole
  and lets the cursor in.
- **`h` and `l` are the editor's.** Sideways is `H` and `L` for now; `h`
  and `l` could become it if `H` and `L` are needed for something else.

## The screen

Home, a review, and a note's, a contract's or a step's page: one window
at its depths. A tour's briefing is the screen too, in a float, while
you walk. ⏎ on a contract opens its page; ⏎ on its head there goes to
its code.

| Key         | Where                | Does                                                      |
| ----------- | -------------------- | --------------------------------------------------------- |
| `j` / `k`   | everywhere           | the next / previous item                                  |
| `}` / `{`   | everywhere           | the next / previous section: a review, a tour, a kind of note, a file |
| `w` / `b`   | everywhere           | the next / previous link or name in backticks, as between words; reading, the editor's |
| `J` / `⏎`   | everywhere           | down a level into what is under the cursor: a note's or a contract's page, a tour or a step to walk |
| `K` / `-`   | below Home           | up a level: a page to its review, a review to Home        |
| `Tab`       | Home                 | each review shows the first three of what wants you, which `j` passes (the default); then all, which `j` goes through; then none |
| `Tab`       | a review             | on a tour, that tour: a row (the default) or its briefing and a tree of its steps; on the tours' rule, every tour; on a contract, every contract or the first few; on a kind of note, its settled notes; on a step, a chunk or a file, every chunk's code; elsewhere, the introduction |
| `o`         | below Home           | open the item and read it line by line                    |
| `L` / `H`   | a page               | the next / previous note, contract or step; from a briefing, its first step |
| `f`         | a review             | its chunks by file, or by tour and note again             |
| `r`         | a page, a review     | reply in the conversation under the cursor, or the page's |
| `a`         | everywhere           | accept the chunk; on a tour, every step's                 |
| `c`         | everywhere           | settle the note, saying how by its kind, or open it again; on a review's line, close the review |
| `space`     | a review             | mark a note: then `r`, `a` and `c` act on each            |
| `n`         | below Home           | a new note, on the line under the cursor or on none       |
| `t`         | a review, a briefing | walk the tour, from its briefing or where you left off    |
| `p`         | a review, a briefing | a step's page                                             |
| `/`         | Home                 | only what mentions something                              |
| `C`         | Home                 | the closed reviews; again, the open ones                  |
| `N`         | Home                 | a new review                                              |
| `?`         | everywhere           | the help                                                  |
| `q` / `Esc` | everywhere           | close; reading, back to items; searching, clear it         |

## A walk

Set over your keys while a walk is on (config `walk`), and put back when
it ends. It opens on the tour's briefing. In the code, the names a step's
text puts in backticks are lit in its chunk; focus and the review's diff
are on, each turned off and on again for the rest of the walk. Its bar
shows `L`/`H`, `gz`, `<leader>hg`, `U` and `q`, ticked while on; the rest
work without being shown.

| Key       | Does                                                  |
| --------- | ----------------------------------------------------- |
| `L` / `H` | the next / previous step; `L` from the briefing into step 1, `H` from step 1 back to it |
| `B`       | the tour's briefing, from any step                    |
| `gz`      | focus: the code but the step's chunk dimmed, off or on |
| `<leader>hg` | the review's diff drawn in, off or on; a step on lines it removed keeps it |
| `U`       | up: back to the review's screen                       |
| `r`       | reply in the step                                     |
| `M`       | the tour's outline                                    |
| `q`       | stop walking                                          |

`J` and `K` are never the walk's: in the code they stay yours (`K` is
your hover), and on its float they are the screen's, `K` up to the
review.

## The code

On the lines a note or a step is on (config `zone`); on any other line,
what they always do.

| Key       | Does                                                 |
| --------- | ---------------------------------------------------- |
| `⏎`       | the note's or the step's page, over the code         |
| `Tab`     | fold its card to one line, or unfold it whole        |
| `S-Tab`   | where cards stack on one line, the next on top       |

Anywhere in the code (config `mappings`): `]h` / `[h` the next / previous
note or step that wants you, `]H` / `[H` any with a conversation, and the
`<leader>h` commands.

## The map and compose

- **The map:** a letter jumps to its note or step, `⏎` opens it, `q`
  or `Esc` closes.
- **Compose:** `C-s`, or `⏎` in normal mode, sends; `q` or `Esc` in
  normal mode closes and drops what you wrote; `:q` sends.
