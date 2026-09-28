# IPOCL in Haskell — Implementation Spec

Source: Riedl & Young, *Narrative Planning: Balancing Plot and Character*, JAIR 39 (2010) 217–267
(`narrative_planning.pdf`). Section, figure and definition numbers below refer to that paper.
Terminology follows `CONTEXT.md`. Architectural decisions are recorded in `docs/adr/`.

## 1. Goal

**Purpose: a usable story generator.** Success means an author can write their own domain as a text file
and get believable stories back in reasonable time. Reproducing the paper's examples serves as a correctness
check. Matching the paper's search behaviour exactly is not a goal.

**Fidelity policy: correct by default.** Where the paper is ambiguous, incomplete, or inconsistent, choose the
reading that produces plans valid under Definitions 3 and 6, and record the choice in §5. A behaviour becomes a
`Config` switch only when there is a concrete reason to vary it.

The system implements the **Intent-based Partial Order Causal Link (IPOCL)** planner as a Haskell library plus CLI.
IPOCL solves the *fabula planning problem*: given a domain, it finds a **sound and believable** partially
ordered plan of Steps that transforms the initial state `I` into one where the Outcome `G` holds.
"Believable" means that every non-Happening Step is in the Interval of a Frame for each of its Actors, and
every Frame has a Motivating step.

### 1.1 Acceptance targets

| Level | Problem | Target (laptop, single core) |
|---|---|---|
| A (first milestone) | Tower variant, Bribe (§4.4), and stories of 5–10 Steps | Solution in < 10 s |
| B (release target) | Full Aladdin (Appendix A.1) with author preferences equivalent to the paper's heuristic | Solution in < 5 min |

For comparison, the paper reports about 12 hours and 1.86 M generated nodes for Aladdin.

### 1.2 Deliverables

1. A library implementing the full algorithm of Figure 5: causal planning, motivation planning, intent planning,
   causal threats and intentional threats, with the completeness test of Definition 6.
2. A POCL baseline mode (Figure 1) that uses the same code with intentionality turned off.
3. Domain grounding, a reachability-based heuristic, weighted A* search with duplicate detection, and seeded
   randomisation.
4. **Author preferences**: declarative steering in the problem file, compiled into heuristic penalties or hard pruning (§4.12).
5. Multiple distinct stories per run (`--count N`).
6. A text domain format and parser, plus a Haskell EDSL. Example domains: Tower (§2.2.1), Bribe (§4.4), Aladdin (A.1).
7. Output: the plan and a template-based narration by default, with Graphviz and a search trace on request.
8. An independent plan validator and a test suite.

Non-goals: QUEST and the evaluation study (§5); a discourse planner or real NLG; hierarchical decomposition; failed
intentions and author goals (these are planned for later versions, see §9).

## 2. Algorithm Summary

### 2.1 Problem (Def. 2)
`⟨I, A, G, Λ⟩`: the initial state, the set of Characters, the Outcome literals, and the Action schemas. v1 adds author
preferences (§4.12).

Action schema (Fig. 2), extended with an optional narration template:

```
ACTION ::= name(?v*)  actors: ?v*  happening: Bool
           constraints: LITERAL*  precondition: LITERAL*  effect: LITERAL*  text: TEMPLATE?
```

- **constraints** are static literals. They can only be satisfied by `I`, and no schema may negate them. They
  determine the legal parameter bindings.
- **precondition** may include `?x ≠ ?y` and negative literals. Negative literals are evaluated under the closed-world assumption against `I`.
- **effect** may include `intends(?a, L)`, where `L` is a literal or a *literal-valued parameter* (e.g. `order`'s
  `?objective`). `intends` may appear only in effects and `I`, and an effect can never be `¬intends(...)`.
- **happening = true**: the Step never needs a Frame and is **never** placed in an Interval.
- **actors**: when there are several, the action is *joint* and **every** Actor needs its own Frame whose Interval contains
  the Step. A participant who is unwilling or unmotivated is a parameter but not an Actor.

### 2.2 Plan (Def. 4)
`⟨S, B, O, L, C⟩` stands for Steps, bindings, orderings, causal links, and Frames. Alongside these, the plan stores
motivation links, the frame-ordering constraints produced by resolving intentional threats, the flaw agenda, and the
set of intent-flaw pairs already proposed.

