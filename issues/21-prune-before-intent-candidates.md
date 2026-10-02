# 21: Prune before computing intent candidates

**What to build:** In `Refine.finalize`, run the hard-preference check (`keep`) before computing intent candidates, not after. Hard preferences read only Steps and Frames, never `planPendingIntent` or `planProposedIntent`, so the result is the same. But the candidates are no longer computed for children that are about to be pruned. Because `Plan`'s fields are strict, the full candidate list and the proposed set are built today before `keep` runs.

**Baseline** (40k expansions of `builtin aladdin`, profiled): `finalize` runs 234k times but only 99k children survive, so about 57% are pruned. `intentCandidates` accounts for about 18% of total time. The expected saving is about 10% of runtime.

**Blocked by:** 13 (Level B: full Aladdin in under 5 minutes).

**Status:** done

- [x] `finalize` prunes first and computes candidates only for surviving plans, in both IPOCL and POCL mode.
- [x] `cabal bench aladdin` reports the same counts as before (first Story: expanded 203247, generated 493512) and the same five Stories.
- [x] All tests pass, including the trace golden test.
- [x] The ticket records the before and after benchmark times when it is closed.

## Result

First Story: 20.7 s → 18.4 s. First five Stories: 30.7 s → 26.9 s. Counts and Stories unchanged.
