## Tests DeterministicRng: same-seed reproducibility, seed/state
## serialization, and the seed-before-state ordering that resuming a snapshot
## depends on.
##
## A contract test that cannot fail is worse than no contract test (see
## ContractScannerTest's docstring), so each of these was confirmed to fail
## once during development before the implementation made it pass.
class_name DeterministicRngTest


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_same_seed_produces_identical_sequence())
	violations.append_array(_test_different_seeds_produce_different_sequences())
	violations.append_array(_test_state_changes_seed_does_not())
	violations.append_array(_test_from_dict_resumes_rather_than_rewinds())
	violations.append_array(_test_to_dict_values_are_strings())
	violations.append_array(_test_large_state_round_trips_exactly_through_from_dict())
	violations.append_array(_test_from_dict_rejects_missing_seed())
	violations.append_array(_test_from_dict_rejects_missing_state())
	violations.append_array(_test_from_dict_rejects_int_values())
	violations.append_array(_test_next_int_stays_in_range_inclusive())
	violations.append_array(_test_next_int_from_equals_to_returns_that_value())
	violations.append_array(_test_next_int_to_less_than_from_returns_from_without_advancing())
	violations.append_array(_test_roll_die_stays_in_range())
	violations.append_array(_test_roll_die_zero_returns_zero_without_advancing())

	if violations.is_empty():
		return true

	printerr("\n=== Deterministic Rng Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


static func _test_same_seed_produces_identical_sequence() -> Array[String]:
	var violations: Array[String] = []
	var a := DeterministicRng.new(12345)
	var b := DeterministicRng.new(12345)

	for i in range(50):
		var draw_a := a.next_int(1, 1000000)
		var draw_b := b.next_int(1, 1000000)
		violations.append_array(
			_expect(
				draw_a == draw_b,
				(
					"draw %d must match between two generators sharing seed 12345: %d vs %d"
					% [i, draw_a, draw_b]
				)
			)
		)

	return violations


static func _test_different_seeds_produce_different_sequences() -> Array[String]:
	var a := DeterministicRng.new(1)
	var b := DeterministicRng.new(2)

	var sequence_a: Array[int] = []
	var sequence_b: Array[int] = []
	for i in range(50):
		sequence_a.append(a.next_int(1, 1000000))
		sequence_b.append(b.next_int(1, 1000000))

	return _expect(
		sequence_a != sequence_b,
		"two generators with different seeds must not produce the identical 50-draw sequence"
	)


static func _test_state_changes_seed_does_not() -> Array[String]:
	var violations: Array[String] = []
	var rng := DeterministicRng.new(7)
	var seed_before := rng.get_seed()
	var state_before := rng.get_state()

	rng.next_int(1, 6)

	violations.append_array(
		_expect(rng.get_seed() == seed_before, "get_seed() must not change after a draw")
	)
	violations.append_array(
		_expect(rng.get_state() != state_before, "get_state() must change after a draw")
	)

	return violations


## The rewind test. A from_dict() that assigns state before seed -- or lets a
## later seed write clobber a restored state -- rewinds the generator to the
## start of its sequence instead of resuming it. This is the exact defect the
## parent Feature exists to catch, and it is invisible to any test that only
## checks the restored generator produces *some* valid draw.
static func _test_from_dict_resumes_rather_than_rewinds() -> Array[String]:
	var violations: Array[String] = []
	var rng := DeterministicRng.new(999)

	for i in range(10):
		rng.next_int(1, 1000000)

	var snapshot := rng.to_dict()

	var expected: Array[int] = []
	for i in range(10):
		expected.append(rng.next_int(1, 1000000))

	var restored := DeterministicRng.from_dict(snapshot)
	violations.append_array(
		_expect(restored != null, "from_dict() must succeed on a well-formed snapshot")
	)
	if restored == null:
		return violations

	for i in range(10):
		var draw := restored.next_int(1, 1000000)
		violations.append_array(
			_expect(
				draw == expected[i],
				(
					(
						"REWIND BUG: from_dict() must resume the sequence after the snapshot, not "
						+ "rewind to the start of it -- draw %d after restore was %d, expected %d "
						+ "(this is what a seed-assigned-after-state bug looks like)"
					)
					% [i, draw, expected[i]]
				)
			)
		)

	return violations


static func _test_to_dict_values_are_strings() -> Array[String]:
	var violations: Array[String] = []
	var rng := DeterministicRng.new(42)
	rng.next_int(1, 6)
	var data := rng.to_dict()

	violations.append_array(
		_expect(typeof(data["seed"]) == TYPE_STRING, 'to_dict()["seed"] must be a String')
	)
	violations.append_array(
		_expect(typeof(data["state"]) == TYPE_STRING, 'to_dict()["state"] must be a String')
	)

	return violations


## JSON numbers are doubles and lose precision above 2^53; str()/to_int() must
## round-trip a state value past that threshold exactly, not merely a small
## one that a double could have represented anyway.
static func _test_large_state_round_trips_exactly_through_from_dict() -> Array[String]:
	var violations: Array[String] = []
	var large_state := "9223372036854775807"  # INT64_MAX, well past 2^53
	var data := {"seed": "1", "state": large_state}

	var rng := DeterministicRng.from_dict(data)
	violations.append_array(
		_expect(rng != null, "from_dict() must succeed on this well-formed large-state snapshot")
	)
	if rng == null:
		return violations

	violations.append_array(
		_expect(
			rng.get_state() == large_state.to_int(),
			"get_state() must reproduce a state value past 2^53 exactly"
		)
	)

	var round_tripped := rng.to_dict()
	violations.append_array(
		_expect(
			round_tripped["state"] == large_state,
			(
				"to_dict() must reproduce the exact decimal string for a state past 2^53, got %s"
				% round_tripped["state"]
			)
		)
	)

	return violations


static func _test_from_dict_rejects_missing_seed() -> Array[String]:
	return _expect(
		DeterministicRng.from_dict({"state": "1"}) == null,
		'from_dict() must return null when "seed" is missing'
	)


static func _test_from_dict_rejects_missing_state() -> Array[String]:
	return _expect(
		DeterministicRng.from_dict({"seed": "1"}) == null,
		'from_dict() must return null when "state" is missing'
	)


static func _test_from_dict_rejects_int_values() -> Array[String]:
	return _expect(
		DeterministicRng.from_dict({"seed": 1, "state": 1}) == null,
		'from_dict() must return null when "seed" and "state" are ints rather than Strings'
	)


static func _test_next_int_stays_in_range_inclusive() -> Array[String]:
	var violations: Array[String] = []
	var rng := DeterministicRng.new(5)

	for i in range(200):
		var draw := rng.next_int(3, 8)
		violations.append_array(
			_expect(draw >= 3 and draw <= 8, "next_int(3, 8) must stay in [3, 8], got %d" % draw)
		)

	return violations


static func _test_next_int_from_equals_to_returns_that_value() -> Array[String]:
	var rng := DeterministicRng.new(5)
	return _expect(rng.next_int(4, 4) == 4, "next_int(4, 4) must return 4")


static func _test_next_int_to_less_than_from_returns_from_without_advancing() -> Array[String]:
	var violations: Array[String] = []
	var rng := DeterministicRng.new(5)
	var state_before := rng.get_state()

	violations.append_array(
		_expect(rng.next_int(8, 3) == 8, "next_int(8, 3) must return from (8) when to < from")
	)
	violations.append_array(
		_expect(
			rng.get_state() == state_before,
			"next_int() must not advance get_state() when to < from"
		)
	)

	return violations


static func _test_roll_die_stays_in_range() -> Array[String]:
	var violations: Array[String] = []
	var rng := DeterministicRng.new(11)

	for i in range(200):
		var roll := rng.roll_die(6)
		violations.append_array(
			_expect(roll >= 1 and roll <= 6, "roll_die(6) must stay in [1, 6], got %d" % roll)
		)

	return violations


static func _test_roll_die_zero_returns_zero_without_advancing() -> Array[String]:
	var violations: Array[String] = []
	var rng := DeterministicRng.new(11)
	var state_before := rng.get_state()

	violations.append_array(_expect(rng.roll_die(0) == 0, "roll_die(0) must return 0"))
	violations.append_array(
		_expect(rng.get_state() == state_before, "roll_die(0) must not advance get_state()")
	)

	return violations
