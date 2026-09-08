## The one module for dice-pool math: rolling d6s, counting them against a
## target number, resolving that target number, and comparing the two totals
## (spec §7.3-7.5). Pure static functions over plain values -- no board, no
## fighters, no `GameState`, no `TurnAction`.
## If another file needs this math, it calls this module; a second copy
## anywhere else is the primary correctness risk in this project.
##
## Never instantiated -- every member is `static`.
##
## Draw order is part of the contract, pinned here because the hand-worked
## tests in `rules/tests/attack_action_test.gd` cannot be written without it:
## `roll_dice()` performs exactly `dice_count` draws, one per die, each of them
## `rng.roll_die(die_sides)`, in that order. Nothing else in this module
## touches the generator.
##
## **Symbol-faced dice are gone.** Spec §7 as revised 2026-09-08 replaced them
## with d6s rolled against a target number, so `roll()`, `success_symbols()`,
## `count_successes()` and the `CRITICAL` symbol have been deleted along with
## the authored die resource they read -- faces, match symbol, bonus symbols
## and all. Do not reintroduce them by appeal to the tabletop original -- see
## the spec's revision notes.
##
## `bonus_count` in `target_modifier()` is a `Flanking` constant
## (NONE/FLANKED/SURROUNDED) supplied by the caller, which decides whether the
## condition holds -- this module receives the decision and applies the
## resulting magnitude, never reads a board itself.
class_name DicePool
extends RefCounted

enum Outcome { HIT, DRAWN, MISS }


## Compares two success totals: `HIT` when `attack_successes` exceeds
## `save_successes`, `DRAWN` when they are equal, `MISS` when
## `save_successes` exceeds `attack_successes`.
static func outcome(attack_successes: int, save_successes: int) -> Outcome:
	if attack_successes > save_successes:
		return Outcome.HIT
	if attack_successes == save_successes:
		return Outcome.DRAWN
	return Outcome.MISS


## Rolls `dice_count` dice of `die_sides` faces through `rng`, returning one
## result per die in draw order (spec §7.3). Delegates to
## `DeterministicRng.roll_die(die_sides)`, once per die, in order -- that
## primitive already handles the `die_sides < 1` degenerate case, so it is
## never re-derived here from `next_int()`.
##
## Degenerate inputs return an empty array without advancing `rng` at all,
## mirroring `DeterministicRng.roll_die()`'s own handling of `sides < 1`: a
## `dice_count` below 1, or a `die_sides` below 1.
static func roll_dice(dice_count: int, die_sides: int, rng: DeterministicRng) -> PackedInt32Array:
	var rolled := PackedInt32Array()

	if dice_count < 1 or die_sides < 1:
		return rolled

	for _i in range(dice_count):
		rolled.append(rng.roll_die(die_sides))

	return rolled


## How many entries of `rolled` are greater than or equal to `target`.
static func count_at_or_above(rolled: PackedInt32Array, target: int) -> int:
	var count := 0

	for value in rolled:
		if value >= target:
			count += 1

	return count


## One roll's signed target-number modifier (spec §7.3).
##
## `bonus_count` is `Flanking.NONE`/`FLANKED`/`SURROUNDED`; the matching
## magnitude is SUBTRACTED. `SURROUNDED` and `FLANKED` are alternatives,
## never cumulative -- a `bonus_count` of `Flanking.SURROUNDED` subtracts
## `surround_modifier` only.
##
## `extra` is added as given and is already signed by the caller -- negative
## for the attack chart's engagement bonus and the save chart's Guard bonus,
## since every §7.3 row is a bonus. It is signed rather than assumed
## negative so a future penalty needs no new parameter.
##
## Names no magnitude of its own: `flank_modifier` and `surround_modifier`
## are parameters because the attack and save charts use different ones
## (spec §8), and because a balance value may not live in GDScript.
static func target_modifier(
	bonus_count: int, flank_modifier: int, surround_modifier: int, extra: int
) -> int:
	var modifier := extra

	if bonus_count == Flanking.SURROUNDED:
		modifier -= surround_modifier
	elif bonus_count == Flanking.FLANKED:
		modifier -= flank_modifier

	return modifier
