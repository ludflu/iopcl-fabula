# 16: Protagonist, Desire, Misbelief, and Realization

**What to build:** Problem-file declarations for the inner layer of Cron's method (*Story Genius*, ch. 5–6, 10). The Protagonist enters the story wanting something, their Desire. A false belief, a Misbelief, stands in the way, and the plot forces a Realization that overturns it.

```lisp
(:protagonist ruby)
(:desire (reunited ruby henry))
(:misbeliefs
  (believes ruby love-is-dangerous)
  (believes nora ruby-is-fragile))
```

There is exactly one Protagonist. Any Character may hold Misbeliefs, because Cron gives villains and secondary characters their own (ch. 6). The Character is read from the belief's first argument.

The Desire is a Required Frame (ticket 15) for the Protagonist, so every Story contains the Protagonist pursuing it.

Misbeliefs need no new planning machinery. A Misbelief is an ordinary fact in the initial state. Domains make it bite through negative preconditions on the Actions the Desire needs. A Realization is any Step whose effect negates a Misbelief. It can be a Happening, or the side effect of an intentional Step:

```lisp
(:action confess-love
  :parameters (?a ?b) :actors (?a)
  :constraints (and (character ?a) (character ?b))
  :precondition (and (loves ?a ?b) (not (believes ?a love-is-dangerous)))
  :effect (reunited ?a ?b))
(:action rescue
  :parameters (?a ?b) :actors (?a)
  :constraints (and (character ?a) (character ?b))
  :precondition (in-danger ?b)
  :effect (and (not (in-danger ?b)) (not (believes ?a love-is-dangerous))))
```

The closed-world negative precondition forces causal planning to find a Realization before the blocked Step.

Domain checks:
- the Protagonist is one of the Characters;
- each Misbelief holds in the initial state, and its first argument is a Character;
- error: no `intends(protagonist, desire)` in the initial state;
- warning: no Action can negate a Misbelief;
- warning: the Misbelief doesn't stand in the way. Relaxed reachability is run with every Action that negates the Protagonist's Misbeliefs removed. If the Desire is still reachable, warn. This is only a warning, because relaxed reachability ignores delete effects and can be wrong in the "reachable" direction.

Narration opens with the Protagonist's Misbelief and Desire, and narrates each Realization as one ("Ruby realizes love is not dangerous.").

**Blocked by:** 07 (Text domain format), 08 (Narration and Graphviz), 15 (Required Frames).

**Status:** todo

- [ ] Parser, printer, and round-trip test for `:protagonist`, `:desire`, and `:misbeliefs`.
- [ ] Each domain check above has a test, including the "doesn't stand in the way" warning firing and not firing.
- [ ] New example domain, `domains/misbelief.ipocl`: the Desire is unreachable without a Realization. The planner finds a Story in which a Realization precedes the blocked Step, the Protagonist has a Frame for the Desire, and the Story passes validation.
- [ ] With the Realization Actions removed, the same problem returns `Exhausted`.
- [ ] A variant where the Realization is a side effect of an intentional Step works the same way.
- [ ] Narration for the example opens with the Misbelief and Desire, and marks the Realization.

**Notes:** Beliefs about what Actions will do, which Cron's scene questions and "expectation, broken" need, are out of scope.
