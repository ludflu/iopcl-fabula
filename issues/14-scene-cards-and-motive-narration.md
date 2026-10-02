# 14: Scene cards and motive narration

**What to build:** A `--cards` output that renders each Step of a Story as a Scene card (Cron, *Story Genius*, ch. 11). Every field comes from plan structure that already exists:

| Card field | Source in the plan |
|---|---|
| Alpha Point | the Step itself (its `:text`, or `<name> <args>`) |
| What happens | the incoming causal links: which earlier Steps made this one possible, and what they supplied |
| The consequence | the Step's effects that some causal or motivation link consumes |
| Why it matters | for each Actor, the Frames whose Interval contains the Step, with their Character goals |
| Internal change | effects that give a Character an Intention, or Realizations (ticket 16) |
| And so? | the outgoing links, and the Steps they enable |

There is one card per Step. Grouping Steps into Cron's larger scenes has no formal basis yet and is left to a later ticket. Cards appear in the same linearisation order as narration. Happenings show no "Why it matters" entry.

Default narration also gains motives, added only where they help. In linearisation order, the first Step of each Frame's Interval gets a clause naming the Character goal ("Jafar sets out to control the President: he bribes the President."). The Frame's final Step gets a closing clause ("…and so Jafar controls the President."). Other Steps in the Interval are narrated as today, so long Stories don't repeat the goal on every line.

**Blocked by:** 08 (Narration and Graphviz).

**Status:** todo

- [ ] `solve --cards` prints one card per non-init, non-goal Step, in linearisation order.
- [ ] Every causal and motivation link in the plan appears on exactly two cards: as "And so?" on its source and as "What happens" on its target.
- [ ] A Step with no consumed effect is flagged on its card ("no consequence used"). A validated Story should never have one, so this is a sanity check.
- [ ] Bribe narration introduces the Villain's goal of controlling the President at the first Step of his Interval, and closes it at Bribe.
- [ ] A Frame whose Interval holds a single Step gets one combined clause, not two.
- [ ] Golden tests for Bribe: the cards output and the updated narration.

**Notes:** Cron's "And so?" asks what the protagonist does next because of the scene. The plan's outgoing links are the mechanical version of that. When ticket 16 adds a Protagonist, the card can also show which of the Protagonist's Frames the Step leads to.