**Frame** (Def. 3): `⟨Interval, character, character goal, final step, motivating step⟩`. Every Step in the Interval
has the Character as an Actor. Every other Step in the Interval precedes the final Step, which has the Character goal
as an effect. The Motivating step establishes `intends(character, character goal)` and precedes every Step in the
Interval.

### 2.3 Flaws
| Flaw | Def. | Meaning |
|---|---|---|
| Open condition `⟨s, p⟩` | POCL | Precondition `p` of `s` has no causal link |
| Causal threat `⟨t, link⟩` | POCL | `t` may fall inside `s_i —p→ s_j` and assert `¬p` |
| Open motivation `⟨c⟩` | 7 | Frame `c` has no Motivating step |
| Intent flaw `⟨s, c⟩` | 8 | Decide whether Step `s` joins Frame `c`'s Interval |
| Intentional threat `⟨c_k, c_i⟩` | 9 | Two Frames of the same Character whose Character goals negate each other |

### 2.4 Refinements (Fig. 5)
- **Causal planning** (open condition `⟨s_need, p⟩`):
  - Choose `s_add`, either an existing Step or a new Step instantiated from a ground Action schema, with an effect
    that unifies with `p`.
  - Add the bindings, `s_add < s_need`, and the link `s_add —p→ s_need`.
  - If `s_add` is new, add open conditions for its preconditions.
  - Run **frame discovery**. For a new non-Happening Step, independently for **each** Actor, choose one effect or `nil`.
    Each non-nil choice creates a Frame, with `s_add` as its final Step, and an open motivation flaw.
  - Run intent-flaw discovery (§4.6) and threat detection (§4.7).
- **Motivation planning** (open motivation `⟨c⟩`): the same as causal planning, but for `intends(char, goal)`. Instead of a causal link,
  record the motivation link `s_add ⇒ c` and add `s_add < s_i` for every `s_i` in the Interval. The initial state can be the
  Motivating step when `I` contains the Intention.
- **Intent planning** (intent flaw `⟨s, c⟩`) has two children:
  1. **Adopt**: add `s` to the Interval. Add `motivator(c) < s` (if a Motivating step exists yet) and `s < final(c)`. Apply
     the frame-ordering constraints (§4.7).
  2. **Reject**: drop the flaw.

  When `s` is adopted, its same-Character predecessors become intent-flaw candidates automatically via §4.6.
- **Termination**:
  - Prune a child as soon as `O` or `B` becomes inconsistent.
  - A node is a solution when its agenda is empty and it has no Orphans.
  - A node whose agenda is empty but which still has Orphans is a dead end.

### 2.5 Completeness (Def. 6)
A plan is complete when (1) every precondition has a causal link, (2) no causal threat remains, and (3) there are no Orphans.

## 3. Project Layout

The cabal skeleton becomes a library, an executable, and a test suite.

```
narrative-planning.cabal
src/IPOCL/
  Syntax.hs         -- Symbol, Var, Term, Atom, Literal, ActionSchema, Problem, Preference
  Pretty.hs         -- prettyprinter instances
  Validate/Domain.hs-- static checks on problems (§4.1)
  Ground.hs         -- grounding + relaxed reachability + effect index (§4.5)
  Bindings.hs       -- codesignation / non-codesignation store, unification
  Ordering.hs       -- partial order with reachability; consistency
  Plan.hs           -- Step, CausalLink, MotivationLink, Frame, Plan, Flaw
  Init.hs           -- initial plan; closed-world support from init
  Threats.hs        -- causal & intentional threat detection
  Intent.hs         -- frame discovery, intent-flaw candidate discovery, orphans
  Refine.hs         -- Plan -> Flaw -> [Child]
  FlawSelect.hs     -- flaw-selection strategy
  Heuristic.hs      -- h_add-based heuristic, orphan/motivation costs, paper's A.1 heuristic
  Preference.hs     -- compile author preferences into penalties / prune predicates
  Search.hs         -- weighted A*, duplicate detection, seeded randomisation, N distinct solutions
  Signature.hs      -- canonical plan signatures (dedupe + story distinctness)
  Validate/Plan.hs  -- independent checker for Def. 6 + simulation
  Linearize.hs      -- topological sort(s)
  Render/Dot.hs     -- Graphviz (Fig. 15 style)
  Render/Narrate.hs -- template narration (Fig. 13 style)
  Parser.hs         -- text format (megaparsec)
  Domains/Tower.hs, Domains/Bribe.hs, Domains/Aladdin.hs
app/Main.hs         -- CLI (optparse-applicative)
test/               -- hspec + QuickCheck
domains/*.ipocl     -- text versions of the example domains
bench/              -- Aladdin acceptance benchmark
```

