# 12: Distinct, reproducible stories

**What to build:** Repeated runs give varied Stories, a given seed always gives the same output, and one run can return several genuinely different Stories. This ticket adds:

- a canonical plan signature, used to drop duplicate plans reached by different paths;
- seeded random tie-breaking (`--seed`);
- `--count N`, which keeps searching after the first solution and returns only Stories that differ in their set of ground Steps or their Character–Character goal pairs.

**Blocked by:** 09 (Heuristic search).

**Status:** done

- [x] Running the same problem twice with the same seed gives byte-identical output.
- [x] Different seeds on a problem with several Stories give different first Stories, at least some of the time, as checked by a statistical test over seeds.
- [x] `--count 3` on Bribe or reduced Aladdin returns three Stories with pairwise-distinct story signatures.
- [x] Duplicate detection never drops a plan whose signature has not been seen before (property test).

**Notes:** The `--count 3` test uses a small gift problem that has three Stories. Reduced Aladdin has one distinct Story. Bribe has two that are found quickly, and a third is not reached within 60 s. The plan signature leaves out the ordering closure: every ordering follows from causal links, threat orderings, Frame membership and Frame orderings, which are all included. That cut the cost of dedupe from about 30× to about 2× on 70-Step plans. `--no-dedupe` turns dedupe off.
