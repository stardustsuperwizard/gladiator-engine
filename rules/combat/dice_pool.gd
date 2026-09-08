## The one module for dice-pool math: rolling, symbol matching, outcome
## comparison, and target-number resolution (spec §7 steps 2-5). Pure static
## functions over plain values and a `DiceProfile` -- no board, no fighters,
## no `GameState`, no `TurnAction`.
## If another file needs this math, it calls this module; a second copy
## anywhere else is the primary correctness risk in this project.
##
## Never instantiated -- every member is `static`.
##
## Draw order is part of the contract, pinned here because the hand-worked
## tests the parent Feature requires cannot be written without it: `roll()`
## performs exactly `dice_count` draws, one per die, each of them
## `rng.next_int(0, profile.face_count() - 1)`, in that order, appending
## `profile.symbol_at(index)` to the result each time. Nothing else in this
## module touches the generator.
##
## `bonus_count` in success_symbols() is a plain `int` (0, 1 or 2) supplied
## by the caller. In target_modifier(), it is a Flanking enum constant
## (NONE/FLANKED/SURROUNDED) also supplied by the caller, which decides
## whether the condition holds -- this module receives the decision and
## applies the resulting magnitude, never reads a board itself.
class_name DicePool
extends RefCounted

enum Outcome { HIT, DRAWN, MISS }

## The universal symbol that always counts (spec §7.4). A symbol identifier,
## not a balance number, and the one symbol string this module may name.
const CRITICAL := "critical"


## Rolls `dice_count` dice from `profile` using `rng`, returning one symbol
## per die in draw order.
##
## Degenerate inputs return an empty pool without advancing `rng` at all,
## mirroring `DeterministicRng.roll_die()`'s handling of `sides < 1`: a
## `dice_count` below 1, a `null` profile, or a profile with no faces all
## return `PackedStringArray()` and draw nothing.
static func roll(profile: DiceProfile, dice_count: int, rng: DeterministicRng) -> PackedStringArray:
	var rolled := PackedStringArray()

	if profile == null or dice_count < 1 or profile.face_count() < 1:
		return rolled

	for _i in range(dice_count):
		var index := rng.next_int(0, profile.face_count() - 1)
		rolled.append(profile.symbol_at(index))

	return rolled


## The set of symbols that count as successes for one roll: `CRITICAL`, then
## `type_symbol`, then the first `bonus_count` entries of
## `profile.bonus_symbols`, in that order.
##
## `type_symbol` is passed in rather than read off `profile.match_symbol` so
## this one function serves both the attack roll (caller passes the weapon's
## `weapon_type`) and the save roll (caller passes `profile.match_symbol`
## itself); the caller decides which to pass.
##
## A `bonus_count` larger than `profile.bonus_symbols.size()` returns every
## bonus symbol without erroring or padding.
static func success_symbols(
	profile: DiceProfile, type_symbol: String, bonus_count: int
) -> PackedStringArray:
	var successes := PackedStringArray([CRITICAL, type_symbol])

	if profile == null:
		return successes

	var bonus_limit: int = min(bonus_count, profile.bonus_symbols.size())
	for i in range(bonus_limit):
		successes.append(profile.bonus_symbols[i])

	return successes


## Counts how many entries of `rolled` are present in `successes`. Repeats
## count individually -- three criticals against a success set containing
## `CRITICAL` counts 3. A rolled symbol absent from `successes` contributes 0.
static func count_successes(rolled: PackedStringArray, successes: PackedStringArray) -> int:
	var count := 0

	for symbol in rolled:
		if symbol in successes:
			count += 1

	return count


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
## mirroring `roll()`: a `dice_count` below 1, or a `die_sides` below 1.
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
