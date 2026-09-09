# Godot — breaking changes, 4.5 → 4.7

Filtered to what can reach `rules/`, `scripts/`, `tests/` or headless
validation. Sourced from the official migration pages listed in `README.md`.

Ordered by how likely each is to bite this project, not by version.

---

## 4.7 — overrides inherit a typed return

> Methods that inherit from a method with a typed return now inherit the return
> type as well, requiring an explicit return statement in the override.
> Add `return null` to the end of the method to fix the error.
>
> — *Upgrading to Godot 4.7*, GDScript

**Why it matters here.** `TurnAction.resolve()` returns `TurnResult`, and
every player action overrides it — so this lands on the whole of
`rules/actions/`, and on every action added after it. A branch of an
overridden `resolve()` that falls off the end without returning is now a
compile error rather than an implicit `null`.

Deliberately no inventory here of which subclasses exist. That list changed
twice while this file was being written, and a count in prose is exactly the
thing that goes stale; `.claude/hooks/session-start.sh` derives it at session
start instead. What is worth writing down is that *`rules/actions/` file* and
*`TurnAction` subclass* are not the same set — `ChargeLockout` lives there and
`extends RefCounted`, because it is spec §6's shared legality predicate rather
than an action — so anything counting actions counts base classes.

This one is friendly: it fails at parse time, so CI catches it. It is listed
because the *fix* is non-obvious if you have not seen the change.

---

## 4.5 — `Resource.duplicate(true)` no longer copies external resources

> `Resource.duplicate(true)` (which performs deep duplication) now only
> duplicates resources internal to the resource file it's called on. In 4.4,
> this duplicated everything instead, including external resources. […] You
> must call `Resource.duplicate_deep(DEEP_DUPLICATE_ALL)` instead to keep the
> old behavior.
>
> — *Upgrading to Godot 4.5*, Core

**Why it matters here — and why it does not bite today.** Nothing in the tree
deep-duplicates a template. `Fighter` is `RefCounted`, holds a *shared*
`FighterTemplate` reference, and never writes through it; `fighter.gd`'s own
header rejects the `template.duplicate()`-per-fighter alternative by name, and
`fighter_test.gd` asserts the sharing so that a design which quietly duplicated
would fail. `FighterTemplate` also has no nested resource to lose: its nine
`@export`s are ints and `PackedStringArray`s, and `warrior.tres` references
nothing but its own script. `CombatProfile` reaches `AttackAction` through
`_init()`, not through the template.

So the row is here as a **guard against a future fix**, not a present bug. The
shape of the trap: a session finds template aliasing surprising, reaches for
`duplicate(true)` as the obvious repair, and gets a copy that silently shares
any sub-resource added later. That failure would not crash — it would produce a
*reproducible wrong answer*, the one class of bug this project's determinism
guarantees cannot catch, because both players get the same wrong number from the
same seed and the test passes.

**Rule.** Do not introduce `duplicate(true)` on an authored `.tres` here. The
settled design is to hold the shared template and copy plain values out of it —
`ability_tags()` and `status_flags()` already hand back copies for exactly this
reason. If a genuine deep copy is ever needed, it is
`duplicate_deep(DEEP_DUPLICATE_ALL)`, and it needs an argument in the PR for
why the sharing design stopped working.

---

## 4.6 — `AStar*` returns an empty path from a disabled start point

> `AStar2D.get_point_path`, `AStar3D.get_point_path`, `AStarGrid2D.get_id_path`
> and `AStarGrid2D.get_point_path` will now return an empty path when `from_id`
> is a disabled/solid point.
>
> — *Upgrading to Godot 4.6*, Navigation

**Why it matters here — and why this project is already clear of it.**
Spec §12 warns that movement is a search problem rather than a coordinate
calculation, routing *around* blocked and occupied hexes, which is the point at
which the engine's own pathfinder looks like the obvious tool.

`MoveAction` (#133) does not use it. It resolves through
`Board.reachable_from()`, hand-rolled with `reachability_test.gd` behind it,
and its docstring says *"Reachability is `Board.reachable_from()`, and only
that."* Charge composes Move, so it inherits that decision.

The row stays because the decision could be revisited. `AStar2D` is a
`RefCounted`, so the `rules/` base-class contract permits it, and the 4.6
change would then apply: a fighter on a hex since marked blocked or occupied is
a disabled start point, and the call returns an empty path rather than erroring.
An empty path and "no legal move" are the same value and different facts —
they would need distinguishing in the action's `FAILURE_*` block rather than
letting an empty array mean both. Extending `reachable_from`'s own search to
return routes avoids the question entirely.

---

## 4.6 — `.tscn` format changed

> `load_steps` is no longer written in scene files. […] Unique node IDs are now
> saved to scene files. […] The changes are backwards-compatible and
> forwards-compatible. […] As a result, when saving a scene that was last
> edited in Godot 4.5 in Godot 4.6, significant diffs will occur in version
> control programs. These diffs are expected.
>
> — *Upgrading to Godot 4.6*, Core

**Why it matters here.** Only `scenes/main.tscn` exists, and it is a stub, so
the blast radius is one file. Worth knowing so a large unexplained diff on a
scene file is not read as a merge accident.

---

## 4.7 — packed array element assignment

> Setting the element of packed arrays no longer calls the setter for the
> entire packed array property.
>
> — *Upgrading to Godot 4.7*, GDScript

**Why it matters here.** `PlayerState`'s four piles (`hand`, `deck`,
`discard`, `scored`) are `Array[String]`, not `Packed*Array`, so the change
does not apply as the tree stands. It is recorded because the card system will
grow these piles and `PackedStringArray` is the tempting swap: if one of them
ever became a packed array behind a setter that does bookkeeping —
dirty-flagging for the state digest, say — per-element assignment would stop
triggering it, and the digest would go stale without an error.

`FighterTemplate.tags` and `ability_tags` *are* `PackedStringArray`, but they
are authored data that is never element-assigned at runtime.

---

## Not applicable, deliberately

Recorded so the next person does not re-check them: 4.5's Android/.NET 9
requirement and C# `StringExtensions` fixes (no C#, no Android); 4.6's glow,
volumetric fog and Mobile renderer changes (no rendering); 4.7's
`CPUParticles*`/`GPUParticles*`, `RichTextLabel`, `LookAtModifier3D` and macOS
11 minimum (no particles, no UI yet, Linux CI); 4.5/4.6 navigation *server*
changes (`NavigationServer2D` region merging and async iteration — this project
does not use the navigation server, and does not use `AStar` either).
