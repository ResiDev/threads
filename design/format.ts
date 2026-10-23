// The format: the JSON an agent writes for a review, one file at
// `.threads/<id>.json`. Every screen is derived from it, so this is the
// real set of primitives. The model reads it in lua/thread/model/, one
// file per type here, and that is the truth: where this file and the
// model differ, this file is wrong. There is no format number; a review
// in an older shape does not read, and `show.lua --check` says what each
// old field became.
//
// The aim: the big picture up front, and every detail hanging off it. A
// review is five things, read top to bottom on one screen: its
// introduction, the contracts the change touches, the tours that walk the
// change, the files (worked out, never written) and its notes, where
// anything else goes.
//
// Code is written once: every chunk is in the review's `chunks`, and
// everything else points at one by its id.
//
// Every object is exact: a field not named here is an error. The types
// read top down: the review, then its parts in the order the screen
// shows them, then what they share.
//
// Check it with: tsc --noEmit --strict design/format.ts

// ── The review ──────────────────────────────────────────────────────────

/** Its id is its file's name, which the file does not hold. */
interface Review {
  title: Line;
  /** None: about the code as it stands, as a tour of how auth works is. */
  diff?: About;
  /** None: open. A message of yours opens a closed review again. */
  status?: "open" | "closed";

  /** The big picture, read first: what the change is for, how it works,
   * and the order the tours tell it in. Names contracts inline: "threads
   * come out of #contract:2". */
  introduction?: Prose;

  /** What other code relies on that the change touched: the joints of
   * the change. Implementation inside a function is not a contract. */
  contracts?: Contract[];

  /** The change, walked: each listed tour a part of it, in the order to
   * read them. Together their steps are on every hunk worth a look. An
   * unlisted tour is seen only where prose places it. */
  tours?: Tour[];

  /** Everything that is not walked: issues, decisions, suggestions,
   * questions, fixes and comments, yours and the agent's. Listed last, a
   * row each, grouped by kind. */
  notes?: Note[];

  /** Every place in the code the review points at, each written once.
   * A chunk nothing points at is warned of. */
  chunks?: Chunk[];
}

/** The diff a review is about: `of` the changes in the working tree, or
 * from `base` to `head` (none: to the working tree). Never both. */
type About =
  | { of: "unstaged" | "staged" | "uncommitted" }
  | { base: Line; head?: Line };

// ── Contracts ───────────────────────────────────────────────────────────

/** A contract is a row in the review's list and a page of its own (⏎
 * opens it, H and L go between them): the contract itself as it was and
 * as it is, why it changed, how far the change reached the code that
 * depends on it, what touches it (worked out), and a conversation. */
interface Contract {
  /** Contracts count their own ids; each is used once. */
  id: Id;
  /** How it reads in the code, or in a few words for a behaviour:
   * "review.grouped(r)", "Tab on a heading". */
  name: Line;
  /** The agent's word for what sort of thing it is: "function", "JSON
   * field", "table", "endpoint", "key". Shown, never interpreted. */
  kind: Line;
  /** The contract itself, whole: added has only `after`, removed only
   * `before`. */
  source: Source;
  /** What changed in it, in a sentence: what the review's list shows. */
  why?: Line;
  /** Its page: what changed, why, and what it costs callers. */
  prose: Prose;
  /** The code that depends on it, each with how far the change reached
   * it: its blast radius. */
  dependents?: Dependent[];
  /** A conversation about it, as a note has. */
  messages?: Message[];
}

type Source =
  | { change: "added"; after: Side }
  | { change: "removed"; before: Side }
  | { change: "changed"; before: Side; after: Side };

/** One side of a contract: a chunk where the code holds it in one place,
 * covering only the contract (a function's signature, not its body),
 * read at its `rev`, `base` for `before` and `head` for `after`; else
 * written out whole. */
type Side = ChunkId | WrittenSource;

/** A contract no one place in the code holds, written out whole as code:
 * a table built by several migrations, a JSON format the code only
 * reads, an endpoint. Neither field may be blank. */
type WrittenSource = { lang: Line; text: string };

/** Code that depends on a contract, and how far the change reached it:
 * the blast radius, one place at a time. Its chunk is the line that uses
 * the contract, not the start of the statement around it. Every impact
 * but `none` says in `text` what it had to do and what it cost; `missed`
 * is code that needs a change the diff did not make. */
