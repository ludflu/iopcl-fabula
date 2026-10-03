# Ticking clocks need Milestones, a frameless generalisation of Required Frames

Cron's overarching plot problem (*Story Genius*, ch. 8) is a consequence that builds tick by tick toward a deadline the Protagonist must beat. A backward-chaining planner only adds Steps that something already in the plan needs. An avoided consequence is never an open condition, so on their own the ticks never enter the plan.

The prototype (`domains/ticking-clock.ipocl`) works around this with today's machinery. The ticks are a chain of Happenings, `storm → river-rises`, and the Protagonist's response causally needs the last one: `sandbag` requires `river-high`. `river-rises` also gives Ruby her Intention. The Story is: the storm breaks, the river rises, Ruby sandbags the bank. The flood Happening is in the domain but never in a Story. The encoding is fragile. It only works when every tick is a precondition, or a motivator, of something the Outcome needs. The author must also bend the domain so the response can't happen early, and nothing says "at least `k` ticks".

We will represent author goals as **Milestones**: pseudo-steps exactly like ticket 15's, but without the Frame requirement. A Milestone is a required literal that any Step may establish, including a Happening or the init Step. Concretely, `planRequired :: IntMap Symbol` becomes `IntMap (Maybe Symbol)`, and `Nothing` skips the "final Step of a matching Frame" filter. Ordering between Milestones (`(:milestones (raining) (river-high))`, each after the last) is a pair of pseudo-step orderings. That's how "the Story passes through these states in order" is expressed. Ordering constraints alone were rejected: in a backward-chaining planner, an ordering cannot pull a Step into the plan, only a precondition can.

"At least `k` ticks" means a Milestone on the `k`-th tick's effect. The tick chain's preconditions then pull in ticks 1 to `k-1`. Counting Steps of a kind is not an open condition and is not monotone during search, so it can't be a flaw or a prunable preference. "Threatened but not reached" is the Outcome's negation of the consequence plus a Milestone on the consequence's last enabling literal (here `river-high`). The Story then really is one Step from disaster, and the existing causal-threat machinery protects the negation.

Escalation via `(:stakes (lost-job ruby) 1 (lost-home ruby) 2)` interacts with partial order. Only pairs of Steps or Frames that are already **necessarily ordered** (`before`) can be required to escalate. The preference counts ordered pairs whose stakes decrease. Orderings are only ever added, never removed, so this count never goes down, and the preference can be pruned on like the ticket 11 rules. Unordered pairs are left to linearisation, which could sort by stakes as a tie-break.

## Considered Options

- **Encode ticks causally in the domain** (the prototype). Works today with no planner change, but the domain author has to make every tick necessary. Kept as the fallback.
- **A tick counter preference** ("at least `k` Happenings tagged `tick`"). Rejected: it can't pull Steps in, and its count isn't monotone.
- **Milestones as a separate mechanism** next to Required Frames. Rejected: ADR-0004 already says pseudo-steps are the building block for author goals.

## Recommendation

Rescope. Build Milestones by generalising ticket 15, which is a small change to `planRequired`, `fulfils`, validation and the heuristic. Add ordered Milestones and the `:stakes` escalation preference over necessarily ordered pairs as a follow-up. Drop the "at least `k` ticks" counter in favour of a Milestone on the `k`-th tick.
