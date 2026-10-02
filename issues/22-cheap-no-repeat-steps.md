# 22: Cheap `no-repeat-steps` check

**What to build:** `Preferences.violations` counts `NoRepeatSteps` by building a `Text` label (`stepLabel`) for every fully bound Step and calling `nub` on the list, which is quadratic. Hard preferences run on every child plan. Instead, key each fully bound Step by its ground action's index and its resolved arguments, and count duplicates with a `Map` or `Set`.

Optionally, go further: since a plan can only gain repeats when a Step is added or its arguments become fully bound, check only the affected Step against the others. Do this only if the simple version still shows up in the profile.

**Baseline** (40k expansions of `builtin aladdin`, profiled): the hard-preference check is about 10% of total time and 15% of allocation. `stepLabel` alone is called 1.25M times. The expected saving is about 9% of runtime.

**Blocked by:** 11 (Author preferences), 13 (Level B: full Aladdin in under 5 minutes).

**Status:** done

- [x] `violations` for `NoRepeatSteps` no longer calls `stepLabel` or `nub`.
- [x] Two Steps of the same schema with different arguments are not repeats. Two with the same ground action and arguments are. A Step whose arguments are not yet fully bound is still ignored. The existing preference tests cover these cases, or new ones are added.
- [x] `cabal bench aladdin` reports the same counts as before (first Story: expanded 203247, generated 493512) and the same five Stories.
- [x] The ticket records the before and after benchmark times when it is closed.

## Result

First Story: 18.4 s → 17.4 s. First five Stories: 26.9 s → 25.4 s. Counts and Stories unchanged. Steps are keyed by `(gaIndex, resolved arguments)`. The resolved arguments are needed because a ground action's literal-valued arguments can still be unbound. New tests cover the different-arguments and unbound-arguments cases. The incremental version wasn't needed: `NoRepeatSteps` no longer shows up in the profile. `violations` is still about 9% of time, but that cost is now in `allow-goals` unification and `framesOf`.
