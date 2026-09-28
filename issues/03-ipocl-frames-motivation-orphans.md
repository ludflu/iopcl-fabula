# 03: IPOCL mode: Frames, motivation and Orphans (single-Actor)

**What to build:** With `--mode ipocl`, the planner only returns Stories in which every non-Happening Step is in a Frame of its Actor, and every Frame has a Motivating step. This ticket adds:

- frame discovery on new Steps (one effect or none per Actor);
- open motivation flaws, repaired by motivation planning from existing Steps, new Steps, or the initial state;
- motivation links and their orderings;
- duplicate-Frame pruning;
- Orphan detection;
- the IPOCL goal test (dead end when the agenda is empty but Orphans remain);
- validator checks for Definitions 3 and 6.

Happenings never get Frames. This ticket covers single-Actor schemas only.

**Blocked by:** 02 (Causal threats and negative preconditions).

**Status:** ready-for-agent

- [ ] `builtin tower --mode ipocl` reports that the search space is exhausted, while POCL mode on the same problem still solves it.
- [ ] A Tower variant with motivating actions solves in IPOCL mode, and every Step in the result is in an Interval.
- [ ] A Frame's Character can be motivated by an Intention listed in the initial state.
- [ ] A Happening in a solution is never an Orphan and never in an Interval.
- [ ] The validator rejects hand-built plans that have an Orphan, an unmotivated Frame, or a Motivating step that does not precede the Interval.
