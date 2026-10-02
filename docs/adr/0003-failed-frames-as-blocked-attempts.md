# Failed Frames are blocked attempts with an unexecuted Step

A failed Frame has an attempted Step that is placed and ordered in the plan but never executed. Exactly one of its preconditions is held false by a threat-protected causal link `c —¬p→ attempt`, and all its other preconditions are linked as normal. We chose this so that every failure has a checkable, narratable cause: the Character "had a real shot" (Cron) and one specific thing stopped them. Only the failed Frame's Character needs a Frame containing an attempted Step, so the joint-action rule (D2) doesn't make other Actors intend an attempt that never happens. Failed Frames enter plans only through Required Frames marked `:fail-first` (ADR-0004), because a preference alone cannot make a backward-chaining planner create Steps that the Outcome doesn't need.

## Considered Options

- **Abandoned Frame**: Interval Steps execute, there is no final Step, and the goal is false at the end. Rejected: nothing records why the Frame failed, so the Story can't say "but…", and an abandoned Frame can't be told apart from padding.
- **Pre-empted Frame**: another Step achieves the goal first or makes it impossible. Rejected as the general form. It can still be expressed as a blocked attempt whose blocker is that Step.

## Consequences

"Step" no longer implies "happens". Simulation, establisher search, Orphan checks, narration, and signatures must all distinguish unexecuted Steps. D14 (duplicate Frames are pruned) gains an exception: one failed Frame may precede a successful Frame for the same Character and Character goal.
