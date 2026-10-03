# 33: Author-facing Story Genius workflow

**What to build:** A **guided path** from a raw story idea to **`solve` + narration + scene cards**, aligned with Cron's blueprinting order (Desire and Misbelief before plot, then causal Story). v1 is **documentation + a small CLI wrapper**, not an LLM writer.

Deliver:

1. **`docs/story-genius-workflow.md`** (or **`docs/guides/story-genius.md`**) with:
   - ordered steps: **Desire → Misbelief → domain sketch → problem file** (`:protagonist`, `:desire`, `:misbeliefs`, `:preferences`, Outcome) → **`narrative-planning solve`** → **`--cards`** / **`--dot`**;
   - pointers to **`misbelief`**, **`aladdin-inner`**, **`ticking-clock`** examples;
   - what the planner **does not** do (prose genesis, market positioning).
2. **`scripts/story-genius/`** or **`narrative-planning story-genius`** subcommand (pick one in grill) that:
   - accepts a **problem name** or paths to domain/problem files;
   - runs **load checks** (`checkProblem`, list **`problemWarnings`**);
   - runs **solve** with sensible defaults (**`--timeout`**, optional **`--weight 1`** hint for large domains);
   - prints **narration** and optionally **`--cards`** to stdout or **`--output-dir`**.
3. **No new planner semantics** in this ticket — wiring and UX only.

**Baseline:** Authors today run **`cabal run narrative-planning -- solve …`** manually; **`--cards`** exists (ticket **14**); Story Genius fields parse (tickets **16**, **19**).

**Blocked by:** 07 (Text domain), 14 (Scene cards), 16 (Protagonist / Misbelief), 08 (Narration).

**Status:** open

- [ ] Guide is linked from **README** or **spec.md** (one line).
- [ ] Wrapper exits non-zero on load/validation failure; prints **`Solved` / `Exhausted` / `LimitHit`** and stats.
- [ ] One **golden or snapshot test** (optional): wrapper on **`misbelief-problem`** produces narration containing misbelief + desire lines (process test in **`spec`** or **`ParserSpec`** CLI section).
- [ ] **Result** lists exact commands for the three example domains.

**Notes:** A future ticket may add **blueprint YAML → problem file** generation; out of scope here (see issue **34** for search-side “good story” steering).

## Grill-with-docs (selected)

**Q1 — Subcommand vs shell script?**

➡️ **`narrative-planning story-genius`** subcommand (same **`optparse-applicative`** style as **`solve` / `builtin`**) that delegates to existing **`run`** logic. Avoid a bash-only script as the only entry point; a thin **`scripts/story-genius-example.sh`** may call the subcommand for CI.

**Q2 — Interactive wizard?**

➡️ **No for v1.** Static **markdown guide** only; no prompts for Desire/Misbelief (that belongs in Cursor/skills or a later ticket).

**Q3 — Output defaults?**

➡️ **Narration on**, **`--cards`** off by default (verbose); flags **`--cards`**, **`--dot FILE`**, **`--no-narrate`** mirror **`solve`**.

**Q4 — “From raw idea” scope?**

➡️ Guide **templates** empty **`.ipocl` snippets** authors copy; ticket does **not** implement idea → IPocl synthesis.

**Q5 — CI surface?**

➡️ **`cabal test spec`** CLI test: **`story-genius misbelief`** (or paths) → **Solved**, stderr clean, stdout contains **`believes`** / **`wants`** narration lines.

**Q6 — Dependency on issue 32?**

➡️ **None.** Workflow documents **`aladdin-inner`** today; add **`aladdin-story-genius`** to the guide when **32** lands.

## Result

*(Fill when closed.)*