type Dependent =
  | { chunk: ChunkId; impact: "none"; text?: string }
  | { chunk: ChunkId; impact: "adapted" | "reworked" | "missed"; text: string };

// ── Tours ───────────────────────────────────────────────────────────────

/** A part of the change, named for what it is about, never for a kind
 * of step ("Tests", "Callers"). Listed, a row in the review's tours; or
 * unlisted, a short walk that explains something, seen only where prose
 * places it with `{{tour:2}}`. Either can be placed. */
type Tour = {
  /** Tours count their own ids; each is used once. */
  id: Id;
  title: Line;
  /** One or more. */
  steps: Step[];
} & (
  | {
      /** None: listed. */
      listed?: true;
      /** Tells it apart from the review's other listed tours: each has
       * its own while there are sixteen or fewer, else a warning. */
      colour: Colour;
      /** Its briefing, the first stop of its walk: what its steps show
       * and how they fit, with a diagram when they have a shape. */
      introduction: Prose;
    }
  | {
      /** The prose it is placed in is its briefing, so it needs none,
       * and it is walked from its first step. A few steps: past three,
       * a warning. Placed nowhere, it is never seen: a warning. */
      listed: false;
      colour?: Colour;
      introduction?: Prose;
    }
);

interface Step {
  /** Steps count their own ids across all the review's tours; each is
   * used once. */
  id: Id;
  /** A claim about the code there, never a topic. */
  title: Line;
  /** None, on no chunk: a page that says nothing but its title, warned
   * of. */
  text?: Prose;
  /** None: a page, for one idea in many places. */
  chunk?: ChunkId;
  /** The user's replies, and the agent's answers. None: no messages. */
  messages?: Message[];
}

// ── Notes ───────────────────────────────────────────────────────────────

/** Whatever is not walked: said once, on a chunk or on no line. A step on
 * the same chunk shows it. Its first message is what it says; the rest
 * are its conversation. Each kind has the statuses it can be in, and
 * only an issue has `issue` and `severity`. */
type Note = {
  /** Notes count their own ids; each is used once. */
  id: Id;
  title: Line;
  /** None: on no line. */
  chunk?: ChunkId;
  /** One or more: the first says what it is. */
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
  /** A remark that asks for nothing, yours or the agent's: no status. */
  | { kind: "comment" }
);

// ── Code ────────────────────────────────────────────────────────────────

/** A chunk's id, a slug of letters, digits, `-`, `_` and `.`:
 * "parse-groups". Steps, notes, contracts, diagram nodes, a message's
 * `changes` and `{{chunk:parse-groups}}` in prose point at a chunk by
 * it. */
type ChunkId = string;

/** Lines of a file, found by quoting the first and the last. */
interface Chunk {
  /** Each chunk has its own. */
  id: ChunkId;
  /** From the repository's root. */
  file: Line;
  /** Where `from` was when written, from 1: the tie-break when its quote
   * appears more than once. */
  line: number;
  /** Its first line, verbatim: one line. */
  from: string;
  /** Its last line, verbatim: the first match after `from`. None: one
   * line. */
  to?: string;
  /** Which version: the review's base or head (only in a review with a
   * `diff`), a commit, or "now", the file as it is, unsaved edits and
   * all. A removed line is "base". */
  rev: "base" | "head" | "now" | (string & {});
}

// ── Prose ───────────────────────────────────────────────────────────────

/** Markdown text, with diagrams attached: an object, never a
 * bare string. A review's and a tour's introduction, a step's text, a
 * contract's page and every message are prose. */
interface Prose {
  /** Markdown, not blank, read when it is drawn. Bold, `#` headings,
   * `-` / `1.` lists and tables are drawn; anything else (links,
   * italics) shows as written. On top of markdown:
   *
   * - `#step:7`, `#note:12`: a link to that step or note.
   *   `other-review#note:12` is one in another review, by its id.
   * - `#contract:3`: a contract, drawn as its name and linking to its
   *   page.
   * - `` `name` ``: code, and a link to it when the name is found in
   *   the repo: where it is defined, else where it appears. A place
   *   written after it pins it: `` `sorted_keys` (json.lua:37) ``.
   * - `{{chunk:id}}`, alone on a line: an excerpt, the chunk's lines read
   *   live from the file and drawn there, fifteen at most. It must name
   *   one of the review's chunks.
   * - `{{diagram:name}}`, alone on a line: the diagram `diagrams[name]`,
   *   drawn there. It must name one of this prose's diagrams.
   * - `{{tour:2}}`, alone on a line: one of the review's tours, drawn
   *   there; Tab turns it from its steps' titles alone, to their text
   *   with where each is, to their code inline; `t` goes to it, ⏎ walks
   *   it.
   * - `{{contract:3}}`, alone on a line: one of the review's contracts,
   *   drawn there; Tab turns it from itself as it is, what changed
   *   marked, to against as it was, to one row; `c` goes to it, ⏎
   *   opens its page. Placing it makes what
   *   it is in one of what touches it.
   * - Any ``` fence is code, drawn as written; nothing inside one is
   *   placed. */
  text: string;
  /** Diagrams by name (letters, digits, `-`, `_` and `.`), each placed
   * in `text` by `{{diagram:name}}`; one never placed is warned of.
   * Write them before `text`, so the prose can describe what they
   * show. */
  diagrams?: Record<string, Diagram>;
}

