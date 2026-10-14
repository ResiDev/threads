--- Highlight groups mixed from the colorscheme, the way tour.nvim's are: the
--- bubbles sit inside your buffer, so they borrow its Normal colours plus one
--- accent for you and one for the agent, rather than a float's surface.

local M = {}

local function rgb(n)
  return math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256
end

--- `top` laid over `bottom` at `alpha`, colours as 0xRRGGBB.
---@param top integer
---@param bottom integer
---@param alpha number  0 is all bottom, 1 all top
---@return integer
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

--- The colours the theme mixes from: the colorscheme's, with fallbacks.
---@return table<string, integer|boolean|nil>
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
    cyan = first_fg { 'DiagnosticInfo', 'Special', 'Type' } or (dark and 0x7dcfff or 0x007197),
  }
end

--- The two blues: a light cyan for tours, a deep blue for conversations.
--- A stop you have replied in is both: a conversation's border with a
--- tour's badge.
local function blues(p)
  if p.dark then
    return M.blend(0xffffff, p.cyan, 0.25), M.blend(p.you, 0x1c48c8, 0.55)
  end
  return p.cyan, M.blend(p.you, 0x000000, 0.8)
end

-- The colours a review's groups are named by (thread.Colour), for a dark
-- background and a light one.
M.GROUPS_DARK = {
  orange = 0xff9e64,
  yellow = 0xe0c070,
  lime = 0xa8d86e,
  teal = 0x4fd6be,
  sky = 0x7dcfff,
  blue = 0x7aa2f7,
  violet = 0xbb9af7,
  pink = 0xf7a1cf,
}
M.GROUPS_LIGHT = {
  orange = 0xb15c00,
  yellow = 0x8f6f00,
  lime = 0x4f7a1f,
  teal = 0x117a6b,
  sky = 0x0a6fa0,
  blue = 0x2e5fd0,
  violet = 0x7847bd,
  pink = 0xb4237a,
}

