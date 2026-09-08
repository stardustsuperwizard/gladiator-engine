## Run This Task

Locally, in Claude Code:

```text
/execute-task 84
```

Or start a Copilot agent session — mobile or desktop — and paste this as the
task description:

````text
Work GitHub issue #84 in this repository.

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

Title the pull request starting with [84], for
example "[84] <what it does>", and include in its
description: Closes #84
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
- Planner Task: A

## Model Tier

- Recommended: `haiku`

## Objective

A `CombatProfile` Resource holding every tuning dial spec §7 reads, and one
authored `.tres`. Purely additive — nothing consumes it in this task.

## Scope

Add `rules/combat/combat_profile.gd`, `class_name CombatProfile extends
Resource`, with `@export`ed fields and no behaviour beyond a clamp helper:

| Field | Authored value | Meaning |
| --- | --- | --- |
| `profile_id: String` | `"standard"` | Opaque, author-assigned. Never a resource path. |
| `die_sides: int` | `6` | Faces per die. |
| `attack_target: int` | `5` | Baseline attack target number. |
| `save_target: int` | `5` | Baseline save target number. |
| `engagement_range: int` | `1` | Distance at or within which an attacker is engaged. |
| `engagement_modifier: int` | `1` | Subtracted from the attack target when the attacker is engaged. |
| `attack_flank_modifier: int` | `1` | Subtracted when the **target** is flanked. |
| `attack_surround_modifier: int` | `2` | Subtracted when the **target** is surrounded. |
| `save_flank_modifier: int` | `2` | Subtracted from the save target when the **attacker** is flanked. |
| `save_surround_modifier: int` | `3` | Subtracted when the **attacker** is surrounded. |
| `guard_modifier: int` | `1` | Subtracted from the save target when the defender is guarded (§6). |
| `min_target: int` | `2` | Clamp floor — a natural 1 always fails. |
| `max_target: int` | `6` | Clamp ceiling — a natural 6 always succeeds. |

Author `resources/combat/combat_profile.tres` with exactly those values.

**Three pairs of dials look alike and are not interchangeable** (spec §7.3, §8):
the attack flanking pair (1/2), the save flanking pair (2/3), and the
engagement/guard singles. They are separate fields because the attack and save
charts price the same board conditions differently. Do not collapse them.

**`attack_target` and `save_target` both being 5 is tuning, not a rule.** They
are separate authored values and either may move alone; do not fold them into
one field because they currently agree.

Add one method and nothing else:

```gdscript
## The target number after `modifier`, clamped to [min_target, max_target].
## `modifier` is signed and, as every §7.3 row is a bonus, ordinarily negative.
func clamped_target(base_target: int, modifier: int) -> int
```

Modifier magnitudes are stored positive; the *caller* decides the sign. That is
deliberate — an authored value reading `guard_modifier = -1` in a `.tres` diff
invites someone to "fix" the negative.

## Files or Subsystems Expected to Change

- `rules/combat/combat_profile.gd` (new)
- `resources/combat/combat_profile.tres` (new)
- `rules/tests/combat_profile_test.gd` (new)
- `tests/resource_data_test.gd` — if it enumerates authored resources, add this one

## Architecture Constraints

- `Resource`, never `Node`. Data only — no rolling, no counting, no reading a
  board or a fighter. `DiceProfile` is the shape to mirror; this replaces it.
- **No `res://resources/` path may appear in `rules/`.** `profile_id` is opaque
  and author-assigned, exactly as `WeaponTemplate` and `DiceProfile` document.
  Enforced by `rules/tests/extraction_contract_test.gd`.
- **`engagement_range` is a distance, not a modifier.** It is compared against
  the attacker-to-target distance; `engagement_modifier` is what that comparison
  is worth. Two fields, two jobs.
- Never mutated after authoring.
- Do not delete `DiceProfile`, and do not touch `DicePool` or `AttackAction`.
  A sibling task removes them; removing them here leaves the tree unbuildable.
- Do not add third-party dependencies or addons.

## Acceptance Criteria

- [ ] `CombatProfile` exists with the thirteen fields above, all `@export`ed
- [ ] `resources/combat/combat_profile.tres` carries exactly the authored values
      in the table
- [ ] The attack ladder: `clamped_target(5, 0) == 5`;
      `clamped_target(5, -1) == 4` (engaged); `clamped_target(5, -2) == 3`
      (engaged, target flanked); `clamped_target(5, -3) == 2` (engaged, target
      surrounded)
- [ ] The save ladder: `clamped_target(5, -1) == 4` (guarded);
      `clamped_target(5, -2) == 3` (attacker flanked);
      `clamped_target(5, -3) == 2` (attacker surrounded)
- [ ] `clamped_target(5, -4) == 2` — guarded *and* attacker surrounded is
      `5 - 1 - 3 = 1`, which the floor raises to 2
- [ ] `clamped_target(5, 1) == 6` and `clamped_target(5, 99) == 6` — the ceiling
      holds, though nothing in the game currently passes a positive modifier
- [ ] `attack_flank_modifier != save_flank_modifier` and
      `attack_surround_modifier != save_surround_modifier` in the authored
      `.tres`, as spec §8's table requires
- [ ] No number from the table appears as a literal in any `.gd` file other than
      a test
- [ ] Existing tests pass
- [ ] `.github/scripts/validate-godot.sh` passes

## Out of Scope

- Consuming the profile anywhere. `AttackAction` is a sibling task.
- Deciding whether an attacker *is* engaged — that is a distance comparison
  against the board, and belongs to `AttackAction` (#87). This task only holds
  the range and the modifier.
- Any ability that raises `engagement_range` (spec §7.3's Polearm example).
  §7.1's tag system is unbuilt.
- `ConstructionBudget` (spec §3.2) — that is #89, a separate Resource with a
  separate job. This one holds combat dials only.
- Deleting `DiceProfile`, `WeaponTemplate`, or any `.tres` under
  `resources/dice/` or `resources/weapons/`.
- Changing `DicePool`.
- Retuning any value.

## Dependencies

| Relationship | Issue | Why |
| --- | --- | --- |
| Blocks | #87 | #87 reads `CombatProfile` and `clamped_target()` |