type Diagram = Flow | Sequence | Calls;

/** Boxes and arrows. */
interface Flow {
  kind: "flow";
  /** One or more, each with an id of its own. */
  nodes: (Node & { id: string })[];
  edges?: { from: string; to: string; label?: Line; dashed?: boolean }[];
  /** None: down. */
  direction?: "down" | "right";
}

/** Messages between participants, in order. */
interface Sequence {
  kind: "sequence";
  /** One or more, each with an id of its own; a label is one line. */
  participants: (Node & { id: string })[];
  /** One or more. `reply` draws it as an answer. A label is one line. */
  messages: { from: string; to: string; label?: Line; reply?: boolean }[];
}

/** A call tree, at most 32 deep. */
interface Calls {
  kind: "calls";
  root: CallNode;
}

type CallNode = Node & { id?: string; children?: CallNode[] };

/** A box: its label, not blank, a Line (more than one only in a flow), and
 * the code it stands for, by its chunk's id. */
interface Node {
  label: string;
  chunk?: ChunkId;
}

// ── Conversations ───────────────────────────────────────────────────────

interface Message {
  from: "you" | "agent";
  /** Yours, set by the plugin: when you wrote it. The agent's has none:
   * the plugin notes when it first showed up. */
  at?: ISOTimestamp;
  prose: Prose;
  /** The agent's only: the chunks it changed in answer, by id. */
  changes?: ChunkId[];
}

/** When, to the second, in local time: "2026-10-13T10:00:00". */
type ISOTimestamp =
  `${number}-${number}-${number}T${number}:${number}:${number}`;

// ── Shared ──────────────────────────────────────────────────────────────

/** One line: no line breaks, tabs or other control characters, since it
 * is drawn as a row, as wide as it measures. Titles, names and labels
 * are lines; prose and code are not, and code quoted from a file (a
 * chunk's `from` and `to`) keeps its tabs. */
type Line = string;

/** A whole number, 1 or more. Steps, notes and contracts each count their
 * own ids from 1. An id is never changed and never reused. Prose links
 * one as `#step:7`, `#note:12`, `#contract:3`, and the .seen file names
 * their conversations `step:7`, `note:12`, `contract:3`. */
type Id = number;

/** The first eight are furthest apart. Red is left out: it reads as
 * wrong. */
type Colour =
  | "orange"
  | "yellow"
  | "lime"
  | "teal"
  | "sky"
  | "blue"
  | "violet"
  | "pink"
  | "rose"
  | "amber"
  | "green"
  | "mint"
  | "cyan"
  | "indigo"
  | "purple"
  | "magenta";

// ── What the screens derive, not written ────────────────────────────────
//
// - whose move each conversation is, from its last message; what you have
//   read, walked and accepted, kept in `<id>.seen`, which only the plugin
//   writes
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
// 1. Does a note carry a tour, for a finding that needs walking? Yes:
//    an unlisted tour, placed in its prose with `{{tour:2}}`.
// 2. `About`: keep `of`, or say both ends directly, `{ base: "HEAD",
//    head: "working tree" }`?

// ── An example: the grouped review view, as this repo's commit 612f974 ──

const example: Review = {
  title: "A review's threads by the agent's groups",
  diff: { base: "7d56f39", head: "612f974" },
  status: "open",
  introduction: {
    text: "The agent now sorts a review's threads into named, coloured groups (#contract:1). Everything that lists threads asks #contract:2 for them, so the screen, H and L and Home all follow the groups.",
  },

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
      id: 1,
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
              { id: "ordered", label: "review.ordered", chunk: "ordered" },
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
