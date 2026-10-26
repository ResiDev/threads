--- The trail: where you were before thread took you somewhere, kept so
--- you can go back, and forward again, as a browser does. A place on the
--- screen, a step of a walk, or a line of code; each time a key or a link
--- takes you elsewhere (go.leave), where you were is kept. Back takes
--- you there, keeping where you are to go forward to; anything new you
--- go to, or starting to write, forgets what is ahead.

local go = require 'thread.go'
local review = require 'thread.model.review'

local M = {}

--- A line of code, in a window.
---@class thread.TrailCode
---@field win integer
---@field buf integer
---@field file string
---@field line integer
---@field col integer

--- Where you were: on the screen, the code under it when it is a float
--- over the code; on a walk, its step (none: its briefing) and the line
--- of its code window when you were in it; or a line of code.
---@class thread.TrailSpot
---@field screen thread.Target|nil  the screen's place, as `place` opens it
---@field walk { review: string, tour: integer, step: integer|nil }|nil
---@field code thread.TrailCode|nil

-- As many as are kept each way.
local MOST = 100

local behind = {} ---@type thread.TrailSpot[]
local ahead = {} ---@type thread.TrailSpot[]

---@param msg string
local function say(msg)
  vim.notify('thread: ' .. msg)
end

---@param win integer
---@return boolean
local function is_float(win)
  return vim.api.nvim_win_get_config(win).relative ~= ''
end

--- A window to show code in: `win` while it is one, else the current
--- one, else the first that is not a float.
---@param win integer|nil
---@return integer|nil
local function code_win(win)
  for _, w in ipairs { win or -1, vim.api.nvim_get_current_win(), unpack(vim.api.nvim_tabpage_list_wins(0)) } do
    if vim.api.nvim_win_is_valid(w) and not is_float(w) then
      return w
    end
  end
end

---@param win integer
---@return thread.TrailCode
local function code_at(win)
  local buf = vim.api.nvim_win_get_buf(win)
  local cur = vim.api.nvim_win_get_cursor(win)
  return { win = win, buf = buf, file = vim.api.nvim_buf_get_name(buf), line = cur[1], col = cur[2] }
end

--- Where you are now.
---@return thread.TrailSpot|nil
local function here()
  local win = vim.api.nvim_get_current_win()
  local w = go.ask 'walking' ---@type thread.Walking|nil
  local walk = w and { review = w.review, tour = w.tour, step = w.step }
  local walk_win = go.ask 'walk window' ---@type integer|nil
  if is_float(win) then
    -- A step's page or a briefing the walk shows.
    if walk and go.ask 'page' == vim.api.nvim_win_get_buf(win) then
      return { walk = walk }
    end
    local s = go.ask 'screen here' ---@type { place: thread.Target, under: integer|nil }|nil
    if s then
      return { screen = s.place, code = s.under and vim.api.nvim_win_is_valid(s.under) and code_at(s.under) or nil }
    end
    -- A card, or what you write in: the code it is over.
    local prev = vim.fn.win_getid(vim.fn.winnr '#')
    win = code_win(prev ~= 0 and prev or nil) or win
    if is_float(win) then
      return nil
    end
  end
  return { walk = win == walk_win and walk or nil, code = code_at(win) }
end

--- What tells two spots apart: not the column, so coming back to a line
--- is coming back.
---@param s thread.TrailSpot|nil
---@return string
local function key(s)
  if not s then
    return ''
  end
  local out = {}
  if s.walk then
    out[#out + 1] = table.concat({ 'walk', s.walk.review, s.walk.tour, s.walk.step or 'briefing' }, ' ')
  end
  if s.screen then
    local at = assert(s.screen.at)
    local parts = { 'screen', at.place, at.review or '', at.note or '', at.contract or '', at.step or '', at.tour or '', s.screen.row or 0 }
    out[#out + 1] = table.concat(parts, ' ')
  end
  if s.code then
    out[#out + 1] = 'code ' .. s.code.buf .. ' ' .. s.code.line
  end
  return table.concat(out, ' | ')
end

--- The code back as it was: its buffer in its window, the cursor where
--- it was.
---@param c thread.TrailCode
---@return boolean
local function to_code(c)
  local win = code_win(c.win)
  if not win then
    return false
  end
  vim.api.nvim_set_current_win(win)
  if vim.api.nvim_buf_is_valid(c.buf) then
    if vim.api.nvim_win_get_buf(win) ~= c.buf then
      vim.api.nvim_win_set_buf(win, c.buf)
    end
  elseif c.file ~= '' and vim.uv.fs_stat(c.file) then
    vim.cmd.edit(vim.fn.fnameescape(c.file))
  else
    return false
  end
  pcall(vim.api.nvim_win_set_cursor, win, { c.line, c.col })
  return true
end

--- Take you to a spot; false when it has gone.
---@param to thread.TrailSpot
---@return boolean
local function restore(to)
  if to.walk then
    local r = review.read(to.walk.review)
    local x = r and r.tours[to.walk.tour]
    local s = r and to.walk.step and review.step(r, to.walk.step) or nil
    if not (r and x) or (to.walk.step and not s) then
      return false
    end
    go.open('walk', { review = r, tour = x, step = s, briefing = not s or nil })
    local win = go.ask 'walk window' ---@type integer|nil
    -- On a step in the code, not its page or the briefing.
    if to.code and win and not is_float(vim.api.nvim_get_current_win()) then
      to.code.win = win
      to_code(to.code)
    end
    return true
  end
  if to.screen then
    -- The code under it first, for the float to open over.
    if to.code then
      go.close 'screen'
      to_code(to.code)
    end
    go.open('place', to.screen)
    return true
  end
  go.close 'screen'
  return to.code ~= nil and to_code(to.code)
end

--- Keep where you are, before you are taken elsewhere: what was ahead
--- is forgotten.
function M.keep()
  local now = here()
  if not now or key(now) == key(behind[#behind]) then
    return
  end
  behind[#behind + 1] = now
  if #behind > MOST then
    table.remove(behind, 1)
  end
  ahead = {}
end

--- `n` spots along `from`, where you are kept on `to`: back or forward.
---@param from thread.TrailSpot[]
---@param to thread.TrailSpot[]
---@param n integer
---@return boolean  false when there was none
local function step(from, to, n)
  local now = here()
  -- Where you are already is not somewhere to go.
  while from[#from] and key(from[#from]) == key(now) do
    table.remove(from)
  end
  local spot ---@type thread.TrailSpot|nil
  for _ = 1, n do
    if not from[#from] then
      break
    end
    if now then
      to[#to + 1] = now
    end
    spot = table.remove(from)
    now = spot
  end
  if not spot then
    return false
  end
  local went = false
  go.within(function()
    went = restore(spot)
  end)
  if not went then
    say 'where you were has gone'
  end
  return true
end

--- Back to where you were before; `n` times back.
---@param n integer|nil
function M.back(n)
  if not step(behind, ahead, math.max(n or 1, 1)) then
    say 'nowhere to go back to'
  end
end

--- Forward again, to where you went back from; false when you have not
--- gone back since you last went somewhere new.
---@param n integer|nil
---@return boolean
function M.forward(n)
  return step(ahead, behind, math.max(n or 1, 1))
end

--- Nothing kept either way.
function M.clear()
  behind, ahead = {}, {}
end

go.on_leave(M.keep)

-- Writing is doing something where you are: forward is forgotten, so
-- the key for it is the editor's again.
vim.api.nvim_create_autocmd('InsertEnter', {
  group = vim.api.nvim_create_augroup('thread.trail', { clear = true }),
  callback = function()
    ahead = {}
  end,
})

return M
