# 30: Tune weighted A* on Aladdin

**What to build:** Add `bench/WeightSweep.hs` (or equivalent) that runs the **Level B bench configuration** (`cfgMaxExpanded = Nothing`, 300 s timeout, seed from CLI) on `aladdinProblem` for **`W ∈ {1, 1.5, 2, 3, 5}`** and **`--greedy`**, printing expanded, generated, wall time, `SearchEnd`, and first-Story Step count. Close the ticket with a **Result** table and a one-paragraph default-`w` recommendation. This is measurement and documentation, not a new search algorithm.

**Procedure:**

1. Seeds **0, 1, 2** (seed **0** is primary; others spot-check stability).
2. Use the same additive heuristic and preferences as `bench/Aladdin.hs`.
3. Compare against baseline **`w = 2`**, seed **0**: **189,899 expanded**, **452,146 generated**, **~8.4–9.0 s**, first Story Frames unchanged from ticket 13.

**Blocked by:** 09 (Heuristic search), 13 (Level B).

**Status:** open

- [ ] `cabal bench weight-sweep` (or documented `cabal run` invocations) reproduces the Result table.
- [ ] Ticket **Result** records all runs; notes that CLI **`defaultSolveConfig`** caps at **200k expanded**, so **`w ≥ 3`**, **`w = 5`**, and **`--greedy`** hit `LimitHit` under the **CLI** unless `--max-nodes` is raised (bench must use no cap).
- [ ] **Default `w` decision** documented in Result and **spec.md** §4.10 (see grill selection below).
- [ ] `cabal test spec` passes; no change to `defaultSolveConfig.cfgWeight` unless the grill decision is revisited.

**Notes:** Tickets **29** and **31** should report Aladdin before/after at **`w = 2`** (canonical bench) and note any **`w = 1`** interaction if expansions move. Beam search remains spec fallback (1), out of scope.

## Grill-with-docs (selected)

**Q1 — Sweep environment:** Use CLI defaults or bench config?

➡️ **Bench config** (`cfgMaxExpanded = Nothing`). CLI’s **200k** cap hides behaviour for **`w ≥ 3`** and greedy (seed 0: `LimitHit` at 200k).

**Q2 — Change the default `w`?** `w = 1` on seed 0 solves with **100,246 expanded** (~47% fewer than `w = 2`) and the **same first-Story Frame set** as today; `w = 1.5` → 119,544; `w = 3` → 365,905 (slower, still Solved with no cap); `w = 5` and greedy did not solve within **500k** expanded in a follow-up run.

➡️ **Keep default `w = 2`** in code and in the Level B benchmark so CI and ticket baselines stay comparable. Document in **spec.md** that **`--weight 1`** (or **1.5**) is the recommended knob for large problems when fewer expansions matter more than matching historical counts.

**Q3 — Deliverable shape?**

➡️ **`bench/WeightSweep.hs`** + cabal stanza; optional one-line pointer in `bench/Aladdin.hs` comment. No change to `app/Main.hs` default unless a later ticket explicitly opts in.

**Q4 — Relation to ticket 29?**

➡️ Run ticket **30** **before** tuning **`h`** in **29**, so expansion wins are not confounded with weight choice.

**Q5 — Acceptance for “success”?**

➡️ Table + written recommendation is enough; **no requirement** to change the default to `w = 1` even if the data favours it.

## Result

*(Fill when closed.)*

**Preview (seed 0, no expansion cap, additive heuristic):**

| W | End | Expanded | Generated |
|---|-----|----------|-----------|
| 1 | Solved | 100,246 | 233,877 |
| 1.5 | Solved | 119,544 | 286,257 |
| 2 | Solved | 189,899 | 452,146 |
| 3 | Solved | 365,905 | 861,193 |
| 5 | LimitHit @ 500k | 500,000 | 1,121,161 |
| greedy | LimitHit @ 500k | 500,000 | 1,055,497 |
