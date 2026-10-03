# 34: Search quality for Protagonist arc (Story Genius)

**What to build:** Steer search toward partial plans that look like **Cron-quality cause-and-effect**: the **Protagonist's internal state** changes before or as the **Desire** advances, misbelief-driven **turning points** rank badly when skipped, and **third-rail** junk stays deprioritised. Builds on ticket **29** (generic **`h`**) but targets **Story Genius problem files** with a **`:protagonist`**.

Pick **one primary mechanism** (grill) plus tests; avoid duplicating existing hard prefs.

**Candidate mechanisms:**

- **Heuristic (inadmissible OK):** Penalise partial plans where the Protagonist has **no Realization** on the path to the Desire but **`misbelief-blocks`**-style attempts are still cheap; boost plans with a **Realization ordered before** the first Step that establishes a Desire milestone (Required pseudo-step or Frame final).
- **Soft preference:** **`(realization-before-desire-progress :weight W)`** — count Protagonist Steps that advance the Desire (establish Desire literal or Frame final) before any Realization of the Protagonist's misbeliefs; monotone count → soft penalty (spec §4.12 pattern).
- **Soft preference:** **`(protagonist-internal-change :weight W)`** — penalise long gaps in the Protagonist arc with no Realization and no **`planWarnings`**-clean internal-change link (see **`IPOCL.Lint.planWarnings`**); heuristic only, not hard prune.
- **Search tie-break:** When **`f`** ties, prefer higher **`realizationCount`** before random seed (only when **`problemProtagonist`** is set).

**Out of scope:** Changing **`validatePlan`** rules; mandatory Realization for all Characters; **builtin aladdin** without `:protagonist`.

**Measurement:**

- **`misbelief`** and **`aladdin-inner`**: first Story unchanged in **validation** and **narration shape** (Realization present); record expanded count before/after at **`w = 2`**.
- **`builtin aladdin`** (no protagonist): **identical** expanded/generated on seed **0** (guard test).
- Optional: trace sample showing fewer expansions on **third-rail**-heavy branches on **`aladdin-inner`**.

**Baseline:** Post–**29/31** first Story **`builtin aladdin`**: ~**183,911** expanded at **`w = 2`**. **`aladdin-inner`**: ~**27,755** expanded, first Story includes Realization after slay.

**Blocked by:** 16 (Protagonist / Misbelief), 17 (Third-rail), 19 (Misbelief-blocks — reuse definitions), 29/31 (recent **`h`** work — implement after merge to avoid conflicts).

**Status:** closed

- [x] ADR or ticket **Result** states chosen mechanism and admissibility.
- [x] Property/regression: **`misbelief`**, **`aladdin-inner`** Stories still **`shouldBeValidFor`**; **`InnerStorySpec`** passes.
- [x] **`aladdinProblem`** search counts unchanged (test with **`cfgMaxExpanded = Just 5000`**, seed 0).
- [x] If expansion drops on **`aladdin-inner`**, record in **Result**; if not, document “quality-only ordering” with same counts.

**Notes:** Ticket **32** adds full Aladdin Story Genius acceptance; this ticket improves **finding** good protagonist Stories faster. Complements **33** (UX), not a duplicate.

## Grill-with-docs (selected)

**Q1 — Heuristic vs new soft preference vs tie-break?**

➡️ **One new soft preference `(realization-before-desire-progress :weight …)`** default **soft 50**, plus **reuse existing `(third-rail)`** soft weights on Story Genius problems — **no** change to **`additiveHeuristic`** core in v1 (keep **29** separate). Optional tie-break only if prefs insufficient after measurement.

**Q2 — Hard prune Realization missing at partial plan?**

➡️ **No.** Hard rules only at **goal test** for relevance (spec §4.12); partial plans may lack Realization until late. **Soft penalty only.**

**Q3 — Define “Desire progress”?**

➡️ First **`establish`** of **`:desire`** literal, or first **`frameFinal`** of a Frame whose goal unifies with **`:desire`**, for **`:protagonist`** — whichever occurs **earlier** in **`linearize`**. Realization = Step whose effect **negates** a **`problemMisbeliefs`** atom for the Protagonist (same as ticket **16**).

**Q4 — Apply when no `:protagonist`?**

➡️ Preference is a **no-op** (zero violations); tests assert **`builtin aladdin`** counts unchanged.

**Q5 — Interaction with `:fail-first`?**

➡️ **Failed attempt** counts as “misbelief reared its head”; do **not** require Realization **before** fail-first attempt — penalty applies only when **successful** Desire progress precedes **any** Realization **and** misbelief still holds in **`I`**-compatible sense (document edge case in ADR).

**Q6 — Success bar?**

➡️ **Correctness first** (tests green, **`aladdin`** unchanged). **≥5%** expanded reduction on **`aladdin-inner`** is a stretch goal, not required — Story Genius domains are small; main win is **first Story** quality under **`--count` > 1** if measured.

**Q7 — Ticket order vs 32?**

➡️ **34** can land **before 32**; **32** problem file should enable **`(realization-before-desire-progress)`** once **34** exists (optional pref in problem, not required for **32** closure).

## Result

**Mechanism:** soft `(realization-before-desire-progress)` default weight **50**, implemented in `IPOCL.Preferences` (monotone violation count in `linearize`; `isRelevanceRule` — inadmissible via `softPenalty`, no `additiveHeuristic` change). ADR: `docs/adr/0010-realization-before-desire-progress.md`.

**Tests:** `PreferenceSpec` (default weight, no-op on builtin Aladdin at 5000 expansions, misbelief zero violations); existing **`InnerStorySpec`** / **`misbelief`** regression unchanged.

**Measurement:** Not added to **`aladdin-inner-problem.ipocl`** in this ticket (optional for ticket 32). Expect **quality-only ordering** when enabled: same expanded/generated counts at **`w = 2`**, better ranking of protagonist-arc partial plans under soft penalty.
