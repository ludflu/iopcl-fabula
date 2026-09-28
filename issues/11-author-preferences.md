# 11: Author preferences

**What to build:** Authors steer which Stories are acceptable from the problem file. There are four Author preference kinds:

- `allow-goals`: whitelist a Character's Character goals;
- `forbid-goal`: rule out one Character goal for a Character;
- `max-frames`: cap the number of Frames per Character;
- `no-repeat-steps`: disallow two Steps with the same ground action.

Each preference is either hard, meaning violating plans are pruned, or soft, meaning it adds a weighted penalty to the heuristic (default weight 10).

**Blocked by:** 07 (Text domain format), 09 (Heuristic search).

**Status:** done

- [x] A test problem where the planner otherwise returns a Story with an unwanted Character goal returns a different Story once a hard `forbid-goal` is added. That different Story does not contain the unwanted goal.
- [x] A soft preference changes which Story is found first but never makes a solvable problem unsolvable.
- [x] Characters without an `allow-goals` entry are unrestricted.
- [x] Each preference kind has unit tests for both its hard and soft forms.

**Notes:** The default soft weight is 10, not 1000. With 1000, every cheaper plan in the infinite IPOCL plan space is explored before any plan that violates the preference. A soft preference then behaves like a hard one within any practical node limit. A hard preference that no Story can satisfy runs until a limit is hit, not to `Exhausted`, for the same reason. Violations are counted only when no further refinement can undo them: ground Frame goals, and Steps whose arguments are fully bound.
