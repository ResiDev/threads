# thread.nvim

Code reviews and explanations by an agent, read and answered in Neovim
a point at a time. The agent writes a topic, a review of a change or how
some code works, as threads, and you read each next to the code and
talk back to it.

- **The introduction** gives the big picture, with a diagram where the
  change has a shape.
- **Contracts** are what other code relies on that the change touched: a
  signature, a format, a behaviour. Each has a page with the contract as
  it is, what changed marked (Tab sets it against as it was), and its
  blast radius: the code that depends on it, and how far the change
  reached each.
- **Tours** walk the change a part at a time. Each opens on a briefing;
  then each step is a card above its code, and `L`/`H` go from one to
  the next.
- **Threads** are everything else, on a line or on none: issues, decisions,
  questions, suggestions, fixes, comments. Each kind has its own
  statuses, and you settle them as you go.
- Every step, thread and contract has its own conversation. A thread of
  yours on any line goes to the agent, and its answer comes back there.

`design/format.ts` is the format the agent writes, `DIRECTION.md` where
it is going, `KEYS.md` every key.

## Install

```lua
{
  dir = '~/path/to/thread.nvim',
  event = 'VeryLazy',
  cmd = 'Thread',
  opts = {},
}
```

The agent's half is the `threads` skill in `skills/`. Link it
where your agent looks for skills, then type `/threads` and ask it for
a topic, or to answer your threads. It loads only when you type it.

## Using it

| Key | |
| --- | --- |
| `<leader>hh` | Home: every topic |
| `<leader>hc` | start a thread on the line, or the selected lines |
| `<leader>ha` | ask about no line in particular |
| `⏎` on a thread's or a step's lines | its page, over the code |
| `Tab` on its lines | close it to its sign, or open it again |
| `S-Tab` where cards stack | the next card on that line |
| `<leader>hr` / `<leader>hd` | reply / settle the thread |
| `<leader>hw` | walk from the step here |
| `L` `H` `B` `r` `M` `U` `q` while walking | next step, previous step, the briefing, reply, the tour's outline, back to the topic, end the walk |
| `gz` `go` `gw` `g?` while walking | dim all but the step's chunk, into the step's card, into it on its first link, every key a walk has |
| `<leader>hq` | stop walking |
| `<leader>hm` | the map: the threads on lines, or while walking the walk |
| `<leader>hg` | draw the topic's diff into the code, or stop |
| `<leader>ht` / `<leader>hx` | every thread open, and the walk's tour, or only what you are on / hide them |
| `]h` `[h` | next / previous thread or step that wants you (`]H` `[H` any) |
| `gb` / `gi` | back to where you were before thread took you elsewhere / forward again |

`:Thread` takes the same as subcommands. On the screen, `j`/`k` go from
item to item, `⏎` goes into one, `K` back out, `Tab` folds, `r` replies,
`a` accepts, `s` settles, and `?` lists every key.

## Development

```sh
make check   # unit tests, the surfaces as text, and the lint
```
