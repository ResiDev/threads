# Explaining code to Alex: research, evidence, and what to change in threads and seam

Written 2026-11-06 from a Claude Code chat in sw-server. It is about how agents
should explain systems so that Alex keeps up with the codebase, and what that
means for threads.nvim (github.com/ResiDev/threads) and seam.nvim
(github.com/ResiDev/seam).

Sources: 1,091 of Alex's messages in sw-server chats (7 Oct to 6 Nov 2026),
the 7 reviews in `sw-server/.threads/`, the READMEs, `seam/SPEC.md` and
`threads/DIRECTION.md`, and the research listed at the end. The plugins were
read, not run.

## The short version

- Few of the failures came from a missing diagram. Most came from replies that
  were too long, covered too many points at once, or skipped a layer Alex did
  not know yet.
- The best learning moments were Alex restating something in their own words
  ("okay this is my understanding: …"). That habit is the one the research
  backs most strongly.
- Threads already fits the research well: one point at a time, next to the
  code. Its problems are in what the agent writes, so the fix is mostly in the
  `threads` skill.
- Seam gives the structure (what a name is, where it comes from, who uses it).
  Threads gives the meaning. They complement each other. Seam has two gaps for
  sw-server: Effect services, and `_tag` unions.

## Results: what went wrong, in Alex's words

| Pattern | Quote | Cause |
|---|---|---|
| Too long | "that explanation is way way too long", "15 essays of prose" | Prose where an artifact was needed |
| Too many points at once | "3. im confused… 5. what do you mean… 9. what race give me an example" | Menus of 6–11 items, each answered shallowly |
| A missing layer | "why am i not fully understanding this? what knowledge am i missing to fully grok this?" (pg transaction crash) | Explained our code, assumed the runtime underneath (Node EventEmitter, AI SDK data parts) |
| A rule with no example | "what does this mean? give me an example" | An abstract rule, no case |
| Too many new names | "what is a relinked vault?", "remind me what is decision missing again" | Design chats added terms faster than they could be learned |
| A key fact said in passing | The My Practice "billed" mix-up | "Grouped by invoice month" was mentioned three times as a side note, never asked as a question |
| Asked for a picture, got text | "that's not a diagram" | ASCII art inside prose |

What worked:

