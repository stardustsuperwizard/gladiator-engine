## Tests DicePool and DiceProfile: pinned draw order, same-seed
## reproducibility, degenerate-input handling that leaves the generator
## untouched, success-symbol construction across bonus_count 0/1/2/oversized,
## success counting (including repeats and non-matching symbols), outcome
## comparison, and a DiceProfile.match_symbol round trip through .tres.
##
## Every fixture DiceProfile here is built in memory with explicit faces
## chosen for this suite -- never loaded from resources/dice/. This suite
## lives under rules/tests and extraction_contract_test.gd forbids naming a
## res://resources/ path anywhere under rules/, and retuning the authored
## provisional dice must never be able to break this suite.
##
## _test_hand_worked_attack_roll_matches_worked_sequence() is the
## specification test the parent Feature requires: it names a fixed seed, a
## fixed fixture face table, records the expected draw indices in a comment
## (captured once from a real run against that seed -- see the comment there),
## and asserts the resulting symbols and counted successes against that
## sequence worked by hand.
class_name DicePoolTest

const TEST_TRES_PATH := "user://dice_pool_test_dice_profile.tres"


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_roll_draws_exactly_n_times_and_advances_state_by_n())
	violations.append_array(_test_roll_same_seed_same_position_produces_identical_sequence())
	violations.append_array(_test_roll_zero_dice_returns_empty_without_advancing())
	violations.append_array(_test_roll_negative_dice_returns_empty_without_advancing())
	violations.append_array(_test_roll_null_profile_returns_empty_without_advancing())
	violations.append_array(_test_roll_profile_with_no_faces_returns_empty_without_advancing())
	violations.append_array(_test_success_symbols_bonus_count_zero())
	violations.append_array(_test_success_symbols_bonus_count_one())
	violations.append_array(_test_success_symbols_bonus_count_two())
	violations.append_array(_test_success_symbols_bonus_count_larger_than_available())
	violations.append_array(_test_count_successes_counts_repeats())
	violations.append_array(_test_count_successes_ignores_symbols_outside_success_set())
	violations.append_array(_test_outcome_hit_when_attack_exceeds_save())
	violations.append_array(_test_outcome_drawn_when_equal())
	violations.append_array(_test_outcome_miss_when_save_exceeds_attack())
	violations.append_array(_test_hand_worked_attack_roll_matches_worked_sequence())
	violations.append_array(_test_dice_profile_match_symbol_round_trips_through_tres())

	if violations.is_empty():
		return true

	printerr("\n=== Dice Pool Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


## A four-face fixture die: index 0 critical, 1 melee, 2 ranged, 3 opening.
## bonus_symbols carries "opening" at index 0 -- the flanking tier -- and
## "advantage" at index 1, which never appears on a face in this fixture and
## exists only to exercise success_symbols() at bonus_count 2.
static func _fixture_profile() -> DiceProfile:
	var profile := DiceProfile.new()
	profile.profile_id = "fixture-die"
	profile.faces = PackedStringArray(["critical", "melee", "ranged", "opening"])
	profile.match_symbol = "melee"
	profile.bonus_symbols = PackedStringArray(["opening", "advantage"])
	return profile


static func _test_roll_draws_exactly_n_times_and_advances_state_by_n() -> Array[String]:
	var violations: Array[String] = []
	var profile := _fixture_profile()
	var dice_count := 6

	var pool_rng := DeterministicRng.new(101)
	var reference_rng := DeterministicRng.new(101)

	var rolled := DicePool.roll(profile, dice_count, pool_rng)
	violations.append_array(
		_expect(rolled.size() == dice_count, "roll() must draw exactly dice_count symbols")
	)

	# Step the independent reference generator the same number of times, the
	# same way roll() is contracted to: one next_int(0, face_count() - 1) per
	# die, in order.
	for _i in range(dice_count):
		reference_rng.next_int(0, profile.face_count() - 1)

	violations.append_array(
		_expect(
			pool_rng.get_state() == reference_rng.get_state(),
			(
				"roll() must advance the generator by exactly dice_count draws, matching a "
				+ "generator stepped independently the same number of times"
			)
		)
	)

	return violations


static func _test_roll_same_seed_same_position_produces_identical_sequence() -> Array[String]:
	var profile := _fixture_profile()
	var rng_a := DeterministicRng.new(555)
	var rng_b := DeterministicRng.new(555)

	var rolled_a := DicePool.roll(profile, 8, rng_a)
	var rolled_b := DicePool.roll(profile, 8, rng_b)

	return _expect(
		rolled_a == rolled_b,
		"two roll() calls on generators sharing a seed and starting position must match"
	)


static func _test_roll_zero_dice_returns_empty_without_advancing() -> Array[String]:
	var violations: Array[String] = []
	var profile := _fixture_profile()
	var rng := DeterministicRng.new(1)
	var state_before := rng.get_state()

	var rolled := DicePool.roll(profile, 0, rng)

	violations.append_array(_expect(rolled.is_empty(), "roll() with dice_count 0 must be empty"))
	violations.append_array(
		_expect(
			rng.get_state() == state_before, "roll() with dice_count 0 must not advance get_state()"
		)
	)

	return violations


static func _test_roll_negative_dice_returns_empty_without_advancing() -> Array[String]:
	var violations: Array[String] = []
	var profile := _fixture_profile()
	var rng := DeterministicRng.new(1)
	var state_before := rng.get_state()

	var rolled := DicePool.roll(profile, -3, rng)

	violations.append_array(
		_expect(rolled.is_empty(), "roll() with a negative dice_count must be empty")
	)
	violations.append_array(
		_expect(
			rng.get_state() == state_before,
			"roll() with a negative dice_count must not advance get_state()"
		)
	)

	return violations


static func _test_roll_null_profile_returns_empty_without_advancing() -> Array[String]:
	var violations: Array[String] = []
	var rng := DeterministicRng.new(1)
	var state_before := rng.get_state()

	var rolled := DicePool.roll(null, 5, rng)

	violations.append_array(_expect(rolled.is_empty(), "roll() with a null profile must be empty"))
	violations.append_array(
		_expect(
			rng.get_state() == state_before,
			"roll() with a null profile must not advance get_state()"
		)
	)

	return violations


static func _test_roll_profile_with_no_faces_returns_empty_without_advancing() -> Array[String]:
	var violations: Array[String] = []
	var profile := DiceProfile.new()
	var rng := DeterministicRng.new(1)
	var state_before := rng.get_state()

	var rolled := DicePool.roll(profile, 5, rng)

	violations.append_array(
		_expect(rolled.is_empty(), "roll() on a profile with no faces must be empty")
	)
	violations.append_array(
		_expect(
			rng.get_state() == state_before,
			"roll() on a profile with no faces must not advance get_state()"
		)
	)

	return violations


static func _test_success_symbols_bonus_count_zero() -> Array[String]:
	var profile := _fixture_profile()
	var successes := DicePool.success_symbols(profile, "melee", 0)

	return _expect(
		successes == PackedStringArray([DicePool.CRITICAL, "melee"]),
		"success_symbols() with bonus_count 0 must be exactly [CRITICAL, type_symbol]"
	)


static func _test_success_symbols_bonus_count_one() -> Array[String]:
	var profile := _fixture_profile()
	var successes := DicePool.success_symbols(profile, "melee", 1)

	return _expect(
		successes == PackedStringArray([DicePool.CRITICAL, "melee", "opening"]),
		"success_symbols() with bonus_count 1 must add bonus_symbols[0] and no more"
	)


static func _test_success_symbols_bonus_count_two() -> Array[String]:
	var profile := _fixture_profile()
	var successes := DicePool.success_symbols(profile, "melee", 2)

	return _expect(
		successes == PackedStringArray([DicePool.CRITICAL, "melee", "opening", "advantage"]),
		"success_symbols() with bonus_count 2 must add bonus_symbols[0] and bonus_symbols[1]"
	)


static func _test_success_symbols_bonus_count_larger_than_available() -> Array[String]:
	var profile := _fixture_profile()
	var successes := DicePool.success_symbols(profile, "melee", 99)

	return _expect(
		successes == PackedStringArray([DicePool.CRITICAL, "melee", "opening", "advantage"]),
		(
			"success_symbols() with a bonus_count larger than bonus_symbols.size() must return "
			+ "every bonus symbol without erroring or padding"
		)
	)


static func _test_count_successes_counts_repeats() -> Array[String]:
	var rolled := PackedStringArray([DicePool.CRITICAL, DicePool.CRITICAL, DicePool.CRITICAL])
	var successes := PackedStringArray([DicePool.CRITICAL])

	return _expect(
		DicePool.count_successes(rolled, successes) == 3,
		"count_successes() must count three criticals against a set containing CRITICAL as 3"
	)


static func _test_count_successes_ignores_symbols_outside_success_set() -> Array[String]:
	var rolled := PackedStringArray(["ranged", "ranged", "melee"])
	var successes := PackedStringArray([DicePool.CRITICAL, "melee", "opening"])

	return _expect(
		DicePool.count_successes(rolled, successes) == 1,
		(
			"count_successes() must contribute 0 for a rolled symbol in neither the type, bonus, "
			+ "nor critical set, counting only the one matching symbol"
		)
	)


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


## The hand-worked specification test.
##
## Fixture die (see _fixture_profile()): index 0 = "critical", 1 = "melee",
## 2 = "ranged", 3 = "opening".
##
## For seed 4242, DeterministicRng.new(4242) drawing next_int(0, 3) six times
## in a row -- exactly what roll() is contracted to do against a four-face
## profile -- produces the index sequence [2, 2, 2, 3, 0, 1]. That sequence
## was captured once from a real run against this seed and is pinned here as
## the specification; it is not re-derived by this test.
##
## Those indices resolve to the symbols:
##   ranged, ranged, ranged, opening, critical, melee
##
## Attack success set with type_symbol "melee" and bonus_count 1 (the
## flanking tier, unlocking bonus_symbols[0] = "opening"):
##   [CRITICAL, "melee", "opening"]
##
## Counting the six rolled symbols against that set by hand:
##   ranged   -> not in the set -> 0
##   ranged   -> not in the set -> 0
##   ranged   -> not in the set -> 0
##   opening  -> in the set     -> 1
##   critical -> in the set     -> 1
##   melee    -> in the set     -> 1
## Total successes: 3.
static func _test_hand_worked_attack_roll_matches_worked_sequence() -> Array[String]:
	var violations: Array[String] = []
	var profile := _fixture_profile()
	var rng := DeterministicRng.new(4242)

	var expected_symbols := PackedStringArray(
		["ranged", "ranged", "ranged", "opening", "critical", "melee"]
	)

	var rolled := DicePool.roll(profile, 6, rng)
	violations.append_array(
		_expect(
			rolled == expected_symbols,
			(
				"roll() of the fixture die with seed 4242 must reproduce the sequence worked by "
				+ "hand from indices [2, 2, 2, 3, 0, 1], got %s" % [rolled]
			)
		)
	)

	var successes := DicePool.success_symbols(profile, "melee", 1)
	violations.append_array(
		_expect(
			successes == PackedStringArray([DicePool.CRITICAL, "melee", "opening"]),
			'the worked success set must be [CRITICAL, "melee", "opening"]'
		)
	)

	var success_count := DicePool.count_successes(rolled, successes)
	violations.append_array(
		_expect(
			success_count == 3,
			"the worked rolled sequence must count exactly 3 successes, got %d" % success_count
		)
	)

	return violations


## DiceProfile.match_symbol -- and the rest of its authored fields -- must
## survive a save to and load from an actual .tres, not merely an in-memory
## assignment. Saved under user://, never under res://resources/: this suite
## lives under rules/tests and extraction_contract_test.gd forbids naming
## that prefix anywhere under rules/.
static func _test_dice_profile_match_symbol_round_trips_through_tres() -> Array[String]:
	var violations: Array[String] = []

	var profile := DiceProfile.new()
	profile.profile_id = "round-trip-die"
	profile.faces = PackedStringArray(["critical", "block", "gap"])
	profile.match_symbol = "block"
	profile.bonus_symbols = PackedStringArray(["gap", "break"])

	var save_result := ResourceSaver.save(profile, TEST_TRES_PATH)
	violations.append_array(
		_expect(save_result == OK, "ResourceSaver.save() must succeed for a populated DiceProfile")
	)
	if save_result != OK:
		return violations

	var loaded_variant: Variant = ResourceLoader.load(
		TEST_TRES_PATH, "", ResourceLoader.CACHE_MODE_IGNORE
	)
	violations.append_array(
		_expect(loaded_variant != null, "ResourceLoader.load() must return the saved .tres")
	)
	if loaded_variant == null:
		_cleanup_tres()
		return violations

	violations.append_array(
		_expect(loaded_variant is DiceProfile, "the loaded resource must be a DiceProfile")
	)
	if not (loaded_variant is DiceProfile):
		_cleanup_tres()
		return violations

	var loaded: DiceProfile = loaded_variant

	violations.append_array(
		_expect(
			loaded.match_symbol == profile.match_symbol,
			"match_symbol must survive the .tres round trip and be readable off the loaded profile"
		)
	)
	violations.append_array(
		_expect(
			loaded.profile_id == profile.profile_id, "profile_id must survive the .tres round trip"
		)
	)
	violations.append_array(
		_expect(loaded.faces == profile.faces, "faces must survive the .tres round trip")
	)
	violations.append_array(
		_expect(
			loaded.bonus_symbols == profile.bonus_symbols,
			"bonus_symbols must survive the .tres round trip"
		)
	)

	_cleanup_tres()
	return violations


## Removes the .tres this suite writes under user:// so repeated runs do not
## depend on state a previous run left behind.
static func _cleanup_tres() -> void:
	var dir := DirAccess.open("user://")
	if dir != null and dir.file_exists(TEST_TRES_PATH.trim_prefix("user://")):
		dir.remove(TEST_TRES_PATH.trim_prefix("user://"))
