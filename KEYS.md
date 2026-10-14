# Keys

Which key does what, on every surface. A few keys mean the same thing
wherever they are; a new surface uses them for those things and nothing
else, and finds other keys for what is its own.

## The keys every surface shares

| Key         | Means                                                         |
| ----------- | ------------------------------------------------------------- |
| `j` / `k`   | down / up an item: a review, a thread, a step, a file, a chunk |
| `J` / `K`   | down / up a level: into what is under the cursor, back out    |
| `⏎`         | the same as `J`                                               |
| `L` / `H`   | sideways: the next / previous thread, or step in a walk       |
| `Tab`       | fold or unfold what you are looking at                        |
| `o`         | open an item to read it line by line; `o` again closes it      |
| `q`         | close the surface; `Esc` too, or back out of what it is doing |

- **`j` and `k` move by items, not lines.** Lines are for reading, which
  `o` lets you into; there `j` and `k` are the editor's again.
- **`J` goes down, `K` goes up.** Never a walk, a section or anything else.
  `-` and `<BS>` also go up on the screen, for those used to them.
- **`L` and `H` stay at the same level.** From a thread to the next
  thread, from a step to the next step; never in or out.
- **`Tab` folds, `o` reads.** `Tab` changes how much of the whole view
  is shown and leaves the cursor where it was; `o` shows one item whole
  and lets the cursor in.
- **`h` and `l` are the editor's.** Sideways is `H` and `L` for now; `h`
  and `l` could become it if `H` and `L` are needed for something else.

## The screen

Home, a review, a thread and a step: one window at four depths.

| Key         | Where                | Does                                                      |
| ----------- | -------------------- | --------------------------------------------------------- |
| `j` / `k`   | everywhere           | the next / previous item                                  |
| `}` / `{`   | everywhere           | the next / previous section: a review, a tour, a file     |
| `J` / `⏎`   | everywhere           | down a level into what is under the cursor                |
| `K` / `-`   | below Home           | up a level                                                |
| `Tab`       | Home                 | each review shows its first three threads, which `j` passes (the default); then all, which `j` goes through; then none |
| `Tab`       | a review             | on a group's heading, that group: a tree, each thread with its files (the default), or a card, a row a thread (always a card with the files beside it); on a contract, every contract or the first few; elsewhere, every group, and the introduction |
| `Tab`       | a thread             | on a tour, that tour: a row (the default) or a tree of its steps with their code; on the tours' rule, every tour; on a contract, every contract or the first few; on a message, fold or unfold every message; on a step, a chunk or a file, show or hide every chunk's code |
| `o`         | below Home           | open the item and read it line by line                    |
| `L` / `H`   | a thread, a step     | the next / previous thread; in a step's page, step        |
| `f`         | a review, a thread   | its chunks by file, or by thread again                    |
| `r`         | everywhere           | reply in the conversation under the cursor                |
| `a`         | everywhere           | accept the chunk; on a thread's head, all of them         |
| `c`         | everywhere           | close the thread you are in, wherever in it, or the review on its line; or open it again |
| `space`     | Home, a review       | mark a thread: then `r`, `a` and `c` act on each          |
| `n`         | below Home           | a new thread, on the line under the cursor or on none      |
| `w`         | all but a step       | walk the thread's tour in the code                        |
| `p`         | a thread             | a step's page                                             |
| `/`         | Home                 | only what mentions something                              |
| `C`         | Home                 | the closed reviews; again, the open ones                  |
| `N`         | Home                 | a new review                                              |
| `?`         | everywhere           | the help                                                  |
| `q` / `Esc` | everywhere           | close; reading, back to items; searching, clear it         |

## A walk

Set over your keys while a walk is on (config `walk`), and put back when
it ends.

| Key       | Does                                   |
| --------- | -------------------------------------- |
| `L` / `H` | the next / previous step               |
| `K`       | up: in a review, back to its screen    |
| `r`       | reply in the step                      |
| `M`       | the tour's outline                     |
| `q`       | stop walking                           |

## The code

On the line a thread is on (config `zone`); on any other line, what they
always do.

| Key       | Does                                                 |
| --------- | ---------------------------------------------------- |
| `⏎`       | focus the thread: the screen, over the code          |
| `Tab`     | fold its card to one line, or unfold it whole        |
| `S-Tab`   | where cards stack on one line, the next on top       |

Anywhere in the code (config `mappings`): `]h` / `[h` the next / previous
thread that wants you, `]H` / `[H` any open one, and the `<leader>h`
commands.

## The map and compose

- **The map:** a letter jumps to its thread or step, `⏎` opens it, `q`
  or `Esc` closes.
- **Compose:** `C-s`, or `⏎` in normal mode, sends; `q` or `Esc` in
  normal mode closes and drops what you wrote; `:q` sends.
