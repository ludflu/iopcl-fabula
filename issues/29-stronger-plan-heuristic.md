# 29: Stronger, more informed `h(plan)`

**What to build:** Improve search ordering by making **`h(plan)`** reflect **hopeless or nearly hopeless intent flaws**, without duplicating work tickets **21–24** already did. **One focused change**, shared with ticket **31**:

- Add an **inadmissible** penalty in `additiveHeuristic` (or via `softPenalty` only if it stays plan-local and does not double-count preferences): for each **pending** intent pair `(s, c)` where **`intentAdoptForeverImpossible plan s c`** (same definition as ADR-0009 / ticket **31**), charge **`hopelessIntentCost`** (default **9**) instead of **`1`**, so weighted A* deprioritises branches that still carry permanently unadoptable intent work.
- **Do not** change core reachability sums, Orphan **`1` vs `2 + intentionCost`** (ticket 13), or soft preference weights on Aladdin (`no-repeat-steps` etc.) in this ticket.
- **Do not** weaken hard pruning in `keep` or inflate `h` instead of implementing ticket **31**’s filter — **31 removes** hopeless pairs; **29 penalises** any that remain or other near-dead patterns later.

**Safety:** Document **inadmissible** heuristic inflation; weighted A* with **`w = 2`** already sacrifices optimality. Property tests: **`h`** is unchanged on plans with no pending hopeless intents; Tiny/Tower smoke tests unchanged.

**Measurement:**

- Primary: `cabal bench aladdin` at **`cfgWeight = 2`**, seed **0** — target **≥ 10%** fewer **expanded** on first Story vs **189,899**, or document why not.
- Secondary: one run at **`w = 1`** (see ticket **30**) to see if ordering gains survive when the open list is already tighter.

**Baseline:** **~8.4–9.0 s**, **189,899 expanded**, **452,146 generated**; five Stories including Figure 15 (ticket 13).

**Blocked by:** 13, 23, 25, **31** (predicate + ADR-0009), **30** (weight baseline documented). Implement **after 31** if both touch the same helper; otherwise land **31** and **29** in one PR with shared `intentAdoptForeverImpossible`.

**Status:** open

- [ ] Named change and inadmissibility note in ticket **Result** and, if needed, one sentence in **spec.md** §4.11.
- [ ] `HeuristicSpec` / preference tests pass; new tests comparing **`h`** with/without hopeless pending intents on crafted Tiny plans.
- [ ] Bench before/after at **`w = 2`**; first Story and five-Story acceptance as ticket 13, or documented intentional difference.
- [ ] **≥ 10%** expansion drop at **`w = 2`**, or **Result** explains interaction (e.g. 31 already removed hopeless pairs so 29 adds little).

**Notes:** If after **31** the predicate rarely leaves pending hopeless pairs, **rescope 29** to the next profile hotspot (**`intentCandidates`** / **`establishers`**) only after a fresh **40k `-prof`** on `main`. Relevance soft penalties (third-rail) already in **`softPenalty`** — out of scope here.

## Grill-with-docs (selected)

**Q1 — Which candidate direction from the original ticket?**

➡️ **Hopeless intent penalty only** for v1. Skip broad Orphan/frame tightening and soft-preference retuning unless **31+29** fail the **10%** target and profiling says otherwise.

**Q2 — Admissible or inadmissible?**

➡️ **Inadmissible** surcharge on hopeless pending intents only; leave ticket 13 Orphan logic admissible as today.

**Q3 — Hard prune vs higher `h`?**

➡️ **Both, split across tickets:** **31** filters; **29** penalises stragglers. Do not replace 31 with heuristic-only.

**Q4 — Success metric at which `w`?**

➡️ **`w = 2`** for acceptance; note **`w = 1`** in Result if expansions differ (ticket **30** preview: **100,246** expanded at **`w = 1`**, same first-Story Frames on seed 0).

**Q5 — Soft preferences “earlier in h”?**

➡️ **No** for Aladdin in this ticket — already encoded with large weights; ticket 25 says the gap is **search quality among live branches**, not **`violations`** micro-opts.

**Q6 — Ticket order?**

➡️ **30 → 31 → 29** (30 baselines weight; 31 predicate; 29 heuristic).

## Result

*(Fill when closed.)*
