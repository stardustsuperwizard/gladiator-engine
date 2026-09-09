## Tests RoundProfile's zero-default shape and GameState's two round-structure
## fields and predicates: combat_segment_complete(), is_final_round(),
## serialization, and purity.
##
## Every RoundProfile fixture here is built in memory with RoundProfile.new()
## -- `rules/` may not reference `res://resources/`, so loading
## round_profile.tres is `tests/resource_data_test.gd`'s job, not this one's.
class_name RoundProfileTest

const SEED := 20260909


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_round_profile_defaults())
	violations.append_array(_test_combat_segment_complete_boundary())
	violations.append_array(_test_combat_segment_complete_guards())
	violations.append_array(_test_combat_segment_complete_scales_with_player_count())
	violations.append_array(_test_is_final_round())
	violations.append_array(_test_fields_round_trip_and_affect_digest())
	violations.append_array(_test_from_dict_refusals())
	violations.append_array(_test_predicates_are_pure())

	if violations.is_empty():
		return true

	printerr("\n=== Round Profile Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


## A minimal two-player state with no fighters and no board content -- what
## every case below that does not care about the board needs.
static func _build_state(seed_value: int = SEED) -> GameState:
	var board := Board.new()
	var state := GameState.new(board, DeterministicRng.new(seed_value))
	state.add_player("north")
	state.add_player("south")
	return state


## 1. A fresh RoundProfile defaults all three exports to their zero values.
static func _test_round_profile_defaults() -> Array[String]:
	var violations: Array[String] = []
	var profile := RoundProfile.new()

	violations.append_array(
		_expect(profile.profile_id == "", 'a fresh RoundProfile\'s profile_id must default to ""')
	)
	violations.append_array(
		_expect(
			profile.turns_per_player == 0,
			"a fresh RoundProfile's turns_per_player must default to 0"
		)
	)
	violations.append_array(
		_expect(
			profile.rounds_per_match == 0,
			"a fresh RoundProfile's rounds_per_match must default to 0"
		)
	)

	return violations


## 2. combat_segment_complete() is false on a fresh two-player state, false at
## one Turn short of the total, true exactly at the total, and true beyond it.
static func _test_combat_segment_complete_boundary() -> Array[String]:
	var violations: Array[String] = []

	var state := _build_state()
	state.turns_per_player = 4

	violations.append_array(
		_expect(
			not state.combat_segment_complete(),
			"combat_segment_complete() must be false on a fresh two-player state"
		)
	)

	state.turns_taken = 4 * 2 - 1
	violations.append_array(
		_expect(
			not state.combat_segment_complete(),
			"combat_segment_complete() must be false one Turn short of the total"
		)
	)

	state.turns_taken = 4 * 2
	violations.append_array(
		_expect(
			state.combat_segment_complete(),
			"combat_segment_complete() must be true exactly at the total"
		)
	)

	state.turns_taken = 4 * 2 + 3
	violations.append_array(
		_expect(
			state.combat_segment_complete(),
			"combat_segment_complete() must be true beyond the total"
		)
	)

	return violations


## 3. False for turns_per_player == 0, for a negative turns_per_player, and
## for a state with no players -- each asserted separately.
static func _test_combat_segment_complete_guards() -> Array[String]:
	var violations: Array[String] = []

	var zero_state := _build_state()
	zero_state.turns_per_player = 0
	zero_state.turns_taken = 100
	violations.append_array(
		_expect(
			not zero_state.combat_segment_complete(),
			"combat_segment_complete() must be false for turns_per_player == 0"
		)
	)

	var negative_state := _build_state()
	negative_state.turns_per_player = -1
	negative_state.turns_taken = 100
	violations.append_array(
		_expect(
			not negative_state.combat_segment_complete(),
			"combat_segment_complete() must be false for a negative turns_per_player"
		)
	)

	var board := Board.new()
	var empty_state := GameState.new(board, DeterministicRng.new(SEED))
	empty_state.turns_per_player = 4
	empty_state.turns_taken = 100
	violations.append_array(
		_expect(
			not empty_state.combat_segment_complete(),
			"combat_segment_complete() must be false for a state with no players"
		)
	)

	return violations


## 4. It scales with player count: the same turns_per_player needs twice as
## many Turns with two players as with one.
static func _test_combat_segment_complete_scales_with_player_count() -> Array[String]:
	var violations: Array[String] = []

	var board := Board.new()
	var one_player_state := GameState.new(board, DeterministicRng.new(SEED))
	one_player_state.add_player("north")
	one_player_state.turns_per_player = 4
	one_player_state.turns_taken = 4

	violations.append_array(
		_expect(
			one_player_state.combat_segment_complete(),
			"combat_segment_complete() must be true for a single player at turns_per_player Turns"
		)
	)

	var two_player_state := _build_state()
	two_player_state.turns_per_player = 4
	two_player_state.turns_taken = 4

	(
		violations
		. append_array(
			_expect(
				not two_player_state.combat_segment_complete(),
				(
					"combat_segment_complete() must be false for two players at only one player's worth "
					+ "of Turns"
				)
			)
		)
	)

	two_player_state.turns_taken = 8
	(
		violations
		. append_array(
			_expect(
				two_player_state.combat_segment_complete(),
				"combat_segment_complete() must be true for two players at twice the single-player total"
			)
		)
	)

	return violations


## 5. is_final_round() is false at round_number == 1 of a 3-round match, true
## at 3, true at 4, and false for rounds_per_match == 0.
static func _test_is_final_round() -> Array[String]:
	var violations: Array[String] = []

	var state := _build_state()
	state.rounds_per_match = 3

	state.round_number = 1
	violations.append_array(
		_expect(
			not state.is_final_round(),
			"is_final_round() must be false at round_number 1 of a 3-round match"
		)
	)

	state.round_number = 3
	violations.append_array(
		_expect(state.is_final_round(), "is_final_round() must be true at round_number 3")
	)

	state.round_number = 4
	violations.append_array(
		_expect(state.is_final_round(), "is_final_round() must be true beyond rounds_per_match")
	)

	var unbounded_state := _build_state()
	unbounded_state.rounds_per_match = 0
	unbounded_state.round_number = 100
	violations.append_array(
		_expect(
			not unbounded_state.is_final_round(),
			"is_final_round() must be false for rounds_per_match == 0"
		)
	)

	return violations


## 6. Both fields survive to_dict()/from_dict(), and two states differing only
## in turns_per_player have different digest()s.
static func _test_fields_round_trip_and_affect_digest() -> Array[String]:
	var violations: Array[String] = []

	var state := _build_state()
	state.turns_per_player = 4
	state.rounds_per_match = 3

	var restored := GameState.from_dict(state.to_dict())
	violations.append_array(
		_expect(restored != null, "from_dict() must accept the reference state's own to_dict()")
	)
	if restored == null:
		return violations

	violations.append_array(
		_expect(restored.turns_per_player == 4, "turns_per_player must survive the round trip")
	)
	violations.append_array(
		_expect(restored.rounds_per_match == 3, "rounds_per_match must survive the round trip")
	)

	var other := _build_state()
	other.turns_per_player = 5
	other.rounds_per_match = 3

	violations.append_array(
		_expect(
			state.digest() != other.digest(),
			"two states differing only in turns_per_player must have different digest()s"
		)
	)

	return violations


## 7. from_dict() returns null for each of: a missing key, a String value, a
## fractional float, and a negative value -- for both keys.
static func _test_from_dict_refusals() -> Array[String]:
	var violations: Array[String] = []

	var base := _build_state()
	base.turns_per_player = 4
	base.rounds_per_match = 3
	var base_dict := base.to_dict()

	for key in ["turns_per_player", "rounds_per_match"]:
		var missing := base_dict.duplicate(true)
		missing.erase(key)
		violations.append_array(
			_expect(
				GameState.from_dict(missing) == null,
				'from_dict() must refuse a dictionary missing "%s"' % key
			)
		)

		var string_valued := base_dict.duplicate(true)
		string_valued[key] = "4"
		violations.append_array(
			_expect(
				GameState.from_dict(string_valued) == null,
				'from_dict() must refuse a String value for "%s"' % key
			)
		)

		var fractional := base_dict.duplicate(true)
		fractional[key] = 4.5
		violations.append_array(
			_expect(
				GameState.from_dict(fractional) == null,
				'from_dict() must refuse a fractional float value for "%s"' % key
			)
		)

		var negative := base_dict.duplicate(true)
		negative[key] = -1
		violations.append_array(
			_expect(
				GameState.from_dict(negative) == null,
				'from_dict() must refuse a negative value for "%s"' % key
			)
		)

	return violations


## 8. Neither predicate mutates: state.digest() and state.rng.get_state() are
## unchanged across a call to each.
static func _test_predicates_are_pure() -> Array[String]:
	var violations: Array[String] = []

	var state := _build_state()
	state.turns_per_player = 4
	state.rounds_per_match = 3
	state.turns_taken = 8
	state.round_number = 3

	var digest_before := state.digest()
	var rng_state_before := state.rng.get_state()

	state.combat_segment_complete()
	violations.append_array(
		_expect(
			state.digest() == digest_before, "combat_segment_complete() must not change digest()"
		)
	)
	violations.append_array(
		_expect(
			state.rng.get_state() == rng_state_before,
			"combat_segment_complete() must not draw from state.rng"
		)
	)

	state.is_final_round()
	violations.append_array(
		_expect(state.digest() == digest_before, "is_final_round() must not change digest()")
	)
	violations.append_array(
		_expect(
			state.rng.get_state() == rng_state_before,
			"is_final_round() must not draw from state.rng"
		)
	)

	return violations
