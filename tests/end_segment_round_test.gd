## The full-round case for spec §10's End Segment: a whole Combat Segment's
## Turns played through `ActionRunner`, then the Segment run against what those
## Turns left behind.
##
## Lives under `tests/` rather than `rules/tests/`, for the reason
## `tests/power_step_gate_test.gd`'s docstring gives: it names `ActionRunner`
## and `Authority`, which are `res://scripts/` code, and
## `rules/tests/extraction_contract_test.gd` fails the build over a `rules/`
## file that names one. The rules-side behaviour of the same Segment -- the
## refusals, the clearing, the counters, the helper on `Fighter` -- is in
## `rules/tests/end_segment_test.gd`.
##
## **The loop does not count Turns.** It plays until
## `GameState.combat_segment_complete()` says the Combat Segment is over, and
## asserts `EndSegment.can_run()` agrees with that answer at every step along
## the way. A test that counted the Turns itself would be asserting its own
## arithmetic rather than the state's, and would keep passing if the counter
## stopped moving. The iteration cap below exists only so a stalled fixture
## fails loudly instead of hanging the headless run; reaching it is a failure.
##
## **Each Turn is played the way spec §5.3 defines one**: the active player's
## core action through the gate, then both players passing the Power Step, which
## is what completes the Turn. Nothing here increments `turns_taken` directly.
##
## `Authority` advances no turn, so `set_active_player()` is how the active
## player rotates between Turns -- the same thing `power_step_gate_test.gd`
## does, and for the same reason.
class_name EndSegmentRoundTest

## Turns per player per round, and rounds in the match. Two players at one Turn
## each makes a Combat Segment of two Turns: short enough to read, and the loop
## never depends on the number.
const TURNS_PER_PLAYER := 1
const ROUNDS_PER_MATCH := 3

## The most Turns the loop will play before declaring the fixture stalled.
## Generous against `TURNS_PER_PLAYER`, because it is a hang guard and not an
## expectation.
const TURN_LIMIT := 16


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_a_full_round_completes_and_the_segment_starts_the_next())

	if violations.is_empty():
		return true

	printerr("\n=== End Segment Round Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


static func _template() -> FighterTemplate:
	var template := FighterTemplate.new()
	template.template_id = "end-segment-round-test-fighter"
	template.move = 1
	template.save = 3
	template.health = 3
	return template


## One fighter each, on their own hex. Guard is the action every Turn below
## takes, so no destination or line of sight is needed -- what matters is that a
## Turn resolves an action and then ends, and that the action leaves a
## round-level flag for the Segment to clear.
static func _build_state() -> GameState:
	var board := Board.new()
	board.add_hex(Vector3i(0, 0, 0), Board.HexType.NORMAL)
	board.add_hex(Vector3i(1, -1, 0), Board.HexType.NORMAL)

	var state := GameState.new(board, DeterministicRng.new(5))
	state.add_player("p1")
	state.add_player("p2")
	state.add_fighter("f1", Fighter.new("f1", _template(), "p1", Vector3i(0, 0, 0)).to_dict())
	state.add_fighter("f2", Fighter.new("f2", _template(), "p2", Vector3i(1, -1, 0)).to_dict())
	board.place_occupant(Vector3i(0, 0, 0), &"f1")
	board.place_occupant(Vector3i(1, -1, 0), &"f2")
	state.turns_per_player = TURNS_PER_PLAYER
	state.rounds_per_match = ROUNDS_PER_MATCH
	return state


## The fighter `player_id` acts with. One each, so this is the whole mapping.
static func _fighter_for(player_id: String) -> String:
	return "f1" if player_id == "p1" else "f2"


static func _stored(state: GameState, fighter_id: String) -> Fighter:
	return Fighter.from_dict(state.fighter(fighter_id), _template())


## Plays one Turn for `player_id` through `runner`: a Guard, then that player's
## Power Step pass, then the opponent's. Returns one violation per step that
## did not resolve, so a broken fixture reports as itself rather than as a
## mysterious assertion further down.
static func _play_turn(
	runner: ActionRunner, authority: Authority, player_id: String, opponent_id: String
) -> Array[String]:
	var violations: Array[String] = []

	authority.set_active_player(player_id)

	var action := runner.run(GuardAction.new(_fighter_for(player_id), _template()), player_id)
	violations.append_array(
		_expect(action.success, "%s's Guard must resolve through the runner" % player_id)
	)

	var own_pass := runner.run(PowerStepPassAction.new(player_id), player_id)
	violations.append_array(
		_expect(own_pass.success, "%s's own Power Step pass must resolve" % player_id)
	)

	var reply := runner.run(PowerStepPassAction.new(opponent_id), opponent_id)
	violations.append_array(
		_expect(reply.success, "%s's Power Step pass must resolve" % opponent_id)
	)

	return violations


## Plays the round's Turns until the state says the Combat Segment is over,
## runs the End Segment, and asserts round 2 begins clean.
static func _test_a_full_round_completes_and_the_segment_starts_the_next() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	var authority := Authority.new(state)
	var runner := ActionRunner.new(authority)
	var players := state.turn_order()

	var played := 0
	while not state.combat_segment_complete():
		if played >= TURN_LIMIT:
			violations.append(
				(
					"the Combat Segment never completed within %d Turns -- the fixture is stalled"
					% TURN_LIMIT
				)
			)
			return violations

		violations.append_array(
			_expect(
				not EndSegment.can_run(state),
				"can_run() must be false while the state reports an incomplete Combat Segment"
			)
		)

		var active: String = players[played % players.size()]
		var opponent: String = players[(played + 1) % players.size()]
		violations.append_array(_play_turn(runner, authority, active, opponent))
		played += 1

	violations.append_array(
		_expect(
			played > 0, "the loop must have actually played Turns for this case to prove anything"
		)
	)
	violations.append_array(
		_expect(
			EndSegment.can_run(state),
			"can_run() must be true once the state reports a complete Combat Segment"
		)
	)

	for player_id in players:
		var fighter := _stored(state, _fighter_for(player_id))
		violations.append_array(
			_expect(
				fighter != null and fighter.has_status_flag(GuardAction.FLAG_GUARDED),
				(
					"%s's fighter must be carrying its round-1 Guard flag into the End Segment"
					% player_id
				)
			)
		)

	var before_round := state.round_number
	var result := EndSegment.run(state)

	violations.append_array(
		_expect(result.success, "the End Segment must run against a completed Combat Segment")
	)
	violations.append_array(
		_expect(
			state.round_number == before_round + 1,
			"round 2 must have begun: round_number %d" % state.round_number
		)
	)
	violations.append_array(
		_expect(state.turns_taken == 0, "the Turn counter must be back to 0 for round 2")
	)
	violations.append_array(
		_expect(
			not state.combat_segment_complete(),
			"round 2's Combat Segment must report itself incomplete again"
		)
	)

	for fighter_id in state.fighter_ids():
		var fighter := _stored(state, fighter_id)
		violations.append_array(
			_expect(
				fighter != null and fighter.status_flags().is_empty(),
				"%s must start round 2 with no round-level flag left" % fighter_id
			)
		)

	# Round 2 is actually playable: the same Turn the loop above played resolves
	# again, which is the whole point of clearing the flags.
	violations.append_array(_play_turn(runner, authority, players[0], players[1]))
	violations.append_array(
		_expect(state.turns_taken == 1, "the first Turn of round 2 must count as one Turn")
	)

	return violations
