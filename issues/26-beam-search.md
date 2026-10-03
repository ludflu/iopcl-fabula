# 26: Beam search

**What to build:** `--search beam` runs a layered beam search over partial plans, as an alternative to weighted A* (`--search best-first`, the default). It is meant for finding *some* Story fast with bounded memory. It is incomplete: it can miss Stories that best-first finds.

**Algorithm:**
- Layer 0 is the initial plan. To build layer `d + 1`, expand every plan in layer `d` with `Refine.expand`. Then keep the best `k` children of the whole layer (`--beam-width k`), ranked by the same priority as best-first: `f = g + w·h`, with `--weight`, `--greedy` and the soft preference penalties all applying. Ties are broken by the seeded hash, as in `IPOCL.Search`.
- A plan that `expand` reports as a `Solution` is emitted as `FoundSolution` when its layer is processed.
- A child whose heuristic is `Nothing` is dropped, as in best-first. `--dedupe` drops repeated signatures across the whole run.
- When a layer comes out empty, the stream ends with `GaveUp`, which `solve` reports as `LimitHit` (ADR-0007). The search never reports `Exhausted`.
- No automatic restarts with a wider beam.

**Where:** `IPOCL.Beam.beamSearch :: Int -> Env -> SearchConfig -> Plan -> [SearchEvent]`. The scaffolding (the `Strategy` type, `--search` and `--beam-width`, the `GaveUp` event, and the `BeamSpec` stub) already exists. Only `IPOCL.Beam`, `test/BeamSpec.hs` and this ticket need to change.

**Events:** each `expand` call emits one `Visited` event, with a reason that also says which layer the plan is in. Node numbers are unique across the run, and `evParent` is correct, so `--trace` works.

**Blocked by:** 09 (Heuristic search), 25 (Drop children with unrepairable threats eagerly).

**Status:** done

- [x] Tiny, Bribe and motivated Tower each give a Story that passes `validatePlan`.
- [x] The same seed gives the same Stories and counts. Different seeds may differ.
- [x] A width-1 beam on a problem whose greedy choice dead-ends reports `LimitHit` with no Stories, not `Exhausted`.
- [x] Memory is bounded by the width: a test checks no layer holds more than `k` plans.
- [x] `--count N` returns distinct Stories when the beam finds them.
- [x] Aladdin results for widths 10, 100, 1000 and 10000 (found or not, time, expansions) are recorded below, and the default `--beam-width` is set to the smallest width that finds an Aladdin Story, or stays at 100 if none does.
- [x] hlint is clean, and all tests pass.

## Decisions (grilling, recommended answers accepted)

1. One `--search` flag selects the strategy, and every strategy emits the same `SearchEvent` stream.
2. Incomplete search reports `LimitHit` via `GaveUp`, never `Exhausted` (ADR-0007).
3. Each strategy lives in its own module, and the shared scaffolding lands first.
4. No glossary entry: search strategies aren't story-domain terms.
5. The beam is layered, keeps the top `k` by the best-first priority, and breaks ties with the seed.
6. The default width is chosen by the Aladdin sweep.
7. Stories are emitted per layer, and the search gives up when a layer is empty.
8. No restarts. `--dedupe` applies as usual.

## Result

Implementation in `IPOCL.Beam`: layered beam with a `Map` keyed by `(priority, tieBreak, node)` and cap-on-insert so memory stays bounded by the width.

Aladdin (`--max-nodes 2000000`, `--timeout 300`):

| width | end | expanded | generated |
|------:|-----|----------|-----------|
| 10 | LimitHit | 1,059 | 1,933 |
| 100 | LimitHit | 10,488 | 19,868 |
| 1000 | LimitHit | 126,364 | 247,011 |
| 2000 | LimitHit | 228,208 | 454,187 |
| 5000 | Solved | 233,521 | 486,992 |
| 8000 | Solved | 358,579 | 735,417 |
| 10000 | Solved | 439,868 | 899,700 |

The smallest width that finds a Story is **5000**. The CLI default stays **100**: a width-5000 default would be surprising on Tiny and Bribe, where width 100 already finds Stories quickly.
