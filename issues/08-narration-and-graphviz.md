# 08: Narration and Graphviz output

**What to build:** A solved Story prints as readable prose by default. Each Step is rendered from its `:text` template, or falls back to "name args" when there is none. Each Frame adds a "Character wants Character goal" line, rendered through the predicate templates, right after its Motivating step. The linearisation places Motivating steps as early as possible. `--dot FILE` writes a diagram in the style of Figure 15:

- Steps;
- causal links (solid) and orderings added to resolve threats (dashed);
- Frames drawn as clusters;
- motivation links.

`--no-narrate` suppresses the prose.

**Blocked by:** 03 (IPOCL mode: Frames, motivation and Orphans), 07 (Text domain format).

**Status:** ready-for-agent

- [ ] The Bribe Story narrates in an order where the Villain's intention is stated before Coerce, and the Hero's intention before Give.
- [ ] Golden tests cover the narration and DOT output for Bribe.
- [ ] A Step with no template is rendered with the fallback format and does not cause an error.
- [ ] The DOT output passes `dot -Tsvg` without errors.
