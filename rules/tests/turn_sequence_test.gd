## Tests `TurnSequence`: spec §5.2's derived Turn allowance, the Combat Segment
## boundary that falls out of it, and the rotation that names the active player.
##
## **Every fixture here places its champions on the board**, because that is
## what the rule counts: a player's Turns in a round are their champions still
## standing, minus the ones already acted with. A fighter added to `GameState`
## but never placed is worth no Turn, which is exactly spec §9's defeated
## fighter and is asserted as such below.
##
## No gate is involved and no game-side type is named anywhere in this file --
## every method under test is a pure function of `GameState`, and who is
## entitled to act is a different question this suite does not ask.
class_name TurnSequenceTest

const SEED := 7

## A hexagonal board of this many rings, which is more hexes than any fixture
## below needs.
const BOARD_RADIUS := 3

## Where champions are placed, one per champion, in the order they are built.
## Six is the largest roster any case here uses.
const HOMES: Array[Vector3i] = [
	Vector3i(0, 0, 0),
	Vector3i(1, -1, 0),
	Vector3i(2, -2, 0),
	Vector3i(3, -3, 0),
	Vector3i(-1, 1, 0),
	Vector3i(-2, 2, 0),
]


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_the_mvp_fixture_is_four_turns())
	violations.append_array(_test_unequal_rosters_skip_the_spent_player())
	violations.append_array(_test_three_players_rotate())
	violations.append_array(_test_remaining_turns_counts_unactivated_champions())
	violations.append_array(_test_combat_segment_complete())
	violations.append_array(_test_a_defeated_champion_takes_its_turn_with_it())
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


# --- Fixtures ---------------------------------------------------------------


static func _board() -> Board:
	var board := Board.new()
	for x in range(-BOARD_RADIUS, BOARD_RADIUS + 1):
		var low := maxi(-BOARD_RADIUS, -x - BOARD_RADIUS)
		var high := mini(BOARD_RADIUS, -x + BOARD_RADIUS)
		for y in range(low, high + 1):
			board.add_hex(Vector3i(x, y, -x - y), Board.HexType.NORMAL)
	return board


## `player_ids[i]` with `champion_counts[i]` champions, each placed on its own
## hex, added player by player so `fighter_ids()` reports each player's
## champions together and in roster order.
##
## The payloads carry `"id"`, `"owner_id"`, `"position"` and an empty
## `"status_flags"` and nothing else -- `TurnSequence` reads one key of them and
## asks `Activation` for the flag, so no `FighterTemplate` is needed here and
## none is built. `"status_flags"` is present rather than omitted because
## `Fighter.with_flags()` writes nothing into a payload that does not already
## carry the array, so `Activation.record()` would silently do nothing.
static func _build_state(player_ids: Array[String], champion_counts: Array[int]) -> GameState:
	var state := GameState.new(_board(), DeterministicRng.new(SEED))
	var placed := 0

	for index in player_ids.size():
		var player_id := player_ids[index]
		state.add_player(player_id)

		for ordinal in champion_counts[index]:
			var fighter_id := "%s_f%d" % [player_id, ordinal]
			var coord := HOMES[placed]
			placed += 1
			(
				state
				. add_fighter(
					fighter_id,
					{
						"id": fighter_id,
						"owner_id": player_id,
						"position": [coord.x, coord.y, coord.z],
						"status_flags": [],
					}
				)
			)
			state.board.place_occupant(coord, StringName(fighter_id))

	return state


## The payload's `"owner_id"`, read the way the rule under test reads it.
static func _owner_of(state: GameState, fighter_id: String) -> String:
	var value: Variant = state.fighter(fighter_id).get("owner_id")
	return value if typeof(value) == TYPE_STRING else ""


## True when `fighter_id` is still the occupant of its own recorded hex.
static func _on_board(state: GameState, fighter_id: String) -> bool:
	var raw: Variant = state.fighter(fighter_id).get("position")
	if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
		return false

	var coord := Vector3i(int(raw[0]), int(raw[1]), int(raw[2]))
	return state.board.occupant_at(coord) == StringName(fighter_id)


## Spec §9's defeat, as the board expresses it: the champion stops being the
## occupant of its own recorded hex, and its stored payload is left alone.
static func _take_off_the_board(state: GameState, fighter_id: String) -> void:
	var raw: Variant = state.fighter(fighter_id).get("position")
	state.board.remove_occupant(Vector3i(int(raw[0]), int(raw[1]), int(raw[2])))


## One Turn by `player_id`: its first unspent champion is activated the way a
## resolved action would activate it, and `turns_taken` rises the way
## `PowerStep.end_on_second_pass()` would raise it once the Power Step ended.
static func _take_a_turn(state: GameState, player_id: String) -> void:
	for fighter_id in state.fighter_ids():
		if _owner_of(state, fighter_id) != player_id:
			continue
		if not _on_board(state, fighter_id):
			continue
		if Activation.has_activated(state, fighter_id):
			continue

		Activation.record(state, fighter_id)
		break

	state.turns_taken += 1


