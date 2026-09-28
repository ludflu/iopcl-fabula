# 07: Text domain format

**What to build:** An author writes a domain file and a problem file in the project's PDDL-flavoured text format, which is not PDDL-compatible, and runs `narrative-planning solve DOMAIN PROBLEM`. The format covers every construct in the spec:

- actors, happenings, constraints, `≠` preconditions, and negative literals;
- `intends` with literal-valued arguments;
- the agents list;
- narration templates and predicate templates;
- author preferences (parsed only; they take effect in ticket 11).

Domain validation errors are reported with their location.

**Blocked by:** 01 (Tracer bullet: POCL solves a one-action story from the CLI).

**Status:** ready-for-agent

- [ ] The Tower, Bribe, and Aladdin domains and problems exist as text files. Each parses into the same value as the built-in Haskell version.
- [ ] Parsing, printing, and parsing again gives an identical value, as shown by a property test.
- [ ] Validation rejects the following, each with a clear message:
  - `intends` in a precondition;
  - an effect of `¬intends`;
  - an effect that negates a static predicate;
  - an actor that is not a parameter;
  - an unknown Character in a preference.
- [ ] `solve` works on the Tower files in POCL mode. It works in IPOCL mode as tickets 03–06 land.
