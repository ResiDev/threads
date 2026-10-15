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
// Code is written once: every chunk is in the review's `chunks`, and
// everything else points at one by its id.
//
// The types read top down: the review, then its parts in the order the
// screen shows them, then what they share.
//
// Check it with: tsc --noEmit --strict design/format-3.ts

// ── The review ──────────────────────────────────────────────────────────

interface Review {
  title: string;
  diff?: About;
  status?: "open" | "closed";

  /** The big picture, read first: what the change is for, how it works,
   * and the order the tours tell it in. Names contracts inline: "threads
   * come out of #contract:2". */
  introduction?: Prose;

  /** What other code relies on that the change touched: the joints of
   * the change. Implementation inside a function is not a contract. */
  contracts?: Contract[];

  /** The change, walked: each tour a part of it, in the order to read
   * them. Together their steps are on every hunk worth a look. */
  tours: Tour[];

  /** Everything that is not walked: issues, decisions, suggestions,
   * questions, fixes and comments, yours and the agent's. Listed last, a
   * row each, grouped by kind. */
  notes?: Note[];

  /** Every place in the code the review points at, each written once. */
  chunks: Chunk[];
}

interface About {
  of?: "unstaged" | "staged" | "uncommitted";
  base?: string;
  head?: string;
}

// ── Contracts ───────────────────────────────────────────────────────────

/** A contract is a row in the review's list and a page of its own (⏎
 * opens it, H and L go between them): the contract itself as it was and
 * as it is, why it changed, how far the change reached the code that
 * depends on it, what touches it (worked out), and a conversation. */
interface Contract {
  id: Id;
  /** How it reads in the code, or in a few words for a behaviour:
   * "review.grouped(r)", "Tab on a heading". */
  name: string;
  /** The agent's word for what sort of thing it is: "function", "JSON
   * field", "table", "endpoint", "key". Shown, never interpreted. */
  kind: string;
  /** The contract itself, whole: added has only `after`, removed only
   * `before`. */
  source: Source;
  /** What it is for, in a sentence: what the review's list shows. */
  why?: string;
  /** Its page: what changed, why, and what it costs callers. */
  prose: Prose;
  /** The code that depends on it, each with how far the change reached
   * it. */
  dependents?: Dependent[];
  /** A conversation about it, as a note has. */
  messages?: Message[];
}

type Source =
  | { change: "added"; after: Side }
  | { change: "removed"; before: Side }
  | { change: "changed"; before: Side; after: Side };

/** One side of a contract: a chunk where the code holds it in one place,
 * read at its `rev`; else written out whole. */
type Side = ChunkId | WrittenSource;

/** A contract no one place in the code holds, written out whole as code:
 * a table built by several migrations, a JSON format the code only
 * reads, an endpoint. */
type WrittenSource = { lang: string; text: string };

/** Code that depends on a contract, and how far the change reached it:
 * the blast radius, one place at a time. Its chunk is the line that
 * depends on the contract, not the start of the statement around it. */
type Dependent =
  | { chunk: ChunkId; impact: "none"; text?: string }
  | { chunk: ChunkId; impact: "adapted" | "reworked" | "missed"; text: string };

// ── Tours ───────────────────────────────────────────────────────────────

/** A part of the change, named for what it is about, never for a kind
 * of step ("Tests", "Callers"). */
interface Tour {
  title: string;
  colour: Colour;
  /** Its briefing, the first stop of its walk: what its steps show and
   * how they fit. */
  introduction: Prose;
  steps: Step[];
}

interface Step {
  id: Id;
  /** A claim about the code there, never a topic. */
  title: string;
  text?: Prose;
  /** None: a page, for one idea in many places. */
  chunk?: ChunkId;
  /** The user's replies, and the agent's answers. */
  messages: Message[];
}

// ── Notes ───────────────────────────────────────────────────────────────

/** Whatever is not walked: said once, on a chunk or on no line. A step on
 * the same chunk shows it. Its first message is what it says; the rest
 * are its conversation. Each kind has the statuses it can be in. */
type Note = {
  id: Id;
  title: string;
  chunk?: ChunkId;
  messages: Message[];
} & (
  | {
      kind: "issue";
      issue: "bug" | "flaw" | "risk";
      severity: "low" | "medium" | "high";
      status: "open" | "fixed" | "won't fix" | "not a problem";
    }
  | { kind: "decision"; status: "open" | "agreed" | "reversed" }
  | { kind: "suggestion"; status: "open" | "taken" | "declined" }
  | { kind: "question"; status: "open" | "answered" }
  | { kind: "fix"; status: "open" | "checked" }
  /** A remark that asks for nothing, yours or the agent's. */
  | { kind: "comment" }
);

