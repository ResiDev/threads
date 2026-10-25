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

--- `colour`'s hue, at least `least` degrees round from red, made
--- saturated `s` and light `l`, both 0 to 1: a colorscheme's soft pastel
--- as a strong colour of the same hue.
---@param colour integer
---@param s number
---@param l number
---@param least number|nil
---@return integer
function M.vivid(colour, s, l, least)
  local r, g, b = rgb(colour)
  r, g, b = r / 255, g / 255, b / 255
  local hi, lo = math.max(r, g, b), math.min(r, g, b)
  local h = 0
  if hi ~= lo then
    local d = hi - lo
    if hi == r then
      h = ((g - b) / d) % 6
    elseif hi == g then
      h = (b - r) / d + 2
    else
      h = (r - g) / d + 4
    end
  end
  h = math.max(h * 60, least or 0)
  local c = (1 - math.abs(2 * l - 1)) * s
  local x = c * (1 - math.abs((h / 60) % 2 - 1))
  local m = l - c / 2
  -- Each sixth of the wheel, which of red, green and blue are c and x.
  local rr, gg, bb = unpack(({
    { c, x, 0 },
    { x, c, 0 },
    { 0, c, x },
    { 0, x, c },
    { x, 0, c },
    { c, 0, x },
  })[math.floor(h / 60) % 6 + 1])
  local function byte(v)
    return math.max(0, math.min(255, math.floor((v + m) * 255 + 0.5)))
  end
  return byte(rr) * 65536 + byte(gg) * 256 + byte(bb)
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

-- The colours a review's tours are named by (thread.Colour),
-- for a dark background and a light one: sixteen, picked to be as far
-- apart as they can be (in OKLab: 0.14 between the closest two on dark,
-- 0.11 on light), each hue's lightness set against its neighbours'. On
-- dark each reads at 4.5:1 or more, on light 3.5:1.
M.GROUPS_DARK = {
  rose = 0xffa1a8,
  orange = 0xff7806,
  amber = 0xad7c01,
  yellow = 0xf6cd01,
  lime = 0xa3b201,
  green = 0x8cfd84,
  mint = 0x0fd39a,
  teal = 0x0c9999,
  cyan = 0x0ffdf5,
  sky = 0x11ccfe,
  blue = 0x1f84f5,
  indigo = 0x9a9efe,
  violet = 0xcdcefe,
  purple = 0xaf60dc,
  magenta = 0xf48bfe,
  pink = 0xf25c94,
}
M.GROUPS_LIGHT = {
  rose = 0xc62b4f,
  orange = 0x974b03,
  amber = 0xb97902,
  yellow = 0x594d02,
  lime = 0x727a02,
  green = 0x116d00,
  mint = 0x049d58,
  teal = 0x015956,
  cyan = 0x0998a1,
  sky = 0x047197,
  blue = 0x014a9a,
  indigo = 0x4162dc,
  violet = 0x936df1,
  purple = 0x7f2da7,
  magenta = 0xc757c1,
  pink = 0x8c0255,
}

-- How far a lit name's colour goes towards white on dark, black on light:
-- enough to read on ThreadNamed's wash, the rest its own.
M.LIFT = 0.2

