# 23: Precomputed literal costs

**What to build:** `Heuristic.literalCost` runs on every open condition, open motivation, and Orphan of every child plan. For each call it scans the lifted effect patterns of the literal's predicate and unifies against each one. Move that work to load time:

- after the reachability fixpoint, compute the final cost of every ground literal a plan can ask for: every ground action's preconditions, the Outcome, and `intends(c, e)` for every Actor `c` and effect `e` of each ground action. Store the costs in one `Map Literal Int` (or `Maybe Int` for unreachable). `literalCost` looks there first, and falls back to today's computation for literals not in the table, such as those with unbound literal-valued arguments;
- precompute the cheapest Intention for each Character (`intends(a, anything)`), which the Orphan estimate currently finds by scanning every `intends` pattern.

**Baseline** (40k expansions of `builtin aladdin`, profiled): `literalCost` accounts for about 12% of total time and 16% of allocation, with 795k calls making 6.2M `unifyAtoms` calls. The expected saving is about 9% of runtime.

**Blocked by:** 09 (Heuristic search), 13 (Level B: full Aladdin in under 5 minutes).

**Status:** done

- [x] A property test: for every literal in the table, the table's cost equals the old computation's result, on Tiny, Tower, Bribe, and Aladdin.
- [x] The Orphan estimate uses the precomputed cost per Character, and a test checks it against the old scan.
- [x] `cabal bench aladdin` reports the same counts as before (first Story: expanded 203247, generated 493512) and the same five Stories.
- [x] Load time for Aladdin stays under 1 s.
- [x] The ticket records the before and after benchmark times when it is closed.

## Result

First Story: 17.4 s → 15.9 s. First five Stories: 25.4 s → 23.2 s. Counts and Stories unchanged. The table is a lazy `Map`, so each cost is computed on first use. Loading Aladdin and expanding one node takes 0.03 s. Outcome literals aren't in the table and fall back to the direct computation, which is only reached while the goal Step still has open conditions. A test on Tiny, Tower, Bribe, and Aladdin checks that every table entry, every Actor's Intention cost, and every Outcome literal agree with the uncached computation.
