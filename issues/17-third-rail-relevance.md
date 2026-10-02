# 17: Third-rail relevance preferences

**What to build:** Author preferences that make the plot serve the Protagonist's inner struggle. Cron calls that struggle the story's third rail (*Story Genius*, introduction and ch. 14): anything that doesn't touch it "will stop the story cold."

The Protagonist's **arc** is the set of Steps in the Protagonist's Intervals, the Motivating steps of the Protagonist's Frames, and every Realization of a Protagonist Misbelief. The goal Step is not part of the arc. Otherwise every Step on the Outcome's causal chain would count trivially.

- `(third-rail)` penalises each Step that has no path, through causal and motivation links, to a Step in the arc.
- `(serves-protagonist c)` penalises each Frame of Character `c` whose final Step has no such path. This is Cron's rule that secondary characters exist to challenge or reaffirm the Misbelief.

Both default to soft, like the other preferences. Domain checking rejects them if there is no Protagonist (ticket 16).

When violations are counted: a Step gains new outgoing links only when it is reused as an establisher, so a Step with no path now may still gain one. Therefore:
- **hard** forms are checked only at the goal test, on complete plans;
- **soft** forms count the paths missing right now. This works as a heuristic estimate, but the count can go down later, unlike the counts in ticket 11.

Add a validator lint, "an internal change must lead to action": every Realization, and every Step that gives a Character an Intention, must have an outgoing link to a later Step in which that Character is an Actor. This reports a warning and does not reject the plan.

**Blocked by:** 11 (Author preferences), 16 (Protagonist, Desire, Misbelief, and Realization).

**Status:** todo

- [ ] On a test problem with an irrelevant side plot that is still on the Outcome's causal chain, a hard `third-rail` yields a Story without it.
- [ ] A hard `third-rail` never prunes a partial plan. A test checks that a partial plan whose Step lacks a path so far is still expanded.
- [ ] `serves-protagonist` has hard and soft tests.
- [ ] The internal-change lint has a test plan that triggers it and one that doesn't.
- [ ] `spec.md` §4.12 documents that soft third-rail penalties can decrease, unlike the other preferences.
