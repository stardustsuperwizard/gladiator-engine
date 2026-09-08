## Run This Task

Locally, in Claude Code:

```text
/execute-task 85
```

Or start a Copilot agent session — mobile or desktop — and paste this as the
task description:

````text
Work GitHub issue #85 in this repository.

Read that issue first, then read the "Executing an
Implementation Task" section of
.github/copilot-instructions.md -- that is your contract.

The issue's Objective, Scope, Architecture Constraints,
Acceptance Criteria and Out of Scope sections are
authoritative. Implement only what they require. Do not
create issues. Do not close the parent epic. Report
discovered out-of-scope work instead of doing it.

Run .github/scripts/validate-godot.sh and report the
command and its result.

Title the pull request starting with [85], for
example "[85] <what it does>", and include in its
description: Closes #85
````

**Pick the model, not the agent.** The `implementer` profile adds nothing a
cloud session can use: its `tools:` and `model:` keys are both ignored there,
and its prose is already in `.github/copilot-instructions.md`. On GitHub
Mobile, selecting a custom agent costs you the model picker — and no picker
means Auto.

Assigning this Issue to Copilot works too: same model choice, no paste, no
agent.

---

## Implementation Agent Contract

The full contract is *Executing an Implementation Task* in
`.github/copilot-instructions.md`. This is its short form.

Implement only the Scope and Acceptance Criteria below. The parent epic
provides context only; it does not expand this task's scope, and neither do
sibling tasks.

Do not:

- broaden this task;
- redesign architecture;
- implement sibling tasks;
- make speculative improvements;
- create additional GitHub Issues;
- close the parent epic.

If additional work is discovered, report it under `Discovered out-of-scope
work` rather than implementing it.

---

## Provenance

- Parent epic: #83
- Planner Task: B

## Model Tier

- Recommended: `haiku`

## Objective

`FighterTemplate` carries spec §3.2's six combat stats and the fighter's own
ability tags, and no longer carries `point_value`. `Fighter` reads the new
stats through to the template as it already does for the old ones.

## Scope

### 1. Add four fields

To `rules/fighters/fighter_template.gd`:

```gdscript
@export var range_hexes: int = 0
@export var attack: int = 0
@export var damage: int = 0
@export var ability_tags: PackedStringArray = PackedStringArray()
```

`range_hexes`, not `range`: `range()` is a GDScript global and a member
shadowing it is at best a warning. `WeaponTemplate` was named around the same
trap and its docstring explains it — carry that reasoning across.

Add `has_ability_tag(tag: String) -> bool` matching the existing `has_tag()` —
exact string match, no normalisation.

### 2. Remove `point_value`

Delete `FighterTemplate.point_value`, `Fighter.point_value()`, and the
`point_value` line from both fighter `.tres` files.

Spec §9 no longer awards it — a defeat is worth a flat 1 point, and §11's third
tiebreaker counts surviving fighters rather than summing their value. Nothing
in `rules/` reads it outside tests, so this is a clean removal.

### 3. Add four readers

To `rules/fighters/fighter.gd`, alongside `move()`/`save()`/`health()`:

```gdscript
func range_hexes() -> int
func attack() -> int
func damage() -> int
func ability_tags() -> PackedStringArray
```

`fighter.gd` carries a `gdlint:ignore = max-public-methods` waiver on line 1
with a written justification, and that justification names the five stat
readers explicitly. It is now four new readers and one deletion — update the
prose to match rather than leaving it describing a shape the file no longer
has, and do not collapse the readers behind a stat-bag object, which the same
docstring forbids.

### 4. Author the values

Taken from the weapon each fighter currently carries, so nothing is retuned:

| | `range_hexes` | `attack` | `damage` | `ability_tags` | from |
| --- | --- | --- | --- | --- | --- |
| `warrior.tres` | 1 | 3 | 2 | `["cleave"]` | `sword.tres` |
| `archer.tres` | 4 | 2 | 1 | `[]` | `bow.tres` |

Leave `move`, `save`, `health`, `tags` and `weapons` exactly as they are.

Both fighters then satisfy spec §3.2's construction budget exactly — 15 points
across the six stats, none below 1 or above 5. That is a property worth
knowing; **asserting it is #89's job, not this task's.**

## Files or Subsystems Expected to Change

- `rules/fighters/fighter_template.gd`
- `rules/fighters/fighter.gd`
- `resources/fighters/warrior.tres`
- `resources/fighters/archer.tres`
- `rules/tests/fighter_template_test.gd`
- `rules/tests/fighter_test.gd`
- `rules/tests/fighter_serialization_test.gd` — if it asserts `point_value`
- `tests/resource_data_test.gd`

## Architecture Constraints

- **Stats are read through to the shared template, never copied out of it.**
  `fighter.gd`'s class docstring is explicit about why (Godot caches and shares
  `Resource` instances). The new readers follow the existing ones exactly.
- **Never write through to the template.** Not `template.attack`, not an
  element of `template.ability_tags`.
- `ability_tags()` returns a copy, matching `weapons()` and `status_flags()`.
- **`Fighter.to_dict()` does not change.** It carries the mutable half only;
  stats live in the authored template, and `point_value` was never in it.
  Adding or removing a stat there would change `GameState.digest()`.
- No number in GDScript — every value is authored in `.tres`.
- Do not remove `weapons`, `WeaponTemplate`, or `Fighter.weapons()`. A sibling
  task does that; removing them here leaves `AttackAction` unbuildable.
- Do not add third-party dependencies or addons.

## Acceptance Criteria

- [ ] `FighterTemplate` exposes `range_hexes`, `attack`, `damage` and
      `ability_tags`, all `@export`ed
- [ ] `FighterTemplate.has_ability_tag()` matches by exact string, and returns
      `false` for a tag not present
- [ ] `Fighter.range_hexes()`, `.attack()`, `.damage()` and `.ability_tags()`
      return the template's values
- [ ] `Fighter.ability_tags()` returns a copy — appending to the returned array
      does not change the template
- [ ] `grep -rn "point_value" rules/ resources/ tests/` returns nothing
- [ ] `warrior.tres` and `archer.tres` carry exactly the values in the table
- [ ] `Fighter.to_dict()` output is byte-identical to before this change, for a
      fighter in the same state
- [ ] Existing tests pass
- [ ] `.github/scripts/validate-godot.sh` passes

## Out of Scope

- Asserting the construction budget — that is #89.
- Deleting `WeaponTemplate`, `FighterTemplate.weapons` or `Fighter.weapons()`.
- Changing `AttackAction`, `DicePool` or `DiceProfile`.
- Deleting `resources/weapons/*.tres`.
- Implementing §9's flat 1-point defeat award or §11's tiebreaker. Scoring does
  not exist yet; this task only removes the stat they used to read.
- Reconciling the duplication this creates. For one task's duration the range,
  dice and damage values exist on both the fighter and its weapon. That is
  expected, and #87 removes the weapon side.

## Dependencies

| Relationship | Issue | Why |
| --- | --- | --- |
| Blocks | #87 | #87 resolves against these stats |
| Blocks | #89 | #89 validates the six stats this adds |

