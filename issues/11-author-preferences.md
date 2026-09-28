# 11: Author preferences

**What to build:** Authors steer which Stories are acceptable from the problem file. There are four Author preference kinds:

- `allow-goals`: whitelist a Character's Character goals;
- `forbid-goal`: rule out one Character goal for a Character;
- `max-frames`: cap the number of Frames per Character;
- `no-repeat-steps`: disallow two Steps with the same ground action.

Each preference is either hard, meaning violating plans are pruned, or soft, meaning it adds a weighted penalty to the heuristic (default weight 1000).

**Blocked by:** 07 (Text domain format), 09 (Heuristic search).

**Status:** ready-for-agent

- [ ] A test problem where the planner otherwise returns a Story with an unwanted Character goal returns a different Story once a hard `forbid-goal` is added. That different Story does not contain the unwanted goal.
- [ ] A soft preference changes which Story is found first but never makes a solvable problem unsolvable.
- [ ] Characters without an `allow-goals` entry are unrestricted.
- [ ] Each preference kind has unit tests for both its hard and soft forms.