Dependencies: `base`, `containers`, `text`, `hashable`, `unordered-containers` (duplicate detection), `random`
(seeded tie-breaking), `megaparsec`, `prettyprinter`, `optparse-applicative`. Tests use `hspec` and `QuickCheck`.
Benchmarks use `tasty-bench`.

## 4. Design

### 4.1 Syntax (`IPOCL.Syntax`, `IPOCL.Validate.Domain`)

```haskell
newtype Symbol = Symbol Text                       deriving (Eq, Ord)
data Var = Var { varName :: Text, varId :: !Int }  deriving (Eq, Ord)  -- varId: 0 in schemas, step id in plans
data Term = TSym Symbol | TVar Var | TLit Literal  deriving (Eq, Ord)  -- TLit: literal-valued args of intends
data Atom = Atom { predicate :: Text, args :: [Term] } deriving (Eq, Ord)
data Literal = Pos Atom | Neg Atom                 deriving (Eq, Ord)
data Precond = PLit Literal | PNeq Term Term

data ActionSchema = ActionSchema
  { asName :: Text, asParams :: [Var], asActors :: [Var], asHappening :: Bool
  , asConstraints :: [Atom], asPre :: [Precond], asEff :: [Literal], asText :: Maybe Template }

data Problem = Problem
  { pInit :: Set Atom, pCharacters :: Set Symbol, pOutcome :: [Literal]
  , pSchemas :: [ActionSchema], pPreferences :: [Preference] }
```

`intends` is an ordinary atom `intends(c, TLit l)`, and `intendsOf :: Literal -> Maybe (Term, Literal)` recognises it.
Domain validation rejects a problem if any of the following holds:
- `intends` appears in a precondition or constraint, or an effect is `¬intends`;
- an effect negates a static (constraint) predicate;
- an actor is not a parameter;
- a variable in a precondition or effect is not a parameter;
- a Happening has no parameters (a warning only);
- a preference names an unknown Character.

### 4.2 Bindings (`IPOCL.Bindings`)
- `Bindings = { subst :: Map Var Term, neq :: Set (Term, Term) }`, kept in fully-dereferenced form.
- `unify` works structurally, including through `TLit` (polarity must match), with an occurs check. It also enforces `neq`.
- The module also provides `addNeq`, `resolve`, `possiblyCodesignate`, and `necessarilyCodesignate`.
- After grounding (§4.5) only literal-valued parameters are free. `Bindings` therefore stays small, and most checks are
  simple equality tests.

### 4.3 Ordering (`IPOCL.Ordering`)
- The order is stored as successor sets together with a cached transitive closure (`IntMap IntSet`), updated
  incrementally on each `addOrder`.
- `addOrder a b` returns `Nothing` if `a` is already reachable from `b` (the edge would create a cycle).
- The module provides `before` and `possiblyBefore`.
- The init Step precedes, and the goal Step follows, every Step.

### 4.4 Plan (`IPOCL.Plan`)

```haskell
type StepId = Int; type FrameId = Int
data Step = Step { stepId :: StepId, ground :: Maybe GroundAction   -- Nothing for init/goal
                 , stepActors :: [Symbol], stepPre :: [Precond], stepEff :: [Literal], happening :: Bool }
data CausalLink = CausalLink { clFrom :: StepId, clCond :: Literal, clTo :: StepId }
data Frame = Frame { fId :: FrameId, fChar :: Symbol, fGoal :: Literal
                   , fFinal :: Maybe StepId          -- always Just in v1; Nothing reserved for failed intentions (§9)
                   , fInterval :: IntSet, fMotivator :: Maybe StepId }
data Flaw = OpenCond StepId Literal | CausalThreat StepId CausalLink | OpenMotivation FrameId
          | IntentFlaw StepId FrameId | IntentionalThreat FrameId FrameId
data Plan = Plan
  { steps :: IntMap Step, bindings :: Bindings, orderings :: Ordering'
  , links :: Set CausalLink, motivations :: IntMap StepId      -- FrameId -> motivating StepId
  , frames :: IntMap Frame, frameOrder :: Set (FrameId, FrameId)
  , agenda :: Agenda, proposedIntent :: Set (StepId, FrameId)
  , nextStep :: StepId, nextFrame :: FrameId, depth :: Int }
```

