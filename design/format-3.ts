// Format 3, a draft: the JSON an agent writes for a review. Every screen
// is derived from it, so this is the real set of primitives.
//
// The aim: the big picture up front, and every detail hanging off it.
// Format 2 told the change thread by thread and left you to piece the
// picture together; here the review lists the contracts the change
// touches, its prose names them, and the screens work out which threads,
// tours and files touch each. DIRECTION.md, "The overview", has the
// screens; the prototype builds `contracts` with chunks inline, as format
// 2 has them, and leaves named chunks for later.
//
// Check it with: tsc --noEmit --strict design/format-3.ts

// ── Names ───────────────────────────────────────────────────────────────

/** A name the review gives a piece of code, used everywhere else to point
 * at it: "grouped", "fold-key". */
type ChunkName = string

/** A contract's id: "review-groups", "tab-folds". Chunk names and contract
 * ids share one namespace, so `[[name]]` in any text finds either. */
type ContractId = string

type Colour = 'orange' | 'yellow' | 'lime' | 'teal' | 'sky' | 'blue' | 'violet' | 'pink'

// ── The review ──────────────────────────────────────────────────────────

interface Review {
  format: 3
  title: string
  diff?: About
  status?: 'open' | 'closed'

  /** The big picture, read first: what the change is for and how it
   * works. Names contracts inline: "threads come out of [[grouped]]". */
  introduction?: string

  /** What other code relies on that the change touched: the joints of
   * the change. Implementation inside a function is not a contract. */
  contracts: Contract[]

  /** Every piece of code the review talks about, once, by name. Files are
   * derived from these; nothing names a file on its own. */
  chunks: Record<ChunkName, Chunk>

  groups?: Group[]
  threads: Thread[]
  rounds?: Round[]
}

interface About {
  of?: 'unstaged' | 'staged' | 'uncommitted'
  base?: string
  head?: string
}

// ── Contracts ───────────────────────────────────────────────────────────

interface Contract {
  id: ContractId
  /** How it reads in the code, or in a few words for a behaviour:
   * "review.grouped(r)", "Tab on a heading". */
  name: string
  /** The agent's word for what sort of thing it is: "function", "JSON
   * field", "table", "endpoint", "key". Shown, never interpreted. */
  kind: string
  change: 'added' | 'changed' | 'removed' | 'relied on'
  /** What it was and what it is: a signature, a shape, a sentence.
   * Added has only `after`, removed only `before`. */
  before?: string
  after?: string
  /** Why it changed, in a sentence: what it is for. */
  why?: string
  /** Where it is defined. A behaviour may have none. */
  at?: ChunkName
  /** The code that relies on it: callers, implementations, tests. Its
   * reach is these, and the files they are in. */
  uses?: ChunkName[]
}

// ── Code ────────────────────────────────────────────────────────────────

/** Lines of a file, found by quoting the first. */
interface Chunk {
  file: string
  line: number
  /** Default 1. */
  lines?: number
  /** Its first line, verbatim. */
  text: string
  /** A line the diff removed, quoted as it was. */
  side?: 'old'
  rev?: string
}

// ── Threads and tours, as in format 2, pointing at chunks by name ───────

interface Group {
  name: string
  colour?: Colour
  summary?: string
}

interface Thread {
  id: number
  title?: string
  group?: string
  chunk?: ChunkName
  status?: 'open' | 'fixed' | "won't fix" | 'not a problem'
  messages: Message[]
}

interface Message {
  from: 'you' | 'agent'
  text: string
  round?: number
  at?: string
  tours?: Tour[]
}

interface Tour {
  title: string
  colour?: Colour
  introduction?: string
  steps: Step[]
}

interface Step {
  id: number
  title: string
  text?: string
  chunk?: ChunkName
  messages: Message[]
}

interface Round {
  sent: string
  snapshot?: string
}

// ── What the screens derive, not written ────────────────────────────────
//
// - a chunk's contracts: those it is `at` or in the `uses` of
// - a contract's files: its `at` and `uses` chunks' files
// - a thread's contracts: its chunks' and its steps' chunks'
// - a group's contracts and files: its threads'
// - a review's files: every chunk's, each marked with the groups whose
//   threads touch it; a thread's: its chunks', marked by tour
//
// A thread's introduction is its first message, so it names contracts
// the same way.

// ── Open questions ──────────────────────────────────────────────────────
//
// 1. Is `before`/`after` text enough, or should they be chunks: the old
//    side and the new, drawn as code?
// 2. Do groups stay? They could become the parts of the system, a
//    contract the joint between two parts; the map of parts and contracts
//    is then derived, not drawn by the agent.
// 3. Do threads keep their own `chunk`, or does a thread's code come only
//    from its steps?

// ── An example: the grouped review view, as this repo's commit 612f974 ──

const example: Review = {
  format: 3,
  title: "A review's threads by the agent's groups",
  diff: { base: '7d56f39', head: '612f974' },
  introduction:
    "The agent now sorts a review's threads into named, coloured [[review-groups]], and each thread says which it is in with [[thread-group]]. Everything that lists threads asks [[ordered]] for them, so the screen, H and L and Home all follow the groups; [[tab-folds]] opens a group as a tree or folds it to a card.",
  contracts: [
    {
      id: 'review-groups',
      name: 'review.groups',
      kind: 'format',
      change: 'added',
      after: '{ name, colour?, summary? }[]',
      why: 'The agent says what the threads are about together, in the order to read them.',
      at: 'parse-groups',
      uses: ['grouped', 'draw-groups'],
    },
    {
      id: 'thread-group',
      name: 'thread.group',
      kind: 'format',
      change: 'added',
      after: 'the name of one of the review\'s groups',
      why: 'Puts a thread in its group; one in none is listed last.',
      at: 'thread-fields',
      uses: ['grouped'],
    },
    {
      id: 'ordered',
      name: 'review.ordered(r)',
      kind: 'function',
      change: 'added',
      after: 'review.ordered(r): thread.Thread[]',
      why: 'One order for every list of threads, so they cannot disagree.',
      at: 'ordered',
      uses: ['view-ordered'],
    },
    {
      id: 'tab-folds',
      name: 'Tab on a heading',
      kind: 'command',
      change: 'changed',
      before: 'Tab folds the messages, or shows the code',
      after: "Tab on a group's heading folds that group; elsewhere, every group",
      why: 'A long review reads as a few cards before you open one.',
      at: 'fold-key',
    },
  ],
  chunks: {
    'parse-groups': { file: 'lua/thread/model/review.lua', line: 140, text: 'local function parse_groups(p, raw)' },
    grouped: { file: 'lua/thread/model/review.lua', line: 402, text: 'function M.grouped(r)' },
    ordered: { file: 'lua/thread/model/review.lua', line: 429, text: 'function M.ordered(r)' },
    'thread-fields': {
      file: 'lua/thread/model/thread.lua',
      line: 38,
      text: "local FIELDS = vim.list_extend({ 'id', 'title', 'group', 'chunk', 'status', 'messages', 'checks' }, labels.FIELDS)",
    },
    'draw-groups': { file: 'lua/thread/draw/review.lua', line: 123, text: 'function M.groups(P, r, o)' },
    'view-ordered': { file: 'lua/thread/screen/view.lua', line: 86, text: '      for _, t in ipairs(review.ordered(r)) do' },
    'fold-key': { file: 'lua/thread/screen/keys.lua', line: 392, text: 'local function fold(api)' },
  },
  threads: [],
}

export { example }
export type { Review }
