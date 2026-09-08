## Tests DicePool: spec §7.3's d6 pool -- roll_dice()'s pinned draw order,
## same-seed reproducibility and degenerate-input handling that leaves the
## generator untouched; count_at_or_above()'s inclusive boundary; and
## target_modifier() across the attack and save charts' different magnitudes.
## Plus outcome() comparison, spec §7.5.
##
## **The symbol model is gone and so are its tests.** Spec §7 as revised
## 2026-09-08 replaced symbol-faced dice with d6s against a target number, so
## `DicePool.roll()`, `success_symbols()`, `count_successes()` and the
## `CRITICAL` constant were deleted from the tree, along with the authored die
## resource and the `.tres` files it typed. Nothing here should be restored by
## appeal to the tabletop original -- see the spec's revision notes.
##
## **No expectation here is a captured dice sequence.** The old suite pinned
## the face indices a fixed seed produced, which was the only way to write a
## hand-worked expectation against symbol dice. Target numbers make that
## unnecessary: a target of 1 counts every face of a d6 and a target of 7
## counts none, so `_test_pool_bounds_are_hand_workable_at_extreme_targets()`
## is worked from the definition of the die rather than from a recording, and
## cannot rot when the engine's generator changes.
class_name DicePoolTest


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_outcome_hit_when_attack_exceeds_save())
	violations.append_array(_test_outcome_drawn_when_equal())
	violations.append_array(_test_outcome_miss_when_save_exceeds_attack())
	violations.append_array(_test_roll_dice_draws_exactly_n_times_and_advances_state_by_n())
	violations.append_array(_test_roll_dice_zero_dice_returns_empty_without_advancing())
	violations.append_array(_test_roll_dice_negative_dice_returns_empty_without_advancing())
	violations.append_array(_test_roll_dice_zero_sides_returns_empty_without_advancing())
	violations.append_array(_test_roll_dice_same_seed_same_position_produces_identical_sequence())
	violations.append_array(_test_count_at_or_above_boundary_is_inclusive())
	violations.append_array(_test_count_at_or_above_empty_array_counts_zero())
	violations.append_array(_test_count_at_or_above_target_above_die_sides_counts_zero())
	violations.append_array(_test_pool_bounds_are_hand_workable_at_extreme_targets())
	violations.append_array(_test_target_modifier_attack_magnitudes())
	violations.append_array(_test_target_modifier_save_magnitudes())
	violations.append_array(_test_target_modifier_extra_composes())
	violations.append_array(_test_target_modifier_extra_is_signed())

	if violations.is_empty():
		return true

	printerr("\n=== Dice Pool Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


static func _test_outcome_hit_when_attack_exceeds_save() -> Array[String]:
	return _expect(
		DicePool.outcome(3, 1) == DicePool.Outcome.HIT,
		"outcome() must be HIT when attack successes exceed save successes"
	)


static func _test_outcome_drawn_when_equal() -> Array[String]:
	return _expect(
		DicePool.outcome(2, 2) == DicePool.Outcome.DRAWN,
		"outcome() must be DRAWN when attack and save successes are equal"
	)


static func _test_outcome_miss_when_save_exceeds_attack() -> Array[String]:
	return _expect(
		DicePool.outcome(1, 3) == DicePool.Outcome.MISS,
		"outcome() must be MISS when save successes exceed attack successes"
	)


static func _test_roll_dice_draws_exactly_n_times_and_advances_state_by_n() -> Array[String]:
	var violations: Array[String] = []
	var dice_count := 3
	var die_sides := 6

	var pool_rng := DeterministicRng.new(202)
	var reference_rng := DeterministicRng.new(202)

	var rolled := DicePool.roll_dice(dice_count, die_sides, pool_rng)

	violations.append_array(
		_expect(rolled.size() == dice_count, "roll_dice() must draw exactly dice_count entries")
	)

	var in_range := true
	for value in rolled:
		if value < 1 or value > die_sides:
			in_range = false
	violations.append_array(
		_expect(in_range, "roll_dice() entries must each fall in [1, die_sides]")
	)

	# Step the independent reference generator the same number of times, the
	# same way roll_dice() is contracted to: one roll_die(die_sides) per die,
	# in order.
	for _i in range(dice_count):
		reference_rng.roll_die(die_sides)

	violations.append_array(
		_expect(
			pool_rng.get_state() == reference_rng.get_state(),
			(
				"roll_dice() must advance the generator by exactly dice_count draws, matching a "
				+ "generator stepped independently the same number of times"
			)
		)
	)

	return violations


static func _test_roll_dice_zero_dice_returns_empty_without_advancing() -> Array[String]:
	var violations: Array[String] = []
	var rng := DeterministicRng.new(1)
	var state_before := rng.get_state()

	var rolled := DicePool.roll_dice(0, 6, rng)

	violations.append_array(
		_expect(rolled.is_empty(), "roll_dice() with dice_count 0 must be empty")
	)
	violations.append_array(
		_expect(
			rng.get_state() == state_before,
			"roll_dice() with dice_count 0 must not advance get_state()"
		)
	)

	return violations


static func _test_roll_dice_negative_dice_returns_empty_without_advancing() -> Array[String]:
	var violations: Array[String] = []
	var rng := DeterministicRng.new(1)
	var state_before := rng.get_state()

	var rolled := DicePool.roll_dice(-3, 6, rng)

	violations.append_array(
		_expect(rolled.is_empty(), "roll_dice() with a negative dice_count must be empty")
	)
	violations.append_array(
		_expect(
			rng.get_state() == state_before,
			"roll_dice() with a negative dice_count must not advance get_state()"
		)
	)

	return violations


static func _test_roll_dice_zero_sides_returns_empty_without_advancing() -> Array[String]:
	var violations: Array[String] = []
	var rng := DeterministicRng.new(1)
	var state_before := rng.get_state()

	var rolled := DicePool.roll_dice(3, 0, rng)

	violations.append_array(
		_expect(rolled.is_empty(), "roll_dice() with die_sides 0 must be empty")
	)
	violations.append_array(
		_expect(
			rng.get_state() == state_before,
			"roll_dice() with die_sides 0 must not advance get_state()"
		)
	)

	return violations


static func _test_roll_dice_same_seed_same_position_produces_identical_sequence() -> Array[String]:
	var rng_a := DeterministicRng.new(777)
	var rng_b := DeterministicRng.new(777)

	var rolled_a := DicePool.roll_dice(8, 6, rng_a)
	var rolled_b := DicePool.roll_dice(8, 6, rng_b)

	return _expect(
		rolled_a == rolled_b,
		"two roll_dice() calls on generators sharing a seed and starting position must match"
	)


static func _test_count_at_or_above_boundary_is_inclusive() -> Array[String]:
	var rolled := PackedInt32Array([1, 3, 4, 6, 6])

	return _expect(
		DicePool.count_at_or_above(rolled, 4) == 3,
		(
			"count_at_or_above() must count entries >= target inclusively, got %d"
			% DicePool.count_at_or_above(rolled, 4)
		)
	)


static func _test_count_at_or_above_empty_array_counts_zero() -> Array[String]:
	return _expect(
		DicePool.count_at_or_above(PackedInt32Array(), 4) == 0,
		"count_at_or_above() of an empty array must be 0"
	)


static func _test_count_at_or_above_target_above_die_sides_counts_zero() -> Array[String]:
	var rolled := PackedInt32Array([1, 2, 3, 4, 5, 6])

	return _expect(
		DicePool.count_at_or_above(rolled, 7) == 0,
		"count_at_or_above() with a target above every rolled value must be 0"
	)


## Roll and count together, on the one pair of targets whose answer is fixed
## by the die rather than by the seed: every face of a d6 is at or above 1,
## and no face is at or above 7. Six dice therefore count 6 and 0, whatever
## the generator produced.
##
## Deliberately not a pinned sequence. An expectation captured from a real run
## would pin Godot's generator rather than spec §7.3, and would go red on an
## engine upgrade that changed nothing about the rules.
static func _test_pool_bounds_are_hand_workable_at_extreme_targets() -> Array[String]:
	var violations: Array[String] = []
	var dice_count := 6
	var die_sides := 6
	var rolled := DicePool.roll_dice(dice_count, die_sides, DeterministicRng.new(4242))

	violations.append_array(
		_expect(
			DicePool.count_at_or_above(rolled, 1) == dice_count,
			(
				"a target of 1 must count every die of a %d-sided pool, got %d"
				% [die_sides, DicePool.count_at_or_above(rolled, 1)]
			)
		)
	)
	violations.append_array(
		_expect(
			DicePool.count_at_or_above(rolled, die_sides + 1) == 0,
			(
				"a target one above die_sides must count no die at all, got %d"
				% DicePool.count_at_or_above(rolled, die_sides + 1)
			)
		)
	)

	return violations


static func _test_target_modifier_attack_magnitudes() -> Array[String]:
	var violations: Array[String] = []

	violations.append_array(
		_expect(
			DicePool.target_modifier(Flanking.NONE, 1, 2, 0) == 0,
			"target_modifier() with Flanking.NONE must apply no modifier"
		)
	)
	violations.append_array(
		_expect(
			DicePool.target_modifier(Flanking.FLANKED, 1, 2, 0) == -1,
			"target_modifier() with Flanking.FLANKED must subtract flank_modifier"
		)
	)
	violations.append_array(
		_expect(
			DicePool.target_modifier(Flanking.SURROUNDED, 1, 2, 0) == -2,
			"target_modifier() with Flanking.SURROUNDED must subtract surround_modifier, not both"
		)
	)

	return violations


static func _test_target_modifier_save_magnitudes() -> Array[String]:
	var violations: Array[String] = []

	violations.append_array(
		_expect(
			DicePool.target_modifier(Flanking.FLANKED, 2, 3, 0) == -2,
			"target_modifier() must use the caller's flank_modifier, not a hardcoded attack value"
		)
	)
	violations.append_array(
		_expect(
			DicePool.target_modifier(Flanking.SURROUNDED, 2, 3, 0) == -3,
			(
				"target_modifier() must use the caller's surround_modifier, not a hardcoded "
				+ "attack value"
			)
		)
	)

	return violations


static func _test_target_modifier_extra_composes() -> Array[String]:
	var violations: Array[String] = []

	violations.append_array(
		_expect(
			DicePool.target_modifier(Flanking.NONE, 1, 2, -1) == -1,
			"target_modifier() must apply extra alone when there is no flanking bonus"
		)
	)
	violations.append_array(
		_expect(
			DicePool.target_modifier(Flanking.SURROUNDED, 1, 2, -1) == -3,
			"target_modifier() must sum extra and the surround modifier"
		)
	)
	violations.append_array(
		_expect(
			DicePool.target_modifier(Flanking.NONE, 2, 3, -1) == -1,
			"target_modifier() must apply a negative extra (e.g. Guard) with no flanking bonus"
		)
	)

	return violations


static func _test_target_modifier_extra_is_signed() -> Array[String]:
	return _expect(
		DicePool.target_modifier(Flanking.NONE, 1, 2, 1) == 1,
		"target_modifier() must not assume extra is negative -- a positive extra must add"
	)