---@param p table
---@return table<string, table>
function M.groups(p)
  local base = p.bg or (p.dark and 0x000000 or 0xffffff)
  -- Cards sit on the buffer's own background: the border alone sets them
  -- apart from the code.
  local card = nil
  local tour, thread = blues(p)
  local g = {}
  g.ThreadText = { fg = M.blend(p.fg, base, 0.95), bg = card }
  g.ThreadCode = { fg = p.code, bg = card }
  g.ThreadYou = { fg = p.you, bold = true }
  g.ThreadAgent = { fg = p.agent, bold = true }
  g.ThreadAgentNew = { fg = p.agent, bold = true, underline = true }
  g.ThreadMeta = { fg = p.muted }
  -- The border and sign say whose move it is: deep blue when it is yours
  -- (an answer to read), pink while the agent works on it.
  g.ThreadBorderWaiting = { fg = M.blend(p.agent, base, 0.8) }
  g.ThreadBorderAnswered = { fg = thread }
  g.ThreadSignWaiting = { fg = p.agent }
  g.ThreadSignAnswered = { fg = thread }
  -- The shapes saying who wrote each message: the agent's lit until read.
  g.ThreadDotYou = { fg = p.you }
  g.ThreadDotAgent = { fg = M.blend(p.agent, base, 0.6) }
  g.ThreadDotAgentNew = { fg = p.agent, bold = true }
  g.ThreadSignDone = { fg = M.blend(p.muted, base, 0.5) }
  -- A link to a step, a note or a contract, `#note:12`.
  g.ThreadLink = { fg = thread, underline = true }
  -- A contract's name, in a list of them and on its page.
  g.ThreadContract = { fg = tour, bold = true }
  g.ThreadAdded = { link = 'Added' }
  g.ThreadRemoved = { link = 'Removed' }
  g.ThreadDiffAdd = { link = 'DiffAdd' }
  g.ThreadDiffDelete = { link = 'DiffDelete' }
  -- The words of a contract's line that changed, over its line's wash.
  g.ThreadDiffAddWord = { link = 'DiffText' }
  g.ThreadDiffDeleteWord = { link = 'DiffText' }
  g.ThreadTitle = { fg = p.fg, bold = true }
  -- A rule across a section's head, and down between the columns.
  g.ThreadTabRule = { fg = M.blend(p.muted, base, 0.5) }
  -- A review's tabs along the top: the one shown bold on a quiet wash of
  -- your blue, the rest quiet, the ‹ › by H and L quieter; the review's
  -- title on the right, dim. The line between a tab and its files.
  g.ThreadTab = { fg = p.muted }
  g.ThreadTabHere = { fg = p.fg, bold = true, bg = M.blend(p.you, base, 0.2) }
  g.ThreadTabArrow = { fg = M.blend(p.muted, base, 0.7) }
  g.ThreadReviewTitle = { fg = M.blend(p.fg, base, 0.7) }
  g.ThreadPaneRule = { fg = M.blend(p.muted, base, 0.45) }
  -- The cursor on the screen while an item is lit: blended away, since
  -- the lit item already says where you are.
  g.ThreadHiddenCursor = { blend = 100, nocombine = true }
  -- The notes you marked, to act on together.
  g.ThreadMarked = { bg = M.blend(p.agent, base, p.dark and 0.16 or 0.1) }
  g.ThreadMarkedBar = { fg = p.agent, bg = M.blend(p.agent, base, p.dark and 0.16 or 0.1) }
  -- The keys a surface lists: the key bright, what it does quiet.
  g.ThreadKey = { fg = p.you, bold = true }
  g.ThreadKeyLabel = { fg = p.muted }
  g.ThreadRange = { bg = p.bg and M.blend(p.you, p.bg, 0.12) or nil }
  -- The message you write where it goes, on a faint wash of your blue so
  -- you see where it ends.
  g.ThreadCompose = { fg = p.fg, bg = p.bg and M.blend(p.you, p.bg, 0.08) or nil }
  -- The lines of the note or step the cursor is on, washed fainter than a range
  -- being commented.
  g.ThreadZone = { bg = p.bg and M.blend(p.you, p.bg, 0.06) or nil }
  -- Walking dimmed, the code but the step's chunk: quiet enough to
  -- read the chunk first, not so quiet the rest is gone.
  g.ThreadDim = { fg = M.blend(p.fg, base, p.dark and 0.35 or 0.45) }
  -- A name the walked step's text puts in backticks, where it is in its
  -- chunk: to be found at a glance, bold on a wash of your blue, lighter
  -- than the code on dark and darker on light. Its text is its own colour
  -- lifted (M.named); this, your text's, where it has none.
  g.ThreadNamed = {
    fg = M.blend(p.dark and 0xffffff or 0x000000, p.fg, M.LIFT),
    bg = p.bg and M.blend(p.you, p.bg, p.dark and 0.45 or 0.36) or nil,
    bold = true,
    underline = p.bg == nil,
    sp = p.you,
  }
  -- A step's highlights: the current one reversed, in the code and the
  -- text alike, its lines in the code washed, its sentence in the text
  -- washed the same. Picking one, each one's number laid over its first
  -- letter, reversed in the light blue of tours.
  g.ThreadHighlightLabel = { fg = base, bg = tour, bold = true }
  g.ThreadHighlightHere = { fg = base, bg = p.you, bold = true }
  g.ThreadHighlightLine = { bg = M.blend(p.you, base, p.dark and 0.14 or 0.1) }
  g.ThreadSentence = { bg = M.blend(p.you, base, p.dark and 0.16 or 0.11) }
  -- A tour's card and an explanation the agent started: nobody's move, in
  -- the light blue of tours.
  g.ThreadBorderInfo = { fg = tour }
  g.ThreadSignInfo = { fg = M.blend(tour, base, 0.75) }
  g.ThreadSignInfoNew = { fg = tour, bold = true }
  -- A step in the code: its number bright, the hairline down its chunk
  -- quieter, the same blue whichever tour it is in.
  g.ThreadSignStep = { fg = tour, bold = true }
  g.ThreadSignStepRail = { fg = M.blend(tour, base, 0.55) }
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
  -- A note's bubble in the code: yellow, so it is never taken for a tour's
  -- step, whose cards are blue; fainter while the cursor is elsewhere.
  g.ThreadBorderNote = { fg = warn }
  g.ThreadBorderNoteQuiet = { fg = M.blend(warn, base, 0.6) }
  g.ThreadSignNote = { fg = M.blend(warn, base, 0.85) }
  -- What the diff did to a file, git's letter.
  g.ThreadFileModified = { fg = M.blend(warn, base, 0.85) }
  -- A review's tours: each its colour, which says only "these belong
  -- together"; the name in it, the bar or tree down its side quieter,
  -- what it is about between the two.
  for name, colour in pairs(p.dark and M.GROUPS_DARK or M.GROUPS_LIGHT) do
    local Name = name:sub(1, 1):upper() .. name:sub(2)
    g['ThreadGroup' .. Name] = { fg = colour, bold = true }
    g['ThreadGroup' .. Name .. 'Line'] = { fg = M.blend(colour, base, 0.6) }
  end
  g.ThreadSummary = { fg = M.blend(p.fg, base, 0.75) }
  -- The files beside a review or a contract: those the item under the
  -- cursor touches lit, the rest faded.
  -- With nothing lit, the files in your text's colour and their
  -- directories in your colorscheme's, no grey.
  g.ThreadSideFile = { fg = p.fg }
  g.ThreadSideDir = { fg = first_fg { 'Directory' } or p.you }
  g.ThreadSideLit = { fg = p.fg, bold = true }
  g.ThreadSideFaded = { fg = M.blend(p.muted, base, 0.5) }
  -- Beside a review, the mark of a file with a note in it.
  g.ThreadSideNote = { fg = M.blend(p.fg, base, 0.55) }
  -- A row at the edge of the files saying how many more are past it.
  g.ThreadSideFlag = { fg = thread, italic = true }
  -- In the main column, what is on the other side of the item: a
  -- contract's tours, steps and notes; theirs, its contracts.
  g.ThreadRelatedBar = { fg = M.blend(p.you, base, 0.45) }
  -- The item the cursor is on, in the screen: a wash and a bar.
  g.ThreadItem = { bg = M.blend(p.you, base, p.dark and 0.1 or 0.07) }
  g.ThreadItemBar = { fg = p.you, bg = M.blend(p.you, base, p.dark and 0.1 or 0.07) }
  -- An accepted chunk's bar down its block.
  g.ThreadAcceptedBar = { fg = ok }
  g.ThreadPoint = { fg = p.fg, bold = true }
  -- A note's kind as a quiet badge, and how severe an issue is.
  g.ThreadKindQuiet = badge(p.muted)
  g.ThreadRiskHigh = { fg = err, bold = true }
  g.ThreadRiskMedium = { fg = warn, bold = true }
  g.ThreadRiskLow = { fg = ok }
  -- An accepted hunk: its tick and a bar down its side.
  g.ThreadAccepted = { fg = ok, bold = true }
  -- An accepted note's row: a green wash under it.
  g.ThreadAcceptedRow = { bg = M.blend(ok, base, p.dark and 0.14 or 0.1) }
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
  -- A review's tabs, what their rows share: the facts in a quiet line
  -- brighter than it; a file and its line; what is done; your move.
  g.ThreadMetaHi = { fg = M.blend(p.fg, base, 0.6) }
  -- The Overview's title, plain and bold, and the quiet line under it.
  g.ThreadPageTitle = { fg = p.fg, bold = true }
  g.ThreadDeck = { fg = p.muted, italic = true }
  -- The link under the cursor on a review's tabs: a wash under its own
  -- colour.
  g.ThreadLinkHere = { bg = M.blend(thread, base, 0.22) }
  g.ThreadFile = { fg = M.blend(p.fg, base, 0.8) }
  g.ThreadFileLine = { fg = p.muted }
  g.ThreadDone = { fg = M.blend(p.fg, base, 0.5) }
  g.ThreadYourMove = { fg = thread, bold = true }
  -- The notes as an inbox. A note's icon is its kind's shape; its colour
  -- says one of two things: an issue, how severe, on a scale from red to
  -- a quiet grey; anything else, whether it asks you (green) or nothing.
  -- Strong colours of the colorscheme's own hues, not its pastels. An
  -- issue by how severe: its error red, its warning made a saturated
  -- orange, then a yellow (at least 52° round, so not orange). What asks
  -- you, its green, which String nearly always is, made deep. Darker on
  -- a light background.
  local l = p.dark and 0 or -0.15
  local green = first_fg { 'String', 'DiagnosticOk' } or ok
  g.ThreadIconHigh = { fg = err, bold = true }
  g.ThreadIconMedium = { fg = M.vivid(warn, 0.9, 0.56 + l), bold = true }
  g.ThreadIconLow = { fg = M.vivid(warn, 0.95, 0.56 + l, 52) }
  g.ThreadIconAsk = { fg = M.vivid(green, 0.75, 0.44 + l), bold = true }
  g.ThreadIconQuiet = { fg = p.muted }
  g.ThreadIconDone = { fg = M.blend(p.muted, base, 0.8) }
  -- Its kind's word beside the icon, quieter than the title it leads to.
  for _, k in ipairs { 'High', 'Medium', 'Low', 'Ask', 'Quiet', 'Done' } do
    g['ThreadIcon' .. k .. 'Word'] = { fg = M.blend(g['ThreadIcon' .. k].fg, base, 0.7) }
  end
  -- A row as a mail list draws a message: unread, bold and dotted; the
  -- title, when, the last words quieter.
  g.ThreadUnread = { fg = thread, bold = true }
  g.ThreadSubject = { fg = p.fg, bold = true }
  g.ThreadWhen = { fg = p.muted }
  g.ThreadWhenUnread = { fg = M.blend(p.fg, base, 0.85), bold = true }
  g.ThreadKindDone = { fg = M.blend(p.muted, base, 0.75) }
  -- Its sections' heads: yours the one block.
  g.ThreadSectionHead = { fg = M.blend(p.fg, base, 0.88), bold = true }
  g.ThreadSectionGlyph = { fg = M.blend(p.fg, base, 0.6) }
  g.ThreadSectionAgent = { fg = M.blend(p.agent, base, 0.85) }
  g.ThreadSectionDone = { fg = p.muted, bold = true }
  g.ThreadSectionYou = { fg = base, bg = thread, bold = true }
  -- A conversation's messages, each with a bar in its writer's colour.
  g.ThreadQuoteYou = { fg = M.blend(p.you, base, 0.7) }
  g.ThreadQuoteAgent = { fg = M.blend(p.agent, base, 0.7) }
  g.ThreadWhoYou = { fg = p.you, bold = true }
  g.ThreadWhoAgent = { fg = p.agent, bold = true }
  g.ThreadMsgText = { fg = M.blend(p.fg, base, 0.85) }
  g.ThreadPlaceholder = { fg = p.muted, italic = true }
  -- Contracts in groups: what needs you in the thread blue, what is
  -- walked quiet; a contract's sign as plain coloured text, its kind
  -- quieter than its name.
  g.ThreadNeedsYou = { fg = thread, bold = true }
  g.ThreadGroupHead = { fg = M.blend(p.fg, base, 0.85), bold = true }
  g.ThreadGroupDone = { fg = p.muted, bold = true }
  -- Changed, as most are, git's blue for a change: only what was added
  -- or removed stands out.
  g.ThreadSignChanged = { fg = first_fg { 'GitSignsChange', 'diffChanged', 'Changed' } or M.blend(tour, base, 0.7), bold = true }
  g.ThreadSignAdded = { fg = p.code, bold = true }
  g.ThreadSignRemoved = { fg = err, bold = true }
  -- A contract's name, in its sign's colour, a changed one's as any
  -- contract's; an added or removed one's rows washed faintly in it, less
  -- faintly with the cursor on it.
  g.ThreadContractChanged = { link = 'ThreadContract' }
  g.ThreadContractAdded = { fg = p.code, bold = true }
  g.ThreadContractRemoved = { fg = err, bold = true }
  g.ThreadContractAddedRow = { bg = M.blend(p.code, base, p.dark and 0.06 or 0.05) }
  g.ThreadContractAddedHere = { bg = M.blend(p.code, base, p.dark and 0.14 or 0.1) }
  g.ThreadContractRemovedRow = { bg = M.blend(err, base, p.dark and 0.06 or 0.05) }
  g.ThreadContractRemovedHere = { bg = M.blend(err, base, p.dark and 0.14 or 0.1) }
  g.ThreadSevDone = { fg = M.blend(p.muted, base, 0.8) }
  g.ThreadKind = { fg = p.muted, italic = true }
  -- How far the change reached a caller, in its bar and the files
  -- beside; a missed one the only block on its row.
  g.ThreadImpactMissed = { fg = err, bold = true }
  g.ThreadImpactReworked = { fg = warn }
  g.ThreadImpactAdapted = { fg = M.blend(p.fg, base, 0.5) }
  g.ThreadBadgeMissed = { fg = base, bg = err, bold = true }
  g.ThreadReachHere = { fg = tour, bold = true }
  g.ThreadSideHead = { fg = M.blend(p.fg, base, 0.6), bold = true }
  -- Tours: a step still to walk quieter than the next; one walked
  -- whole a quiet block, the one block a tour's row may have.
  g.ThreadStepTodo = { fg = M.blend(p.fg, base, 0.72) }
  g.ThreadBadgeWalked = { fg = M.blend(p.fg, base, 0.75), bg = M.blend(p.muted, base, 0.55), bold = true }
  -- A side's sign on its wash.
  g.ThreadRemovedSign = { fg = first_fg { 'Removed', 'DiffRemoved' } or err, bg = hl('DiffDelete').bg, bold = true }
  g.ThreadAddedSign = { fg = first_fg { 'Added', 'DiffAdded' } or ok, bg = hl('DiffAdd').bg, bold = true }
  -- A contract's page: a caller's code numbered quietly, its own line's
  -- number brighter; a caller the change missed, its line washed red and
  -- what it cost said in red.
  g.ThreadLineNr = { fg = M.blend(p.muted, base, 0.7) }
  g.ThreadLineHere = { fg = M.blend(p.fg, base, 0.85), bold = true }
  g.ThreadMissedLine = { link = 'DiffDelete' }
  g.ThreadMissedSign = { fg = err, bg = hl('DiffDelete').bg, bold = true }
  g.ThreadMissedText = { fg = err }
  return g
