# thread.nvim

Threads on your code, answered by an agent. A prototype that combines
comments.nvim and tour.nvim around one primitive: **the thread**.

- Start a thread on a line, or ask a question about no line at all.
- The agent answers in the thread. When the answer needs more than one
  place, it **leads to a tour**: stage by stage and step by step, that you
  walk with `L`/`H` and end with `q`.
- Reply in any stop of a tour and it becomes a thread of its own, right
  where it is.
- Ask for a review and the agent groups a diff by what each change is for,
  explains each group once, and rates how risky it is. You read it on its
  own screen, accept or ask about each hunk or any line of one, removed
  lines too, and walk the hunks in the code with the removed lines drawn
  in. Ask for a fix there and the agent's change shows under its answer.
- Home shows every conversation, every tour, and every review.

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
| `Tab` on its lines | fold it to one line, or show it whole |
| `S-Tab` where cards stack | the next card on that line |
| `<leader>hr` / `<leader>hd` | reply / close |
| `<leader>hw` | walk the tour the thread's answer leads to, or the one it is in |
| `L` `H` `r` `M` `q` while walking | next stop, previous stop, reply in it, the whole tour, end the walk |
| `⏎` on a card | open it: a stop as its page, a thread in the float; reply there with `r` |
| `<leader>hq` | stop walking |
| `<leader>hm` | the map: the batch, or while walking the walk |
| `<leader>hz` | dim everything but the thread you are on |
| `<leader>hg` | draw the thread's changes into the code |
| `<leader>ht` / `<leader>hx` | bubbles or one line each / hide them |
| `]h` `[h` | next / previous thread that is your move (`]H` `[H` any) |
| `<leader>hb` | every batch |

`:Thread` takes the same as subcommands.

In Home, `1`–`4` switch tabs: threads, tours, review, closed, and `H`/`L`
go to the one on the left or right. `?` lists every key. On a review's
screen, `j`/`k` go from item to item, `a` accepts the one you are on, `r`
replies on it, `o` opens it, `⏎` goes into it (a hunk: walked in the code)
and `K` back out. In a hunk opened with `o`, `r` starts a thread on the
line the cursor is on, a removed one too, `⏎` on a place the agent's
answer lists as changed goes there, and `c` closes a thread when its fix is
done.

## Development

```sh
make check   # unit tests, screens, the end-to-end smoke test and the lint
```
