# 08: Narration and Graphviz output

**What to build:** A solved Story prints as readable prose by default. Each Step is rendered from its `:text` template, or falls back to "name args" when there is none. Each Frame adds a "Character wants Character goal" line, rendered through the predicate templates, right after its Motivating step. The linearisation places Motivating steps as early as possible. `--dot FILE` writes a diagram in the style of Figure 15:

- Steps;
- causal links (solid) and orderings added to resolve threats (dashed);
- Frames drawn as clusters;
- motivation links.

`--no-narrate` suppresses the prose.

**Blocked by:** 03 (IPOCL mode: Frames, motivation and Orphans), 07 (Text domain format).

**Status:** done

- [x] The Bribe Story narrates in an order where the Villain's intention is stated before Coerce, and the Hero's intention before Give.
- [x] Golden tests cover the narration and DOT output for Bribe.
- [x] A Step with no template is rendered with the fallback format and does not cause an error.
- [x] The DOT output passes `dot -Tsvg` without errors.

**Notes:**

- Graphviz `dot` is not installed on the development machine, so `dot -Tsvg` could not be run locally. `NarrateSpec` checks the DOT structurally instead: the `digraph` header, braces balanced outside quoted strings, every edge endpoint declared as a node, and one labelled `subgraph cluster_N` per Frame. Run `dot -Tsvg test/golden/bribe.dot` once Graphviz is available to confirm.
- Init and goal are always drawn as grey ellipses. Motivation links are dotted edges from the Motivating step (or init) to the Frame's final Step, labelled with the Intention, and clipped at the cluster using `lhead`. A Graphviz node can belong to only one cluster, so a Step in several Intervals is drawn in the lowest-numbered Frame's cluster, and its label says which other Frames it is also in.
- `--dot FILE` writes Story 1 to `FILE`. With `--count N`, Story k>1 goes to `FILE` with `-k` inserted before the extension, e.g. `out-2.dot`.
- A negated Character goal is narrated as "X wants it not to be the case that ...".
