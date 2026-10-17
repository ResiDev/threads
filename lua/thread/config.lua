local M = {}

M.defaults = {
  -- Where reviews live, relative to the repository root.
  dir = '.threads',
  -- Keep the reviews out of git through .git/info/exclude.
  exclude = true,
  -- Global keys; any one may be false.
  mappings = {
    home = '<leader>hh',
    add = '<leader>hc',
    ask = '<leader>ha',
    -- The note or step the cursor is on: open it, reply, settle it.
    open = '<leader>ho',
    reply = '<leader>hr',
    close = '<leader>hd',
    toggle = '<leader>ht', -- every note open, and the walk's tour; or only what you are on
    hide = '<leader>hx',
    map = '<leader>hm',
    walk = '<leader>hw',
    stop = '<leader>hq',
    diff = '<leader>hg',
    -- The next or previous note or step that wants you, or any with a
    -- conversation.
    next = ']h',
    prev = '[h',
    next_all = ']H',
    prev_all = '[H',
  },
  -- Set while a walk is on, and put back when it ends.
  walk = {
    -- From the briefing, the first step; from the last, nowhere.
    next = 'L',
    -- From the first step, back to the briefing.
    prev = 'H',
    -- The tour's briefing, from any step.
    briefing = 'B',
    reply = 'r',
    map = 'M', -- the tour's outline
    up = 'U', -- back to the review's screen
    help = 'g?', -- every key a walk has
    -- Dim, on as a walk starts: the code but the step's chunk dimmed.
    -- Off for the rest of the walk, or on again. The diff is the same with
    -- `mappings.diff`.
    dim = 'gz',
    -- Into the step's card, a float over it with a cursor in it: `w` and
    -- `b` go between its links, ⏎ follows one, `q` comes out. `links` goes
    -- in on the first link.
    enter = 'go',
    links = 'gw',
    quit = 'q',
  },
  -- Keys that act on the note or step the cursor is on, and do what they always
  -- do on any other line. Any one may be false.
  zone = {
    focus = '<CR>',
    -- The same, where another plugin takes ⏎: the page, from the code or
    -- from inside its card.
    page = 'gp',
    -- A card cut short, whole; then closed to its sign; then open again.
    fold = '<Tab>',
    -- Into its card, a float over it with a cursor in it: `w` and `b` go
    -- between its links, ⏎ follows one, `q` comes out. A note's, or the
    -- step walked.
    enter = 'go',
    -- On a note: the next or previous note of its review, in the code.
    next_note = 'L',
    prev_note = 'H',
    -- Where cards stack on one line: bring the next one to the top.
    next = '<S-Tab>',
    -- A message more or fewer, when you want the steps between.
    more = false,
    less = false,
  },
  ui = {
    -- Widest a bubble's text runs, in columns.
    width = 72,
    -- Nerd Font shapes for who wrote a message: 󰀄 you, 󰚩 the agent. false:
    -- ● you, ▲ the agent.
    icons = true,
  },
}

M.options = vim.deepcopy(M.defaults)

--- The defaults with `opts` over them.
---@param opts table|nil
function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
end

return M