## Plays Turns until `active_player()` names nobody, recording who each one
## belonged to. `bound` fails the case rather than looping forever.
static func _play_the_segment(state: GameState, bound: int) -> Array[String]:
	var reported: Array[String] = []

	while not TurnSequence.active_player(state).is_empty():
		if reported.size() >= bound:
			reported.append("<unbounded>")
			return reported

		var active := TurnSequence.active_player(state)
		reported.append(active)
		_take_a_turn(state, active)

	return reported


# --- The Segment's shape ----------------------------------------------------


## The MVP fixture -- two players, two champions each -- is exactly four Turns,
## p1, p2, p1, p2, and names nobody at `turns_taken == 4`.
static func _test_the_mvp_fixture_is_four_turns() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state(["p1", "p2"], [2, 2])
	var expected := ["p1", "p2", "p1", "p2"]

	var reported := _play_the_segment(state, 12)

	violations.append_array(
		_expect(
			reported == expected,
			"two champions each must be the four Turns %s, got %s" % [expected, reported]
		)
	)
	violations.append_array(
		_expect(
			state.turns_taken == 4,
			"four Turns must leave turns_taken at 4, got %d" % state.turns_taken
		)
	)
	violations.append_array(
		_expect(
			TurnSequence.active_player(state) == "",
			(
				"turns_taken 4 of a two-by-two round must name nobody, got %s"
				% TurnSequence.active_player(state)
			)
		)
	)
	violations.append_array(
		_expect(
			TurnSequence.combat_segment_complete(state),
			"a round whose every champion has acted must report the Segment complete"
		)
	)

	return violations


## Three champions against one: four Turns, p1, p2, p1, p1. The Segment does
## not end when the shorter roster is spent, and no further Turn is offered to
## the player who spent it.
static func _test_unequal_rosters_skip_the_spent_player() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state(["p1", "p2"], [3, 1])
	var expected := ["p1", "p2", "p1", "p1"]

	var reported := _play_the_segment(state, 12)

	violations.append_array(
		_expect(
			reported == expected,
			"three champions against one must be the Turns %s, got %s" % [expected, reported]
		)
	)
	violations.append_array(
		_expect(
			TurnSequence.combat_segment_complete(state),
			"the unequal-roster Segment must be complete after its four Turns"
		)
	)

	return violations


## Three players, two champions each: the rotation walks all three, so a
## two-player alternation hard-coded into the resolver fails on the first lap.
static func _test_three_players_rotate() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state(["p1", "p2", "p3"], [2, 2, 2])
	var expected := ["p1", "p2", "p3", "p1", "p2", "p3"]

	var reported := _play_the_segment(state, 12)

	violations.append_array(
		_expect(
			reported == expected,
			"three players of two champions must rotate as %s, got %s" % [expected, reported]
		)
	)

	return violations


# --- The allowance itself ---------------------------------------------------


## `remaining_turns()` is the count of a player's champions that are the
## board's occupant of their own recorded position and do not hold the
## activation flag -- and zero for a player id in no turn order.
static func _test_remaining_turns_counts_unactivated_champions() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state(["p1", "p2"], [2, 2])

	violations.append_array(
		_expect(
			TurnSequence.remaining_turns(state, "p1") == 2,
			(
				"two champions on the board must be two Turns, got %d"
				% TurnSequence.remaining_turns(state, "p1")
			)
		)
	)

	Activation.record(state, "p1_f0")
	violations.append_array(
		_expect(
			TurnSequence.remaining_turns(state, "p1") == 1,
			(
				"an activated champion must not be counted, got %d"
				% TurnSequence.remaining_turns(state, "p1")
			)
		)
	)
	violations.append_array(
		_expect(
			TurnSequence.remaining_turns(state, "p2") == 2,
			(
				"activating p1's champion must not touch p2's allowance, got %d"
				% TurnSequence.remaining_turns(state, "p2")
			)
		)
	)

	_take_off_the_board(state, "p1_f1")
	violations.append_array(
		_expect(
			TurnSequence.remaining_turns(state, "p1") == 0,
			(
				"a champion off the board must not be counted, got %d"
				% TurnSequence.remaining_turns(state, "p1")
			)
		)
	)

	violations.append_array(
		_expect(
			TurnSequence.remaining_turns(state, "nobody") == 0,
			(
				"a player id in no turn order must have no Turns, got %d"
				% TurnSequence.remaining_turns(state, "nobody")
			)
		)
	)

	return violations


