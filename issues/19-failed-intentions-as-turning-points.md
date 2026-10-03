# 19: Failed intentions as turning points

**What to build:** Frames whose Character goal is never achieved, so that Stories can contain Cron's turning points (*Story Genius*, ch. 7). In each one, the protagonist "will most likely have a real shot at getting the thing she wants, and something will happen that causes her misbelief to rear its head and prevent her from getting it."

This implements the failed intentions planned in `spec.md` §9. A **failed Frame** is a blocked attempt:
- it has `fFinal = Nothing`, a Motivating step, and an **attempted Step**. The attempted Step is a Step from an Action schema that would achieve the Character goal. It is placed in the plan and ordered, but it is **unexecuted**: simulation skips its effects, and none of its effects may establish anything;
- the attempted Step is in the Frame's Interval. Other Interval Steps precede it as usual;
- exactly one precondition `p` of the attempted Step is blocked. Its "establisher" is a causal link `c —¬p→ attempt`, where `c` is a Step that asserts `¬p` or the init Step under the closed-world assumption. The link is threat-protected like any other. A Misbelief that is still held is the typical blocker: the link comes from the init Step, and no Realization may fall between;
- the attempted Step's other preconditions are linked as normal, which gives the Character a real shot;
- only the failed Frame's Character needs a Frame containing the attempted Step. Its other Actors are exempt from the Orphan check for it. "Aladdin tries to marry Jasmine, but she doesn't love him" makes no claim that Jasmine intended anything. Record this next to D2 in `spec.md` §5.

Anything may block an attempt: a Step asserting `¬p`, or the initial state. A new soft Author preference, `(misbelief-blocks)`, penalises Protagonist attempts blocked by anything other than one of the Protagonist's own Misbeliefs. Cron's turning points are driven by the misbelief, but a rival getting there first is good plot too.

See ADR-0003.

Failed Frames enter plans only through Required Frames (ticket 15) marked `:fail-first`:

```lisp
(:required-frames (ruby (reunited ruby henry) :fail-first))
```

This requires two Frames of Ruby for that Character goal: a failed Frame, and then a successful one. Every Step of the failed Frame, including the attempted Step, is ordered before the first Step of the successful Frame's Interval.

D14 (duplicate Frames are pruned) gains one exception: a failed Frame and a successful Frame with the same Character and Character goal may coexist when the failed one is ordered entirely first. Record this in `spec.md` §5.

Narration and Scene cards (ticket 14) render the attempt as "Ruby tries to confess her love to Henry, but she still believes love is dangerous." The blocked precondition comes from its predicate text.

**Blocked by:** 06 (Joint actions and intentional threats), 15 (Required Frames), 16 (Protagonist, Desire, Misbelief, and Realization).

**Status:** done

- [x] Every function over Frames handles `fFinal = Nothing`, and every function over Steps handles unexecuted Steps. Existing code is audited and has tests for both.
- [x] Validation checks each failed Frame independently. It needs a Motivating step and an attempted Step whose schema has the Character goal as an effect. The attempted Step must have exactly one precondition that is false at its position in simulation, and all its other preconditions must hold there.
- [x] Unexecuted Steps establish nothing. A test tries to reuse one as an establisher and finds no such child.
- [x] On the ticket-16 example with `:fail-first`, the Story has Ruby try and fail while the Misbelief holds, then a Realization, then Ruby succeed.
- [x] A second failed Frame for the same Character goal, or one ordered after the successful Frame, is pruned.
- [x] Without `:fail-first`, the planner never creates failed Frames.
- [x] A joint attempted Step (`marry`) needs a Frame only for the failed Frame's Character. The other Actor is not an Orphan.
- [x] `misbelief-blocks` changes which blocker is chosen when both a Misbelief and a rival's Step could block the attempt. Hard and soft tests.
- [x] Story signatures distinguish failed Frames from successful ones with the same goal.

**Notes:** The "Ruby tries to … but …" narration needs predicate text for the blocked precondition's negation. Ticket 08's `:predicate-text` may need a negated form.

## Result

`(ruby (reunited ruby henry) :fail-first)` sets `rfFailFirst`, and schemas can give `:attempt-text`. Each fail-first pseudo-step starts in `planOpenAttempts` as an `OpenAttempt` flaw (IPOCL mode only). `openAttempt` adds a new Step for each ground action that would achieve the goal with the Character as an Actor, for each choice of one precondition `q`. The Step goes into `planUnexecuted` with an open condition for `¬q` in place of `q`, and a failed Frame (`frameFinal = Nothing`, `frameAttempt = Just k`) is created and recorded in `planFailFirst`. Attempts draw on every ground action, not only reachable ones (`envAttemptIndex`, built lazily), because a blocked precondition may be one nothing can achieve: Ruby tries to elope but has no car.

`finalize` runs `orderFailFirst`. Once the successful Frame fulfils the pseudo-step, every member of the failed Frame is ordered before every member of the successful one, and plans that can't be ordered that way are pruned.

Unexecuted Steps:
- Effects: they never establish anything, never threaten, and are never adopted into other Frames. Preferences, lint and scene cards ignore their effects. `no-repeat-steps` skips them.
- Orphans: they only need a Frame for the failed Frame's Character.

D14 counts only successful Frames. A second failed Frame for the same goal is refused. `frameEnd` (final Step or attempted Step) replaces `frameFinal` wherever members must come first.

`(misbelief-blocks)` counts Protagonist attempts whose blocking link is not `init —m→` for one of the Protagonist's own Misbeliefs. The count only grows, so it can be pruned on.

Validation works out the attempted Steps from the failed Frames and checks:
- that they match `planUnexecuted`;
- that each has exactly one blocked precondition and that nothing links from it;
- that its schema effects include the goal;
- that simulation finds exactly one precondition false and applies none of its effects;
- that each fail-first Required Frame has a failed Frame entirely before the successful one.

Output:
- Narration and cards render "ruby tries to tell henry she loves him, but ruby believes love is dangerous."
- The report marks "(attempt, blocked)" and "(fails)".
- DOT draws attempts dotted.
- Story signatures mark both.

`spec.md` §5 records the D2 and D14 exceptions, and the Aladdin counts are unchanged.
