# 31: "No possible Frame" lookahead for intent flaws

**What to build:** Implement a **monotone** “this intent flaw cannot adopt” test and use it to **avoid scheduling hopeless `(Step, Frame)` intent work**, without violating ADR-0002. Spec §8 fallback (2) is the motivation; this ticket **does not** try to prove full “no Frame can ever explain this Step” in one shot. It **does** drop or auto-resolve pairs where **adoption is permanently impossible** under the partial order (while “stay out” remains a valid child when `keep` allows it).

**Definition (implement in `docs/adr/0009-no-possible-frame-lookahead.md` before code):**

- **`intentAdoptForeverImpossible :: Plan -> StepId -> FrameId -> Bool`** — true when the **adopt** branch of `resolveIntentFlaw` would fail because required frame orderings (`addOrder` fold in `adopt`) cannot be satisfied, and **adding only future orderings** cannot fix that failure (partial order only accumulates constraints; the check mirrors today’s `adopt` ordering fold on the current plan).
- **Out of scope for v1:** Orphan-only “no frame will ever exist” reasoning (ticket 25: **~2%** expansion ceiling on orphan-only dead subtrees). Do **not** hard-prune whole plans in `keep` on that basis.

**Hook:** In `finalize`, after `intentCandidates` and **`keep`**, filter **`fresh`** before updating `planPendingIntent` / `planProposedIntent`:

- If **`intentAdoptForeverImpossible`**, do **not** enqueue `(s, c)` as a pending intent flaw (the only remaining decision is “stay out”, handled by the plan’s existing structure / later candidates — document in ADR-0009 why this matches ADR-0002’s “decide each pair once”).
- If the spike shows many pairs with **no adopt and no keep** either, treat as **`keep`** failure (already dropped).

**Shared module:** Export the predicate from `IPOCL.Refine` (or a small `IPOCL.IntentFeasible`) for ticket **29**.

**Testing:**

- Property test on sampled paths (Tower, motivated Tower, Bribe, Aladdin): for every visited plan, every **removed** pair satisfies `intentAdoptForeverImpossible`; every **kept** pending pair either was already proposed or adopt is still possible. Keep a slow oracle: recompute `intentCandidates` and compare to unfiltered baseline on small depth limits.
- `cabal bench aladdin` at **`w = 2`**: record expanded/generated; Figure 15 among first five Stories, or document change.

**Baseline:** First Story **189,899 expanded**, **452,146 generated**, **~8.4–9.0 s** (tickets 21–25, 23–24).

**Blocked by:** 03 (IPOCL frames, motivation, Orphans), ADR-0002, 13 (Level B). **Do after:** ticket **30** (weight baseline). **Before / with:** ticket **29** (shared predicate).

**Status:** open

- [ ] ADR-0009 written and linked from this ticket.
- [ ] Filter in `finalize`; ADR-0002 “each pair once” argument spelled out in ADR.
- [ ] Property tests on sampled paths; `PlannerSpec` / equivalence tests pass.
- [ ] **Result** with before/after bench; if expansion drop **< 5%**, document and still ship if correctness story is clean (predicate may be rare).

**Notes:** If the predicate is expensive, cache per `(s,c)` only for `fresh` pairs. Ticket **29** may add heuristic surcharges for pairs that are not forever impossible but are unlikely — different hook.

## Grill-with-docs (selected)

**Q1 — Full semantic “no possible Frame” or narrower?**

➡️ **Narrow, monotone adopt impossibility** first. Full “no Frame can ever explain Step” needs future frames/links (ADR-0002) and is easy to get wrong.

**Q2 — Hook: `finalize` filter vs `keep` plan prune?**

➡️ **`finalize` filter on `fresh` pairs only**, not whole-plan `keep`.

**Q3 — Orphan lookahead?**

➡️ **Exclude** from this ticket (ticket 25 ceiling).

**Q4 — If adopt impossible but “stay out” valid, is skipping the flaw sound?**

➡️ **Yes**, when documented in ADR-0009: the planner never needs an adopt branch that is permanently inconsistent; rejecting adoption is the only outcome. Equivalence tests guard regressions.

**Q5 — Spike before code?**

➡️ **Optional 20k trace** counting intent expansions where adopt is `Nothing`; if negligible, close with “no-op in practice” still acceptable if tests pass. Do not block implementation on the spike.

**Q6 — Order vs 29?**

➡️ **Implement 31 first** (hard filter); **29** adds **heuristic** use of the same predicate for pairs that remain pending.

## Result

*(Fill when closed.)*