The Character in a Frame is a `Symbol`, not a `Term`, because the parameters of actor slots are always constraint-bound
and therefore ground (the validator enforces this). All fields are strict.

### 4.5 Grounding (`IPOCL.Ground`)
This step runs once at load time.
1. **Enumerate ground actions.** For each schema, solve its constraint atoms against the static facts of `I` (a conjunctive
   query) and check the `≠` preconditions that are already ground. Each solution is a `GroundAction`. Literal-valued
   parameters that no constraint covers (e.g. `?objective`) stay lifted inside the `GroundAction`.
2. **Relaxed reachability.** Run a forward fixpoint from `I` that ignores delete effects, using CWA negative facts that are
   true in `I`. Treat an effect with a lifted `?objective` as able to produce `intends(c, L)` for any `L` that is some
   ground action's effect. Discard unreachable ground actions. The costs from this pass feed `h_add` (§4.11).
3. **Index effects** by `(polarity, predicate, first ground arg)` so establisher lookup does not scan every action.

Establishers for an open condition `p`:
- existing Steps that may precede `s_need` and have an effect unifying with `p`;
- the init Step (a positive `p` in `I`, or a negative `p` under CWA);
- new Steps drawn from the indexed ground actions.

### 4.6 Intentionality (`IPOCL.Intent`)
- **Frame discovery**: see §2.4. It applies only to new non-Happening Steps. There is one independent `Maybe effect` choice
  per Actor, which gives `(e+1)^a` children. A child is pruned if it creates a second Frame with the same `(Character,
  Character goal)` as an existing Frame, since duplicate Frames are redundant.
- **Intent-flaw candidates**: these are recomputed after every refinement and filtered through `proposedIntent`. A pair
  `(s, c)` is a candidate if `s` is not a Happening, `s ∉ Interval(c)`, `char(c) ∈ actors(s)`, and either:
  - **Condition 1**: a link `s —p→ s_j` exists with `s_j ∈ Interval(c)`; or
  - **Condition 2** (contracting out, Fig. 6): `s` is the Motivating step of some Frame `c_i ≠ c`, and `final(c_i)` has a
    causal link to some `s_j ∈ Interval(c)`.

  This subsumes the spreading activation in Figure 5 and does not depend on refinement order (see ADR-0002).
- **Orphans**: `orphans :: Plan -> [(StepId, Symbol)]` returns every (non-Happening Step, Actor) pair for which no Frame of
  that Actor contains the Step.

### 4.7 Threats (`IPOCL.Threats`)
- **Causal threat**: a Step `t` threatens `s_i —p→ s_j` when:
  - `t ∉ {s_i, s_j}`;
  - `t` may fall between the two (both `possiblyBefore s_i t` and `possiblyBefore t s_j` hold);
  - an effect of `t` possibly codesignates with `¬p`.

  The resolvers are promotion, demotion, and separation (only when the codesignation is merely possible).
- **Intentional threat**: two Frames of the same Character, not yet ordered, whose Character goals are necessarily complementary.
  There are two resolvers:
  - record `(c1, c2)` in `frameOrder` and add `s1 < s2` for every member of `c1` and every member of `c2`. Motivating steps
    are not ordered, because a Frame motivated by the initial state could then never come second;
  - the same in the reverse direction.

  If the goals are only *possibly* complementary, the pair is re-checked after later bindings.
- **Frame-order invariant**: when a Step joins a Frame that appears in `frameOrder`, the required orderings are added in the
  recorded direction.
- Motivation links are not threat-protected. They don't need to be, because no effect can be `¬intends` (§4.1).
- Threats are agenda flaws, detected after each refinement and de-duplicated.

### 4.8 Refinement (`IPOCL.Refine`)

```haskell
data Child = Child { childPlan :: Plan, reason :: Text }
refine :: Env -> Plan -> Flaw -> [Child]     -- Env = grounded problem + compiled preferences
```

Each child is built by a pure pipeline:

```
establish → link/orderings → open conditions → frame discovery (list) → intent candidates → threats → hard-preference prune
```

The pipeline runs in the list/`Maybe` monad, so a `Nothing` at any stage drops that child.

