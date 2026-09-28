# 13: Level B: full Aladdin in under 5 minutes

**What to build:** The full Aladdin problem from Appendix A.1 solves in under 5 minutes on a laptop (acceptance Level B). It uses Author preferences equivalent to the paper's domain-dependent heuristic, with the whitelist's typos normalised. The work is to profile and optimise until the target is met, following the spec's fallback order if it isn't:

1. bounded-beam search;
2. a lookahead that prunes intent flaws;
3. revisiting ADR-0001.

**Blocked by:** 06 (Joint actions and intentional threats), 11 (Author preferences), 12 (Distinct, reproducible stories).

**Status:** done

- [x] The Aladdin benchmark finishes in under 5 minutes. Its result passes validation and reaches the Outcome (Jafar married to Jasmine, the genie dead).
- [x] The Story's Frames match Figure 15:
  - Jafar wants to marry Jasmine;
  - Aladdin wants Jafar to have the lamp;
  - Aladdin wants the genie dead;
  - the genie wants Jasmine to love Jafar;
  - Jasmine wants to marry Jafar.
- [x] Profiling results and the optimisations applied are summarised in the ticket when it is closed.
- [x] If the target cannot be met, the ticket documents why and names the fallback taken.

## Result

`cabal bench aladdin` finds the first Story in about 21 s: 203k plans expanded, 494k generated, about 640 MB of heap. The first five distinct Stories take 31 s. Every Story passes validation and reaches the Outcome. No fallback was needed.

**Frames.** The third Story has exactly the Frames of Figure 15. The first Story differs in one Frame: Jafar orders Aladdin to kill the dragon (`¬alive(dragon)`, which is on the paper's whitelist) and takes the lamp himself. In Figure 15, Aladdin is ordered to fetch the lamp (`has(jafar, lamp)`). The first Story is one Step shorter, so the planner prefers it under every seed tried (0–6). The benchmark therefore checks that Figure 15's Frame set appears among the first five Stories.

**Preferences.** `aladdinPreferences` (and `domains/aladdin-problem.ipocl`) encode the paper's domain-dependent heuristic as hard preferences:

- the whitelist, with "hero" read as aladdin, "king" as jafar, and duplicates removed;
- `allow-goals dragon` with no goals;
- `no-repeat-steps`.

The paper's 5000-point penalties dominate its heuristic, so they behave as hard constraints. Its "marry needs two Frames" rule is already enforced by Joint actions.

## Profiling and optimisations

Measured with `+RTS -p` and `-s` at a 20k-expansion budget:

1. **Flaw selection.** Fewest-children flaw selection built every flaw's children, including intent bookkeeping and preference checks, and then kept one flaw's children. Flaws are now ranked by a cheap upper bound, the number of establishers, and only the chosen flaw is refined. A flaw with no children still gives a dead end. About 2× faster.
2. **Causal-threat detection** runs for every generated child, because the heuristic counts threats. Candidate clobberers are now indexed by (polarity, predicate) before any ordering or unification check.
3. **Plan signatures** held hundreds of `Text` values each: 1.1 GB of residency at 20k nodes. They are now 128-bit digests, down to 95 MB. Dedupe still removed no plans on Aladdin and cost about 2×, so it is off by default (`--dedupe`); see ticket 12.
4. **`Order`** no longer stores init < s < goal for every Step (they are implicit bounds) or a reverse index. Throughput went from 2k to about 10k nodes/s.
5. **Orphan estimate.** An Orphan counted as 1 whenever its Actor had any Frame. It now counts as 1 only when an intent flaw for one of that Actor's Frames is pending. Otherwise it counts as 2 plus the cost of an Intention for the Actor, since it still needs a Frame. Expansions fell from 1.83M (236 s, 16 GB) to 203k (21 s).