// ── Code ────────────────────────────────────────────────────────────────

/** A chunk's id, a slug: "parse-groups". Steps, notes, contracts and
 * `{{chunk:parse-groups}}` in prose point at a chunk by it. */
type ChunkId = string;

/** Lines of a file, found by quoting the first and the last. */
interface Chunk {
  id: ChunkId;
  file: string;
  /** Where `from` was when written: the tie-break when its quote appears
   * more than once. */
  line: number;
  /** Its first line, verbatim. */
  from: string;
  /** Its last line, verbatim: the first match after `from`. None: one
   * line. */
  to?: string;
  /** Which version: the review's base or head, a commit, or "now", the
   * file as it is, unsaved edits and all. A removed line is "base". */
  rev: "base" | "head" | "now" | (string & {});
}

// ── Prose ───────────────────────────────────────────────────────────────

/** Markdown text, with diagrams attached. Used wherever someone explains
 * something: tours, steps, contracts, messages. */
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
   * - `{{chunk:id}}`, alone on a line: an excerpt, the chunk's lines read
   *   live from the file and drawn there.
   * - `{{diagram:name}}`, alone on a line: the diagram `diagrams[name]`,
   *   drawn there.
   * - Any other ``` fence is code, drawn as written. */
  text: string;
  /** Diagrams by name, each placed in `text` by `{{diagram:name}}`. Write
   * them before `text`, so the prose can describe what they show. */
  diagrams?: Record<string, Diagram>;
}

/** A flow, a sequence or a call tree; see the skill. */
type Diagram = { kind: "flow" | "sequence" | "calls" } & Record<
  string,
  unknown
>;

// ── Conversations ───────────────────────────────────────────────────────

interface Message {
  from: "you" | "agent";
  /** Yours, set by the plugin: when you wrote it. */
  at?: ISOTimestamp;
  prose: Prose;
  /** The agent's: the code it changed in answer. */
  changes?: ChunkId[];
}

/** When, to the second, in local time: "2026-10-13T10:00:00". */
type ISOTimestamp =
  `${number}-${number}-${number}T${number}:${number}:${number}`;

// ── Shared ──────────────────────────────────────────────────────────────

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

// ── What the screens derive, not written ────────────────────────────────
//
// - a chunk's contracts: those whose source or dependents name it or
//   overlap it
// - a step's notes: those on its chunk, shown on the step as it is walked
// - a tour's, a step's, a note's contracts: those its chunks touch
// - a contract's page: the tours, steps and notes that touch it, and its
//   files
// - a review's files: every chunk's, each marked with the tours whose
//   steps are in it, and with the notes
// - the notes' heading: how many of each kind are open

// ── Open questions ──────────────────────────────────────────────────────
//
// 1. Does a note carry a tour, for a finding that needs walking? Not
//    yet: it says where with excerpts, or names steps by `#step:7`.
// 2. `About`: keep `of`, or say both ends directly, `{ base: "HEAD",
//    head: "working tree" }`?
// 3. The review's `introduction` is a string while a tour's is Prose.
//    Should the review's carry diagrams too?
// 4. Rounds: kept only if a diff of what the agent changed in a round is
//    wanted.

// ── An example: the grouped review view, as this repo's commit 612f974 ──

