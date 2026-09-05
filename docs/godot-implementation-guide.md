# Godot Implementation Guide

Engine-specific practices for building this rules engine in **Godot 4 / GDScript**.

`hex-skirmish-game-spec.md` is deliberately engine-agnostic — it describes
mechanics, not an implementation. This document is where the Godot specifics
live, so the spec stays portable and there is one place to look when the
question is "how does this work in Godot."

---

## 1. Keep the rules module out of the scene tree

Rules classes extend `RefCounted` or `Resource` — never `Node`.

A `Node` drags in the scene tree, lifecycle callbacks, `_process`, and
parent/child coupling. None of that belongs in a deterministic resolver, and
all of it makes headless testing harder. Rules objects should be constructible
with `.new()` and usable with no scene loaded at all.

Concretely, inside `rules/`:

- No `Node`, no `get_node()`, no `$` paths.
- No `_process` / `_physics_process` — a turn-based resolver has no frame loop.
- No access to autoloads/singletons. An autoload reference is a hidden global
  input and quietly destroys purity.
- No `await`, timers, or tweens. Resolution is synchronous and instantaneous;
  animation is the view's problem.
- No `print()` for anything the caller needs — return it in the result.

Use static typing throughout
(`func resolve(state: GameState, action: TurnAction) -> TurnResult:`).
Typed GDScript is both faster and catches a class of errors the dynamic path
will not.

---

## 2. What the extraction contract test can actually enforce

GDScript has no module system. `class_name` registers globally, so nothing
structurally prevents `rules/` from referencing game code — the compiler will
not stop you.

The contract test (extraction plan §3.3) is therefore a **lint-style script**,
not a compiler guarantee: it scans `rules/**/*.gd` for forbidden
`preload`/`load` paths, forbidden `class_name` identifiers, and the `Node`
inheritance ruled out above, and fails the build on a hit. Know its limits — it
catches the obvious violation, not a clever one.

Write it before there is anything to fix. A contract test added after the
violations exist becomes a to-do list nobody works through.

---

## 3. Game data lives in Resources

Fighters, weapons, and cards should be custom `Resource` subclasses saved as
`.tres` files:

```gdscript
class_name WeaponTemplate
extends Resource

@export var display_name: String
@export var range: int
@export var dice_count: int
@export var damage_value: int
@export_enum("melee", "ranged") var type: String
@export var ability_tags: PackedStringArray
```

This delivers the extraction plan's "templates ship as data, not as a class
concept" almost for free, and Godot's inspector becomes the balance editor —
which is what makes tuning dice counts and point values cheap instead of a code
change.

**The gotcha that will bite you:** Godot caches and shares `Resource`
instances. Load the same `.tres` twice and you get the *same object*. If a
runtime fighter holds a direct reference to its template and you write a damage
counter onto it, you have mutated the shared template and every other fighter
using it.

Keep templates immutable and copy out of them: either `.duplicate()` on
instantiation, or — better — make the runtime `Fighter` a plain `RefCounted`
that reads stats from a template reference and stores mutable state (damage
counter, status flags, position) in its own fields. The second keeps the
"what it is" / "what has happened to it" split clean, which the spec's data
model (§3) already implies.

---

## 4. Hex coordinates

Use **cube coordinates** (`Vector3i`, with `x + y + z == 0`) or axial
(`Vector2i`) internally. Red Blob Games' hex grid reference is the canonical
source for these algorithms; do not re-derive them.

Godot's `TileMapLayer` supports hex tiles but addresses them in **offset**
coordinates. Convert at the view boundary and never let an offset coordinate
into the rules module — mixing the two is the most common source of hex bugs.

**Distance** (spec §2) is "shortest hex-step path, blocked hexes included in the
count" — that is plain cube distance,
`(abs(dx) + abs(dy) + abs(dz)) / 2`. No pathfinding required, which is a
deliberate and convenient simplification in the spec.

**Movement** (spec §6) *does* need to path around blocked hexes. Do not reach
for `AStarGrid2D` — it is rectangular-grid only and will not help here. With
Move stats in the 3–6 range, a breadth-first flood fill from the origin over
unblocked, unoccupied neighbours is simpler than configuring `AStar2D`, fast
enough to be irrelevant, and yields the set of reachable hexes for UI
highlighting as a side effect.

