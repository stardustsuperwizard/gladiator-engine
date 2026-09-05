# GitHub Copilot Instructions

## Project Context

This repo (`gladiator-engine`) is a Godot 4 **turn-based hex-grid skirmish
game**. Two players, small rosters of fighters, a fixed number of rounds, and
combat resolved by a dice pool with symbol matching. The ruleset lives as a
self-contained module in `rules/`, with the game that drives it in `scripts/`
and `scenes/`.

The mechanics are inherited from a settled tabletop game and are not up for
redesign; the numbers are, which is why they live in `resources/` as data
rather than in the resolver.

Read and follow `AGENTS.md` before making repository changes. The three
documents that define the work are `docs/hex-skirmish-game-spec.md` (the
rules), `docs/moba-to-hex-skirmish-extraction-plan.md` (scope and build order)
and `docs/godot-implementation-guide.md` (Godot mechanics).

**Current state: the project is at Slice 0** — extraction plan §5.1. Board,
two fighters, one Attack routed through the authority object, and tests
asserting the result against the tabletop rules worked by hand. Everything in
§5.3 is deferred on purpose; check that list before building something that
feels obviously missing.

## Path-Scoped Instructions

Some directories carry additional instructions that apply automatically when you touch
files inside them. On github.com these are honored by the Copilot cloud agent and by
Copilot code review.

| File | Applies to |
| --- | --- |
| `.github/instructions/rules.instructions.md` | `rules/**` — the combat ruleset |

They are additive, not replacements. This file and `AGENTS.md` still apply.

## Work Delegation

Human-authored GitHub Issues and project documentation remain the
source of truth for intended behavior.

Roles, model routing, and the session flow are defined in
`docs/AGENT_WORKFLOW.md`. Execution sessions start cold: the task Issue
is the only context carried across the handoff. If a constraint is not
written in the Issue, it does not exist.

## Declaring Issue dependencies

One Issue waiting on another is written in exactly one place: the
`## Dependencies` table that every Issue template carries.

```markdown
## Dependencies

| Relationship | Issue | Why |
| --- | --- | --- |
| Blocked by | #12 | Needs the effect container API |
| Blocks | #34 | #34 consumes the resolver this adds |
```

Two relationship words and only two. `Blocked by` means this Issue cannot
start until that one closes; `Blocks` is the same edge written from the other
end. Write whichever end you know about — both, when you know both. When
there are no dependencies, leave the template's row alone:

```markdown
| None | — | — |
```

**Add the `blocker` label to any Issue with a `Blocks` row.** That label is
the trigger: `.github/workflows/issue-dependencies.yml` fires on it, reads the
table, and creates GitHub's native blocked-by relationship. The label also
makes the set queryable — `is:issue is:open label:blocker` is every Issue
something is waiting on.

The table is the declaration; the GitHub relationship is derived from it.
That direction matters, because everything downstream reads the relationship
and none of it reads the table: the control plane orders dispatch by it,
`agent:implementer:copilot` refuses a task whose blockers are open, and
`issue-linking.yml`
warns when work starts on a blocked task anyway. An edge that exists only in
someone's head is an implementer implementing step three before step one exists.

Three rules follow from that:

- **Do not create the relationship by hand and leave the table saying
  something else.** The table wins, and a sweep will report the difference.
- **Do not use `gh issue create --blocked-by` or `gh issue edit
  --add-blocked-by`.** Those need GitHub CLI 2.94.0 and fail as unknown flags
  on anything older. More to the point, a chain wired that way exists only if
  the call succeeded, and nothing records the intent if it did not — which is
  the state this repository was in. Write the row and add the label instead.
- **Never delete a dependency to unblock yourself.** If the edge is wrong,
  correct the table and say so.

The chain can always be rebuilt from the tables: dispatch
`issue-dependencies.yml` with **sweep** ticked. It is add-only — an edge in
GitHub that no table declares is reported, never removed.

The grammar lives in `.github/scripts/issue_dependencies.py`, which also
accepts the older `- Blocked by: #12` bullet form so Issues filed before this
standard still sync.

## Executing an Implementation Task

This section applies whenever you are working an Issue titled `[impl]`, or
any Issue carrying the `implementation` label. It is the same contract as
`.github/agents/02-implementer.agent.md`, restated here because almost no cloud
session loads that file: assigning Copilot from an Issue offers no agent
picker, and on GitHub Mobile choosing a custom agent gives up the model
picker. This file is read on every session regardless, which makes it — not
the profile — the contract of record. A short form also appears in the
**Implementation Agent Contract** section of the Issue itself.

### The contract

Treat the Issue's **Objective**, **Scope**, **Architecture Constraints**,
**Acceptance Criteria**, and **Out of Scope** sections as the authoritative
implementation contract.

The parent Feature provides context only. It does not expand your scope.
Neither do sibling tasks, and neither does anything you notice in passing.

### Procedure

1. Read the complete contract before changing anything.
2. Inspect the existing code and tests relevant to the task.
3. Implement the smallest change that satisfies the acceptance criteria.
4. Follow existing repository architecture and conventions.
5. Add or update tests when the acceptance criteria require it, or when they
   are needed to demonstrate the requested behavior.
6. Run `.github/scripts/validate-godot.sh`.
7. Fix defects that validation surfaces **within** the task's scope.
8. Stop and report anything you cannot resolve inside the contract.

