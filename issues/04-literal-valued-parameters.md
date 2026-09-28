# 04: Literal-valued parameters

**What to build:** A Character can give another Character a goal. An example is "the king orders the knight to get the lamp", where the Action schema's effect `intends(?knight, ?objective)` has a parameter that stands for a whole literal. This ticket adds:

- unification through literal-valued terms, including polarity and an occurs check;
- leaving such parameters lifted after grounding;
- satisfying an open motivation by binding them.

**Blocked by:** 03 (IPOCL mode: Frames, motivation and Orphans).

**Status:** ready-for-agent

- [ ] A small domain with `order` and `give` solves in IPOCL mode. In the result, the knight's Frame for "the king has the lamp" is motivated by the king's order Step, whose objective is bound to that literal.
- [ ] Unit tests cover unifying nested and negative literals inside `intends`, and show that unification fails when polarity differs.
- [ ] The validator accepts plans whose Steps still have literal-valued parameters bound only through the binding store.
