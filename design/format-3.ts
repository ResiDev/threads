// Format 3, a draft: the JSON an agent writes for a review. Every screen
// is derived from it, so this is the real set of primitives.
//
// The aim: the big picture up front, and every detail hanging off it. A
// review is five things, read top to bottom on one screen: its prose,
// the contracts the change touches, the tours that walk the change, the
// files (worked out, never written) and notes, where anything else goes.
// Format 2 told the change thread by thread, and a big change became
// dozens of threads of one tour of one step; here there are no threads.
// DIRECTION.md, "No threads: tours and notes", has the screens.
//
// Chunks stay inline, as format 2 has them; named chunks, every place
// written once and pointed at by name, come later.
//
// Check it with: tsc --noEmit --strict design/format-3.ts

/** Steps, notes and contracts each count their own ids from 1. An id is
 * never changed and never reused. Prose links one as `#step:7`,
 * `#note:12`, `#contract:3`. */
type Id = number;

type Colour =
  | "orange"
  | "yellow"
  | "lime"
  | "teal"
  | "sky"
  | "blue"
  | "violet"
  | "pink";

// ── The review ──────────────────────────────────────────────────────────

interface Review {
  format: 3;
  title: string;
  diff?: About;
  status?: "open" | "closed";

  /** The big picture, read first: what the change is for, how it works,
   * and the order the tours tell it in. Names contracts inline: "threads
   * come out of #contract:2". */
  introduction?: string;

  /** What other code relies on that the change touched: the joints of
   * the change. Implementation inside a function is not a contract. */
  contracts?: Contract[];

  /** The change, walked: each tour a part of it, in the order to read
   * them. Together their steps are on every hunk worth a look. */
  tours: Tour[];

  /** Anything else worth saying, in any primitive: a finding, a
   * question, a decision and what it traded away, a diagram of the
   * whole, a worked example, the checks run. And the user's own
   * comments, on a line or on no line. Drawn last, each whole. */
  notes?: Note[];

  rounds?: Round[];
}

interface About {
  of?: "unstaged" | "staged" | "uncommitted";
  base?: string;
  head?: string;
}

// ── Prose ───────────────────────────────────────────────────────────────

/** Markdown text, with diagrams attached. Used
 * wherever someone explains something: steps, contracts, messages */
interface Prose {
  /** Markdown, read when it is drawn. Bold, `#` headings and `-` / `1.`
   * lists are drawn; anything else (tables, links, italics) shows as
   * written. On top of markdown:
   *
   * - `#step:7`, `#note:12`: a link to that step or note.
   *   `other-review#note:12` is one in another review.
   * - `#contract:3`: a contract, drawn as its name and linking to its
   *   page.
   * - `` `name` ``: code, and a link to it when the name is found in
   *   the repo: where it is defined, else where it appears. A place
   *   written after it pins it: `` `sorted_keys` (json.lua:37) ``.
   * - An excerpt: a fence whose language is `code`, holding a Chunk as
   *   JSON. The screen reads those lines from the file and draws them
   *   there, so the text shows the real code rather than a copy of it.
   *   6 lines unless the chunk's `lines` says, 15 at most.
   * - Any other ``` fence is just normal markdown eg ```ts
   * - `{{name}}`, alone on a line: the diagram `diagrams[name]`, drawn
   *   there. */
  text: string;
  /** Diagrams by name, each placed in `text` by `{{name}}`. Write them
   * before `text`, so the prose can describe what they show. */
  diagrams?: Record<string, Diagram>;
}

// ── Contracts ───────────────────────────────────────────────────────────
type WrittenSource = { lang: string; text: string };

type Side = WrittenSource | Chunk;

type Source =
  | { change: "added"; after: Side }
  | { change: "removed"; before: Side }
  | { change: "changed"; before: Side; after: Side };

/** Code that depends on a contract, and how far the change reached it:
 * the blast radius, one place at a time. Its chunk is the line that
 * depends on the contract, not the start of the statement around it. */
type Dependent = Chunk &
  (
    | { impact: "none"; text?: string }
    | { impact: "adapted" | "reworked" | "missed"; text: string }
  );

/** A contract is a row in the review's list and a page of its own (⏎
 * opens it, H and L go between them): its prose, its shape as blocks,
 * what callers can count on, each use with what the change means for
 * it, what touches it (worked out), and a conversation. */
interface Contract {
  id: Id;
  /** How it reads in the code, or in a few words for a behaviour:
   * "review.grouped(r)", "Tab on a heading". */
  name: string;
  /** The agent's word for what sort of thing it is: "function", "JSON
   * field", "table", "endpoint", "key". Shown, never interpreted. */
  kind: string;
  /** A signature block written short: what it was and what it is, a
   * line each. Added has only `after`, removed only `before`. */
  source: Source;
  /** What it is for, in a sentence: what the review's list shows. */
  why?: string;
  prose: Prose;
  /** LLM identifies the changed chunks and writes a verdict */
  dependents?: Dependent[];
  /** A conversation about it, as a note has. */
  messages?: Message[];
}

// ── Code ────────────────────────────────────────────────────────────────

/** Lines of a file, found by quoting the first. */
interface Chunk {
  file: string;
  line: number;
  /** Default 1. */
  lines?: number;
  /** Its first line, verbatim. */
  text: string;
  /** A line the diff removed, quoted as it was. */
  side?: "old";
  rev?: string;
}

// ── Tours ───────────────────────────────────────────────────────────────

/** A part of the change, named for what it is about, never for a kind
 * of step ("Tests", "Callers"). */
