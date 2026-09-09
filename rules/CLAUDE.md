# CLAUDE.md — `rules/`

A directory-scoped pointer, loaded when a session touches files in `rules/`.
It holds no rules of its own; everything it points at is the source of truth.

## Read before editing anything here

- **`.github/instructions/rules.instructions.md`** — the module contract in
  full: boundaries, the command gate, naming, data, combat math, state.
  Copilot loads it from `applyTo: "rules/**"`; this file is how a Claude Code
  session gets the same thing.
- `rules/README.md` — module layout, and which spec section each directory
  implements.
- `docs/hex-skirmish-game-spec.md` — the mechanics. The authority. A session
  that believes a rule is wrong says so and stops; it does not fix the rule in
  the resolver.
- `docs/godot-implementation-guide.md` — the Godot 4 mechanics behind the
  constraints, and the engine's sharp edges.
- `docs/engine-reference/godot/` — what changed in the engine after the
  model's training data. Check it before reaching for an API from memory;
  `deprecated-apis.md` lists the ones that bite this module specifically.

## The three that are not negotiable

Stated here only so a session cannot miss them. Each is enforced by a contract
test, so violating one fails the build rather than the review.

1. **One-way arrow.** `rules/` names nothing in `res://scripts/`,
   `res://scenes/` or `res://resources/`, and uses no game-side type even by
   global `class_name`. `rules/tests/extraction_contract_test.gd` and
   `tests/inbound_type_contract_test.gd`.
2. **Off the scene tree.** `RefCounted` or `Resource`, never `Node`; no
   autoload, no `await`, no `_process`, no timers.
   `rules/tests/base_class_contract_test.gd`.
3. **Randomness is an explicit input.** Never `randi()`, `randf()` or
   `randi_range()` here. The seed *and* the generator position are part of
   `GameState`. `rules/tests/ambient_rng_contract_test.gd`.

## Adding a player action

One new `TurnAction` subclass in `rules/actions/`, with its own `FAILURE_*`
constant block. No edit to `ActionRunner`, no edit to `Authority`, no registry,
no command enum, no dispatch table. If adding an action needs a change to the
gate, the gate is wrong — say so rather than making the change.

## Before saying it works

`.github/scripts/validate-godot.sh`, and report the exact command and result.
Exit code 127 means Godot was not found: that is *could not validate*, not
*validated*.
