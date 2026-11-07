# Keys

Which key does what, on every surface. A few keys mean the same thing
wherever they are; a new surface uses them for those things and nothing
else, and finds other keys for what is its own.

## The keys every surface shares

| Key         | Means                                                         |
| ----------- | ------------------------------------------------------------- |
| `j` / `k`   | down / up an item: a topic, a tour, a step, a thread, a contract, a chunk |
| `J` / `K`   | down / up a level: into what is under the cursor, back out    |
| `⏎`         | the same as `J`                                               |
| `L` / `H`   | sideways: the next / previous tab of a topic, thread, contract, or step in a walk |
| `Tab`       | fold or unfold what you are looking at                        |
| `o`         | open an item to read it line by line; `o` again closes it      |
| `q`         | close the surface; `Esc` too, or back out of what it is doing |

- **`j` and `k` move by items, not lines.** Lines are for reading, which
  `o` lets you into; there `j` and `k` are the editor's again.
- **`J` goes down, `K` goes up.** Never a walk, a section or anything else.
  `-` and `<BS>` also go up on the screen, for those used to them.
- **`L` and `H` stay at the same level.** From a topic's tab to the
  next tab, from a thread to the next thread, from a step to the next step;
  never in or out. A walk's briefing is the step before the first.
- **`Tab` folds, `o` reads.** `Tab` changes how much of the whole view
  is shown and leaves the cursor where it was; `o` shows one item whole
  and lets the cursor in.
- **`h` and `l` are the editor's.** Sideways is `H` and `L` for now; `h`
  and `l` could become it if `H` and `L` are needed for something else.

## The screen

Home, a topic, and a thread's, a contract's or a step's page: one window
at its depths. A topic is up to four tabs, Overview, Contracts, Tours
and Threads, named along the top row (Contracts and Tours only when it has
some, so a topic of threads is Overview and Threads); the bottom row lists the keys of the
one shown. ⏎ on a tour's row on Tours opens its briefing, a page of
Tours (`Tours › 1` along the top), the files beside it as Tours has
them, `H`/`L` the tour before and after, `t` walking it; while you walk,
the briefing is the screen in a float. ⏎ on a contract opens its page, a
page of Contracts (`Contracts › 3` along the top), the files beside it
as Contracts has them down to its callers: `j`/`k` go through those, and
the code of the one under the cursor shows beside the list, across the
page, or under its row below 120 columns; ⏎ on
a caller or on its head goes to that code, `o` on its change reads it
whole. ⏎ on a thread opens its page, a page of Threads (`Threads › 8` along
the top), its head as Threads draws its row: what it says, its
conversation, then the function its code is in, `n` on a line of it a
thread there, and the contracts that code touches as Contracts lists
them, the one under the cursor opened; `H`/`L` go through the topic's
threads in its order. On Contracts and Threads the item under the cursor opens under its
row: a contract as it was and as it is, a thread's last messages. Looking
at a thread does not read it, `⏎` or `r` does.

| Key         | Where                | Does                                                      |
| ----------- | -------------------- | --------------------------------------------------------- |
| `j` / `k`   | everywhere           | the next / previous item; with none, as on a topic's Overview, a line; on a contract's page, its parts and each caller; in prose, each section, each excerpt, tour or contract placed, and the text going on after one |
| `}` / `{`   | everywhere           | the next / previous section: a topic, a tour, a section of a topic's Threads; on a contract's page, its change, its prose, its callers, each message |
| `w` / `b`   | everywhere           | the next / previous link or name in backticks, as between words; reading, the editor's |
| `J` / `⏎`   | everywhere           | down a level into what is under the cursor: a thread's or a contract's page, a tour's briefing on Tours, a tour or a step to walk |
| `K` / `-`   | below Home           | up a level: a page to its topic, a briefing to Tours, a topic to Home |
| `Tab`       | Home                 | each topic shows the first three of what wants you, which `j` passes (the default); then all, which `j` goes through; then none |
| `Tab`       | anywhere             | on a tour placed in prose, it: its title, steps and files alone (the default), then its steps' titles, then each step's text and where it is, then their code inline; on a contract placed in prose, it: as it is, what changed marked (the default), then against as it was, then one row; one added or removed, as it is, then one row |
| `Tab`       | a contract's page    | the next view of its change and its callers' code, round: split (the default), side, as it is (a bar in the margin where a line changed or was added, nothing washed); kept from one contract to the next. One added or removed shows its one side in each |
| `o`         | below Home           | open the item and read it line by line                    |
| `L` / `H`   | a topic             | the next / previous tab, round from Threads to Overview and back |
| `L` / `H`   | a page               | the next / previous thread, contract, tour's briefing or step; over the code, walking, `L` from a briefing into its first step |
| `r`         | a page, a topic     | reply in the conversation under the cursor, or the page's |
| `e`         | a page               | edit your message under the cursor, where it is: one the agent has not answered yet |
| `d`         | a page               | delete your message under the cursor, one not answered yet, into the unnamed register; a thread's text, the thread, asked first |
| `a`         | a thread, a topic     | accept the thread: the code it is on, as it reads now; its head, or on Threads the line under its row, says `✓ accepted`. Steps and tours are walked, not accepted |
| `s`         | everywhere           | settle the thread, saying how by its kind, or open it again; on a topic's line, close the topic |
| `space`     | a topic             | mark a thread: then `r`, `a` and `s` act on each            |
| `n`         | below Home           | a new thread, on the line under the cursor or on none       |
| `t`         | a topic, a briefing | walk the tour, from its briefing or where you left off; on a contract, the first tour on its code, from its first step there |
| `t`         | a thread, a contract   | to a tour placed in its prose: from inside a message, its first; from a tour, the next, on down the page and round; `⏎` on its title walks it, `⏎` on a step walks from that step |
| `c`         | a thread, a contract   | to a contract placed in its prose, as `t` goes to a tour; `⏎` on it opens its page |
| `p`         | a topic, a briefing | a step's page                                             |
| `/`         | Home                 | only what mentions something                              |
| `C`         | Home                 | the closed topics; again, the open ones                  |
| `N`         | Home                 | a new topic                                              |
| `?`         | everywhere           | the help                                                  |
| `q` / `Esc` | everywhere           | close; reading, back to items; searching, clear it         |

