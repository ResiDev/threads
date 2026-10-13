-- Screens as text, compared with a folder of them: each window (a
-- float's size, title and footer; the buffer's lines; its extmarks), then
-- the screen itself. A change to what you see fails; UPDATE=1 writes them
-- anew. tests/screens.lua and tests/surfaces.lua use it.

local H = require 'tests.helpers'

local C = {}

---@diagnostic disable-next-line: deprecated
local diff = vim.text and vim.text.diff or vim.diff

local function hl_name(h)
  if type(h) == 'table' then
    return table.concat(vim.tbl_map(tostring, h), '+')
  end
  return h == nil and '' or tostring(h)
end

local function chunks(list)
  if type(list) ~= 'table' then
    return tostring(list)
  end
  local out = {}
  for _, c in ipairs(list) do
    out[#out + 1] = '[' .. tostring(c[1]) .. '|' .. hl_name(c[2]) .. ']'
  end
  return table.concat(out)
end

local function ns_name(id)
  for name, n in pairs(vim.api.nvim_get_namespaces()) do
    if n == id then
      return name
    end
  end
  return tostring(id)
end

local FIELDS = {
  'hl_group',
  'line_hl_group',
  'number_hl_group',
  'sign_text',
  'sign_hl_group',
  'virt_text_pos',
  'virt_text_win_col',
  'priority',
  'hl_eol',
  'virt_lines_above',
}

local function mark_lines(m)
  local d = m[4]
  local parts = { ns_name(d.ns_id), m[2] .. ':' .. m[3] }
  if d.end_row then
    parts[#parts + 1] = 'to ' .. d.end_row .. ':' .. tostring(d.end_col)
  end
  for _, k in ipairs(FIELDS) do
    if d[k] ~= nil then
      parts[#parts + 1] = k .. '=' .. hl_name(d[k])
    end
  end
  if d.virt_text then
    parts[#parts + 1] = 'vt=' .. chunks(d.virt_text)
  end
  local out = { table.concat(parts, ' ') }
  for _, vl in ipairs(d.virt_lines or {}) do
    out[#out + 1] = '    vl ' .. chunks(vl)
  end
  return out
end

---@param win integer
---@param bar fun(s: string): string
local function window(win, bar)
  local c = vim.api.nvim_win_get_config(win)
  local buf = vim.api.nvim_win_get_buf(win)
  local out = {}
  if c.relative ~= '' then
    out[#out + 1] = string.format('== float %dx%d at %s,%s z%s', c.width, c.height, tostring(c.row), tostring(c.col), tostring(c.zindex))
    if c.title then
      out[#out + 1] = 'title ' .. chunks(c.title)
    end
    if c.footer then
      out[#out + 1] = 'footer ' .. chunks(c.footer)
    end
  else
    out[#out + 1] = string.format('== window %dx%d', vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win))
  end
  out[#out + 1] = 'buffer ' .. (vim.bo[buf].filetype ~= '' and vim.bo[buf].filetype or '-') .. ' ' .. vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':t')
  local wbar = vim.wo[win].winbar
  if wbar ~= '' then
    out[#out + 1] = 'winbar ' .. bar(wbar)
  end
  out[#out + 1] = 'cursor ' .. table.concat(vim.api.nvim_win_get_cursor(win), ':')
  for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    out[#out + 1] = string.format('%3d|%s', i, l)
  end
  -- Highlights sorted, so the order they were made in does not matter;
  -- marks that draw something in the order Neovim keeps them.
  local hls, drawn = {}, {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
    local d = m[4]
    if d.virt_text or d.virt_lines or d.sign_text then
      vim.list_extend(drawn, mark_lines(m))
    else
      hls[#hls + 1] = mark_lines(m)[1]
    end
  end
  table.sort(hls)
  vim.list_extend(out, hls)
  vim.list_extend(out, drawn)
  return out
end

local function order(a, b)
  local ca, cb = vim.api.nvim_win_get_config(a), vim.api.nvim_win_get_config(b)
  local fa, fb = ca.relative ~= '', cb.relative ~= ''
  if fa ~= fb then
    return not fa
  end
  if (ca.zindex or 0) ~= (cb.zindex or 0) then
    return (ca.zindex or 0) < (cb.zindex or 0)
  end
  local pa, pb = vim.api.nvim_win_get_position(a), vim.api.nvim_win_get_position(b)
  if pa[1] ~= pb[1] then
    return pa[1] < pb[1]
  end
  return pa[2] < pb[2]
end

--- A set of screens kept in `dir`: `shot(name)` takes one, `finish()`
--- says what changed and ends Neovim.
---@param dir string
---@param root string  written as <root>
---@param bar (fun(s: string): string)|nil  a winbar as it is written
---@return { shot: fun(name: string), finish: fun(label: string) }
function C.new(dir, root, bar)
  local update = vim.env.UPDATE == '1'
  local failures = {}
  bar = bar or function(s)
    return s
  end
  local function capture(name)
    H.settle()
    local wins = vim.api.nvim_tabpage_list_wins(0)
    table.sort(wins, order)
    local out = {}
    for _, w in ipairs(wins) do
      vim.list_extend(out, window(w, bar))
    end
    out[#out + 1] = '== screen'
    for _, row in ipairs(H.screen()) do
      out[#out + 1] = (row:gsub('%s+$', ''))
    end
    for i, l in ipairs(out) do
      out[i] = (l:gsub(vim.pesc(root), '<root>'))
    end
    local path = dir .. '/' .. name .. '.txt'
    if update then
      vim.fn.mkdir(dir, 'p')
      vim.fn.writefile(out, path)
      return
    end
    local want = vim.fn.filereadable(path) == 1 and vim.fn.readfile(path) or {}
    if vim.deep_equal(want, out) then
      os.remove(path .. '.actual')
    else
      vim.fn.writefile(out, path .. '.actual')
      failures[#failures + 1] = '--- ' .. name .. '\n' .. diff(table.concat(want, '\n') .. '\n', table.concat(out, '\n') .. '\n')
    end
  end
  return {
    shot = capture,
    finish = function(label)
      if #failures > 0 then
        io.stderr:write(label .. ' changed; the new ones are in ' .. dir .. '/*.actual\n' .. table.concat(failures, '\n') .. '\n')
        vim.cmd 'cquit 1'
      end
      io.stdout:write(label .. (update and ': written\n' or ': ok\n'))
      vim.cmd 'qa!'
    end,
  }
end

return C
