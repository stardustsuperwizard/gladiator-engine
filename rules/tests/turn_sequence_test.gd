## Tests `TurnSequence.active_player()`: the derived answer to whose Turn of
## the Combat Segment it is, from `turn_order()` and `turns_taken` alone.
##
## No gate is involved and no game-side type is named anywhere in this file --
## `active_player()` is a pure function of `GameState`, and who is entitled to
## act is a different question this suite does not ask.
class_name TurnSequenceTest


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_two_players_alternate())
	violations.append_array(_test_three_players_rotate())
	violations.append_array(_test_segment_complete_returns_empty())
	violations.append_array(_test_unconfigured_states_return_empty())
	violations.append_array(_test_nothing_mutates())
	violations.append_array(_test_round_trip_reports_the_same_active_player())
	violations.append_array(_test_to_dict_key_set_is_unchanged())

	if violations.is_empty():
		return true

	printerr("\n=== Turn Sequence Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


## `player_ids`, each with one fighter, and `turns_per_player` set inline --
## never from `res://resources/round/round_profile.tres`, per
## `rules/tests/round_profile_test.gd`'s own note.
static func _build_state(player_ids: Array[String], turns_per_player: int) -> GameState:
	var state := GameState.new(Board.new(), DeterministicRng.new(7))
	for player_id in player_ids:
		state.add_player(player_id)
		state.add_fighter(
			"f_%s" % player_id, {"id": "f_%s" % player_id, "owner_id": player_id}
		)
	state.turns_per_player = turns_per_player
	return state


## Two players, `turns_per_player` 4: `turns_taken` 0..7 names p1, p2, p1, p2,
## p1, p2, p1, p2 in that order, not a hard-coded two-entry alternation.
static func _test_two_players_alternate() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state(["p1", "p2"], 4)
	var expected := ["p1", "p2", "p1", "p2", "p1", "p2", "p1", "p2"]

	for turns_taken in range(expected.size()):
		state.turns_taken = turns_taken
		violations.append_array(
			_expect(
				TurnSequence.active_player(state) == expected[turns_taken],
				(
					"turns_taken %d must name %s, got %s"
					% [turns_taken, expected[turns_taken], TurnSequence.active_player(state)]
				)
			)
		)

	return violations


## Three players, `turns_per_player` 2: the same modulus rotates through all
## three, so a two-player alternation hard-coded into the resolver would fail
## this on its very first wraparound.
static func _test_three_players_rotate() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state(["p1", "p2", "p3"], 2)
	var expected := ["p1", "p2", "p3", "p1", "p2", "p3"]

	for turns_taken in range(expected.size()):
		state.turns_taken = turns_taken
		violations.append_array(
			_expect(
				TurnSequence.active_player(state) == expected[turns_taken],
				(
					"turns_taken %d must name %s, got %s"
					% [turns_taken, expected[turns_taken], TurnSequence.active_player(state)]
				)
			)
		)

	return violations


## At `turns_taken` 8 of a two-player, 4-Turns-each round --
## `combat_segment_complete()` is true -- the answer is `""`, not a wraparound
## to the front of the order for a ninth Turn.
static func _test_segment_complete_returns_empty() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state(["p1", "p2"], 4)
	state.turns_taken = 8

	violations.append_array(
		_expect(
			state.combat_segment_complete(), "turns_taken 8 of a 2 x 4 round must be complete"
		)
	)
	violations.append_array(
		_expect(
			TurnSequence.active_player(state) == "",
			"a complete Combat Segment must answer no active player"
		)
	)

	return violations


## `""` for a state with no players, and for one whose `turns_per_player` is
## zero or negative.
static func _test_unconfigured_states_return_empty() -> Array[String]:
	var violations: Array[String] = []

	var no_players := _build_state([], 4)
	violations.append_array(
		_expect(
			TurnSequence.active_player(no_players) == "",
			"a state with no players must answer no active player"
		)
	)

	var zero_turns := _build_state(["p1", "p2"], 0)
	violations.append_array(
		_expect(
			TurnSequence.active_player(zero_turns) == "",
			"turns_per_player 0 must answer no active player"
		)
	)

	var negative_turns := _build_state(["p1", "p2"], -1)
	violations.append_array(
		_expect(
			TurnSequence.active_player(negative_turns) == "",
			"a negative turns_per_player must answer no active player"
		)
	)

	return violations


## `state.digest()` and `state.rng.get_state()` are identical before and after
## every call above, including every `""` path.
static func _test_nothing_mutates() -> Array[String]:
	var violations: Array[String] = []

	var cases: Array[GameState] = [
		_build_state(["p1", "p2"], 4),
		_build_state(["p1", "p2", "p3"], 2),
		_build_state(["p1", "p2"], 4),
		_build_state([], 4),
		_build_state(["p1", "p2"], 0),
		_build_state(["p1", "p2"], -1),
	]
	cases[2].turns_taken = 8

	for state in cases:
		var digest_before := state.digest()
		var rng_state_before := state.rng.get_state()

		TurnSequence.active_player(state)

		violations.append_array(
			_expect(
				state.digest() == digest_before, "active_player() must not change state.digest()"
			)
		)
		violations.append_array(
			_expect(
				state.rng.get_state() == rng_state_before,
				"active_player() must not draw from state.rng"
			)
		)

	return violations


## A state serialized with `to_dict()` part-way through a round and rebuilt
## with `GameState.from_dict()` reports the identical active player as the
## state it was serialized from.
static func _test_round_trip_reports_the_same_active_player() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state(["p1", "p2", "p3"], 3)
	state.turns_taken = 4

	var restored := GameState.from_dict(state.to_dict())

	violations.append_array(_expect(restored != null, "a mid-round state must round trip"))
	violations.append_array(
		_expect(
			restored != null
			and TurnSequence.active_player(restored) == TurnSequence.active_player(state),
			"a restored state must report the identical active player"
		)
	)

	return violations


## This task adds no key to `GameState.to_dict()` -- the active player is
## derived, never serialized.
static func _test_to_dict_key_set_is_unchanged() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state(["p1", "p2"], 4)
	var expected_keys: Array = [
		"board",
		"rng",
		"round_number",
		"turns_taken",
		"turns_per_player",
		"rounds_per_match",
		"power_step_open",
		"power_step_passes",
		"turn_order",
		"players",
		"fighter_order",
		"fighters",
	]

	violations.append_array(
		_expect(
			state.to_dict().keys() == expected_keys,
			"to_dict()'s key set must be unchanged by this task"
		)
	)

	return violations
