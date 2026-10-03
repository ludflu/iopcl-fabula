# No-possible-Frame lookahead (monotone adopt impossibility)

Spec §8 lists pruning intent flaws when no Frame can explain a Step. We implement the **monotone** slice first: when **adoption** of `(Step, Frame)` is **permanently inconsistent** with the partial order, the planner treats the decision as **stay out** without enqueueing an intent flaw.

## Predicate

`intentAdoptForeverImpossible plan s c` mirrors the ordering fold in `resolveIntentFlaw`'s adopt branch. If `addOrder` fails for any required edge, failure is permanent: orderings only accumulate.

## Hook

In `finalize`, after `intentCandidates` and before updating pending intents:

- **Pending:** only pairs that are not forever impossible.
- **Proposed:** both pending pairs and skipped pairs are inserted into `planProposedIntent`, so ADR-0002's "each pair decided once" holds: skipped pairs are implicitly resolved as reject-adopt.

## Heuristic (ticket 29)

Pending pairs that remain hopeless before filtering elsewhere receive `hopelessIntentCost` in `additiveHeuristic` (inadmissible; weighted A* already uses `w > 1`).

## Soundness

We never skip a pair whose adopt branch could become satisfiable later solely by adding orderings that remove constraints. `addOrder` failures are due to cycles or violations of implicit init/goal bounds; future refinements add more `before` edges, not fewer.
