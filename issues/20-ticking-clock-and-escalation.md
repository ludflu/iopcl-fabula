# 20: Ticking clock and escalation (exploratory)

**What to build:** A way for authors to require Cron's overarching plot problem (*Story Genius*, ch. 8). The problem must build, carry a specific impending consequence, and have a deadline that forces the Protagonist to act. This ticket is a design spike: produce a written design and one prototype domain, not a finished feature.

Candidate formalisation to evaluate:
- **Ticking clock**: a chain of Happenings, `tick-1 → tick-2 → … → consequence`, each enabled by the last, plus a Protagonist Frame that must defeat it. The author marks the consequence as one the Story must threaten but not reach: the Outcome contains its negation, and the Story must contain at least `k` ticks. That requires "author goals", the intermediate states the Story must pass through, from `spec.md` §9.
- **Escalation**: authors annotate literals with a stakes rank, `(:stakes (lost-job ruby) 1 (lost-home ruby) 2 …)`. A Preference then asks that the Protagonist's successive Frames, or the ticks, be ordered with stakes that never decrease.

**Blocked by:** 15 (Required Frames), 16 (Protagonist, Desire, Misbelief, and Realization), 19 (Failed intentions as turning points).

**Status:** done

- [x] A design note in `docs/adr/` covers how author goals are represented (pseudo-goal Steps or ordering constraints), what "the Story must contain at least `k` ticks" means for a backward-chaining planner, and how stakes interact with partial order. Only Steps ordered relative to each other can be required to escalate.
- [x] A prototype domain where the planner produces a Story with at least two ticks before the Protagonist defeats the consequence.
- [x] A recommendation: build it, rescope it, or drop it.

**Notes:** IPOCL plans backward from the Outcome, so a consequence that is avoided never becomes an open condition. Something has to pull the ticks into the plan. Ticket 15's pseudo-steps already pull in a Character goal that has a Frame. The spike should decide whether ticks need a frameless version, a **Milestone**: a required literal that any Step, including a Happening, may establish. If so, recommend generalising ticket 15 rather than adding a parallel mechanism.

## Result

`docs/adr/0005-ticking-clocks-need-milestones.md` is the design note. The prototype is `domains/ticking-clock.ipocl` with `-problem.ipocl`, tested in `TickingSpec`. The Story is: the storm breaks, the river rises (two ticks, and the second gives Ruby her Intention), then Ruby sandbags the bank. It is valid, and the flood never happens. The prototype uses no new planner machinery: the ticks are pulled in because the Protagonist's response needs them causally.

**Recommendation: rescope.** Build Milestones as a frameless generalisation of ticket 15: `planRequired :: IntMap (Maybe Symbol)`, where `Nothing` skips the Frame check. Express "at least `k` ticks" as a Milestone on the `k`-th tick's effect, rather than as a counter that can neither pull in Steps nor be pruned on. Add `:stakes` escalation later, as a preference over necessarily ordered pairs only. That count only grows, so it can be pruned on.

The spike also found and fixed a bug from ticket 17. The per-preference location check in `checkedProblem` blanked the Protagonist, so every `(third-rail)` in a problem file was rejected. It now checks the full problem and keeps only the preference messages. `ParserSpec` has a regression test.
