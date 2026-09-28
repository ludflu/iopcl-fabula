# 10: Search trace

**What to build:** `--trace FILE` records the search in the style of Appendix A.3. For every expanded node it writes the node id, parent id, the reason the node exists (for example "created new step 3: love-spell(…) to solve intends(…)" or "adoption of step 8 by frame 4"), the flaw being worked on, and the number of children. Tracing costs nothing when it is off. The trace is extended to cover each new flaw type as later tickets add them.

**Blocked by:** 01 (Tracer bullet: POCL solves a one-action story from the CLI).

**Status:** ready-for-agent

- [ ] A trace of the tiny problem shows the complete path from the initial plan to the solution.
- [ ] Every refinement kind that exists at the time of implementation produces a human-readable reason.
- [ ] A golden test covers a short trace excerpt.
- [ ] A run without `--trace` performs no trace formatting work, as shown by benchmark or inspection.