**Line of sight** (spec §2) is a hex line-draw: interpolate between the two hex
centres and round each sample to the nearest hex. Budget for one real edge
case — a line passing exactly along the boundary between two hexes. Pick a
tie-break convention (a small epsilon nudge, applied consistently) and write a
test asserting symmetry, because "A can see B but B cannot see A" is a
genuinely confusing bug to hit in play.

---

## 5. Determinism and RNG

Combat is a dice pool (spec §7), so the resolver is stochastic — and a
stochastic function is only "pure simulation" if its randomness is an explicit
input.

- Never call global `randi()`, `randf()`, or `randi_range()` from rules code.
  They read a hidden global generator and make the resolver irreproducible.
- Own a `RandomNumberGenerator` instance, seed it explicitly, and store both its
  `seed` and its `state` in the serialized game state. `state` advances as you
  draw; persisting only the seed loses your place mid-match.
- The test for whether you got this right: the same starting state plus the same
  action sequence must produce the same match every time, in a fresh process.

One decision buys replays, mid-match save/load, reproducible bug reports ("here
is the seed"), and later, network sync.

When networking eventually arrives, the safe default is that the authority rolls
and sends results, rather than both sides rolling from a shared seed.
Shared-seed lockstep is achievable but demands bit-identical evaluation order on
both ends — a much stronger constraint than it looks.

---

## 6. Logical board, visual board

Two separate things: a `Board` in the rules module that knows occupancy and
terrain, and a board *scene* that knows sprites, highlights, and animation.

The view observes; it does not decide. The flow is: UI gathers intent →
authority object validates and resolves → result returned/emitted → view
animates the result. The view never mutates game state and never calls into
`rules/` directly (extraction plan §5.2).

Signals travel up, direct calls travel down. Resist a global event-bus autoload —
in a turn-based game with one authority chokepoint you do not need one, and it
re-introduces exactly the hidden coupling the rules-module discipline exists to
prevent.

Keep the autoload count near zero. The authority/session object is the one
defensible candidate, and even that can simply be owned by the match scene.

---

## 7. Testing

Use **GdUnit4** or **GUT** — either is fine; pick one and do not revisit it. Run
headless (`godot --headless`) so the suite works in CI and in an agent session
with no window.

The tests that matter most are the ones the extraction plan §5.1 describes: a
known board state, a known seed, a known action, asserted against what the
tabletop rules produce when worked by hand. Those tests *are* the specification.
Write them alongside the resolver, not after it.

Because the rules module is `RefCounted` and dependency-free, these tests need
no scene, no `SceneTree` fixtures, and no mocking framework — which is the
practical payoff of §1 above.

---

## 8. Version control

- `.godot/` stays ignored (it already is) — a regenerable import cache.
- Keep scenes and resources in Godot's **text** format (`.tscn` / `.tres`, the
  default) so diffs are readable and merges are possible.
- Godot 4.4+ generates a `.uid` file next to each script. **Commit these.** They
  are how the engine tracks script identity across moves and renames; ignoring
  or deleting them causes broken references. They are not currently ignored,
  which is correct.
- `*.import` sidecar files for assets are also committed — only the
  `.godot/imported/` cache they point at is disposable.
- Godot rewrites `project.godot` on the import pass. It replaces the file
  header with its own boilerplate and drops comments inside sections it
  manages, such as `[autoload]`. Committing anything else there produces a
  dirty tree on every validation run.
- So do not explain things in engine-managed files. Put the explanation next
  to the code it describes. The worked example is the note that
  `tests/test_bootstrap.gd` deliberately carries no `class_name` — a global
  class sharing an autoload's name is a parse error in Godot 4 — which was
  stripped from `project.godot` and survives in that script's own docstring,
  where it belongs. The same rule holds for `.tscn`, `.tres` and `.uid`.

---

## 9. Networking (deferred — notes for when you arrive)

None of this is MVP work (extraction plan §5.3). It is written down only so the
deferred decision is not re-litigated from scratch later.

Godot 4's high-level multiplayer (`MultiplayerAPI`, `@rpc` annotations,
`ENetMultiplayerPeer`) is more than adequate for a turn-based game: the traffic
is a handful of small messages per turn, and none of the latency-hiding
machinery a real-time game needs applies.

If §5.2's discipline held — every action through one authority object — this
should be a matter of changing where that object lives and how `TurnAction`s
reach it, not a rules change. That is the bet the architecture makes. If it
turns out to be a rewrite, the discipline slipped somewhere, and that is worth
discovering before more is built on top of it.
