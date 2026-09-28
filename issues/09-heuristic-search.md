# 09: Heuristic search: reachability costs, weighted A* and flaw selection

**What to build:** Stories of 5–10 Steps come back in under 10 seconds (acceptance Level A). This ticket adds:

- relaxed reachability at load time, which also prunes unreachable ground actions;
- an effect index;
- an additive-cost heuristic over open conditions, open motivations, and Orphans;
- weighted A* (`--weight`, `--greedy`);
- the fixed flaw-selection policy: threats first, then dead-end or forced flaws, then fewest children;
- node, expansion, and time limits;
- `--heuristic paper`, the domain-independent heuristic from Appendix A.1.

**Blocked by:** 06 (Joint actions and intentional threats).

**Status:** ready-for-agent

- [ ] Tower-variant, Bribe, and reduced-Aladdin runs each finish in under 10 s on a laptop, as recorded by a benchmark.
- [ ] Unreachable ground actions are never offered as establishers.
- [ ] Hitting any limit reports the stats and whatever solutions were found, and does not crash.
- [ ] Heuristic search returns the same solution validity as breadth-first search on small problems (property test).