---@param p table
---@return table<string, table>
function M.groups(p)
  local base = p.bg or (p.dark and 0x000000 or 0xffffff)
  -- Bubbles sit on the buffer's own background, as Home's threads do: the
  -- border alone sets them apart from the code.
  local card = nil
  local tour, thread = blues(p)
  local g = {}
  g.ThreadText = { fg = M.blend(p.fg, base, 0.95), bg = card }
  g.ThreadCode = { fg = p.code, bg = card }
  g.ThreadFold = { fg = p.muted, bg = card, italic = true }
  g.ThreadYou = { fg = p.you, bold = true }
  g.ThreadAgent = { fg = p.agent, bold = true }
  g.ThreadAgentNew = { fg = p.agent, bold = true, underline = true }
  g.ThreadMeta = { fg = p.muted, italic = true }
  -- The border and sign say whose move it is: deep blue when it is yours
  -- (an answer to read), pink while the agent works on it.
  g.ThreadBorderWaiting = { fg = M.blend(p.agent, base, 0.8) }
  g.ThreadBorderAnswered = { fg = thread }
  -- A stop you replied in is both: between the tour's cyan and the blue.
  g.ThreadBorderBoth = { fg = M.blend(tour, thread, 0.5) }
  g.ThreadSignBoth = { fg = M.blend(tour, thread, 0.5) }
  g.ThreadSignWaiting = { fg = p.agent }
  g.ThreadSignAnswered = { fg = thread }
  -- The shapes saying who wrote each message: the agent's lit until read.
  g.ThreadDotYou = { fg = p.you }
  g.ThreadDotAgent = { fg = M.blend(p.agent, base, 0.6) }
  g.ThreadDotAgentNew = { fg = p.agent, bold = true }
  g.ThreadSignDone = { fg = M.blend(p.muted, base, 0.5) }
  -- Home: inline code in messages, and the change since you sent, coloured
  -- the way the colorscheme colours a diff.
  g.ThreadInlineCode = { fg = p.code }
  -- A name in a message that points at code: underlined, and lit when on it.
  g.ThreadRef = { fg = p.code, underline = true }
  g.ThreadRefFocus = { fg = p.code, bg = M.blend(p.code, base, p.dark and 0.25 or 0.18), underline = true, bold = true }
  -- A link to another thread, `#12`.
  g.ThreadLink = { fg = thread, underline = true }
  -- A contract named in prose, `[[id]]`, and in a list of them.
  g.ThreadContract = { fg = tour, bold = true }
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
  g.ThreadStopBadge = { fg = base, bg = tour, bold = true }
  g.ThreadKeyLabel = { fg = p.muted }
  g.ThreadRange = { bg = p.bg and M.blend(p.you, p.bg, 0.12) or nil }
  -- The lines of the thread the cursor is on, washed fainter than a range
  -- being commented.
  g.ThreadZone = { bg = p.bg and M.blend(p.you, p.bg, 0.06) or nil }
  -- A tour's card and an explanation the agent started: nobody's move, in
  -- the light blue of tours.
  g.ThreadBorderInfo = { fg = tour }
  g.ThreadSignInfo = { fg = M.blend(tour, base, 0.75) }
  g.ThreadSignInfoNew = { fg = tour, bold = true }
  -- Notes: a number on the line, its text after it or hung above it, and
  -- the line itself washed; the mark is the word it is about.
  g.ThreadNote = { fg = M.blend(p.fg, base, 0.85), italic = true }
  g.ThreadNoteNum = { fg = tour, bold = true }
  g.ThreadNoteLine = { bg = p.bg and M.blend(tour, p.bg, p.dark and 0.14 or 0.12) or nil }
  g.ThreadNoteMark = { fg = p.fg, bg = p.bg and M.blend(tour, p.bg, p.dark and 0.35 or 0.3) or nil, bold = true }
  -- Walking with focus on: the code outside the thread washed out.
  g.ThreadDim = { fg = M.blend(p.fg, base, 0.35) }
  -- Where you are in a walk, and the walk's name.
  g.ThreadCrumb = { fg = p.muted }
  g.ThreadCrumbHere = { fg = tour, bold = true }
  g.ThreadLeads = { fg = tour }
  -- The winbar while walking.
  local bar = p.bg and M.blend(tour, p.bg, p.dark and 0.14 or 0.1) or nil
  g.ThreadWalkBar = { fg = p.muted, bg = bar }
  g.ThreadWalkBarHere = { fg = tour, bold = true, bg = bar }
  g.ThreadWalkBarKey = { fg = p.fg, bold = true, bg = bar }
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
  -- The same, quiet: a tag in a list, its colour without the wash and
  -- faded towards the background, so the title stays what you read first.
  local function quiet(colour)
    return { fg = M.blend(colour, base, 0.85) }
  end
  g.ThreadTagBad = quiet(err)
  g.ThreadTagWarn = quiet(warn)
  g.ThreadTagInfo = quiet(p.you)
  g.ThreadTagGood = quiet(ok)
  g.ThreadTagQuiet = { fg = p.muted }
  -- A file under a thread in a list: its name under the title, and what
  -- the diff did to it, git's letter, fainter still.
  g.ThreadFile = { fg = M.blend(p.fg, base, 0.72) }
  g.ThreadFileModified = { fg = M.blend(warn, base, 0.85) }
  g.ThreadFileAdded = { fg = M.blend(ok, base, 0.85) }
  g.ThreadFileDeleted = { fg = M.blend(err, base, 0.85) }
  g.ThreadFileSame = { fg = p.muted }
  -- A review's groups: each its colour, which says only "these belong
  -- together"; the name in it, the bar or tree down its side quieter,
  -- what it is about between the two.
  for name, colour in pairs(p.dark and M.GROUPS_DARK or M.GROUPS_LIGHT) do
    local Name = name:sub(1, 1):upper() .. name:sub(2)
    g['ThreadGroup' .. Name] = { fg = colour, bold = true }
    g['ThreadGroup' .. Name .. 'Line'] = { fg = M.blend(colour, base, 0.6) }
  end
  g.ThreadGroupNone = { fg = p.muted, bold = true }
  g.ThreadGroupNoneLine = { fg = M.blend(p.muted, base, 0.6) }
  g.ThreadSummary = { fg = M.blend(p.fg, base, 0.75) }
  -- The files beside a review or a thread: those the item under the
  -- cursor touches lit, the rest faded.
  g.ThreadSideFile = { fg = M.blend(p.fg, base, 0.88) }
  g.ThreadSideDir = { fg = M.blend(p.fg, base, 0.6), italic = true }
  g.ThreadSideLit = { fg = p.fg, bold = true }
  g.ThreadSideFaded = { fg = M.blend(p.muted, base, 0.5) }
  -- A row at the edge of the files saying how many more are past it.
  g.ThreadSideFlag = { fg = thread, italic = true }
  -- In the main column, what is on the other side of the item: a
  -- contract's threads, a thread's contracts.
  g.ThreadRelatedBar = { fg = M.blend(p.you, base, 0.45) }
  -- The item the cursor is on, in the screen: a wash and a bar.
  g.ThreadItem = { bg = M.blend(p.you, base, p.dark and 0.1 or 0.07) }
  g.ThreadItemBar = { fg = p.you, bg = M.blend(p.you, base, p.dark and 0.1 or 0.07) }
  -- An accepted chunk's bar down its block.
  g.ThreadAcceptedBar = { fg = ok }
  g.ThreadPoint = { fg = p.fg, bold = true }
  -- A review group's kind, as a commit's prefix, and how risky it is.
  g.ThreadKindQuiet = badge(p.muted)
  g.ThreadRiskHigh = { fg = err, bold = true }
  g.ThreadRiskMedium = { fg = warn, bold = true }
  g.ThreadRiskLow = { fg = ok }
  -- An accepted hunk: its tick and a bar down its side.
  g.ThreadAccepted = { fg = ok, bold = true }
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
