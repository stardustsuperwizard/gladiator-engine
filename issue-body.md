## Run This Task

Locally, in Claude Code:

```text
/execute-task 86
```

Or start a Copilot agent session — mobile or desktop — and paste this as the
task description:

````text
Work GitHub issue #86 in this repository.

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

Title the pull request starting with [86], for
example "[86] <what it does>", and include in its
description: Closes #86
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
- Planner Task: C

## Model Tier

- Recommended: `sonnet`

## Objective

`DicePool` gains spec §7.3's target-number resolution: roll d6, count dice that
meet or beat a target. Added **alongside** the existing symbol functions, which
a sibling task removes once `AttackAction` has switched.

## Scope

Add three static functions to `rules/combat/dice_pool.gd`:

```gdscript
## Rolls `dice_count` dice of `die_sides` faces through `rng`, returning one
## result per die in draw order.
static func roll_dice(
    dice_count: int, die_sides: int, rng: DeterministicRng
) -> PackedInt32Array

## How many entries of `rolled` are greater than or equal to `target`.
static func count_at_or_above(rolled: PackedInt32Array, target: int) -> int

## One roll's signed target-number modifier (spec §7.3). `bonus_count` is
## Flanking.NONE/FLANKED/SURROUNDED; the matching magnitude is SUBTRACTED.
## `extra` is added as given and is already signed by the caller -- negative
## for the attack chart's engagement bonus and the save chart's Guard bonus,
## since every §7.3 row is a bonus. It is signed rather than assumed negative
## so a future penalty needs no new parameter.
static func target_modifier(
    bonus_count: int,
    flank_modifier: int,
    surround_modifier: int,
    extra: int
) -> int
```

**`target_modifier()` names no number.** The magnitudes are parameters because
the attack and save charts use *different* ones — attack is −1/−2, save is
−2/−3 (spec §8) — and because a balance value may not live in GDScript. A
version that returns a hardcoded −1 or −2 is wrong on both counts.

`SURROUNDED` and `FLANKED` are alternatives, never cumulative: a `bonus_count`
of `Flanking.SURROUNDED` subtracts `surround_modifier` only.

**`roll_dice()` must delegate to `DeterministicRng.roll_die(die_sides)`,** once
per die, in order. That primitive already exists and already documents the
degenerate case — "one die numbered 1 through `sides`", returning 0 without
advancing when `sides < 1`. Do not re-derive it from `next_int()`.

Degenerate inputs return an empty array **without advancing the generator**,
mirroring the existing `roll()`: a `dice_count` below 1, or a `die_sides` below
1.

`outcome()` is unchanged. Do not touch it.

## Files or Subsystems Expected to Change

- `rules/combat/dice_pool.gd`
- `rules/tests/dice_pool_test.gd`

## Architecture Constraints

- **Pure static functions over plain values.** No board, no fighters, no
  `GameState`, no `TurnAction`, and — importantly — **no `CombatProfile`**. This
  module takes plain integers so it does not depend on the authored resource;
  the caller reads the profile and passes numbers down. Never instantiated.
- **Randomness is an explicit input.** `rng` is a parameter. Never call global
  `randi()`/`randf()`/`randi_range()`. Enforced by
  `rules/tests/ambient_rng_contract_test.gd`.
- **Draw order is the contract** (spec §7.3): exactly `dice_count` draws, one
  per die, in order, and nothing else in this module touching the generator.
- **This module is the only place dice-pool math lives.** A second copy
  anywhere is the primary correctness risk in this project.
- **Deciding *whether* a condition holds is not this module's job.** It is
  handed a `bonus_count` and an `extra`; it never measures a distance, never
  compares against an engagement range, and never reads a status flag.
- **Clamping is not here.** `CombatProfile.clamped_target()` owns the clamp;
  `target_modifier()` returns an unclamped signed integer.
- **Do not delete or change `roll()`, `success_symbols()` or
  `count_successes()` in this task.** `AttackAction` still calls all three;
  removing them here leaves the tree unbuildable. The dead-code window is
  deliberate and closes in the sibling integration task.
- Do not add third-party dependencies or addons.

## Acceptance Criteria

- [ ] `roll_dice(3, 6, rng)` returns 3 entries, each in `[1, 6]`, and advances
      the generator exactly 3 times
- [ ] `roll_dice(0, 6, rng)` and `roll_dice(3, 0, rng)` each return an empty
      array and leave `rng.get_state()` unchanged
- [ ] Two generators built from the same seed produce identical `roll_dice()`
      results for the same arguments, in a fresh process
- [ ] `count_at_or_above([1,3,4,6,6], 4) == 3` — the boundary is inclusive
- [ ] `count_at_or_above([], 4) == 0`, and a target above `die_sides` counts 0
- [ ] Attack magnitudes: `target_modifier(Flanking.NONE, 1, 2, 0) == 0`;
      `target_modifier(Flanking.FLANKED, 1, 2, 0) == -1`;
      `target_modifier(Flanking.SURROUNDED, 1, 2, 0) == -2`
- [ ] Save magnitudes, same function, different arguments:
      `target_modifier(Flanking.FLANKED, 2, 3, 0) == -2`;
      `target_modifier(Flanking.SURROUNDED, 2, 3, 0) == -3`
- [ ] `extra` composes: `target_modifier(Flanking.NONE, 1, 2, -1) == -1`
      (engaged, nothing else); `target_modifier(Flanking.SURROUNDED, 1, 2, -1)
      == -3` (engaged against a surrounded target);
      `target_modifier(Flanking.NONE, 2, 3, -1) == -1` (guarded)
- [ ] `extra` is signed, not assumed negative:
      `target_modifier(Flanking.NONE, 1, 2, 1) == 1`
- [ ] No integer magnitude for flanking, surrounding, guard or engagement
      appears as a literal in `dice_pool.gd`
- [ ] `roll()`, `success_symbols()` and `count_successes()` still exist and
      still behave exactly as before
- [ ] Existing tests pass
- [ ] `.github/scripts/validate-godot.sh` passes

## Out of Scope

- Changing `AttackAction` to use any of this. Sibling task.
- Deleting the symbol-matching functions, `DiceProfile`, or
  `resources/dice/*.tres`.
- Changing `Flanking`. `bonus_count()` already returns the `NONE`/`FLANKED`/
  `SURROUNDED` selector this consumes; read it, do not rewrite it.
- Reading `CombatProfile`. This module takes plain integers on purpose.
- Clamping.
- Measuring engagement, or anything else that requires a board.

## Dependencies

| Relationship | Issue | Why |
| --- | --- | --- |
| Blocks | #87 | #87 calls `roll_dice()`, `count_at_or_above()` and `target_modifier()` |

