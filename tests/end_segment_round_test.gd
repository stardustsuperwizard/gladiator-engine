## Plays a whole round through the gate and then ends it: the case the parent
## epic calls `happy_path`, and the one that proves the pieces compose.
##
## Each Turn is an action submitted through `ActionRunner`, followed by both
## players passing the Power Step -- which is what completes a Turn (spec
## §5.3) -- until `GameState.combat_segment_complete()` reports the Combat
## Segment over. **The loop reads that off the state; it never counts Turns
## itself.** `MAX_TURNS` bounds a runaway loop and is not the loop's
## condition: a run that reaches it is reported as a failure rather than
## quietly stopping at the right answer.
##
## Then `EndSegment.run()` ends the round, and round 2 begins clean: the flags
## the round's actions set are gone, `round_number` has advanced, `turns_taken`
## is back to zero, and a fighter that acted in round 1 acts again through the
## same gate.
##
## Lives under `tests/` rather than `rules/tests/`, for the reason
## `tests/power_step_gate_test.gd`'s docstring gives: it names `ActionRunner`
## and `Authority`, which are `res://scripts/` code, and
## `rules/tests/extraction_contract_test.gd` fails the build over a `rules/`
## file that names one. The rules-side behaviour of the same Segment -- what
## `run()` clears, what it refuses and what it leaves alone -- is in
## `rules/tests/end_segment_test.gd`.
##
## **The End Segment is not submitted through the runner, and that is the
## point.** It is not a `TurnAction`, no player submits it, and it has no
## requester whose entitlement `Authority` could answer; see `EndSegment`'s own
## docstring. Every *command* in this file goes through `ActionRunner`; the
## Segment boundary between the two rounds does not.
##
## Nothing here rotates the active player by rule. `Authority` advances no
## turn, and spec §5.2's turn order is not built; `set_active_player()` is how
## this case moves it, exactly as `power_step_gate_test.gd` does.
class_name EndSegmentRoundTest

const ORIGIN := Vector3i(0, 0, 0)
const F1_ROUND_1 := Vector3i(1, -1, 0)
const F1_ROUND_2 := Vector3i(2, -2, 0)
const F2_HOME := Vector3i(3, -3, 0)

const BOARD_RADIUS := 3

## Spec §5.2's Turns per player and §5.1's rounds per match, chosen for this
## case: two players at two Turns each is a four-Turn Combat Segment.
const TURNS_PER_PLAYER := 2
const ROUNDS_PER_MATCH := 3

