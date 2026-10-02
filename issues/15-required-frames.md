# 15: Required Frames

**What to build:** Let the author demand that every Story contains a particular Frame:

```lisp
(:required-frames
  (ruby (reunited ruby henry))
  (jafar (married-to jafar jasmine)))
```

IPOCL plans backward from the Outcome, so a Frame only arises when some Step on the Outcome's causal chain gets it through frame discovery. A Character goal outside the Outcome is never pursued. A Required Frame seeds the plan with a **pseudo-step**: a Step with no Actors and no effects, whose one precondition is the Character goal. It is ordered after the init Step and before the goal Step, and is otherwise free. Whatever establishes that precondition must be the final Step of a Frame with that Character and Character goal.

The Character goal only has to become true at some point. It is protected up to the pseudo-step and may be undone afterwards, so a Desire can be achieved and then lost.

This is the mechanism behind the Protagonist's Desire (ticket 16), and potentially behind failed attempts (ticket 19) and ticks (ticket 20). It is a narrow version of the "author goals" in `spec.md` §9.

Rules:
- a new establisher Step must, in frame discovery, choose the required Character goal for the required Character. Children that make any other choice for that Actor are pruned;
- an existing Step can satisfy the requirement only if it is already the final Step of a matching Frame (D11: a reused Step never becomes the final Step of a new Frame);
- the goal test fails while any Required Frame is unsatisfied;
- the heuristic counts an unsatisfied Required Frame like an open motivation plus the h_add cost of its Character goal.

**Blocked by:** 06 (Joint actions and intentional threats), 09 (Heuristic search), 11 (Author preferences).

**Status:** todo

- [ ] Parser, printer, and round-trip test for `:required-frames`.
- [ ] Domain checks reject an unknown Character, and warn when a required Character goal is unreachable.
- [ ] On Bribe, requiring the Hero to hold a Frame for `has(villain, money)` gives the same Story as today. Requiring a Frame the Outcome doesn't need adds Steps for it.
- [ ] A Story never satisfies a Required Frame through another Character's Frame, or through a Step that isn't in any Frame.
- [ ] Every Story passes validation, and validation checks Required Frames independently of the search code.
- [ ] A test where a later Step undoes the required Character goal still yields a valid Story.
- [ ] Pseudo-steps are never narrated, are not Orphans, and are left out of story signatures.

**Notes:** See ADR-0004. Ticket 19 extends Required Frames with `:fail-first`. The pseudo-step is the building block that the "author goals" in `spec.md` §9 would also use.