### 4.9 Flaw selection (`IPOCL.FlawSelect`)
Choosing which flaw to work on is not a backtracking point. The policy is fixed:
1. Causal and intentional threats.
2. Any flaw with 0 or 1 children (dead ends and forced moves), found by calling `refine` on a bounded sample.
3. Otherwise, the flaw with the fewest children (least-cost flaw repair, LCFR). Ties go to open motivations, then open
   conditions, then intent flaws. After that, the most recently added flaw wins (LIFO).

Intent flaws come last among ties because each has only two cheap children, and delaying them gives more of the plan a chance
to be settled first.

### 4.10 Search (`IPOCL.Search`)
- **Weighted A\***: `f = g + w·h`, where `g` is the number of Steps plus the number of Frames and the default is `w = 2`.
  `--greedy` sets `f = h`.
- **Duplicate detection**: each plan's canonical `Signature` (§4.13) is stored in a `HashSet`, and a child is dropped if its
  signature has been seen. This matters because recomputing intent flaws and the Adopt/Reject choices can reach the same plan
  by several paths.
- **Seeded randomisation**: `--seed N`. Ties in `f` are broken by a per-node random key drawn from a `StdGen` that is split
  deterministically, so the same seed always gives the same stories.
- **Multiple stories**: `--count N` keeps searching after the first solution and yields only solutions whose *story
  signature* differs from all previous ones.
- Limits are maximum generated nodes, maximum expanded nodes, and wall-clock time. The result is `Solved [Plan] Stats |
  Exhausted Stats | LimitHit [Plan] Stats`.
- An optional trace callback records the node, parent, reason, flaw, and child count, reproducing the style of Appendix A.3.

### 4.11 Heuristic (`IPOCL.Heuristic`)
`h(plan)` is an estimate of the remaining refinements. It is the sum of:
- for each open condition `p`: `cost(p)`, the h_add cost from the relaxed reachability pass (§4.5). This is 0 if `p` holds in `I`.
- for each open motivation `c`: `1 + cost(intends(char c, goal c))`;
- for each Orphan: 2 (one intent flaw plus the Frame it needs). If the Actor has no Frames at all, add `1 + min cost of an
  intends for that Actor`;
- for each intent flaw and threat: 1;
- the soft penalties from author preferences (§4.12).

`--heuristic paper` selects the Appendix A.1 domain-independent heuristic instead, for comparison. POCL mode drops the
motivation, orphan, and intent terms.

### 4.12 Author preferences (`IPOCL.Preference`)
Preferences are declared in the problem file. Each one is either **hard**, meaning a child that violates it is pruned, or
**soft**, meaning a penalty is added to `h`. The default is soft with weight 1000.

```lisp
(:preferences
  (allow-goals aladdin (has jafar lamp) (not (alive genie)) (not (alive dragon)) (married-to aladdin jasmine))
  (allow-goals jafar (married-to jafar jasmine))
  (allow-goals jasmine (married-to jasmine jafar))
  (allow-goals genie (loves jasmine jafar) (loves jafar jasmine) (loves aladdin jasmine))
  (forbid-goal jafar (not (alive jasmine)) :hard)
  (max-frames jasmine 1 :weight 50)
  (no-repeat-steps :weight 5000))
```

- `allow-goals c L*` penalises any Frame of `c` whose Character goal is not in the list. Characters with no `allow-goals`
  entry are unrestricted.
- `forbid-goal c L` penalises or prunes a Frame of `c` with that Character goal.
- `max-frames c n` penalises the Frames beyond `n` for Character `c`.
- `no-repeat-steps` penalises two Steps with the same ground action.

Aladdin's paper heuristic becomes the preferences above. Its "marry needs two frames" rule is not needed, because the
joint-action rule (§2.1) already enforces it.

### 4.13 Signatures (`IPOCL.Signature`)
- **Plan signature**: identifies plans for duplicate detection. It is built from:
  - the multiset of ground actions, with Step ids renamed canonically by a deterministic ordering of ground action and
    parents;
  - the links, orderings, Frames (`Character`, `Character goal`, Interval, Motivating step), and the agenda.
- **Story signature**: identifies a story for distinctness in `--count`. It is the multiset of ground actions together with
  the set of `(Character, Character goal)` Frames. Orderings are ignored, so two plans that differ only in step order count as
  the same story.

### 4.14 Validation, linearisation, and rendering
- `Validate.Plan.checkComplete :: Problem -> Plan -> [Violation]` re-checks Definitions 3 and 6 without using any search code.
  It then simulates one topological linearisation from `I` under CWA, checking each precondition and the Outcome.
