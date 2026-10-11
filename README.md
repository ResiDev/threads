# thread.nvim

Threads on your code, answered by an agent. A prototype that combines
comments.nvim and tour.nvim around one primitive: **the thread**.

- Start a thread on a line, or ask a question about no line at all.
- The agent answers in the thread. When the answer needs more than one
  place, it **leads to a tour**: stage by stage and step by step, that you
  walk with `L`/`H` and end with `q`.
- Reply in any stop of a tour and it becomes a thread of its own, right
  where it is.
- Home shows every conversation, every tour, and the review of a diff.

`DESIGN.md` has the whole idea: the model, walking, the file format, and
the decisions.

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
where your agent looks for skills, then ask it to "answer my threads".

## Using it

| Key | |
| --- | --- |
| `<leader>hc` | start a thread on the line, or the selected lines |
| `<leader>ha` | ask about no line in particular |
| `<leader>hh` | Home |
| `⏎` on a thread's lines | focus it: the thread in a centred float |
| `+` / `-` on its lines | more or less of it |
| `<leader>hr` / `<leader>hd` | reply / close |
| `<leader>hw` | walk the tour the thread's answer leads to, or the one it is in |
| `L` `H` `q` while walking | next stop, previous stop, end the walk |
| `⏎` on a card | open it: a stop as its page, a thread in the float; reply there with `r` |
| `<leader>hq` | stop walking |
| `<leader>hm` | the map: the batch, or while walking the walk |
| `<leader>hz` | dim everything but the thread you are on |
| `<leader>hg` | draw the thread's changes into the code |
| `<leader>ht` / `<leader>hx` | bubbles or one line each / hide them |
| `]h` `[h` | next / previous thread that is your move (`]H` `[H` any) |
| `<leader>hb` | every batch |

`:Thread` takes the same as subcommands, plus `import <tour>` to read a
tour.nvim `.tour` file in as threads.

In Home, `1`–`6` and `0` switch tabs: inbox, yours, the agent's, tours,
review, closed, all. `?` lists every key.

## Development

```sh
make check   # unit tests and the end-to-end smoke test
```
