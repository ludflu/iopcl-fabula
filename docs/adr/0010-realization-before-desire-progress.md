# Realization before Desire progress (soft preference)

Story Genius problems declare a Protagonist, a Desire, and Misbeliefs. Good Stories usually show internal change (a Realization) before or as the Desire advances. Search can still reach valid Stories that put successful Desire progress first; we steer away from those partial plans with a soft preference rather than hard pruning.

## Mechanism

`(realization-before-desire-progress :weight W)` with default **soft 50**. Violations are counted in `linearize` order: each Protagonist Step that advances the Desire **before** the first Realization of a Protagonist Misbelief (same Realization definition as ticket 16 / `protagonistArc`). The count is monotone: adding a Realization earlier can only decrease violations.

## Desire progress

- A causal link or effect of a Protagonist Step that establishes the `:desire` literal (unifies with the problem's `:desire` under plan bindings).
- The `frameFinal` of a successful Protagonist Frame whose goal unifies with `:desire`. Failed `:fail-first` Frames (`frameFinal = Nothing`) do not count.

## Admissibility

Soft only; inadmissible penalty via `softPenalty` on `h`. Like `third-rail`, violations can decrease on partial plans, so hard pruning is disabled (`isRelevanceRule`); hard strength is checked only at the goal test.

## Scope

No `:protagonist` → zero violations (builtin Aladdin unchanged). No change to `additiveHeuristic` (ticket 29). Does not alter `validatePlan` or require Realizations on partial plans.

## `:fail-first` edge case

A blocked attempt shows the Misbelief blocking action; it is not successful Desire progress, so the penalty does not demand a Realization before it. The penalty applies when **successful** Desire progress precedes **any** Realization while Misbeliefs still hold in the narrative sense the planner tracks.