## A bound on the Turn loop, not a count of the Turns it should take. Reaching
## it is a failure: the loop is meant to stop because the state says the
## Segment is complete.
const MAX_TURNS := 12


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_a_full_round_completes_and_the_end_segment_begins_the_next())

	if violations.is_empty():
		return true

	printerr("\n=== End Segment Round Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


# --- Fixtures ---------------------------------------------------------------


static func _template() -> FighterTemplate:
	var template := FighterTemplate.new()
	template.template_id = "end-segment-round-test-fighter"
	template.move = 1
	template.save = 2
	template.health = 5
	return template


## A hexagonal board of `BOARD_RADIUS` rings, one fighter per player, the round
## structure configured, and `p1` active by construction -- `Authority` seeds
## the active player from the front of the turn order.
static func _build_state() -> GameState:
	var board := Board.new()
	for x in range(-BOARD_RADIUS, BOARD_RADIUS + 1):
		var low := maxi(-BOARD_RADIUS, -x - BOARD_RADIUS)
		var high := mini(BOARD_RADIUS, -x + BOARD_RADIUS)
		for y in range(low, high + 1):
			board.add_hex(Vector3i(x, y, -x - y), Board.HexType.NORMAL)

	var state := GameState.new(board, DeterministicRng.new(5))
	state.add_player("p1")
	state.add_player("p2")
	state.turns_per_player = TURNS_PER_PLAYER
	state.rounds_per_match = ROUNDS_PER_MATCH

	_place(state, "f1", "p1", ORIGIN)
	_place(state, "f2", "p2", F2_HOME)
	return state


static func _place(state: GameState, fighter_id: String, owner_id: String, coord: Vector3i) -> void:
	state.add_fighter(fighter_id, Fighter.new(fighter_id, _template(), owner_id, coord).to_dict())
	state.board.place_occupant(coord, StringName(fighter_id))


## The stored fighter, parsed back over this suite's one template.
static func _stored(state: GameState, fighter_id: String) -> Fighter:
	return Fighter.from_dict(state.fighter(fighter_id), _template())


## True when the stored fighter holds none of `StatusFlags.round_level()`.
static func _is_clear(state: GameState, fighter_id: String) -> bool:
	var fighter := _stored(state, fighter_id)
	if fighter == null:
		return false

	for flag in StatusFlags.round_level():
		if fighter.has_status_flag(flag):
			return false

	return true


## Plays one whole Turn through the gate: the active player's `action`, then
## both players passing the Power Step, then the active player rotated to the
## opponent. Spec §5.3: the Turn is over when the Power Step has ended.
static func _play_turn(
	runner: ActionRunner, authority: Authority, action: TurnAction
) -> Array[String]:
	var violations: Array[String] = []
	var active := authority.active_player_id()
	var opponent := "p2" if active == "p1" else "p1"

	var resolved := runner.run(action, active)
	violations.append_array(
		_expect(
			resolved.success, "the active player's action must resolve, got %s" % resolved.reason
		)
	)

	var first := runner.run(PowerStepPassAction.new(active), active)
	violations.append_array(
		_expect(
			first.success, "the active player's Power Step pass must resolve, got %s" % first.reason
		)
	)

	var second := runner.run(PowerStepPassAction.new(opponent), opponent)
	violations.append_array(
		_expect(
			second.success, "the opponent's Power Step pass must resolve, got %s" % second.reason
		)
	)

	authority.set_active_player(opponent)
	return violations


# --- The full round ---------------------------------------------------------


static func _test_a_full_round_completes_and_the_end_segment_begins_the_next() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	var authority := Authority.new(state)
	var runner := ActionRunner.new(authority)

	violations.append_array(
		_expect(
			not state.combat_segment_complete(),
			"a round that has not been played must not report a complete Combat Segment"
		)
	)

	# The round's first Turn is a Move, so the round has a `"moved"` flag in it
	# for the End Segment to clear. Every later Turn is a Guard, which any
	# fighter may take from where it stands however many Turns the round has.
	violations.append_array(
		_play_turn(runner, authority, MoveAction.new("f1", F1_ROUND_1, _template()))
	)

	var played := 1
	while not state.combat_segment_complete():
		played += 1
		if played > MAX_TURNS:
			(
				violations
				. append_array(
					_expect(
						false,
						(
							(
								"the Combat Segment never reported complete in %d Turns -- the loop must stop "
								+ "because the state says so"
							)
							% MAX_TURNS
						)
					)
				)
			)
			return violations

		var actor := "f1" if authority.active_player_id() == "p1" else "f2"
		violations.append_array(_play_turn(runner, authority, GuardAction.new(actor, _template())))

	violations.append_array(
		_expect(
			not state.power_step_open and state.power_step_passes().is_empty(),
			"the completed Combat Segment must leave no Power Step open and no pass recorded"
		)
	)
	violations.append_array(
		_expect(
			not _is_clear(state, "f1"),
			"the round's actions must have left a round-level flag for the End Segment to clear"
		)
	)
	violations.append_array(
		_expect(EndSegment.can_run(state), "a complete Combat Segment must be runnable")
	)

	var result := EndSegment.run(state)

	violations.append_array(
		_expect(result.success, "the End Segment must run, got %s" % result.reason)
	)
	violations.append_array(
		_expect(
			_is_clear(state, "f1") and _is_clear(state, "f2"),
			"round 2 must begin with no round-level flag on either fighter"
		)
	)
	violations.append_array(
		_expect(
			state.round_number == 2 and state.turns_taken == 0,
			"round 2 must begin at round_number 2 with turns_taken back to 0"
		)
	)
	violations.append_array(
		_expect(
			not state.combat_segment_complete(),
			"round 2's Combat Segment must not already be complete"
		)
	)
	violations.append_array(
		_expect(
			not state.power_step_open and state.power_step_passes().is_empty(),
			"the End Segment must leave the Power Step and the pass record at rest"
		)
	)

	# And round 2 is played the same way: the fighter that Moved in round 1
	# Moves again, through the same gate.
	violations.append_array(
		_play_turn(runner, authority, MoveAction.new("f1", F1_ROUND_2, _template()))
	)
	violations.append_array(
		_expect(
			_stored(state, "f1").position() == F1_ROUND_2,
			"the fighter that Moved in round 1 must have Moved again in round 2"
		)
	)
	violations.append_array(
		_expect(
			state.turns_taken == 1, "round 2's first completed Turn must be counted as its first"
		)
	)

	return violations
