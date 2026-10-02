# 18: Backstory on demand

**What to build:** Let the planner invent backstory facts when a Step needs them. Cron makes a plot point possible by digging into the past: "the answer always lies in the past" (*Story Genius*, ch. 12–13). Her example is deciding that Nora owns the house Ruby lives in. This is initial-state revision (Riedl & Young 2006, "Story planning as exploratory creativity").

The author lists candidate facts that are neither true nor false at the start:

```lisp
(:possible-backstory
  (owns nora house)
  (owes jafar genie)
  (intends jasmine (married-to jasmine aladdin)))
```

Causal and motivation planning gain one more establisher kind. When an open condition unifies with a possible-backstory literal, the init Step can supply it by committing the literal. A committed literal behaves as if it were in the initial state from then on, and is listed in output under "Backstory".

Each commitment adds to `g`: 3 for a fact and 5 for an Intention, overridable per problem. Intentions cost more because a Frame motivated by backstory skips motivation planning entirely. If backstory were cheap, search would explain every motive by fiat. `(max-backstory n)` is a new Author preference that caps the number of commitments, hard or soft like the others.

Consistency rules:
- committing `p` is inconsistent if the plan already has a causal link `init —¬p→ s`, which is how closed-world support is recorded today. The reverse is also true: once `p` is committed, `¬p` gets no closed-world support;
- a possible-backstory literal never gets closed-world support. Until it's committed, it is unknown, not false;
- domain checking rejects a candidate that contradicts `:init`, or that is a static constraint predicate.

**Blocked by:** 02 (Causal threats and negative preconditions), 09 (Heuristic search), 11 (Author preferences).

**Status:** todo

- [ ] A test problem that returns `Exhausted` without `:possible-backstory` is solved once the one missing fact is listed, and the output shows that fact under "Backstory".
- [ ] A test where one Step needs `p` and another needs `¬p` from the init Step: the plan that commits `p` can't also use closed-world support for `¬p`.
- [ ] Every Story passes validation when the committed literals are added to the initial state.
- [ ] Committed literals are part of the story signature, so two Stories that differ only in their backstory count as distinct.
- [ ] The heuristic treats a possible-backstory literal as reachable at commitment cost.
- [ ] Aladdin's Stories are unchanged when the problem has no `:possible-backstory`, and still keep their `order` Steps when it lists Intentions those Steps could otherwise supply.
- [ ] `max-backstory` has hard and soft tests.
- [ ] Parser, printer, and round-trip test.

**Notes:** Backstory holds facts and Intentions only. Cron's origin scenes and turning points are past *events*. Steps set before the story begins would need a pre-story region of the ordering and flashback narration, so they're out of scope here. Possible-backstory Intentions are the most useful case: they give a Frame a Motivating step without inventing a motivating Action.