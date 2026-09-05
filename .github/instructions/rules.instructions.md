---
applyTo: "rules/**"
---

# Ruleset module (`rules/`)

`rules/` implements the turn-based hex-combat ruleset in
`docs/hex-skirmish-game-spec.md`. It is a self-contained module with a strictly
one-way dependency arrow: the game depends on `rules/`, never the reverse. Most
rules below exist to keep that true.

**Why the module stays self-contained:** client and server must run identical
simulation, so the rules must be loadable without dragging in scenes, input, or
presentation. The same isolation is what makes replays, save/load, headless AI
search, and hand-checkable unit tests possible. It is not about shipping this
module to other projects — see `EXTRACTION_LOG.md` #1 for why that goal was
rejected outright.

`rules/README.md` holds the module layout; `docs/godot-implementation-guide.md`
holds the Godot mechanics behind these rules.

## Boundaries

- **No outward references.** Nothing here may reference `res://scripts/`,
  `res://scenes/`, or `res://resources/`. Enforced on every build by
  `rules/tests/extraction_contract_test.gd`.
- **No inbound game types either.** Unlike the repo this contract came from,
  `rules/` does not use game-side classes at all — not by `res://` path and not
  by global `class_name`. The source's contract test checks paths only, which
  let its `rules/` depend on `Action`/`ActionResult` from `scripts/`; its own
  README calls that "limited inbound dependencies." We do not have that hole.
  `TurnAction` and `TurnResult` live in `rules/state/` because they are the
  resolver's own signature.
- **Off the scene tree.** `RefCounted` or `Resource`, never `Node`. No
  autoloads, no `await`, no timers, no `_process`/`_physics_process`. A
  turn-based resolver has no frame loop.
- **Do not reach sideways into the game to change it.** If the ruleset appears
  to need a change in `scripts/` or `scenes/`, stop and say so in the PR rather
  than making it.

## Command gate

- **Every player-originated command must be gated.** A player-initiated action
  flows through `TurnAction` → `ActionRunner.run()` → `Authority.can_perform()`
  before resolution. The UI never calls into `rules/` directly, not even in
  local hotseat where the gate looks like pure ceremony. If hotseat bypasses
  it, LAN and dedicated server both require rebuilding the calling convention
  later.
- **`Authority` answers "who may act right now"** — turn order, ownership,
  session. That is a game-side question, so `Authority` lives in `scripts/` and
  the rules module has no opinion about it.
- **Command taxonomy: one `TurnAction` subclass, no `ActionRunner`/`Authority`
  edit.** Adding a new player command means adding one new `TurnAction`
  subclass with its own `FAILURE_*` constant block. It requires no edit to the
  runner or the gate, and no command registry, command-kind enum, or dispatch
  table. Generality comes from subclassing. If adding an action ever requires
  touching the gate, the gate is wrong.

## Naming

- **No class-name prefix.** Godot has no namespaces — `class_name` is one flat
  registry — but this project takes no third-party addons, so the registry
  holds only our classes and Godot's built-ins. The `rules/` boundary is
  legible from the path.
- **Do not shadow a Godot built-in.** The flat registry is still flat: check
  that a new `class_name` is not already an engine type before taking it.
- The source repo prefixes every rules class `Moba` and documents that choice
  as "keep by inertia, not by argument" — its original reasons had both
  expired. Do not import the prefix here.

## Data

- **No fighter, weapon, or card number is written in GDScript.** Values load
  from `resources/`. Dice counts, damage, health, saves, ranges, point values,
  card effects — all data.
- **Game content is authored as `.tres`** in the Godot inspector. The
  mechanics are inherited from a settled tabletop game, but the numbers will be
  tuned, and tuning must never mean editing the resolver.
- **Templates are immutable; runtime state is not.** Godot caches and shares
  `Resource` instances, so a runtime fighter writing a damage counter onto its
  template mutates every fighter sharing it. Copy out of templates. See
  `docs/godot-implementation-guide.md` §3.

## Combat math

- **One module contains the dice-pool resolution.** If another file needs it,
  it calls that module. A second copy of the resolution math is the primary
  correctness risk in this project.
- Formulas are `static`, take plain values, return plain values, and touch no
  node and no scene tree. That is what makes them unit-testable headless.
- **Percentages are fractions** — `0.05`, never `5.0`.
- **Randomness is an explicit input, never ambient.** Never call global
  `randi()`, `randf()`, or `randi_range()`. The `RandomNumberGenerator`'s seed
  *and* its current `state` are part of the game state, so the same state plus
  the same action sequence reproduces the same match in a fresh process. This
  is not a nicety: replays, save/load, deterministic tests, and network sync
  all fail together without it.
- **The tests are the specification.** Unit tests that deal a known board and a
  known seed and assert the outcome against the tabletop rules worked by hand
  are what "correct" means here. Write them alongside the resolver.

## State

- **`GameState` is fully serializable** — board, fighters, hands, decks,
  discard and scored piles, scores, round and turn counters, and the RNG seed
  and state. A snapshot that omits the generator position cannot reproduce the
  match that follows it.
- **Resolution is synchronous.** It takes a state and an action and returns a
  result. It does not animate, wait, or schedule.

## General

- Prefer typed GDScript.
- **Do not add third-party dependencies or addons.** This project builds what
  it needs. A test framework is the one sanctioned exception. If something
  looks like it wants a plugin, say so in the PR rather than adding one.
- Run `.github/scripts/validate-godot.sh` and report the exact command and its
  result. Exit code 127 means Godot was not found — that is "could not
  validate", not "validated successfully".
