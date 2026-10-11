--- Highlight groups mixed from the colorscheme, the way tour.nvim's are: the
--- bubbles sit inside your buffer, so they borrow its Normal colours plus one
--- accent for you and one for the agent, rather than a float's surface.

local M = {}

local function rgb(n)
  return math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256
end

function M.blend(top, bottom, alpha)
  local tr, tg, tb = rgb(top)
  local br, bg, bb = rgb(bottom)
  local function c(v)
    return math.max(0, math.min(255, math.floor(v + 0.5)))
  end
  return c(br + (tr - br) * alpha) * 65536 + c(bg + (tg - bg) * alpha) * 256 + c(bb + (tb - bb) * alpha)
end

local function hl(name)
  local ok, def = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  return ok and def or {}
end

local function first_fg(names)
  for _, name in ipairs(names) do
    local def = hl(name)
    if def.fg then
      return def.fg
    end
  end
end

function M.palette()
  local normal = hl 'Normal'
  local dark = vim.o.background == 'dark'
  local fg = normal.fg or (dark and 0xd0d0d0 or 0x303030)
  return {
    bg = normal.bg,
    fg = fg,
    dark = dark,
    you = first_fg { 'Title', 'Function', '@function', 'Identifier' } or (dark and 0x7aa2f7 or 0x2a5db0),
    agent = first_fg { 'Statement', 'Keyword', '@keyword', 'Special' } or (dark and 0xbb9af7 or 0x7a3db0),
    muted = first_fg { 'Comment', 'NonText' } or M.blend(fg, normal.bg or 0, 0.45),
    code = first_fg { '@markup.raw', 'String' } or fg,
  }
end

