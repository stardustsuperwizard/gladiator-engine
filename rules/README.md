# Rules Module

The turn-based hex-combat ruleset specified in
`docs/hex-skirmish-game-spec.md`. Self-contained, with a strictly one-way
dependency arrow: **the game depends on `rules/`, never the reverse.**

## Architectural constraints

- **No outward dependencies.** Nothing here references `res://scripts/`,
  `res://scenes/`, or `res://resources/`. Enforced on every build by
  `tests/extraction_contract_test.gd`.
- **No inward dependencies either.** Unlike the repo this pattern was adapted
  from, `rules/` does not use game-side types at all — not even by global
  `class_name`. See *Why `TurnAction` lives here* below.
- **Off the scene tree.** `RefCounted` or `Resource`, never `Node`. No
  autoloads, no `await`, no `_process`, no timers. See
  `docs/godot-implementation-guide.md` §1.
- **Deterministic.** Resolution is a function of state and action only. The
  RNG seed and generator position are part of the game state; nothing here
  reads an ambient generator. Same state + same action → same result, every
  time, in a fresh process.
- **Numbers are data.** Dice counts, damage, health, saves, point values and
  card effects load from `.tres`; only the rules that consume them live here.

## Layout

| Directory | Holds | Spec |
| --- | --- | --- |
| `board/` | Hex coordinates, distance, line of sight, occupancy | §2 |
| `combat/` | Dice-pool resolution, symbol matching, flanking | §7–8 |
| `fighters/` | Runtime fighter and weapon model, status flags, damage | §3, §9 |
| `cards/` | Scoring and ability decks, hands, draw/discard | §4, §10 |
| `state/` | `GameState`, `TurnAction`, `TurnResult`, serialization, RNG | §3 |
| `actions/` | One `TurnAction` subclass per player command | §6 |
| `tests/` | Contract and regression suites | — |

## Why `TurnAction` lives here, not in the game

The source repo keeps `Action`/`ActionResult` in game-side `scripts/` and lets
`rules/` reference them by global `class_name`. Its contract test only forbids
*path* references (`preload`, `load`), so that arrangement passes — but it
means the rules module does not actually stand alone, and the README there
acknowledges it as "limited inbound dependencies."

Ours closes that hole. `TurnAction` and `TurnResult` are the resolver's own
signature, so they belong to the resolver. What stays on the game side is
`Authority` — *who may act right now*, a question about turn order, session
and ownership that the rules module has no opinion about. The game asks the
rules to resolve; the rules never ask the game anything.

Practical consequence: adding a new player action is one new `TurnAction`
subclass and nothing else. No registry, no edit to the authority object. If
adding an action ever requires touching the gate, the gate is wrong.

## Running the tests

```
.github/scripts/validate-godot.sh
```

Two passes — `--import`, then `--headless --quit` — and the suites' result
becomes the exit code. Registering a suite is one entry in `_suites` in
`tests/test_bootstrap.gd`.
