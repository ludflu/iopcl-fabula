# Narrative Planning

A story generator that builds fabula plans: partially ordered sequences of character actions that reach an author's outcome while every character appears to act intentionally.

## Language

### Story world

**Character**:
A story-world entity that can hold intentions, drawn from the problem's set of agents.
_Avoid_: Agent

**Actor**:
The role a Character plays when it intentionally performs a particular Step, as named by the Action schema's actors slot.
_Avoid_: Agent, performer

**Intention**:
A world-state fact `intends(character, literal)` stating that it is reasonable for that Character to have that goal.
_Avoid_: Using "intention" for a Frame

### Goals

**Outcome**:
The author's required end-state literals; the story must reach it, but no Character need want it.
_Avoid_: Goal, goal situation (unqualified)

**Character goal**:
The literal a Character is pursuing within one Frame.
_Avoid_: Goal (unqualified)

### Plan structure

**Action schema**:
A parameterised template describing an event that can happen in the story world.
_Avoid_: Operator, action (for the template)

**Step**:
One instance of an Action schema placed in a plan.
_Avoid_: Action, operator (for the instance)

**Happening**:
A Step whose Action schema is marked as not requiring any Character's intent, such as an accident or a force of nature.

**Frame**:
The record that a Character commits to a Character goal, with the Steps it performs in pursuit of it and the Step that achieves it.
_Avoid_: Frame of commitment (long form is fine in prose), intention, interval

**Interval**:
The set of Steps belonging to one Frame.
_Avoid_: Interval of intentionality (long form is fine in prose)

**Motivating step**:
The Step (or the initial state) whose effect gives a Frame's Character the Intention for that Frame's Character goal.

**Joint action**:
A Step with more than one Actor; each Actor must have its own Frame whose Interval contains it.

**Orphan**:
A non-Happening Step that, for at least one of its Actors, is in no Interval of that Actor's Frames.

### Authoring

**Author preference**:
A declarative, author-supplied rule in the problem file that steers which stories are acceptable, either as a hard prohibition or a soft penalty.
_Avoid_: Heuristic (that is the search's internal estimate), constraint (reserved for an Action schema's static filter)

**Story**:
A solution plan identified by its set of Steps and its Frames' Character–Character goal pairs, ignoring step ordering.
_Avoid_: Fabula plan (fine in prose), solution
