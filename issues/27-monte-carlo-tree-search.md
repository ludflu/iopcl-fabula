# 27: Monte Carlo tree search

**What to build:** `--search mcts` runs Monte Carlo tree search (UCT) over partial plans, as an alternative to weighted A*. It aims at varied Stories and anytime behaviour, not optimal ones.

**Algorithm:**
- **Tree:** nodes are partial plans. Children come from `Refine.expand`, and a node's children are created all at once the first time it is selected.
- **Selection:** from the root, descend by UCB1: `Q/N + c·sqrt(ln N_parent / N)` (`--mcts-c`, default `sqrt 2`). Unvisited children are taken first, in seeded random order. Exhausted children are skipped.
- **Rollout:** from the selected node, descend without adding nodes to the tree. At each step, with probability 0.8 take the child with the lowest `f = g + w·h` (the best-first priority, including soft penalties), and otherwise take a uniformly random child. Stop at a `Solution`, a dead end, or after `--mcts-rollout-depth` steps (default 150, about twice the depth of Aladdin's first Story).
- **Reward:** 1 for a `Solution`, 0 for a dead end or a hopeless plan (`h` is `Nothing`), and `1 / (1 + h)` when the rollout is cut off. Back-propagate the reward along the selected path.
- **Stories:** a complete plan reached during selection or a rollout is emitted as `FoundSolution`. The existing distinct-Story filter drops repeats.
- **Exhaustion:** a tree node is exhausted when it is a dead end, or when all of its children are exhausted. A node that is a `Solution` is exhausted once emitted. If the root becomes exhausted, the search has seen the whole space, and the stream ends normally, which `solve` reports as `Exhausted` or `Solved`. Otherwise the stream is unbounded, and only node limits, `--count` or `--timeout` stop it.
- **Randomness:** an in-house SplitMix generator, built on `Signature.mix64` and seeded from `--seed`. No new package dependency.

**Where:** `IPOCL.Mcts.mctsSearch :: MctsParams -> Env -> SearchConfig -> Plan -> [SearchEvent]`. The scaffolding (the `Strategy` type, the `MctsParams` record, the `--search`, `--mcts-c` and `--mcts-rollout-depth` flags, the `GaveUp` event, and the `MctsSpec` stub) already exists. Only `IPOCL.Mcts`, `test/MctsSpec.hs` and this ticket need to change.

**Events:** every `expand` call emits one `Visited` event, both tree expansions and rollout steps. Rollout steps say "rollout" in their reason, so `--max-nodes` counts all the work and `--trace` shows it.

**Blocked by:** 09 (Heuristic search), 25 (Drop children with unrepairable threats eagerly).

**Status:** done

- [x] Tiny, Bribe and motivated Tower each give a Story that passes `validatePlan`.
- [x] The same seed gives the same Stories and counts.
- [x] Unmotivated Tower (no believable Story) ends `Exhausted`, because the root becomes exhausted.
- [x] `--count 3` on Bribe returns distinct Stories, or as many as exist.
- [x] Aladdin results within 1,000,000 expansions (found or not, time, expansions) are recorded below for seeds 0, 1 and 2.
- [x] hlint is clean, and all tests pass.

## Decisions (grilling, recommended answers accepted)

1. One `--search` flag selects the strategy, and every strategy emits the same `SearchEvent` stream.
2. Incomplete search reports `LimitHit`, never `Exhausted`. The exception is MCTS when the root is truly exhausted (ADR-0007).
3. Each strategy lives in its own module, and the shared scaffolding lands first.
4. No glossary entry.
9. Selection uses UCT with `c = sqrt 2`, configurable.
10. Rollouts are ε-greedy (0.8 lowest `f`), capped at depth 150, configurable.
11. Rewards are 1 for a Story, 0 for a dead end, and `1/(1+h)` at the cap. Stories found in rollouts are emitted.
12. Exhaustion is tracked in the tree, and an exhausted root means truly exhausted.
13. Every `expand` call counts as an expansion. Randomness comes from an in-house SplitMix seeded by `--seed`.

## Result

Implementation in `IPOCL.Mcts`: persistent `IntMap` tree, UCB1 selection, ε-greedy rollouts with SplitMix64 randomness, back-propagation and exhaustion marking.

Aladdin within 1,000,000 expansions (`--timeout 300`):

| seed | end | expanded | generated |
|-----:|-----|----------|-----------|
| 0 | LimitHit | 1,000,000 | 2,254,489 |
| 1 | LimitHit | 1,000,000 | 2,258,578 |
| 2 | LimitHit | 1,000,000 | 2,259,705 |

MCTS did not find Aladdin's first Story within the budget on these seeds. For comparison, best-first finds it in ~189,899 expansions (~8.4 s). MCTS is better suited to smaller problems and to returning varied Stories on Bribe (two distinct Stories with `--count 3`).

The MCTS spec tests take most of the suite runtime (~5 min total) because the stream is intentionally unbounded until the root exhausts.
