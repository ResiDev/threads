# thread.nvim

Code reviews by an agent, read and answered in Neovim. The agent writes a
review of a change, or of how some code works, and you read it next to
the code and talk back to it point by point.

- **The introduction** gives the big picture, with a diagram where the
  change has a shape.
- **Contracts** are what other code relies on that the change touched: a
  signature, a format, a behaviour. Each has a page with the contract as
  a diff of its two sides and its blast radius: the code that depends on
  it, and how far the change reached each.
- **Tours** walk the change a part at a time. Each opens on a briefing;
  then each step is a card above its code, and `L`/`H` go from one to
  the next.
- **Notes** are everything else, on a line or on none: issues, decisions,
  questions, suggestions, fixes, comments. Each kind has its own
  statuses, and you settle them as you go.
- Every step, note and contract has its own conversation. A note of
  yours on any line goes to the agent, and its answer comes back there.

`DESIGN.md` has the whole idea, `design/format.ts` the format the agent
writes, `KEYS.md` every key.

## Install

```lua
{
  dir = '~/path/to/thread.nvim',
  event = 'VeryLazy',
  cmd = 'Thread',
  opts = {},
}
```

The agent's half is the `answering-threads` skill in `skills/`. Link it
where your agent looks for skills, then ask it for a review, or to
"answer my threads".

## Using it

| Key | |
| --- | --- |
| `<leader>hh` | Home: every review |
| `<leader>hc` | start a note on the line, or the selected lines |
| `<leader>ha` | ask about no line in particular |
| `⏎` on a note's or a step's lines | its page, over the code |
| `Tab` on its lines | fold its card to one line, or show it whole |
| `S-Tab` where cards stack | the next card on that line |
| `<leader>hr` / `<leader>hd` | reply / settle the note |
| `<leader>hw` | walk from the step here |
| `L` `H` `J` `K` `B` `r` `M` `q` while walking | next step, previous step, next tour, previous tour, the briefing, reply, the tour's outline, end the walk |
| `<leader>hq` | stop walking |
| `<leader>hm` | the map: the notes on lines, or while walking the walk |
| `<leader>hg` | draw the review's diff into the code |
| `<leader>ht` / `<leader>hx` | bubbles or one line each / hide them |
| `]h` `[h` | next / previous note or step that wants you (`]H` `[H` any) |

`:Thread` takes the same as subcommands. On the screen, `j`/`k` go from
item to item, `⏎` goes into one, `K` back out, `Tab` folds, `r` replies,
`a` accepts, `c` settles, and `?` lists every key.

## Development

```sh
make check   # unit tests, the surfaces as text, and the lint
```