### Guardrails

Do not:

- broaden the requested scope;
- redesign architecture;
- implement adjacent or sibling tasks;
- make speculative improvements;
- create GitHub Issues;
- modify unrelated systems because you spotted an opportunity;
- silently resolve architectural or product ambiguity;
- inherit additional work from the parent Feature;
- close the parent Feature.

If you find work outside the contract, do not implement it and do not file an
Issue for it. Report it under **Discovered out-of-scope work** and let the
planner decide.

If the task genuinely cannot be implemented without making an architectural
or product decision the contract does not already settle, stop and report the
ambiguity rather than deciding it. Minor choices that follow established
repository patterns do not need escalation.

### Completion report

The pull request title must start with `[<n>]`, where `<n>` is the
Implementation Task Issue number (for example `[94] Add hex line-of-sight
tie-break`), and its description must close that Issue — `Closes #<n>` — and
must not close the parent Feature. Report:

1. **Files changed** — each file and why.
2. **Acceptance criteria** — each one, and whether it is satisfied.
3. **Validation** — the exact command run and its result.
4. **Discovered out-of-scope work** — or `None`.
5. **Unresolved issues** — anything that blocked complete implementation,
   or `None`.

Do not report the task complete if required validation failed. If validation
fails for a pre-existing or clearly out-of-scope reason, say so explicitly
rather than expanding the task to fix it.

## Godot

- This project targets Godot 4.
- Use Godot 4 APIs and conventions.
- Do not introduce Godot 3 APIs or deprecated Godot 3 patterns.
- Use GDScript unless an Issue explicitly requires another language.
- Prefer typed GDScript where practical.
- Preserve Godot scene and resource serialization conventions.
- Do not manually rewrite `.tscn`, `.tres`, or `project.godot` more broadly
  than required by the Issue.

## Project Architecture

The project is in two layers: the self-contained ruleset in `rules/`, and the
game that drives it in `scripts/` and `scenes/`. `rules/` has a one-way
dependency arrow — the game depends on the rules, never the reverse — enforced
on every build by `rules/tests/extraction_contract_test.gd`.

Before implementing a feature:

1. Inspect the existing shared types and extension points in `scripts/`.
2. Prefer using or extending those over duplicating their behavior.
3. Keep rules behavior inside `rules/`, with its one-way dependency arrow
   intact, unless the Issue explicitly changes that boundary.

## Architecture

Three responsibilities, kept separate:

- **`rules/` — pure simulation.** Takes a `TurnAction` and a `GameState`,
  returns a `TurnResult`. `RefCounted`/`Resource` only, never `Node`. No scene
  tree, no autoloads, no ambient RNG. See
  `.github/instructions/rules.instructions.md`.
- **`Authority` (in `scripts/`) — who may act right now.** Turn order,
  ownership, session. Every action passes through
  `ActionRunner.run()` → `Authority.can_perform()` before resolution,
  **including in local hotseat**, where it looks like pure ceremony. If hotseat
  bypasses it, LAN and dedicated server both require rebuilding the calling
  convention later.
- **The view (in `scenes/`) — renders results.** Observes; never decides. It
  never mutates game state and never calls into `rules/` directly.

Adding a new player command means adding one new `TurnAction` subclass. It
requires no edit to the runner or the gate, and no registry, enum, or dispatch
table. If adding an action requires touching the gate, the gate is wrong.

Preserve this separation unless an Issue explicitly changes it.

## Scenes and Nodes

This is a 2D, turn-based game. There is no player controller, no character
movement, and no physics.

- Board rendering uses `TileMapLayer` (hex tiles) or drawn `Node2D`s. Godot
  addresses hex tiles in **offset** coordinates; the rules module uses cube
  coordinates. Convert at the view boundary and never let an offset coordinate
  into `rules/`. See `docs/godot-implementation-guide.md` §4.
- Prefer composition of nodes over deep inheritance hierarchies.
- Do not add `_physics_process`, `CharacterBody`, gravity, or collision. A
  fighter moves because the rules said it did, not because a body integrated a
  velocity.

## Input

Input is pointer selection on a hex grid plus UI buttons for the core actions.

- Use named Input Map actions rather than hard-coding keys in gameplay logic.
- Preserve existing input actions unless an Issue explicitly changes them.
- Never assume a mouse cursor or a hover state — touch has neither.
- Input produces a `TurnAction` and hands it to the authority object. It never
  reaches into `rules/`.

## Signals and Coupling

Prefer signals or existing extension points when communication does
not require direct ownership.

Avoid creating global dependencies or new autoload singletons merely to
connect unrelated systems.

## Scope

Follow `AGENTS.md`.

In particular:

- Implement only what the Issue requires.
- Treat acceptance criteria as requirements.
- Treat explicitly out-of-scope behavior as prohibited for that change.
- Do not opportunistically redesign neighboring systems.
- Do not introduce abstractions solely for hypothetical future features.

## Validation

When changing Godot scripts, scenes, or resources, run:

```
.github/scripts/validate-godot.sh
```

This is the same validation CI runs. It performs an import pass (scenes and
resources resolve) and a headless boot (scripts parse, autoloads initialize).

- Report the exact command and its result.
- Report any validation that could not be performed, rather than omitting it.
- Exit code 127 means Godot was not on PATH — that is "could not validate",
  not "validated successfully".

Do not weaken validation to make a change pass.
