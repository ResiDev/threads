local M = {}

M.defaults = {
  -- The rebuild's surfaces in place of today's, until the switch
  -- (DIRECTION.md, stage 6). `THREAD_REBUILD=1 nvim` sets it too.
  rebuild = vim.env.THREAD_REBUILD == '1',
  -- Where batches live, relative to the repository root.
  dir = '.threads',
  -- Keep the batches out of git through .git/info/exclude.
  exclude = true,
  -- How a new batch asks the agent to answer: 'inline' (into the threads) or
  -- 'chat' (in the conversation, with a one-line note in each thread).
  reply = 'inline',
  -- Global keys; any one may be false.
  mappings = {
    home = '<leader>hh',
    add = '<leader>hc',
    ask = '<leader>ha',
    -- The thread the cursor is on: focus it, reply, close it.
    open = '<leader>ho',
    reply = '<leader>hr',
    close = '<leader>hd',
    menu = '<leader>hb',
    toggle = '<leader>ht', -- bubbles or one line each
    hide = '<leader>hx',
    map = '<leader>hm',
    walk = '<leader>hw',
    stop = '<leader>hq',
    dim = '<leader>hz',
    diff = '<leader>hg',
    -- The next or previous thread where it is your move, or any open one.
    next = ']h',
    prev = '[h',
    next_all = ']H',
    prev_all = '[H',
  },
  -- Set while a walk is on, and put back when it ends.
  walk = {
    next = 'L',
    prev = 'H',
    reply = 'r',
    map = 'M', -- the tour's outline
    up = 'K', -- in a review, back to its screen
    quit = 'q',
  },
  -- Keys that act on the thread the cursor is on, and do what they always
  -- do on any other line. Any one may be false.
  zone = {
    focus = '<CR>',
    -- A card one line, or whole.
    fold = '<Tab>',
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
    -- 'auto' draws changes with CodeDiff when it is installed; 'builtin'
    -- always uses Vim's own diff.
    diff = 'auto',
  },
}

M.options = vim.deepcopy(M.defaults)

--- The defaults with `opts` over them.
---@param opts table|nil
function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
end

return M
