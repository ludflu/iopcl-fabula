# Story Genius author workflow

This guide follows Lisa Cron's *Story Genius* blueprinting order: nail the protagonist's **Desire** and **Misbelief** before plot mechanics, then encode cause-and-effect in IPOCL and let **`narrative-planning`** search for a sound Story. v1 is documentation plus the **`story-genius`** CLI wrapper — not an LLM that writes prose.

## Ordered steps

1. **Desire** — What does the protagonist want, in domain terms? Pick a literal the planner can treat as a Required Frame (see `:desire` below).
2. **Misbelief** — What false belief makes them resist the Desire? Express it as `(believes <character> …)` facts that hold in `:init` and block Steps until a Realization overturns them.
3. **Domain sketch** — Actions, preconditions, effects, and `:text` templates for the world and the turning points (Realizations, blocked attempts, Happenings). Start from a small example domain if you are new to IPOCL.
4. **Problem file** — Wire Story Genius fields and preferences:

   ```ipocl
   (define (problem my-story-1)
     (:domain my-domain)
     (:agents ...)
     (:init ...)
     (:goal ...)                    ; Outcome G
     (:protagonist hero)
     (:desire (goal-literal hero ...))
     (:misbeliefs
       (believes hero ...))
     (:preferences
       (third-rail)
       (misbelief-blocks)
       ...))
   ```

5. **Load and solve** — Either run the wrapper (recommended) or **`solve`** directly:

   ```bash
   narrative-planning story-genius my-story
   # same as:
   narrative-planning solve domains/my-story.ipocl domains/my-story-problem.ipocl
   ```

6. **Read the Story** — Default output includes the partial-order plan and **narration**. Add **`--cards`** for Story Genius scene cards, or **`--dot FILE`** for Graphviz (Figure 15 style).

The wrapper runs **`checkProblem`**, prints **`problemWarnings`** on stderr, applies a default **`--timeout`** (300 s), and ends with **`Solved`**, **`Exhausted`**, or **`LimitHit`** plus expansion stats. It exits non-zero on load/validation failure or when no story is found.

### Flags (mirror `solve`)

| Flag | Default for `story-genius` | Meaning |
|------|----------------------------|---------|
| (narration) | on | Omit with **`--no-narrate`** |
| **`--cards`** | off | Scene card per Step |
| **`--dot FILE`** | off | Write Story 1 to FILE (`-2`, `-3`, … for later stories) |
| **`--timeout SECONDS`** | 300 | Wall-clock limit |
| **`--weight W`** | 2 | Weighted A* heuristic weight |
| **`--output-dir DIR`** | off | Also write per-story narration (and cards if requested) under DIR |

For very large domains (full **`aladdin.ipocl`**), the wrapper prints a hint to try **`--weight 1`** if search is slow.

## Example domains (exact commands)

Three worked Story Genius examples ship in **`domains/`**:

### `misbelief` — misbelief blocks the Desire

Ruby loves Henry but believes love is dangerous; a Realization must precede reunion.

```bash
narrative-planning story-genius misbelief
# or:
narrative-planning solve domains/misbelief.ipocl domains/misbelief-problem.ipocl
narrative-planning story-genius misbelief --cards
```

### `aladdin-inner` — small Aladdin cast, unworthy-of-princess misbelief

Fast regression-scale domain with protagonist, desire, misbeliefs, and Realization after the slay beat.

```bash
narrative-planning story-genius aladdin-inner
# or:
narrative-planning solve domains/aladdin-inner.ipocl domains/aladdin-inner-problem.ipocl
```

### `ticking-clock` — escalation / milestone prototype

Storm and river ticks motivate the protagonist's response (see ADR-0005).

```bash
narrative-planning story-genius ticking-clock
# or:
narrative-planning solve domains/ticking-clock.ipocl domains/ticking-clock-problem.ipocl
```

You can pass explicit paths instead of a short name:

```bash
narrative-planning story-genius domains/misbelief.ipocl domains/misbelief-problem.ipocl
```

## What the planner does not do

- **Prose genesis** — It does not draft scenes, dialogue, or market copy. Narration is template-based over your domain `:text` and predicate templates.
- **Market positioning** — No genre, comp titles, or audience analysis.
- **Idea → IPocl synthesis** — Copy the snippets above; a future ticket may generate problem files from blueprint YAML (out of scope here).

## Further reading

- Terminology: **`CONTEXT.md`**
- Algorithm and CLI overview: **`spec.md`**
- Misbelief turning points and **`misbelief-blocks`**: issue 19; failed attempts: issue 19 / ADR-0003
- Ticking clocks: **`docs/adr/0005-ticking-clocks-need-milestones.md`**

When **`aladdin-story-genius`** lands (issue 32), add it to the example list here as the full-scale Cron arc demo.
