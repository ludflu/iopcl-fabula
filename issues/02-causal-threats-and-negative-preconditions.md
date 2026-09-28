# 02: Causal threats and negative preconditions

**What to build:** POCL mode solves the Tower domain from §2.2.1, where the Outcome is that the princess is locked in the tower and the king is dead. This ticket adds:

- causal-threat detection as agenda flaws, resolved by promotion, demotion, or separation;
- support for negative preconditions and negative Outcome literals from the initial state under the closed-world assumption;
- reuse of existing Steps as establishers;
- validator simulation of a linearisation from the initial state.

**Blocked by:** 01 (Tracer bullet: POCL solves a one-action story from the CLI).

**Status:** ready-for-agent

- [ ] `narrative-planning builtin tower --mode pocl` returns a valid plan, for example "princess kills king; princess locks herself in tower".
- [ ] A test plan with an unresolved clobbering Step is flagged as a causal threat. Each of the three resolvers produces a consistent child when it applies.
- [ ] Negative preconditions that the initial state satisfies (the fact is absent) are supported by the init Step.
- [ ] Every returned plan passes validation, and simulating it reaches the Outcome.
- [ ] Property test: no refinement produces a child with cyclic orderings or inconsistent bindings.
