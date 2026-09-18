## Tests RoundProfile's zero-default shape and GameState's round-structure
## field: is_final_round(), serialization, and purity.
##
## **The Combat Segment boundary is not here any more.** Spec §5.2 as revised
## 2026-09-17 derives a round's Turn allowance from the board, so the predicate
## left `GameState` for `TurnSequence` and its cases left this suite for
## `rules/tests/turn_sequence_test.gd`. Spec §5.2 as further revised 2026-09-18
## (epic #377) removed the authored Turns-per-player dial altogether: `rounds_per_match`
## is the only round-structure field left here.
##
## Every RoundProfile fixture here is built in memory with RoundProfile.new()
## -- `rules/` may not reference `res://resources/`, so loading
## round_profile.tres is `tests/resource_data_test.gd`'s job, not this one's.
class_name RoundProfileTest

const SEED := 20260909


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_round_profile_defaults())
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


## 1. A fresh RoundProfile defaults its two round-structure exports to their
## zero values.
static func _test_round_profile_defaults() -> Array[String]:
	var violations: Array[String] = []
	var profile := RoundProfile.new()

	violations.append_array(
		_expect(profile.profile_id == "", 'a fresh RoundProfile\'s profile_id must default to ""')
	)
	violations.append_array(
		_expect(
			profile.rounds_per_match == 0,
			"a fresh RoundProfile's rounds_per_match must default to 0"
		)
	)
	violations.append_array(
		_expect(
			# Object.get() is the dynamic accessor: it returns null for a
			# property the script does not declare rather than failing to
			# compile, which is what proves epic #377 removed the dial
			# rather than merely leaving it unauthored.
			profile.get(&"turns_per_player") == null,
			"a fresh RoundProfile must carry no Turns-per-player dial"
		)
	)

	return violations


## 2. is_final_round() is false at round_number == 1 of a 3-round match, true
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


## 3. rounds_per_match survives to_dict()/from_dict(), and two states
## differing only in rounds_per_match have different digest()s.
static func _test_fields_round_trip_and_affect_digest() -> Array[String]:
	var violations: Array[String] = []

	var state := _build_state()
	state.rounds_per_match = 3

	var restored := GameState.from_dict(state.to_dict())
	violations.append_array(
		_expect(restored != null, "from_dict() must accept the reference state's own to_dict()")
	)
	if restored == null:
		return violations

	violations.append_array(
		_expect(restored.rounds_per_match == 3, "rounds_per_match must survive the round trip")
	)
	violations.append_array(
		_expect(
			# Object.get() is the dynamic accessor: it returns null for a
			# property the script does not declare rather than failing to
			# compile, which is what proves epic #377 removed the dial
			# rather than merely leaving it unauthored.
			restored.get(&"turns_per_player") == null,
			"the round-tripped state must carry no Turns-per-player dial"
		)
	)

	var other := _build_state()
	other.rounds_per_match = 5

	violations.append_array(
		_expect(
			state.digest() != other.digest(),
			"two states differing only in rounds_per_match must have different digest()s"
		)
	)

	return violations


## 4. from_dict() returns null for each of: a missing key, a String value, a
## fractional float, and a negative value.
static func _test_from_dict_refusals() -> Array[String]:
	var violations: Array[String] = []

	var base := _build_state()
	base.rounds_per_match = 3
	var base_dict := base.to_dict()

	var key := "rounds_per_match"

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


## 5. is_final_round() does not mutate: state.digest() and
## state.rng.get_state() are unchanged across a call.
static func _test_predicates_are_pure() -> Array[String]:
	var violations: Array[String] = []

	var state := _build_state()
	state.rounds_per_match = 3
	state.turns_taken = 8
	state.round_number = 3

	var digest_before := state.digest()
	var rng_state_before := state.rng.get_state()

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