---@param p table
---@return table<string, table>
function M.groups(p)
  local base = p.bg or (p.dark and 0x000000 or 0xffffff)
  -- Bubbles sit on the buffer's own background, as Home's threads do: the
  -- border alone sets them apart from the code.
  local card = nil
  local g = {}
  g.ThreadText = { fg = M.blend(p.fg, base, 0.95), bg = card }
  g.ThreadCode = { fg = p.code, bg = card }
  g.ThreadFold = { fg = p.muted, bg = card, italic = true }
  g.ThreadYou = { fg = p.you, bold = true }
  g.ThreadAgent = { fg = p.agent, bold = true }
  g.ThreadMeta = { fg = p.muted, italic = true }
  -- The border and sign say whose move it is: blue when it is yours (a
  -- draft to send, an answer to read), pink while the agent works on it.
  g.ThreadBorderDraft = { fg = M.blend(p.muted, base, 0.8) }
  g.ThreadBorderWaiting = { fg = M.blend(p.agent, base, 0.8) }
  g.ThreadBorderAnswered = { fg = M.blend(p.you, base, 0.85) }
  g.ThreadSignDraft = { fg = M.blend(p.you, base, 0.6) }
  g.ThreadSignWaiting = { fg = p.agent }
  g.ThreadSignAnswered = { fg = p.you }
  -- Home's message dots say who wrote each message instead.
  g.ThreadDotYou = { fg = p.you }
  g.ThreadDotAgent = { fg = p.agent }
  g.ThreadSignDone = { fg = M.blend(p.muted, base, 0.5) }
  -- Home: inline code in messages, and the change since you sent, coloured
  -- the way the colorscheme colours a diff.
  g.ThreadInlineCode = { fg = p.code }
  -- A name in a message that points at code: underlined, and lit when on it.
  g.ThreadRef = { fg = p.code, underline = true }
  g.ThreadRefFocus = { fg = p.code, bg = M.blend(p.code, base, p.dark and 0.25 or 0.18), underline = true, bold = true }
  g.ThreadAdded = { link = 'Added' }
  g.ThreadRemoved = { link = 'Removed' }
  g.ThreadDiffAdd = { link = 'DiffAdd' }
  g.ThreadDiffDelete = { link = 'DiffDelete' }
  g.ThreadFocus = { fg = p.you }
  g.ThreadTitle = { fg = p.fg, bold = true }
  -- Home's tabs, and the keys it lists: the key bright, what it does quiet.
  local raised = M.blend(p.you, base, p.dark and 0.22 or 0.14)
  g.ThreadTab = { fg = p.muted }
  g.ThreadTabKey = { fg = M.blend(p.muted, base, 0.6) }
  g.ThreadTabActive = { fg = p.fg, bg = raised, bold = true }
  g.ThreadTabKeyActive = { fg = p.you, bg = raised, bold = true }
  g.ThreadTabRule = { fg = M.blend(p.muted, base, 0.5) }
  g.ThreadTabUnder = { fg = p.you }
  g.ThreadMarked = { bg = M.blend(p.agent, base, p.dark and 0.16 or 0.1) }
  g.ThreadMarkedBar = { fg = p.agent, bg = M.blend(p.agent, base, p.dark and 0.16 or 0.1) }
  g.ThreadKey = { fg = p.you, bold = true }
  g.ThreadBadge = { fg = base, bg = p.you, bold = true }
  -- A tour stop's badge on its card: where it is in its tour.
  g.ThreadStopBadge = { fg = base, bg = M.blend(p.you, base, 0.85), bold = true }
  g.ThreadKeyLabel = { fg = p.muted }
  g.ThreadRange = { bg = p.bg and M.blend(p.you, p.bg, 0.12) or nil }
  -- The lines of the comment the cursor is on, washed fainter than a range
  -- being commented.
  g.ThreadZone = { bg = p.bg and M.blend(p.you, p.bg, 0.06) or nil }
  -- A tour's card and an explanation the agent started: nobody's move, but
  -- in blue, strong enough to stand off the code around it.
  g.ThreadBorderInfo = { fg = M.blend(p.you, base, 0.85) }
  g.ThreadSignInfo = { fg = M.blend(p.you, base, 0.7) }
  g.ThreadSignInfoNew = { fg = p.you }
  -- Notes: a number on the line, its text after it or hung above it, and
  -- the line itself washed; the mark is the word it is about.
  g.ThreadNote = { fg = M.blend(p.fg, base, 0.85), italic = true }
  g.ThreadNoteNum = { fg = p.you, bold = true }
  g.ThreadNoteLine = { bg = p.bg and M.blend(p.you, p.bg, p.dark and 0.16 or 0.12) or nil }
  g.ThreadNoteMark = { fg = p.fg, bg = p.bg and M.blend(p.you, p.bg, p.dark and 0.4 or 0.3) or nil, bold = true }
  -- Walking with focus on: the code outside the thread washed out.
  g.ThreadDim = { fg = M.blend(p.fg, base, 0.35) }
  -- Where you are in a walk, and the walk's name.
  g.ThreadCrumb = { fg = p.muted }
  g.ThreadCrumbHere = { fg = p.you, bold = true }
  g.ThreadLeads = { fg = p.you }
  -- The winbar while walking.
  g.ThreadWalkBar = { fg = p.muted, bg = p.bg and M.blend(p.you, p.bg, p.dark and 0.14 or 0.1) or nil }
  g.ThreadWalkBarHere = { fg = p.you, bold = true, bg = p.bg and M.blend(p.you, p.bg, p.dark and 0.14 or 0.1) or nil }
  g.ThreadWalkBarKey = { fg = p.fg, bold = true, bg = p.bg and M.blend(p.you, p.bg, p.dark and 0.14 or 0.1) or nil }
  -- Verdicts, as tour.nvim draws them: a badge, its colour on a wash of itself.
  local err = first_fg { 'DiagnosticError', 'Error' } or 0xf7768e
  local warn = first_fg { 'DiagnosticWarn', 'WarningMsg' } or 0xe0af68
  local ok = first_fg { 'DiagnosticOk', 'String' } or (p.dark and 0x9ece6a or 0x3a7a33)
  local function badge(colour)
    return { fg = colour, bold = true, bg = p.bg and M.blend(colour, p.bg, 0.18) or nil }
  end
  g.ThreadVerdictBad = badge(err)
  g.ThreadVerdictWarn = badge(warn)
  g.ThreadVerdictInfo = badge(p.you)
  g.ThreadVerdictGood = badge(ok)
  g.ThreadPoint = { fg = p.fg, bold = true }
  -- Diagrams: the structure quiet, what you can follow in the accent.
  g.ThreadDiagramBox = { fg = M.blend(p.fg, base, 0.45) }
  g.ThreadDiagramEdge = { fg = M.blend(p.fg, base, 0.55) }
  g.ThreadDiagramLifeline = { fg = M.blend(p.fg, base, 0.28) }
  g.ThreadDiagramNode = { fg = p.code }
  g.ThreadDiagramText = { fg = M.blend(p.fg, base, 0.9) }
  g.ThreadDiagramLabel = { fg = p.muted, italic = true }
  g.ThreadDiagramHint = { fg = M.blend(p.muted, base, 0.75) }
  g.ThreadDiagramHere = { fg = p.code, bold = true, bg = p.bg and M.blend(p.code, p.bg, 0.16) or nil }
  g.ThreadBroken = { fg = err, italic = true }
  g.ThreadFloat = { link = 'NormalFloat' }
  -- Review: a change no thread explains.
  g.ThreadUnexplained = { fg = warn }
  return g
end

function M.apply()
  for name, def in pairs(M.groups(M.palette())) do
    def.default = true
    vim.api.nvim_set_hl(0, name, def)
  end
end

return M
