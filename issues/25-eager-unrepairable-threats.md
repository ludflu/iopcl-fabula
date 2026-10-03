# 25: Drop children with unrepairable threats eagerly

**What to build:** `Refine.keep` drops a child with a recorded causal threat that no promotion, demotion or separation can repair. Today such a child is pushed onto the open list, popped, and expanded once only to report "no way to repair causal threat".

**Analysis** (full trace of Aladdin's first Story, 203,247 expansions; the solution is 74 refinements deep):
- 163k expansions are in branches still alive when the Story is found. The search spends most of its effort on plans that look about as promising as the solution, not on plans that die.
- Subtrees ending only in "orphans remain" hold 4.3k expansions, about 2%. That's the upper bound on pruning hopeless Orphans earlier, so it isn't worth building.
- Subtrees ending only in unrepairable threats hold 31k expansions, but they are tiny (at most 15 expansions, about 2.3 on average): threats are already caught within a couple of refinements. 14,118 expansions are the dead ends themselves.
- Delaying place bindings (`marry(jafar, jasmine, ?place)`) would need finite-domain variables in `Bindings`, and the heuristic currently costs non-ground preconditions at 0. Not attempted.

**Blocked by:** 24 (Incremental causal-threat detection).

**Status:** done

- [x] A child with an unrepairable threat never reaches the open list. A test checks that no plan visited in 3,000 Aladdin expansions is a causal-threat dead end.
- [x] The five Aladdin Stories are unchanged.
- [x] The ticket records the before and after benchmark numbers.

## Result

| | before | after |
|---|---|---|
| first Story | 9.1 s, 203,247 expanded, 493,512 generated | 8.4 s, 189,899 expanded, 452,146 generated |
| first five Stories | 13.3 s, 296,675 expanded | 13.0 s, 291,066 expanded |
| order Intentions as backstory | 7.8 s, 181,063 expanded | 7.8 s, 173,614 expanded |

Expansions drop by 6.6% for the first Story, but time by only about 5%, because a dead-end expansion was cheap. Bigger gains need a more informed heuristic, not more pruning.
