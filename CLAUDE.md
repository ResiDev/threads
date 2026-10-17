# thread.nvim

`design/format.ts` is the format, DIRECTION.md where it is going, KEYS.md every key (keep it in step), CODING_STANDARDS.md the rules.

## Checking

- `make check`: specs, surfaces, lint. `SPEC=walk make test` runs some. `UPDATE=1 make surfaces` rewrites snapshots; read the diff first.
- Specs run headless and never redraw, so passing tests are not proof something looks or feels right. For anything a person sees or presses, look before saying it works:
  - `make view STEPS='3G; <leader>hw; go; w'` drives a real Neovim in tmux. After each step it writes `$TMPDIR/thread-view/NN.txt` (screen and `:Thread debug`) and `NN.png`; read the picture for anything visual.
  - Steps use Vim key notation (`<Tab>`, `<CR>`, `<leader>ht`), plus `:cmd`, `=lua expr` and `wait 500`.
  - `CONFIG=mine` runs the user's own config (other plugins, their keys); use it when keys are involved. `REPO=<path>` uses a real repository. `KEEP=1` leaves it running.
- Something you can't reproduce: ask the user to run `:Thread debug` and read `~/.local/state/nvim/thread-debug.txt`. It lists each note and step with its size and why, keys other plugins took, and every mark drawn.
- Format with stylua (`~/.local/share/nvim/mason/bin/stylua lua tests`).
