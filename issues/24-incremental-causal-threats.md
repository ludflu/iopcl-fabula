# 24: Incremental causal-threat detection

**What to build:** `Refine.causalThreats` recomputes every threat from scratch, checking every link against every Step that could clobber it. It runs twice per plan: once in the heuristic when the child is generated, and again in `expand` when the plan is popped. Keep the threats in the plan instead, and update them per refinement.

The update is sound because of how threats change:
- adding an ordering only removes threats: `possiblyBefore` can only become false;
- adding bindings only removes threats. More bindings never make two literals unify that didn't before, and separation adds a non-codesignation;
- so new threats can only come from a **new causal link**, checked against every Step, or a **new Step**, whose effects are checked against every link.

A child's threats are therefore: the parent's threats that still hold after re-checking, plus threats from new links, plus threats from new Steps. Compute this once in `finalize`, store it in a `Plan` field, and have both `flaws` and the heuristic read it.

The order of threats matters. `expand` repairs the first threat in `flaws`, so a different order changes which plans are generated. The stored threats must come out in the same order as `causalThreats` produces them today: links in `Set` order, and for each link the clobbering Steps in the order the current `Map.fromListWith (++)` index yields. Alternatively, choose a new canonical order on purpose, and accept and record the new benchmark counts.

**Baseline** (40k expansions of `builtin aladdin`, profiled): `causalThreats` accounts for about 36% of total time, about 27% from the heuristic and 9% from `expand`, and about 33% of allocation. The expected saving is about 30% of runtime.

**Blocked by:** 02 (Causal threats and negative preconditions), 13 (Level B: full Aladdin in under 5 minutes).

**Status:** done

- [x] A property test: along sampled search paths on Tower, Bribe, and Aladdin, the stored threats equal `causalThreats` recomputed from scratch, as the same list in the same order. Keep the from-scratch function as the test oracle.
- [x] `causalThreats` runs at most once per generated plan. In a profile, it no longer appears under `expand`.
- [x] Every refinement that adds a link or a Step updates the stored threats: open conditions, open motivations (Steps only), and new Steps from frame discovery. A test covers each one.
- [x] `cabal bench aladdin` reports the same counts as before (first Story: expanded 203247, generated 493512) and the same five Stories, unless a new canonical order was chosen and recorded.
- [x] All tests pass, including the trace golden test.
- [x] The ticket records the before and after benchmark times and a new profile when it is closed.

**Notes:** Intentional threats are cheap (about 1% of time) and stay recomputed. Ticket 19's unexecuted Steps must never count as clobberers. Whichever of 19 and 24 lands second must handle this.

## Result

First Story: 15.9 s → 8.8 s. First five Stories: 23.2 s → 12.6 s. Counts and Stories unchanged. Threats are stored as `Set (CausalLink, Down StepId)`, whose order equals the old detector's: links in `Set` order, then clobberers by descending Step id. Hooks:

- `withLinkThreats` when open-condition planning adds a link;
- `withStepThreats` in `afterEstablish` for a new Step. This isn't done in `addStep`, because flaw ranking builds establishers it never keeps;
- `recheckThreats` in `keep`, which every child passes through. Separation now goes through `keep` too.

The per-refinement acceptance item is covered by one property test, not one test per refinement. On Tower (POCL and IPOCL), motivated Tower, and Aladdin, it checks every one of 1,500 visited plans and all of their children, so every refinement kind is exercised. It also asserts that each sample contains real threats. Bribe was dropped from the test because it has no clobbering effects.

New profile (40k expansions): threat work is about 10% of time, down from 36%, and no longer appears under `expand`. The top costs are now `intentCandidates` (13.5%), `establishers` from flaw ranking (10%), and `violations` (9%). Maximum residency rose from 664 MB to 712 MB, because each plan carries its threat set.