- `Linearize` produces a deterministic topological order, preferring Motivating steps as early as possible so that narration
  reads naturally. It can enumerate all orders for small plans.
- `Render.Narrate` walks the linearisation and prints each Step's `:text` template. A Step without a template is printed as
  `"<name> <args>"`. For each Frame it prints `"<Character> wants <goal>."` right after the Motivating step. The goal
  literal is rendered with the same template mechanism for predicates, via an optional `(:predicate-text ...)` section in
  the domain.
- `Render.Dot`: draws Steps, causal links (solid), orderings added for threat resolution (dashed), Frames as clusters, and
  motivation links.
- Default CLI output is the plan listing plus the narration. `--dot FILE` and `--trace FILE` are opt-in.

### 4.15 Input format (`IPOCL.Parser`)

The format is PDDL-flavoured and **not** PDDL-compatible. It adds `:actors`, `:happening`, `:constraints`, `:text`,
`:agents`, `:preferences`, `:predicate-text`, and literal-valued arguments to `intends`.

```lisp
(define (domain aladdin)
  (:predicate-text (alive ?x) "?x is alive" (loves ?a ?b) "?a loves ?b")
  (:action slay
    :parameters (?slayer ?monster ?place)
    :actors (?slayer)
    :constraints (and (knight ?slayer) (monster ?monster) (place ?place))
    :precondition (and (at ?slayer ?place) (at ?monster ?place) (alive ?slayer) (alive ?monster))
    :effect (not (alive ?monster))
    :text "?slayer slays ?monster.")
  (:action appear-threatening
    :parameters (?monster ?char ?place) :actors (?monster) :happening t
    :constraints (and (monster ?monster) (character ?char) (place ?place))
    :precondition (and (at ?monster ?place) (at ?char ?place) (scary ?monster) (neq ?monster ?char))
    :effect (intends ?char (not (alive ?monster)))
    :text "?monster appears threatening to ?char."))
(define (problem aladdin-1) (:domain aladdin)
  (:agents aladdin jafar jasmine genie dragon)
  (:init (character aladdin) ...)
  (:goal (and (married-to jafar jasmine) (not (alive genie))))
  (:preferences ...))
```

The Haskell EDSL comes first, and the text format is added in M6. A round-trip test (parse → pretty → parse) is required.

### 4.16 CLI

```
narrative-planning solve DOMAIN PROBLEM [--mode ipocl|pocl] [--count N] [--seed N]
    [--weight W | --greedy] [--heuristic default|paper] [--max-nodes N] [--timeout S]
    [--trace FILE] [--dot FILE] [--no-narrate]
narrative-planning validate DOMAIN PROBLEM PLAN
narrative-planning builtin tower|bribe|aladdin [solve options]
```

## 5. Decisions on Ambiguities in the Paper

| # | Issue | Decision |
|---|---|---|
| D1 | Fig. 5 3a says "the character of `s_add`" (singular), but §4.5 gives `(e+1)^a` branching. | Each Actor chooses an effect or `nil` independently. |
| D2 | What "intentional" means for joint actions. | Every Actor needs its own Frame that contains the Step. |
| D3 | Can Happenings be in Intervals? | Never. They get no frame discovery and no intent flaws. |
| D4 | Figs. 1 and 5 resolve threats inside each refinement, while the A.3 trace treats threats as flaws. | Threats are agenda flaws. |
| D5 | Condition 2 uses inconsistent indices, and discovery only runs for `s_add`. | Candidates are recomputed after every refinement (§4.6, ADR-0002). |
| D6 | Motivation links are not threat-protected. | Effects can never be `¬intends`, so no protection is needed. |
| D7 | Figure 5's "adopt" step allows either ordering (`s_i < s` or `s < s_i`) for Frames ordered with respect to `c`. | Use the direction recorded in `frameOrder`. |
| D8 | Intentional threats between goals that are only possibly complementary. | Flag only necessary complements, and re-check after bindings change. |
| D9 | Negative preconditions against `I`. | Closed-world assumption. |
| D10 | Def. 3 requires each member to precede the final Step, but "adopt" only orders `motivator < s`. | Also add `s < final(c)`. |
| D11 | Can a reused Step become the final Step of a new Frame? | No, as in the paper. This keeps the search systematic. |
| D12 | Fig. 15 has `married(K,J)` where the domain uses `married-to`. | Treated as a notational slip. |
| D13 | Can an `intends(...)` effect or a negative literal be a Character goal? | Yes. |
| D14 | Duplicate Frames with the same Character and Character goal. | Pruned (§4.6). |
| D15 | Init and goal Steps. | They have no Actors and are never Orphans. |