## `combat_segment_complete()` is false for an empty turn order, false while
## any player has an unactivated champion on the board, and true when none
## does -- whether the champions were activated or removed.
static func _test_combat_segment_complete() -> Array[String]:
	var violations: Array[String] = []

	var no_players := _build_state([], [])
	violations.append_array(
		_expect(
			not TurnSequence.combat_segment_complete(no_players),
			"a state with an empty turn order must not report a complete Segment"
		)
	)

	var state := _build_state(["p1", "p2"], [1, 1])
	violations.append_array(
		_expect(
			not TurnSequence.combat_segment_complete(state),
			"a fresh round must not report a complete Segment"
		)
	)

	Activation.record(state, "p1_f0")
	violations.append_array(
		_expect(
			not TurnSequence.combat_segment_complete(state),
			"one player's champion still unactivated must leave the Segment incomplete"
		)
	)

	Activation.record(state, "p2_f0")
	violations.append_array(
		_expect(
			TurnSequence.combat_segment_complete(state),
			"every champion activated must report the Segment complete"
		)
	)

	var wiped := _build_state(["p1", "p2"], [1, 1])
	_take_off_the_board(wiped, "p1_f0")
	_take_off_the_board(wiped, "p2_f0")
	violations.append_array(
		_expect(
			TurnSequence.combat_segment_complete(wiped),
			"a board with no champion left on it must report the Segment complete"
		)
	)

	return violations


## A champion removed before it acted takes its Turn with it: the round is one
## Turn shorter, and the Turn it would have had is offered to nobody.
static func _test_a_defeated_champion_takes_its_turn_with_it() -> Array[String]:
	var violations: Array[String] = []

	var undisturbed := _build_state(["p1", "p2"], [2, 2])
	var full := _play_the_segment(undisturbed, 12)

	var state := _build_state(["p1", "p2"], [2, 2])
	_take_a_turn(state, TurnSequence.active_player(state))

	# p2's second champion, still unactivated, is defeated mid-round.
	_take_off_the_board(state, "p2_f1")

	var shortened: Array[String] = ["p1"]
	shortened.append_array(_play_the_segment(state, 12))

	(
		violations
		. append_array(
			_expect(
				shortened.size() == full.size() - 1,
				(
					"defeating an unactivated champion must shorten the round by one Turn, %s against %s"
					% [shortened, full]
				)
			)
		)
	)
	violations.append_array(
		_expect(
			shortened == ["p1", "p2", "p1"],
			'the shortened round must be ["p1", "p2", "p1"], got %s' % [shortened]
		)
	)
	violations.append_array(
		_expect(
			TurnSequence.combat_segment_complete(state),
			"the shortened round must leave the Segment complete"
		)
	)

	return violations


## `""` for a state with no players, and for a state whose players have no
## champion on the board at all.
static func _test_unconfigured_states_return_empty() -> Array[String]:
	var violations: Array[String] = []

	var no_players := _build_state([], [])
	violations.append_array(
		_expect(
			TurnSequence.active_player(no_players) == "",
			"a state with no players must answer no active player"
		)
	)

	var no_champions := _build_state(["p1", "p2"], [0, 0])
	violations.append_array(
		_expect(
			TurnSequence.active_player(no_champions) == "",
			"players with no champion on the board must answer no active player"
		)
	)

	return violations


# --- Purity and serialization -----------------------------------------------


## `state.digest()` and `state.rng.get_state()` are identical before and after
## every method here, including every `""` path.
static func _test_nothing_mutates() -> Array[String]:
	var violations: Array[String] = []

	var spent := _build_state(["p1", "p2"], [1, 1])
	Activation.record(spent, "p1_f0")
	Activation.record(spent, "p2_f0")

	var cases: Array[GameState] = [
		_build_state(["p1", "p2"], [2, 2]),
		_build_state(["p1", "p2", "p3"], [2, 2, 2]),
		spent,
		_build_state([], []),
		_build_state(["p1", "p2"], [0, 0]),
	]

	for state in cases:
		var digest_before := state.digest()
		var rng_state_before := state.rng.get_state()

		TurnSequence.remaining_turns(state, "p1")
		TurnSequence.combat_segment_complete(state)
		TurnSequence.active_player(state)

		violations.append_array(
			_expect(state.digest() == digest_before, "TurnSequence must not change state.digest()")
		)
		violations.append_array(
			_expect(
				state.rng.get_state() == rng_state_before,
				"TurnSequence must not draw from state.rng"
			)
		)

	return violations


## A state serialized with `to_dict()` part-way through a round and rebuilt
## with `GameState.from_dict()` reports the identical active player and the
## identical allowance as the state it was serialized from.
static func _test_round_trip_reports_the_same_active_player() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state(["p1", "p2", "p3"], [2, 2, 2])
	_take_a_turn(state, "p1")
	_take_a_turn(state, "p2")

	var restored := GameState.from_dict(state.to_dict())

	violations.append_array(_expect(restored != null, "a mid-round state must round trip"))
	if restored == null:
		return violations

	violations.append_array(
		_expect(
			TurnSequence.active_player(restored) == TurnSequence.active_player(state),
			"a restored state must report the identical active player"
		)
	)
	violations.append_array(
		_expect(
			(
				TurnSequence.remaining_turns(restored, "p1")
				== TurnSequence.remaining_turns(state, "p1")
			),
			"a restored state must report the identical allowance"
		)
	)

	return violations


## The allowance is derived, never serialized: this task adds no key to
## `GameState.to_dict()`.
static func _test_to_dict_key_set_is_unchanged() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state(["p1", "p2"], [1, 1])
	var expected_keys: Array = [
		"board",
		"rng",
		"round_number",
		"turns_taken",
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