- Real data traced through the system ("how the ai sdk sees it, how the
  database sees it").
- Before and after diffs.
- HTML mockups for UI.
- Questions asked on code Alex was reading at that moment (`@file [lines]`).
- Restating it themselves. Each restatement surfaced a misconception that
  could then be corrected.

## The research

**Mayer's theory of multimedia learning.** People process words and pictures
in two channels. Working memory holds only a few pieces at once. Learning needs
active processing: picking out what matters, organising it, and linking it to
what you know. Effort comes in three kinds:

- **Extraneous**: spent on the presentation, not the idea. Cut it.
- **Essential**: what the idea itself needs. Manage it.
- **Generative**: making sense of it, where the learning happens. Encourage it.

| Principle | Finding | Effect size (d) | In practice |
|---|---|---|---|
| Coherence | Cut interesting but irrelevant material | 0.70–0.86 | No side notes, and no asides about other things the agent noticed |
| Signalling | Point to the key structure | 0.46 | Verdict first, the key line in bold |
| Redundancy | Saying the same thing twice in two forms hurts | 0.87 | A diagram *or* prose for a point, not both |
| Spatial contiguity | Put the words next to what they describe | 0.79 | The explanation next to the code line, not `file.ts:48` plus a paragraph elsewhere |
| Segmenting | Learner-paced pieces beat one block | 0.67–0.79 | One item per turn |
| Pre-training | Teach the parts and names before the process | 0.46 | "pg client is an EventEmitter" before the crash sequence |
| Multimedia | Words plus pictures beat words alone | large | Only when the picture shows how it works |

d is the difference between groups in standard deviations: 0.2 is small, 0.5
medium, 0.8 large. Caveats: an independent meta-analysis of 181 of Mayer's
studies found a smaller overall effect (g = 0.37), and it shrinks over time.
Most studies are short lab lessons with students. The effects are largest for
newcomers learning complex material.

**Self-explanation** (Chi 1989; Bisra et al. 2018, a meta-analysis of 64
studies). Learners who explain each step to themselves learn more than those
who re-read. Prompting people to do it helps by a moderate amount.

**The testing effect** (Roediger & Karpicke 2006). Trying to recall beats
re-reading, a week later, even though the readers saw the text more often.

**The illusion of explanatory depth** (Rozenblit & Keil 2002). People rate
their understanding of zips and toilets much lower after trying to explain
them step by step. Reading an explanation feels like understanding.

**Refutation texts** (science education, e.g. Tippett 2010). To change a
belief, state the misconception, say why it is wrong, then give the right
model. Giving only the right model works less well.

**The expertise reversal effect** (Kalyuga et al. 2003). Step-by-step help
that suits a newcomer slows down someone who knows the area.

**Program comprehension** (Pennington 1987). Programmers first build a model
of the code's structure (control flow, what calls what), then a model of what
it means in the domain.

**Anthropic, "How AI assistance impacts the formation of coding skills"**
(29 Jan 2026). A randomised trial with 52 mostly junior engineers learning
Trio in 35 minutes. The AI group scored 50% on the quiz and the hand-coding
group 67% (d = 0.74). The AI group was about 2 minutes faster, which was not
significant. The biggest gap was on debugging. By how people used the AI:

| Pattern | n | Score |
|---|---|---|
| Generated code, then asked questions to understand it | 2 | 86% |
| Code plus explanations | 3 | 68% |
| Conceptual questions only | 7 | 65% |
| Handed everything to the AI | 4 | 39% |
| A question or two, then handed over | 4 | 35% |
| AI to debug or check | 4 | 24% |

Limits: the groups are tiny, there was no long-term follow-up, and the
authors draw no causal link. They expect agentic tools to have stronger
effects. Alex mostly works the top way: generating code, then asking
questions about it. The risk is in long autonomous runs where only the
summary is read.

## Rules for explaining (for AGENTS.md or a skill)

1. Verdict in 1–2 lines, then one real example traced end to end, then the
   mechanism only as deep as asked, then stop.
2. Pick the format from the question:

   ```text
   how does data move?         → trace table: one record at each stage
   what states/outcomes?       → state diagram, rendered
   what changes?               → before/after diff
   what does the UI look like? → HTML mockup
   what should I read?         → at most 3 files, ranked, or a short tour
   ```
3. One item at a time. Rank long lists instead of sending menus.
4. If a question survives two rounds, name the missing layer and teach it
   alone first.
5. When Alex restates, mark each claim right, wrong or nearly right, and
   correct the wrong ones directly.
6. At most two new terms per answer, each defined on first use.
7. Ask about definitions with an example ("work in March, invoiced in May:
   which month?"). Don't state them in passing.
8. Optional "predict what happens if…" checks on core code.

Example of rule 1, on "how is gbpOf nullable?":

```text
Verdict: null only for a non-zero, non-GBP amount with no rate for its day.

amount  currency  units_per_gbp  →  gbpOf
0       EUR       null           →  0        a zero needs no rate
500     GBP       null           →  500      GBP needs no rate
500     EUR       1.17           →  427.35
500     EUR       null           →  null     500 / null is null in SQL

Mechanism: a `case` whose last branch divides by the joined rate.
Stop: want to see how filteredSum treats that null?
```

## Threads: what to change

How it fits the research: one thread per point (segmenting), next to the code
(spatial contiguity), replies in place (self-explanation). In use, Alex
replies point by point ("yup that seems like a good change") and restates
("Okay this is my understanding: we only fetch the first 200 documents…").

What the 7 reviews in `sw-server/.threads/` show:

1. The agent's first message in a thread averages 1,200–1,400 characters.
2. One review has 31 threads, and several were dismissed ("pointless edge
   case", "man this is some random edge case").
3. Threads can draw flow, sequence and call diagrams, but the 7 reviews hold
   9, 7 of them in one review (how partner referrals work). The three biggest
   reviews have none. Alex noted on 15 Oct: "none of the tour ever seems to
   use diagrams, they are higher leverage".
4. Restatements get a vague "yes" instead of a check of each claim.
5. A thread can still confuse ("you're really confusing me here").

Changes:

- **In the `threads` skill (then `answering-threads`)**:
  - A lead of about 3 lines and one example per thread, the rest folded.
  - 5–10 threads shown, the rest in a folded "minor, probably skip" group.
  - A diagram whenever the point is states, flow or "which path does this
    take".
- **A "my understanding" message kind.** Alex writes down their model. The
  agent answers with each claim marked right, wrong or nearly right.
- **Build the planning mode next** (the end of `DIRECTION.md`): a thread per
  decision, options side by side, one example of each. The worst confusion was
  in design chats, not reviews: the web-search R1–R6 menu, the Harvey sync
  design, the pg transaction fix.

## Seam: what to change

How it fits: it answers "what is X?" and "where does it come from?" from the
LSP with one key, and nothing it shows is made up. That is pre-training as a
tool, and the structure model from Pennington. It was built from 1 Nov and has
been used once in chat (`@seam://code/11`), so these are gaps to consider, not
verdicts.

1. **Effect services and schemas are out of v1.** In sw-server those are the
   main contracts: layers, `Context.Tag` services and tagged errors.
2. **A `_tag` union view.** The general state view was dropped on 31 Oct
   because code keeps state in too many ways. sw-server's coding standards
   require `_tag` unions, so the narrow case fits here. On 5 Nov Alex asked,
   on a seam link: "what is the recheck uploader for now? … when does that
   happen only if uploader uknown?". A view of where each variant is made and
   matched answers that from facts (illustrative, not real line numbers):

   ```text
   RecheckUploader  made in  retries.ts:52  stored uploader failed the check, < 14 days after upload
                    matched  newFiles.ts:140, problemEmails.ts:88
   RetryFailure     made in  retries.ts:47  a transfer failed, under the retry limit
   ```
3. **A link to threads.** A key on a seam row starts a thread ("why does this
   exist?") with seam's facts attached, so the agent starts from correct
   structure and Alex gets the meaning.

A challenge: eleven rounds of mocks and a 1,186-line spec in five days. Before
more design rounds, use it for a week and note which questions it answered
without asking an agent.

## Open decisions

- Where the explaining rules live: `AGENTS.md` (every agent) or a memory.
- What to build first: the threads skill changes (cheapest, the most effect
  right away), the "my understanding" message, the planning mode, or seam's
  `_tag` view.
- Fix the `show-me` skill, which still says to use Mermaid.

## Sources

- Anthropic, How AI assistance impacts the formation of coding skills:
  https://www.anthropic.com/research/AI-assistance-coding-skills
  (paper: https://arxiv.org/abs/2601.20245)
- Chi et al. 1989, self-explanation:
  https://pcl.sitehost.iu.edu/rgoldsto/courses/cogscilearning/chiselfexplanation.pdf
- Bisra et al. 2018, self-explanation meta-analysis:
  https://doi.org/10.1007/s10648-018-9434-x
- Mayer's principles and effect sizes: https://edtechbooks.org/docx/10349
- Which multimedia strategies actually improve learning?:
  https://carlhendrick.substack.com/p/which-multimedia-strategies-actually
- From memory, not checked online in this chat: Roediger & Karpicke 2006,
  Rozenblit & Keil 2002, Tippett 2010, Kalyuga et al. 2003, Pennington 1987.
