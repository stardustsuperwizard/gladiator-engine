## The one module for dice-pool math: rolling, symbol matching, and outcome
## comparison (spec §7 steps 2-5). Pure static functions over plain values and
## a `DiceProfile` -- no board, no fighters, no `GameState`, no `TurnAction`.
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
## `bonus_count` is a plain `int` (0, 1 or 2) supplied by the caller. This
## module does not know what flanking or surrounding is, does not compute
## either, and never reads a board -- sibling task #43 produces that integer.
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