## 6. Milestones

Each milestone ends with green tests.

1. **M0 Scaffolding**: set up the library, exe, test and bench stanzas, with `-Wall -Werror` in CI and `fourmolu` and `hlint` config.
2. **M1 Core data**: `Syntax`, `Pretty`, `Validate.Domain`, `Bindings`, `Ordering`, with property tests.
3. **M2 Grounding and the POCL baseline**:
   - build `Ground`, `Plan`, `Init`, causal threats, `Refine` (open conditions and threats only), `Search`, `Validate.Plan`,
     and `Linearize`;
   - acceptance: POCL solves Tower, and solves Aladdin in POCL mode.
4. **M3 Frames and motivation**: frame discovery, open motivation flaws, motivation planning, Orphans, the IPOCL goal test.
5. **M4 Intent planning and intentional threats**:
   - build intent candidates (conditions 1 and 2), Adopt and Reject, `frameOrder`, and the frame-order invariant;
   - acceptance: Level A (§1.1). The Bribe run must place Coerce in the Villain's Interval.
6. **M5 Performance and steering**:
   - build the h_add heuristic, LCFR, signatures and duplicate detection, preferences, seeding, and `--count`;
   - acceptance: Level B, full Aladdin in under 5 minutes, producing a story equivalent to Fig. 15.
7. **M6 I/O**: the parser, round-trip tests, the CLI, narration templates, and DOT output.
8. **M7 Hardening**: profiling (`+RTS -s`), a bounded open list as an optional escape hatch, and documentation.

## 7. Testing Strategy

- **Unit tests** cover:
  - unification through literal-valued terms, and non-codesignation;
  - ordering closure;
  - CWA support from `I`;
  - grounding and reachability;
  - each refinement operator on hand-built plans;
  - each preference kind.
- **Property tests** (QuickCheck):
  - no child has a cyclic `O` or an inconsistent `B`;
  - every solution passes `Validate.Plan`;
  - on small random domains, a POCL-mode solution simulates correctly;
  - an IPOCL solution exists only if a POCL solution exists;
  - duplicate detection never drops a plan with a new signature;
  - the same seed gives the same output.
- **Equivalence tests** check that recomputed intent candidates equal Figure 5's eager formulation (frame discovery plus
  spreading activation) along sampled search paths.
- **Scenario tests**:
  - Tower: with no motivating actions, IPOCL returns `Exhausted` while POCL finds "princess kills king". With a variant that has
    motivating actions, every Step is in an Interval.
  - Bribe: the Frames are Villain → `controls(vil, prez)` (motivated by `I`) and Hero → `has(vil, $)` (motivated by Coerce), and
    Coerce is in the Villain's Interval.
  - Aladdin: the benchmark in `bench/` (Level B) checks the Frame set against Fig. 15.
  - `--count 3` returns three stories with distinct story signatures.
- **Golden tests**: narration and DOT output for Bribe, and a trace excerpt.

## 8. Risks

- **Missing Level B.** The branching factor is about 6.6 on average, reaching 98, at a depth of about 82. The mitigations are
  grounding and reachability pruning, h_add, LCFR, duplicate detection, and preferences. If Aladdin still takes more than 5
  minutes after M5, the fallbacks are, in order: (1) bounded-beam search; (2) pruning intent flaws with a "no possible Frame"
  lookahead; (3) revisiting ADR-0001.
- **Soundness bugs in intentionality bookkeeping**: guarded by the independent validator and the equivalence property.
- **Memory**: persistent structures and strict fields help, but the duplicate-detection set grows with the number of
  expanded nodes. The mitigation is to cap it with `--max-nodes`.

## 9. Planned for Later Versions (design must not preclude)

- **Failed intentions**: Frames with `fFinal = Nothing`, meaning the Character tried and failed or was pre-empted (§4.6 of the paper).
  v1 never creates them, but every function over Frames must handle `Nothing`.
- **Author goals**: intermediate states the story must pass through (Riedl 2009), added as ordered pseudo-goal Steps.