const example: Review = {
  title: "A review's threads by the agent's groups",
  diff: { base: "7d56f39", head: "612f974" },
  status: "open",
  introduction:
    "The agent now sorts a review's threads into named, coloured groups (#contract:1). Everything that lists threads asks #contract:2 for them, so the screen, H and L and Home all follow the groups.",

  contracts: [
    {
      id: 1,
      name: "review.groups",
      kind: "JSON field",
      source: {
        change: "added",
        after: {
          lang: "ts",
          text: [
            "interface Review {",
            "  groups?: Group[];",
            "  threads: (Thread & { group?: string })[];",
            "}",
            "",
            "interface Group {",
            "  name: string;",
            "  colour?: Colour; // none: the next in the palette",
            "  summary?: string;",
            "}",
          ].join("\n"),
        },
      },
      why: "The agent says what the threads are about together, in the order to read them.",
      prose: {
        text: "Threads were one flat list in the order written. A review now names its groups once, and each thread names the one it is in, so the screen can draw a heading per group and colour its files.\n\nThe format is only ever read by `parse_groups`, so it is written out here rather than pointed at:\n\n{{chunk:parse-groups}}",
      },
      dependents: [
        {
          chunk: "draw-grouped",
          impact: "reworked",
          text: "The review screen draws a heading and a tree per group, where it drew one list of threads.",
        },
      ],
    },
    {
      id: 2,
      name: "review.ordered(r)",
      kind: "function",
      source: { change: "added", after: "ordered" },
      why: "One order for every list of threads, so they cannot disagree.",
      prose: {
        text: "Every list of threads asks for them in the groups' order: grouped first, the threads in no group last.",
      },
      dependents: [
        {
          chunk: "keys-hl",
          impact: "adapted",
          text: "H and L step through `review.ordered(r)`, where they stepped through `r.threads`.",
        },
        {
          chunk: "view-home",
          impact: "adapted",
          text: "Home lists a review's open threads in the same order as its screen.",
        },
      ],
    },
  ],

  tours: [
    {
      title: "Groups in the file",
      colour: "teal",
      introduction: {
        diagrams: {
          shape: {
            kind: "flow",
            direction: "right",
            nodes: [
              { id: "file", label: "groups in the file" },
              { id: "grouped", label: "review.grouped" },
              { id: "ordered", label: "review.ordered" },
              { id: "screens", label: "screen, H and L, Home" },
            ],
            edges: [
              { from: "file", to: "grouped", label: "checked" },
              { from: "grouped", to: "ordered" },
              { from: "ordered", to: "screens" },
            ],
          },
        },
        text: "A review names its groups once; each thread names the one it is in. Everything downstream reads them in one order:\n\n{{diagram:shape}}",
      },
      steps: [
        {
          id: 1,
          title:
            "A group the review does not name is an error, with the names it does",
          chunk: "unknown-group",
          text: {
            text: "A typo in a thread's `group` would otherwise drop it into the threads in no group, silently. The error lists the names the review does have, so the agent can fix it in one pass.",
          },
          messages: [],
        },
        {
          id: 2,
          title: "Every list of threads goes through review.ordered",
          chunk: "ordered",
          text: {
            text: "One function, so the screen, H and L and Home cannot disagree about the order (#contract:2).",
          },
          messages: [],
        },
      ],
    },
  ],

  notes: [
    {
      id: 1,
      kind: "decision",
      status: "open",
      title: "A thread in no group is listed last, with a warning",
      chunk: "unknown-group",
      messages: [
        {
          from: "agent",
          prose: {
            text: "Failing would lose your own threads, which have no group. See #step:1.",
          },
        },
      ],
    },
    {
      id: 2,
      kind: "issue",
      issue: "flaw",
      severity: "low",
      status: "open",
      title: "A ninth group repeats a colour",
      chunk: "group-type",
      messages: [
        {
          from: "agent",
          prose: {
            text: "The palette has eight colours, and a group with none takes the next. Past eight, two groups share one and their files can't be told apart.",
          },
        },
      ],
    },
    {
      id: 3,
      kind: "question",
      status: "open",
      title: "Should Home show each thread's group?",
      messages: [
        {
          from: "you",
          at: "2026-10-14T09:12:00",
          prose: {
            text: "Home lists the threads in the groups' order but never says which group each is in.",
          },
        },
      ],
    },
  ],

  chunks: [
    {
      id: "group-type",
      file: "lua/thread/model/review.lua",
      line: 43,
      from: "---@class (exact) thread.Group",
      to: "---@field summary string|nil",
      rev: "head",
    },
    {
      id: "parse-groups",
      file: "lua/thread/model/review.lua",
      line: 143,
      from: "local function parse_groups(p, raw)",
      to: "end",
      rev: "head",
    },
    {
      id: "unknown-group",
      file: "lua/thread/model/review.lua",
      line: 224,
      from: "      if type(t.group) == 'string' and not groups[t.group] then",
      to: "      end",
      rev: "head",
    },
    {
      id: "ordered",
      file: "lua/thread/model/review.lua",
      line: 429,
      from: "--- Its threads in the order its groups put them, which H and L go by.",
      to: "function M.ordered(r)",
      rev: "head",
    },
    {
      id: "draw-grouped",
      file: "lua/thread/draw/review.lua",
      line: 144,
      from: "  local list = review.grouped(r)",
      rev: "head",
    },
    {
      id: "keys-hl",
      file: "lua/thread/screen/keys.lua",
      line: 225,
      from: "  local list = review.ordered(r)",
      rev: "head",
    },
    {
      id: "view-home",
      file: "lua/thread/screen/view.lua",
      line: 86,
      from: "      for _, t in ipairs(review.ordered(r)) do",
      rev: "head",
    },
  ],
};

export { example };
export type { Review };
