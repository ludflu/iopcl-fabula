# 05: Intent planning and "contracting out"

**What to build:** Steps that a Character performs to set up its own later Steps are pulled into that Character's Interval, and so are the Steps by which it motivates another Character to act on its behalf. The result is that the §4.4 Bribe story comes out whole. This ticket adds:

- intent flaws with Adopt and Reject resolutions;
- candidates from both conditions: a same-Actor causal predecessor, and a Motivating step of a Frame that serves this Frame;
- recomputing candidates after every refinement, with each Step–Frame pair proposed at most once (ADR-0002);
- the orderings added on Adopt: after the Motivating step, and before the final Step.

**Blocked by:** 04 (Literal-valued parameters).

**Status:** done

- [x] `builtin bribe` returns a Story containing Bribe, Give, and Coerce.
- [x] In that Story, the Villain's Frame for controlling the President is motivated by the initial state, and the Hero's Frame for the Villain having the money is motivated by Coerce.
- [x] Coerce is in the Villain's Interval.
- [x] An equivalence test on sampled search paths shows that the recomputed candidates match the paper's eager formulation (frame discovery plus spreading activation).
- [x] No Step–Frame pair is ever proposed twice in one search branch.
