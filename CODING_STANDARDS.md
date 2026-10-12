# Coding standards

How code in thread.nvim is written. DIRECTION.md says where it goes,
GLOSSARY.md what things are called.

## Layers

Each layer requires only the layers below it.

```
init        commands, keys, config
surfaces    screen/  code/  walk  focus  page  map  compose
actions     the verbs: reply, close, accept, run
draw/       one drawer per primitive
prose/      the text primitives
model/      the primitives and their state
store/      the files on disk, and what you have seen
ui/         drawing
base/       finding code, and config; nothing of reviews
```

- **Foundations know nothing of reviews.** `base/` and `ui/` never
  require `store/` or anything above it. The repo root comes from
  `base/repo`, the options from `config`, which sits with them.
- **Store is storage, model is meaning.** `store/` reads and writes the
  files and knows no primitives. `model/` says what the data means and
  works out each primitive's state.
- **One drawer per primitive.** A thread is drawn by `draw/thread`
  everywhere, at the size asked for: a line, a card, whole.
- **Actions never call a surface.** An action changes the data and saves
  it; the store fires `User ThreadChanged`, and the surfaces redraw.
- **Surfaces reach each other through `go`.** Each registers what it
  opens, and `go.open(x)` sends `x` there without requiring it.
- **Types count, not only requires.** A layer names no type declared in
  a layer above it, in any annotation. A type belongs to the layer of the
  file that declares it.
- **A test enforces it.** `tests/independence_spec.lua` fails on a
  require that points up a layer, and on a type that does.
- **The rebuild goes bottom-up.** `built` in `tests/layers.lua` names the
  highest layer done; raise it when the next is, and the layer test and
  the strict lint hold that layer from then on.

## Modules

- **One module, one job.** If saying what it does takes a paragraph, it is
  two modules.
- **What is on `M` is the interface.** Everything else is `local`. Never
  create a global.
- **Require at the top of the file.** A require inside a function hides a
  cycle. Break the cycle instead: an event, or a function registered from
  above.
- **Data is plain tables**, as read from the file, passed to module
  functions: `thread.status(t)`, never `t:status()`. Metatables are for
  caches (`__mode = 'k'`), not for data.
- **Names are the glossary's words.** Code about a step says `step`, never
  `stop` or `item`.
- **A comment says what a thing is for, or why**, in a sentence. Not what
  the next line does.

## Types

- **Every function on `M` is annotated**: `---@param` for each parameter,
  `---@return` when it returns. In the layers built, the lint fails one
  with none, and lua-language-server one with some missing.
- **Each primitive is a `---@class (exact)`**, so a field it does not name
  is an error. That suits data an agent writes by hand.
- **Data from the file is checked once, where `model/` reads it**, beside
  its class so the two cannot drift. Past that, code trusts its types and
  does not check again.
- **The layers built pass lua-language-server with every check on**
  (`.luarc.strict.json`). Today's code keeps `.luarc.json`'s looser
  checks until it is rebuilt.

## Nil

- **Return early**: `if not x then return end` at the top, not the rest of
  the function nested in an `if`.
- **Say what you know.** Where a value is set and the checker cannot see
  it, `assert(x)` or `---@cast x thread.Review`.
- **`a and b or c` gives `c` whenever `b` is false or nil.** Use an `if`
  when `b` can be either.

## Tests

A test pins behaviour at a seam, where one part meets another or meets
you:

- a layer's interface: what is on `M` in `base/`, `store/` and `model/`;
- the file: what the agent writes is read right, and what the plugin
  writes is what the agent will read;
- the editor: the keys a person presses, and what they then see;
- the layers themselves: `tests/independence_spec.lua` fails on a require
  or a type that points up a layer.

Not private functions, and not how a screen is put together inside.

- **Its name says the behaviour**, subject first: `jump: goes to the
  thread from a modified buffer, hidden off`.
- **Each test builds what it needs**, its repository and its review, and
  shares nothing with the one before.
- **A bug is fixed after a test shows it.**
- **Screen tests** pin what a person sees, as text. Re-record one only
  after reading its diff.

Delete a test that:

- would still pass with the behaviour broken;
- restates the code, checking a function returns what its one line
  returns;
- pins a detail nobody relies on, a column or a highlight name, that a
  screen test already covers;
- tests something that no longer exists.

## Before a commit

`make check`: the tests, the screen tests, the smoke run and the lint.
The lint is stylua's formatting; lua-language-server over the whole
repository, and with every check on over the layers built; a function
there with no annotations; and a warning for a file over 600 lines.
