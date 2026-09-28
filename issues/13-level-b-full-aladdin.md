# 13: Level B: full Aladdin in under 5 minutes

**What to build:** The full Aladdin problem from Appendix A.1 solves in under 5 minutes on a laptop (acceptance Level B). It uses Author preferences equivalent to the paper's domain-dependent heuristic, with the whitelist's typos normalised. The work is to profile and optimise until the target is met, following the spec's fallback order if it isn't:

1. bounded-beam search;
2. a lookahead that prunes intent flaws;
3. revisiting ADR-0001.

**Blocked by:** 06 (Joint actions and intentional threats), 11 (Author preferences), 12 (Distinct, reproducible stories).

**Status:** ready-for-agent

- [ ] The Aladdin benchmark finishes in under 5 minutes. Its result passes validation and reaches the Outcome (Jafar married to Jasmine, the genie dead).
- [ ] The Story's Frames match Figure 15:
  - Jafar wants to marry Jasmine;
  - Aladdin wants Jafar to have the lamp;
  - Aladdin wants the genie dead;
  - the genie wants Jasmine to love Jafar;
  - Jasmine wants to marry Jafar.
- [ ] Profiling results and the optimisations applied are summarised in the ticket when it is closed.
- [ ] If the target cannot be met, the ticket documents why and names the fallback taken.
