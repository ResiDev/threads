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
| `}` / `{`   | everywhere           | the next / previous section: a review, a tour, a kind of note |
| `w` / `b`   | everywhere           | the next / previous link or name in backticks, as between words; reading, the editor's |
| `J` / `⏎`   | everywhere           | down a level into what is under the cursor: a note's or a contract's page, a tour or a step to walk |
| `K` / `-`   | below Home           | up a level: a page to its review, a review to Home        |
| `Tab`       | Home                 | each review shows the first three of what wants you, which `j` passes (the default); then all, which `j` goes through; then none |
| `Tab`       | a review             | on a tour, that tour: a row (the default) or its briefing and a tree of its steps; on the tours' rule, every tour; on a contract, every contract or the first few; on a kind of note, its settled notes; on a step, a chunk or a file, every chunk's code; elsewhere, the introduction |
| `Tab`       | anywhere             | on a tour placed in prose, it: its steps' titles alone (the default), then each step's text and where it is, then their code inline; on a contract placed in prose, it: as it is, what changed marked (the default), then against as it was, then one row; one added or removed, as it is, then one row |
| `Tab`       | a contract's page    | on its head or the contract itself, one changed: show or hide it against as it was |
| `o`         | below Home           | open the item and read it line by line                    |
| `L` / `H`   | a page               | the next / previous note, contract or step; from a briefing, its first step |
| `r`         | a page, a review     | reply in the conversation under the cursor, or the page's |
| `e`         | a page               | edit your message under the cursor, where it is: one the agent has not answered yet |
| `d`         | a page               | delete your message under the cursor, one not answered yet, into the unnamed register; a note's text, the note, asked first |
| `a`         | a note, a review     | accept the note: the code it is on, as it reads now; its head says `✓ accepted`. Steps and tours are walked, not accepted |
| `s`         | everywhere           | settle the note, saying how by its kind, or open it again; on a review's line, close the review |
| `space`     | a review             | mark a note: then `r`, `a` and `s` act on each            |
| `n`         | below Home           | a new note, on the line under the cursor or on none       |
| `t`         | a review, a briefing | walk the tour, from its briefing or where you left off    |
| `t`         | a note, a contract   | to a tour placed in its prose: from inside a message, its first; from a tour, the next, on down the page and round; `⏎` on its title walks it, `⏎` on a step walks from that step |
| `c`         | a note, a contract   | to a contract placed in its prose, as `t` goes to a tour; `⏎` on it opens its page |
| `p`         | a review, a briefing | a step's page                                             |
| `/`         | Home                 | only what mentions something                              |
| `C`         | Home                 | the closed reviews; again, the open ones                  |
| `N`         | Home                 | a new review                                              |
| `?`         | everywhere           | the help                                                  |
| `q` / `Esc` | everywhere           | close; reading, back to items; searching, clear it         |

## A walk

Set over your keys while a walk is on (config `walk`), and put back when
it ends. It opens on the tour's briefing. In the code, the names a step's
text puts in backticks are lit in its chunk; the dimming and the review's diff
are on, each turned off and on again for the rest of the walk. Its bar
shows `L`/`H`, `gz`, `<leader>hg`, `g?` and `q`, `gz` as what it will do
(`undim` while dimmed, else `dim`) and the diff ticked while on,
and the step's card `go` too; `g?` lists every key. On a step whose lines
the diff removed, the diff stays drawn turned off: both say `diff kept`.

| Key       | Does                                                  |
| --------- | ----------------------------------------------------- |
| `L` / `H` | the next / previous step; `L` from the briefing into step 1, `H` from step 1 back to it |
| `B`       | the tour's briefing, from any step                    |
| `gz`      | dim: the code but the step's chunk dimmed, off or on   |
| `<leader>hg` | the review's diff drawn in, off or on; a step on lines it removed keeps it, and says so |
| `go`      | into the step's card, a float over it (below)         |
| `gw`      | into the card, on its first link                      |
| `U`       | up: back to the review's screen                       |
| `g?`      | every key a walk has, in a float                      |
| `r`       | reply in the step                                     |
| `M`       | the tour's outline                                    |
| `q`       | stop walking; a walk started from a note or a contract, back on it |

`J` and `K` are never the walk's: in the code they stay yours (`K` is
your hover), and on its float they are the screen's, `K` up to the
review.

### In a card, gone into

The float `go` lays over a step's card, or a note's bubble, drawn whole
while you are in it: a walked step's card otherwise shows its text and as
much of its conversation as fits in 12 rows, and whose move it is.
Leaving it, the walk moving on, or the review changing closes it, and it
folds back.

| Key             | Does                                              |
| --------------- | ------------------------------------------------- |
| `j` / `k`       | the next / previous part: its text, a message, a note on its chunk; the one you are in lit |
| `w` / `b`       | the next / previous link, or name in backticks    |
| `⏎`             | follow the one under the cursor                   |
| `gw`            | the next link                                     |
| `r`             | reply, written in the card under its last message |
| `e`             | edit your message under the cursor, over itself: one the agent has not answered yet |
| `d`             | delete it, into the unnamed register              |

Its bottom edge says `e/d` only while the cursor is on a message of yours
it can edit or delete.
| `q` / `Esc` / `go` | out, back to the code where you were           |

## The code

On the lines a note or a step is on (config `zone`); on any other line,
what they always do.

| Key       | Does                                                 |
| --------- | ---------------------------------------------------- |
| `⏎`       | the note's or the step's page, over the code         |
| `gp`      | the same, for where another plugin has `⏎`; inside a bubble or card too |
| `go`      | into the note's bubble, a float over it: `w` / `b` between its links, `⏎` follows one, `r` / `e` / `d` reply, edit, delete, `q` out; walking, the step's |
| `L` / `H` | on a note, the next / previous note of its review in the code, its bubble open; on a step, yours (a walk has its own) |
| `Tab`     | a bubble or card cut short shows whole, every message uncut; then closes to its sign; then opens cut short again. One with nothing cut closes |
| `S-Tab`   | where cards stack on one line, the next on top       |

A note's bubble is framed in yellow, a step's in blue, so the two are
never taken for each other. Its head is the note's kind and its title,
whole. In the sign column a note is a yellow bracket down its lines,
`┏ ┃ ┗` (`╺` on one line); a step its number on its first line, in the
light blue of tours, then a hairline that closes the same way, `│ └`.

Anywhere in the code (config `mappings`): `]h` / `[h` the next / previous
note or step that wants you, `]H` / `[H` any with a conversation, and the
`<leader>h` commands.

## The map and compose

- **The map:** a letter jumps to its note or step, `⏎` opens it, `q`
  or `Esc` closes.
- **Compose:** a reply is written in place, under the conversation's
  last message, on the screen or in a card in the code; an edit over the
  message itself; with neither on screen, in a float. `C-s`, or
  `⏎` in normal mode, sends; `q` or `Esc` in normal mode closes and drops
  what you wrote; `:q` sends.