end

local lifted = {} ---@type table<string, string>  a colour, quiet or not -> its group

--- The group a name lit in the code is drawn in: ThreadNamed's wash and
--- weight, its text its own colour `fg` lifted by M.LIFT; ThreadNamed
--- itself when it has none. `quiet`, while another is current: its own
--- colour on a fainter wash, not bold. One group a colour, made again
--- when the colorscheme changes.
---@param fg integer|nil
---@param quiet boolean|nil
---@return string
function M.named(fg, quiet)
  if not fg and not quiet then
    return 'ThreadNamed'
  end
  local id = string.format('%s%06x', quiet and 'Quiet' or '', fg or 0)
  if not lifted[id] then
    local base = hl 'ThreadNamed'
    local p = M.palette()
    local you = p.you --[[@as integer]]
    local under = p.bg --[[@as integer|nil]]
    local out = p.dark and 0xffffff or 0x000000
    lifted[id] = 'ThreadNamed' .. id
    if quiet then
      local bg = under and M.blend(you, under, p.dark and 0.2 or 0.15) or nil
      vim.api.nvim_set_hl(0, lifted[id], { fg = fg or base.fg, bg = bg, underline = bg == nil, sp = base.sp })
    else
      vim.api.nvim_set_hl(0, lifted[id], { fg = M.blend(out, fg or 0, M.LIFT), bg = base.bg, bold = base.bold, underline = base.underline, sp = base.sp })
    end
  end
  return lifted[id]
end

local washed = {} ---@type table<string, string>  a group -> it on ThreadSentence's wash

--- A group as it is in the sentence of a step's text the current
--- highlight is in: its own colours on ThreadSentence's wash.
---@param group string
---@return string
function M.sentence(group)
  if not washed[group] then
    local def = vim.deepcopy(hl(group)) --[[@as vim.api.keyset.highlight]]
    def.bg = hl('ThreadSentence').bg
    washed[group] = group .. 'Sentence'
    vim.api.nvim_set_hl(0, washed[group], def)
  end
  return washed[group]
end

function M.apply()
  lifted, washed = {}, {}
  for name, def in pairs(M.groups(M.palette())) do
    def.default = true
    vim.api.nvim_set_hl(0, name, def)
  end
end

return M
