# 28: Parallel child generation inside one expansion

**What to build:** When `Refine.expand` has chosen a flaw and `refine` must produce several `Child` plans, build those children in parallel on a multi-capability RTS. The search still pops one frontier plan at a time and still picks one flaw per expansion; only the work to construct the child list for that flaw is parallel.

**Where to parallelize:**
- `openCondition` and `openMotivation`: one child per successful `establishers` candidate (the main fan-out on Aladdin).
- `afterEstablish`: each branch from `discoverFrames` before `finalize`.
- Not in this ticket: parallel flaw-count estimates, parallel frontier pops, or parallel `openAttempt` over the attempt index.

**How:**
- New `IPOCL.Parallel.parallelMap` using `Control.Parallel.Strategies` (`parMap rdeepseq`), gated by list length ≥ `IPCL_PARALLEL_MIN` (default **4**, overridable via environment variable for tests) and `getNumCapabilities > 1`.
- `Child` gets a shallow `NFData` instance so workers force the plan build before returning.
- Add `parallel` to library dependencies. The executable already uses `-threaded -rtsopts`.

**Blocked by:** 09 (Heuristic search), 25 (Eager unrepairable threats).

**Status:** done

- [x] With `cfgParallelMin = 999` (sequential) and `cfgParallelMin = 4`, `solvePure` on Bribe and motivated Tower gives the same `resultExpanded`, `resultGenerated` and story signatures for the same seed.
- [x] `cabal bench aladdin` with `+RTS -N1` and `+RTS -N4` reports the same expanded/generated counts (189899 / 452146 for the first Story).
- [x] Wall-clock for the first Aladdin Story with `+RTS -N4` did not improve on the dev machine (9.8 s vs 9.0 s); counts unchanged.
- [x] hlint clean; all tests pass (204 examples).

## Decisions (grill-with-docs, recommended answers accepted)

1. **Scope:** parallelize child construction only, not flaw choice or the frontier loop (ADR-0008).
2. **API:** no new CLI flag; use `+RTS -N` and env `IPCL_PARALLEL_MIN` for tests. Default threshold 4 candidates.
3. **Determinism:** `parMap` preserves list order; same Stories and same search counts as sequential when run single-threaded.
4. **Glossary:** no `CONTEXT.md` entry (implementation detail).
5. **Dependency:** the `parallel` package (Strategies), not `async` (would require `IO` in `Refine`).
6. **Bench:** Level B counts must match; record before/after wall-clock for first Story with `-N1` vs `-N4`.

## Result

`IPOCL.Parallel.parallelMap` wraps `parMap rseq` when the candidate list length is at least `cfgParallelMin` (default 4, 0 = off) and the RTS reports more than one capability. Hooked in `openCondition`, `openMotivation` and `afterEstablish`. `SolveConfig` gained `cfgParallelMin`; `Env` stores the same for searches that bypass `solvePure`.

| | +RTS -N1 | +RTS -N4 |
|--|----------|----------|
| first Story expanded / generated | 189899 / 452146 | 189899 / 452146 |
| first Story wall-clock (CLI) | 9.0 s | 9.8 s |
| Level B bench first Story | 8.7 s | 8.7 s |

Semantics match sequential code; this run showed no wall-clock win on Aladdin, likely because child batches are often small and `Plan` copies dominate. The hook remains for problems with wider establisher fan-out and for faster machines.
