--- The float you write a thread or a reply in, opened under the line it is
--- about. It is a markdown buffer, so everything you know about editing works.
--- <C-s> or Enter (in normal mode) saves it, q or <Esc> in normal mode throws
--- it away, and leaving the window keeps what you wrote rather than losing it.

local M = {}

local ns = vim.api.nvim_create_namespace 'thread.compose'

---@class thread.ComposeOpts
---@field title string
---@field initial string|nil
---@field bufnr integer|nil   the code buffer, to mark the lines being commented
---@field from integer|nil
---@field to integer|nil
---@field on_save fun(text: string)

---@param opts thread.ComposeOpts
function M.open(opts)
  local src_win = vim.api.nvim_get_current_win()
  local src_buf = opts.bufnr or vim.api.nvim_get_current_buf()
  if opts.from then
    vim.api.nvim_buf_set_extmark(src_buf, ns, opts.from - 1, 0, {
      end_row = (opts.to or opts.from) - 1,
      end_col = 0,
      hl_eol = true,
      line_hl_group = 'ThreadRange',
    })
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'markdown'
  if opts.initial and opts.initial ~= '' then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(opts.initial, '\n', { plain = true }))
  end

  local info = vim.fn.getwininfo(src_win)[1]
  local width = math.max(30, math.min(76, info.width - info.textoff - 4))
  local anchor_line = opts.to or opts.from or vim.api.nvim_win_get_cursor(src_win)[1]
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'win',
    win = src_win,
    bufpos = { anchor_line - 1, 0 },
    row = 1,
    col = info.textoff > 0 and 0 or 1,
    width = width,
    height = 4,
    border = 'rounded',
    style = 'minimal',
    title = ' ' .. opts.title .. ' ',
    title_pos = 'left',
    footer = ' <C-s> save · q cancel ',
    footer_pos = 'right',
  })
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true

  local done = false
  local function close(save)
    if done then
      return
    end
    done = true
    local text = vim.trim(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n'))
    vim.api.nvim_buf_clear_namespace(src_buf, ns, 0, -1)
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_win_is_valid(src_win) then
      vim.api.nvim_set_current_win(src_win)
    end
    vim.cmd 'stopinsert'
    if save and text ~= '' then
      opts.on_save(text)
    end
  end

  local map = function(modes, lhs, fn)
    vim.keymap.set(modes, lhs, fn, { buffer = buf, nowait = true })
  end
  map({ 'n', 'i' }, '<C-s>', function()
    close(true)
  end)
  map('n', '<CR>', function()
    close(true)
  end)
  map('n', 'q', function()
    close(false)
  end)
  map('n', '<Esc>', function()
    close(false)
  end)

  -- Grow with the text, up to a point.
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    buffer = buf,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        local rows = vim.api.nvim_win_text_height(win, {}).all
        vim.api.nvim_win_set_height(win, math.max(4, math.min(14, rows)))
      end
    end,
  })
  vim.api.nvim_create_autocmd('WinLeave', {
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(function()
        close(true)
      end)
    end,
  })

  if not opts.initial or opts.initial == '' then
    vim.cmd 'startinsert'
  end
  return win, buf
end

return M
