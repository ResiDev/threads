# Reviews agents wrote

Test data for `draw/` and the screen tests: reviews in format 2, written
by agents following `skills/answering-threads/SKILL.md`, about this
repository at commit `9cde8c4`. Check that commit out, put a review in
its `.threads/`, and every chunk in it is found.

- `the-skill-on-format-2-and-stage-2-fixes.json`: a review of the diff
  from `75d4504`. Eight threads by intent, riskiest first, with tours of
  what changed, every caller and the tests; a bug, flaws and trade-offs;
  steps on removed lines; diagrams and checks.
- `how-the-model-works-out-its-state.json`: a review of the code as it
  stands. Five threads, one tour each, with pages, excerpts, links,
  diagrams and worked examples.

Then a round of replies: one in a thread with a chunk the user started,
two in threads' own conversations and three in steps, all answered by a
third agent; one thread closed as not a problem. Nothing waits in either.

Their steps had no ids when the agents wrote them; when steps got ids
(after stage 4), each was numbered in order along its thread's tours,
so `#12.3` still names the step it did, and the links they wrote
for a step of a thread's first tour as `#1.1.3` read `#1.3`.

The first review's `groups`, and each thread's `group`, were added by
hand once reviews had groups, as the skill now has the agent write them.

Their steps and messages had `notes`, marks on lines; those were taken
out when marks were (2026-10-15), so what they said is no longer in
either review.
