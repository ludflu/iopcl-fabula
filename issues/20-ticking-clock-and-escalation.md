# 20: Ticking clock and escalation (exploratory)

**What to build:** A way for authors to require Cron's overarching plot problem (*Story Genius*, ch. 8). The problem must build, carry a specific impending consequence, and have a deadline that forces the Protagonist to act. This ticket is a design spike: produce a written design and one prototype domain, not a finished feature.

Candidate formalisation to evaluate:
- **Ticking clock**: a chain of Happenings, `tick-1 → tick-2 → … → consequence`, each enabled by the last, plus a Protagonist Frame that must defeat it. The author marks the consequence as one the Story must threaten but not reach: the Outcome contains its negation, and the Story must contain at least `k` ticks. That requires "author goals", the intermediate states the Story must pass through, from `spec.md` §9.
- **Escalation**: authors annotate literals with a stakes rank, `(:stakes (lost-job ruby) 1 (lost-home ruby) 2 …)`. A Preference then asks that the Protagonist's successive Frames, or the ticks, be ordered with stakes that never decrease.

**Blocked by:** 15 (Required Frames), 16 (Protagonist, Desire, Misbelief, and Realization), 19 (Failed intentions as turning points).

**Status:** todo

- [ ] A design note in `docs/adr/` covers how author goals are represented (pseudo-goal Steps or ordering constraints), what "the Story must contain at least `k` ticks" means for a backward-chaining planner, and how stakes interact with partial order. Only Steps ordered relative to each other can be required to escalate.
- [ ] A prototype domain where the planner produces a Story with at least two ticks before the Protagonist defeats the consequence.
- [ ] A recommendation: build it, rescope it, or drop it.

**Notes:** IPOCL plans backward from the Outcome, so a consequence that is avoided never becomes an open condition. Something has to pull the ticks into the plan. Ticket 15's pseudo-steps already pull in a Character goal that has a Frame. The spike should decide whether ticks need a frameless version, a **Milestone**: a required literal that any Step, including a Happening, may establish. If so, recommend generalising ticket 15 rather than adding a parallel mechanism.
