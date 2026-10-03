# 32: Story Genius profile for Level B Aladdin

**What to build:** A **second Level B acceptance story** for full-scale Aladdin that uses Cron's inner-layer machinery (ticket **16**–**19**), without replacing the paper's Figure 15 check on **`builtin aladdin`**.

Deliver:

1. **`domains/aladdin-story-genius.ipocl`** (or extend **`aladdin-inner`** only if one domain can cover both — see grill) and a matching **problem file** with:
   - full Appendix A.1 cast and actions (same reach as Level B), not the reduced inner cast only;
   - **`:protagonist`**, **`:desire`**, **`:misbeliefs`** for Aladdin (aligned with **`aladdin-inner`**: e.g. unworthy-of-princess misbelief, desire to marry Jasmine);
   - **`:third-rail`** (and other Story Genius prefs as needed);
   - optional **`:fail-first`** Required Frame for at least one turning point, if the domain supports it without breaking validation;
   - paper-equivalent **`:preferences`** whitelist so search remains tractable (reuse **`aladdinPreferences`** patterns from ticket **13**).
2. **`bench/AladdinStoryGenius.hs`** (or a flag on **`bench/Aladdin.hs`**) that solves this problem under the same budget as Level B (**300 s**, no expansion cap), and checks:
   - valid Story, Outcome reached;
   - narration contains **misbelief + desire opening** and at least one **Realization** (or documented **`:fail-first`** attempt line);
   - **Figure 15 is not required** for this bench (paper parity stays on **`cabal bench aladdin`**).
3. Document in **spec.md** §1.1 or §7: two Level B targets — **paper (Fig. 15 among first five)** vs **Story Genius (protagonist arc)**.

**Baseline:** **`domains/aladdin-inner*.ipocl`** solves in ~**2 s**, ~**28k** expanded (small cast). **`cabal bench aladdin`** unchanged: Figure 15 among first five, ~**184k–190k** expanded at **`w = 2`**.

**Blocked by:** 13 (Level B), 16 (Protagonist / Misbelief), 17 (Third-rail), 18 (Backstory), 19 (Failed intentions — optional for v1).

**Status:** closed

- [x] Problem loads via **`solve domains/…`** and **`checkProblem`** is clean (warnings documented).
- [x] New bench (or documented target) passes in CI alongside **`bench aladdin`**.
- [x] At least one **`InnerStorySpec`**-style test on the **full-scale** problem (not only inner cast).
- [x] **Result** records expanded/generated/time and a sample narration excerpt.

**Notes:** Do not change the first Story of **`builtin aladdin`** for seed 0 unless intentionally scoped; this ticket adds a **parallel** acceptance path.

## Grill-with-docs (selected)

**Q1 — New domain vs reuse `aladdin-inner`?**

➡️ **New pair `aladdin-story-genius.ipocl` + problem** that **imports or duplicates** the full **`aladdin.ipocl`** schemas/actions, plus Story Genius problem fields. Keep **`aladdin-inner`** as the **small, fast regression** demo; full-scale is this ticket.

**Q2 — Replace Figure 15 bench?**

➡️ **No.** **`cabal bench aladdin`** stays the paper/whitelist acceptance. Add **`cabal bench aladdin-story-genius`** (name TBD) for Cron arc checks.

**Q3 — Required `:fail-first` for v1?**

➡️ **Optional for v1.** **Required:** protagonist, desire, misbelief, Realization in the **first** Story, **`third-rail`**. Add **`:fail-first`** in a follow-up commit only if the full domain encodes a clean blocked attempt without weakening Level B prefs.

**Q4 — Protagonist misbelief content?**

➡️ Reuse **`(believes aladdin (unworthy aladdin))`** and desire **`(married-to aladdin jasmine)`** from **`aladdin-inner-problem`**, with domain actions updated so the misbelief blocks at least one Desire-relevant Step until a Realization (mirror inner slay/pillage beat).

**Q5 — Success metric?**

➡️ Bench **Solved** within **5 minutes**; first Story passes **`validatePlan`**; narration matches **`InnerStorySpec`** patterns (misbelief open, one Realization); expanded count recorded but **no** fixed cap (informative only).

## Result

**Domain/problem:** `domains/aladdin-story-genius.ipocl` + `domains/aladdin-story-genius-problem.ipocl` — full Appendix A.1 cast/actions with inner-layer `believes`/`unworthy`, `slay` Realization, blocked `marry`, protagonist/desire/misbelief, `third-rail`, and paper-style `allow-goals` whitelist (lamp via `:possible-backstory`).

**Bench (`cabal bench aladdin-story-genius`, seed 0, `w = 2`, 300 s budget):** first Story **Solved** in **1.3 s**, **27,755** expanded, **72,171** generated. **`cabal bench aladdin`** unchanged (Figure 15 path on `builtin aladdin`).

**Narration excerpt (first Story):**

```
aladdin believes aladdin is unworthy of a princess.
aladdin wants aladdin is married to jasmine.
…
aladdin slays dragon.
aladdin realizes it is not the case that aladdin is unworthy of a princess.
…
aladdin and jasmine wed in an extravagant ceremony …
```

**Tests:** `InnerStorySpec` full-scale load + arc narration; `spec.md` §1.1 and §7 note the dual Level B targets.