## A walk

Set over your keys while a walk is on (config `walk`), and put back when
it ends. It opens on the tour's briefing. In the code, a step's
highlights, the names its text puts in backticks, are lit in its chunk;
none is current as a step opens. The dimming and the topic's diff are
on, each turned off and on again for the rest of the walk. Its bar shows
`L`/`H`, `gn` and `gs` when the step has highlights, `gz`, `<leader>hg`,
`g?` and `q`, `gz` as what it will do (`undim` while dimmed, else `dim`)
and the diff ticked while on, and the current highlight as
`2/4 next_id`; the step's card says `go` too; `g?` lists every key. On a
step whose lines the diff removed, the diff stays drawn turned off: both
say `diff kept`.

| Key       | Does                                                  |
| --------- | ----------------------------------------------------- |
| `L` / `H` | the next / previous step; `L` from the briefing into step 1, `H` from step 1 back to it |
| `B`       | the tour's briefing, from any step                    |
| `gn` / `gN` | in the code, the next / previous highlight made current: lit, its lines washed, its sentence lit in the text, the cursor on it; past the last, or before the first, none. `3gn` the third; elsewhere, Vim's own |
| `gs`      | in the code, pick a highlight: each one's number laid over its first letter, 1 to 9, and after its name in the step's card; a digit makes that one current, any other key leaves it as it was |
| `gz`      | dim: the code but the step's chunk dimmed, off or on   |
| `<leader>hg` | the topic's diff drawn in, off or on; a step on lines it removed keeps it, and says so |
| `go`      | into the step's card, a float over it (below)         |
| `gw`      | into the card, on its first link                      |
| `U`       | up: back to the topic's screen                       |
| `g?`      | every key a walk has, in a float                      |
| `r`       | reply in the step                                     |
| `M`       | the tour's outline                                    |
| `q`       | stop walking; a walk started from a thread or a contract, back on it |

`J` and `K` are never the walk's: in the code they stay yours (`K` is
your hover), and on its float they are the screen's, `K` up to the
topic.

### In a card, gone into

The float `go` lays over a step's card, or a thread's bubble, drawn whole
while you are in it: a walked step's card otherwise shows its text and as
much of its conversation as fits in 12 rows, and whose move it is.
Leaving it, the walk moving on, or the topic changing closes it, and it
folds back.

| Key             | Does                                              |
| --------------- | ------------------------------------------------- |
| `j` / `k`       | the next / previous part: its text, a message, a thread on its chunk; the one you are in lit |
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

On the lines a thread or a step is on (config `zone`); on any other line,
what they always do.

| Key       | Does                                                 |
| --------- | ---------------------------------------------------- |
| `⏎`       | the thread's or the step's page, over the code         |
| `gp`      | the same, for where another plugin has `⏎`; inside a bubble or card too |
| `go`      | into the thread's bubble, a float over it: `w` / `b` between its links, `⏎` follows one, `r` / `e` / `d` reply, edit, delete, `q` out; walking, the step's |
| `L` / `H` | on a thread, the next / previous thread of its topic in the code, its bubble open; on a step, yours (a walk has its own) |
| `Tab`     | a bubble or card cut short shows whole, every message uncut; then closes to its sign; then opens cut short again. One with nothing cut closes |
| `S-Tab`   | where cards stack on one line, the next on top       |

A thread's bubble is framed in yellow, a step's in blue, so the two are
never taken for each other. Its head is the thread's kind and its title,
whole. In the sign column a thread is a yellow bracket down its lines,
`┏ ┃ ┗` (`╺` on one line); a step its number on its first line, in the
light blue of tours, then a hairline that closes the same way, `│ └`.

Anywhere in the code (config `mappings`): `]h` / `[h` the next / previous
thread or step that wants you, `]H` / `[H` any with a conversation, and the
`<leader>h` commands.

## Back and forward

Anywhere, on the screen, walking or in the code (config `mappings`), as
a browser goes back. Each time a key or a link takes you elsewhere, from
one place on the screen to another, from the screen to the code or back,
into a walk or out of it, or `]h` and a thread's `L`/`H` in the code,
where you were is kept. Going from step to step in a walk is not: the
walk is kept at the step you leave it on.

| Key  | Does                                                           |
| ---- | -------------------------------------------------------------- |
| `gb` | back to where you were: a place on the screen, the row the cursor was on, over the code it was over; a walk, on its step, walking again; a line of code. `3gb` three back |
| `gi` | forward again, after `gb`. With nowhere ahead, or once you start writing, the editor's own `gi` |

## The map and compose

- **The map:** a letter jumps to its thread or step, `⏎` opens it, `q`
  or `Esc` closes.
- **Compose:** a reply is written in place, under the conversation's
  last message, on the screen or in a card in the code; an edit over the
  message itself; with neither on screen, in a float. `C-s`, or
  `⏎` in normal mode, sends; `q` or `Esc` in normal mode closes and drops
  what you wrote; `:q` sends.
