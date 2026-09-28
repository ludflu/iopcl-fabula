# 06: Joint actions and intentional threats

**What to build:** Joint actions are believable only when every Actor has its own Frame containing the Step. A Character never pursues two conflicting Character goals at the same time. This ticket adds:

- frame discovery per Actor for Joint actions, giving `(e+1)^a` children;
- the every-Actor Orphan rule;
- intentional-threat detection between Frames of the same Character whose Character goals are necessarily complementary;
- resolution by ordering one Frame entirely before the other;
- keeping that frame ordering when Steps are later adopted into either Frame.

**Blocked by:** 05 (Intent planning and "contracting out").

**Status:** ready-for-agent

- [ ] A reduced Aladdin problem with a marriage solves. In the result, the `marry` Step is in both the groom's and the bride's Intervals.
- [ ] A plan where only one Actor of a Joint action has a Frame is not accepted as a solution.
- [ ] Two Frames of the same Character with complementary Character goals end up fully ordered. Every Step of one Frame, including its Motivating step, precedes every Step of the other.
- [ ] Adopting a Step into an ordered Frame adds the orderings in the recorded direction. If that creates a cycle, the child is pruned.