interface Tour {
  title: string;
  /** A different one from the review's other tours: it marks the tour's
   * files beside it. */
  colour?: Colour;
  /** One sentence on what its steps show. */
  introduction?: string;
  steps: Step[];
}

interface Step extends Labels {
  id: Id;
  /** A claim about the code there, never a topic. */
  title: string;
  text?: string;
  /** None: a page, for one idea in many places. */
  chunk?: Chunk;
  /** On lines of its chunk. */
  diagram?: Diagram;
  checks?: Check[];
  /** The user's replies, and the agent's answers. */
  messages: Message[];
}

// ── Notes ───────────────────────────────────────────────────────────────

/** Whatever does not walk: said once, on a chunk or on no line. Its
 * first message is what it says, with every primitive a message has;
 * the rest are its conversation. */
interface Note extends Labels {
  id: Id;
  title?: string;
  chunk?: Chunk;
  status?: "open" | "fixed" | "won't fix" | "not a problem";
  messages: Message[];
  checks?: Check[];
}
/** When, to the second, in local time: "2026-10-13T10:00:00". */
type ISOTimestamp =
  `${number}-${number}-${number}T${number}:${number}:${number}`;

interface Message {
  from: "you" | "agent";
  /* ISO timestamp */
  at?: ISOTimestamp;
  prose: Prose;
  changes?: Chunk[];
}

// ── The rest, as in format 2 ────────────────────────────────────────────

interface Labels {
  verdict?:
    | "bug"
    | "flaw"
    | "risk"
    | "trade-off"
    | "decision"
    | "how it works"
    | "fine";
  severity?: "low" | "medium" | "high";
  risk?: "low" | "medium" | "high";
  risk_why?: string;
  kind?:
    | "feat"
    | "fix"
    | "refactor"
    | "perf"
    | "test"
    | "docs"
    | "chore"
    | "style";
}

interface Check {
  text: string;
  run: string;
}

/** A flow, a sequence or a call tree; see the skill. */
type Diagram = { kind: "flow" | "sequence" | "calls" } & Record<
  string,
  unknown
>;

interface Round {
  sent: string;
  snapshot?: string;
}

// ── What the screens derive, not written ────────────────────────────────
//
// - a chunk's contracts: those it is `at` or in the `uses` of
// - a tour's, a step's, a note's contracts: those its chunks touch
// - a contract's page: the tours, steps and notes that touch it, and its
//   files
// - a review's files: every chunk's, each marked with the tours whose
//   steps are in it, and with the notes

// ── Open questions ──────────────────────────────────────────────────────
//
// 1. Does a note carry a tour, for a finding that needs walking? Not
//    yet: it says where with excerpts, or names steps by `#step:7`.
// 2. A tour has no status. Is a finding about a step a note on the
//    step's chunk, or labels on the step? Both read; the note can close.
// 3. A contract's `before`/`after` stay strings, a signature block
//    written short; its shape's blocks say the rest. Should an example
//    be a chunk, read from the code at the base and the head?

// ── An example: the grouped review view, as this repo's commit 612f974 ──

const example: Review = {
  format: 3,
  title: "A review's threads by the agent's groups",
  diff: { base: "7d56f39", head: "612f974" },
  introduction:
    "The agent now sorts a review's threads into named, coloured [[review-groups]]. Everything that lists threads asks [[ordered]] for them, so the screen, H and L and Home all follow the groups.",
  contracts: [
    {
      id: "review-groups",
      name: "review.groups",
      kind: "format",
      change: "added",
      why: "The agent says what the threads are about together, in the order to read them.",
      text: "Threads were one flat list in the order written. A review now names its groups once, and each thread names the one it is in, so the screen can draw a heading per group and colour its files.",
      at: {
        file: "lua/thread/model/review.lua",
        line: 140,
        text: "local function parse_groups(p, raw)",
      },
      shape: [
        {
          kind: "fields",
          title: "a group",
          rows: [
            { name: "name", type: "string", change: "added" },
            {
              name: "colour",
              type: "Colour?",
              change: "added",
              note: "else the next in the palette",
            },
            { name: "summary", type: "string?", change: "added" },
          ],
        },
      ],
      promises: [
        {
          text: "A thread in no group is listed last, never dropped.",
          change: "added",
        },
      ],
      uses: [
        {
          file: "lua/thread/draw/review.lua",
          line: 88,
          text: "for _, g in ipairs(review.grouped(r)) do",
          verdict: "updated",
        },
      ],
    },
    {
      id: "ordered",
      name: "review.ordered(r)",
      kind: "function",
      change: "added",
      after: "review.ordered(r): thread.Thread[]",
      why: "One order for every list of threads, so they cannot disagree.",
      at: {
        file: "lua/thread/model/review.lua",
        line: 429,
        text: "function M.ordered(r)",
      },
    },
  ],
  tours: [
    {
      title: "Groups in the file",
      colour: "teal",
      introduction:
        "A review names its groups once; each thread names the one it is in.",
      steps: [
        {
          id: 1,
          title:
            "A group the review does not name is an error, with the names it does",
          chunk: {
            file: "lua/thread/model/review.lua",
            line: 140,
            text: "local function parse_groups(p, raw)",
          },
          messages: [],
        },
      ],
    },
  ],
  notes: [
    {
      id: 2,
      title: "A thread in no group is listed last, with a warning",
      verdict: "decision",
      messages: [
        {
          from: "agent",
          text: "Failing would lose the user's own threads, which have no group. See #1.",
        },
      ],
    },
  ],
};

export { example };
export type { Review };
