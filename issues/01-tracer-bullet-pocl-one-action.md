# 01: Tracer bullet: POCL solves a one-action story from the CLI

**What to build:** Running the built-in "tiny" problem from the CLI produces a validated, linearised plan. The domain has one Action schema whose single effect achieves the Outcome. This ticket lays the foundations every later ticket builds on:

- the project restructured into a library, an executable, and a test suite;
- the **complete** syntax types from the spec: literal-valued terms, actors, happening flag, constraints, `≠` preconditions, narration templates, preferences;
- constraint-based grounding against the initial state;
- the ordering structure with cycle detection;
- a POCL refinement loop that handles open conditions only;
- a plain breadth-first search;
- an independent plan validator;
- a topological linearisation.

**Blocked by:** None (can start immediately).

**Status:** ready-for-agent

- [ ] The build and test commands pass with `-Wall` and no warnings.
- [ ] `narrative-planning builtin tiny` prints a plan with exactly one Step between the init and goal Steps.
- [ ] Grounding enumerates one ground action per legal constraint binding and rejects bindings that violate ground `≠` preconditions.
- [ ] Adding an ordering that would create a cycle is rejected, as shown by property tests.
- [ ] The validator accepts the solution and rejects a hand-built plan that has an unsupported precondition.
- [ ] The syntax types can represent every construct in the Aladdin domain of Appendix A.1, as shown by a construction test.
