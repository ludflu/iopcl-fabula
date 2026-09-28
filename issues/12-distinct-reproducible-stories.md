# 12: Distinct, reproducible stories

**What to build:** Repeated runs give varied Stories, a given seed always gives the same output, and one run can return several genuinely different Stories. This ticket adds:

- a canonical plan signature, used to drop duplicate plans reached by different paths;
- seeded random tie-breaking (`--seed`);
- `--count N`, which keeps searching after the first solution and returns only Stories that differ in their set of ground Steps or their Character–Character goal pairs.

**Blocked by:** 09 (Heuristic search).

**Status:** ready-for-agent

- [ ] Running the same problem twice with the same seed gives byte-identical output.
- [ ] Different seeds on a problem with several Stories give different first Stories, at least some of the time, as checked by a statistical test over seeds.
- [ ] `--count 3` on Bribe or reduced Aladdin returns three Stories with pairwise-distinct story signatures.
- [ ] Duplicate detection never drops a plan whose signature has not been seen before (property test).
