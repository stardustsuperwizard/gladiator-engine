## Tests the gate half of spec §5.3's Power Step: who may submit a pass, and
## the Turn the Step's ending completes.
##
## **The suite that settles the epic's question is
## `_test_a_move_does_not_count_a_turn_but_the_power_step_does()`.** A Move
## resolves through `ActionRunner` and `turns_taken` does not move; both
## players then pass and it rises by exactly one. Spec §5.3: a Turn is not over
## until its Power Step has ended, and anything counting Turns counts completed
## Turns, not resolved actions.
##
## Lives under `tests/` rather than `rules/tests/`, for the reason
## `tests/action_runner_test.gd`'s docstring gives: it names `ActionRunner` and
## `Authority`, which are `res://scripts/` code, and
## `rules/tests/extraction_contract_test.gd` fails the build over a `rules/`
## file that names one. The rules-side behaviour of the same feature -- what a
## pass does once it has reached `resolve()` -- is in
## `rules/tests/power_step_test.gd`.
##
## **A gate refusal and an action failure stay distinguishable**, and
## `_test_a_closed_step_refuses_the_opponent_and_fails_the_active_player()` is
## the case that proves it: the same closed Power Step produces
## `Authority.REFUSED_NOT_YOUR_TURN` for the non-active player, who never
## reaches `resolve()`, and `PowerStepPassAction.FAILURE_STEP_NOT_OPEN` for the
## active player, who does.
##
## Nothing here rotates the active player by rule. `Authority` advances no
## turn; `set_active_player()` is how these cases move it.
class_name PowerStepGateTest


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_a_move_does_not_count_a_turn_but_the_power_step_does())
	violations.append_array(_test_an_open_step_admits_the_opponents_pass_and_no_more())
	violations.append_array(_test_a_closed_step_refuses_the_opponent_and_fails_the_active_player())
	violations.append_array(_test_a_pass_by_a_stranger_is_refused_by_the_gate())
	violations.append_array(_test_every_refusal_leaves_the_state_identical())

	if violations.is_empty():
		return true

	printerr("\n=== Power Step Gate Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


## `ids` as an `Array[String]`, for comparing against `power_step_passes()`.
## A helper rather than an inline cast: `==` binds tighter than `as`, so
## `passes() == ["p2"] as Array[String]` casts the comparison rather than the
## literal and does not compile.
static func _record(ids: Array) -> Array[String]:
	var out: Array[String] = []
	out.append_array(ids)
	return out


## A one-hex-per-fighter board with a free destination, so a Move is legal for
## either fighter. `p1` is the active player by construction -- `Authority`
## seeds it from the front of the turn order.
static func _build_state() -> GameState:
	var board := Board.new()
	board.add_hex(Vector3i(0, 0, 0), Board.HexType.NORMAL)
	board.add_hex(Vector3i(1, 0, -1), Board.HexType.NORMAL)
	board.add_hex(Vector3i(1, -1, 0), Board.HexType.NORMAL)
	board.add_hex(Vector3i(0, 1, -1), Board.HexType.NORMAL)

	var state := GameState.new(board, DeterministicRng.new(3))
	state.add_player("p1")
	state.add_player("p2")
	state.add_fighter("f1", Fighter.new("f1", _template(), "p1", Vector3i(0, 0, 0)).to_dict())
	state.add_fighter("f2", Fighter.new("f2", _template(), "p2", Vector3i(1, 0, -1)).to_dict())
	board.place_occupant(Vector3i(0, 0, 0), &"f1")
	board.place_occupant(Vector3i(1, 0, -1), &"f2")
	return state


static func _template() -> FighterTemplate:
	var template := FighterTemplate.new()
	template.template_id = "power-step-gate-test-fighter"
	template.move = 1
	return template


## The epic's question, answered end to end through the gate: resolving a core
## action does not advance `turns_taken`; ending the Power Step does.
static func _test_a_move_does_not_count_a_turn_but_the_power_step_does() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	var authority := Authority.new(state)
	var runner := ActionRunner.new(authority)
	var before_turns := state.turns_taken

	var move := runner.run(MoveAction.new("f1", Vector3i(1, -1, 0), _template()), "p1")

	violations.append_array(
		_expect(move.success, "the active player's Move must resolve through the runner")
	)
	violations.append_array(
		_expect(
			state.turns_taken == before_turns,
			"a resolved Move must not advance turns_taken -- the Turn is not over yet"
		)
	)
	violations.append_array(
		_expect(state.power_step_open, "a resolved Move must open the Turn's Power Step")
	)

	var first_pass := runner.run(PowerStepPassAction.new("p1"), "p1")
	violations.append_array(
		_expect(first_pass.success, "the active player's Power Step pass must resolve")
	)
	violations.append_array(
		_expect(state.turns_taken == before_turns, "one pass must not advance turns_taken")
	)

	var second_pass := runner.run(PowerStepPassAction.new("p2"), "p2")
	violations.append_array(
		_expect(second_pass.success, "the non-active player's Power Step pass must resolve")
	)
	violations.append_array(
		_expect(
			state.turns_taken == before_turns + 1,
			"the second pass in a row must advance turns_taken by exactly one"
		)
	)
	violations.append_array(
		_expect(not state.power_step_open, "the second pass in a row must close the Power Step")
	)

	return violations


## With the Step open the non-active player may pass -- and may still do
## nothing else. Their Move, on a fighter they own, is refused
## `REFUSED_NOT_YOUR_TURN` exactly as it would be with the Step closed.
static func _test_an_open_step_admits_the_opponents_pass_and_no_more() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	var runner := ActionRunner.new(Authority.new(state))

	runner.run(MoveAction.new("f1", Vector3i(1, -1, 0), _template()), "p1")

	var opponent_move := runner.run(MoveAction.new("f2", Vector3i(0, 1, -1), _template()), "p2")
	violations.append_array(
		_expect(
			opponent_move.reason == Authority.REFUSED_NOT_YOUR_TURN,
			(
				"an open Power Step must not let the non-active player Move -- a command naming an "
				+ "actor stays gated to the active player"
			)
		)
	)
	violations.append_array(
		_expect(
			state.board.occupant_at(Vector3i(1, 0, -1)) == &"f2",
			"the refused Move must never have reached resolve(), so the board is unchanged"
		)
	)

	var opponent_pass := runner.run(PowerStepPassAction.new("p2"), "p2")
	violations.append_array(
		_expect(
			opponent_pass.success, "an open Power Step must let the non-active player submit a pass"
		)
	)
	violations.append_array(
		_expect(
			state.power_step_passes() == _record(["p2"]),
			"the permitted pass must have reached resolve() and been recorded"
		)
	)

	return violations


## The closed Step, from both sides. The non-active player is stopped by the
## gate and never reaches `resolve()`; the active player reaches it and is
## turned back by the action's own vocabulary.
static func _test_a_closed_step_refuses_the_opponent_and_fails_the_active_player() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	var runner := ActionRunner.new(Authority.new(state))

	violations.append_array(
		_expect(not state.power_step_open, "this case requires a state with no open Power Step")
	)

	var opponent := runner.run(PowerStepPassAction.new("p2"), "p2")
	violations.append_array(
		_expect(
			opponent.reason == Authority.REFUSED_NOT_YOUR_TURN,
			"with the Power Step closed the non-active player's pass must be refused by the gate"
		)
	)

	var active := runner.run(PowerStepPassAction.new("p1"), "p1")
	violations.append_array(
		_expect(
			active.reason == PowerStepPassAction.FAILURE_STEP_NOT_OPEN,
			(
				"with the Power Step closed the active player's pass must reach resolve() and fail "
				+ "with the action's own FAILURE_STEP_NOT_OPEN"
			)
		)
	)
	violations.append_array(
		_expect(
			active.reason != Authority.REFUSED_NOT_YOUR_TURN,
			"a gate refusal and an action failure must stay distinguishable"
		)
	)

	return violations


## A pass naming a player the state has never heard of, submitted by that same
## stranger. The gate answers first: they are in no turn order, so they are
## entitled to nothing, and `FAILURE_NO_SUCH_PLAYER` is never reached.
static func _test_a_pass_by_a_stranger_is_refused_by_the_gate() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	var runner := ActionRunner.new(Authority.new(state))

	runner.run(MoveAction.new("f1", Vector3i(1, -1, 0), _template()), "p1")

	var result := runner.run(PowerStepPassAction.new("p3"), "p3")

	violations.append_array(
		_expect(
			result.reason == Authority.REFUSED_NOT_YOUR_TURN,
			"a pass from a requester in no turn order must be refused by the gate"
		)
	)
	violations.append_array(
		_expect(
			state.power_step_passes().is_empty(),
			"the refused pass must never have reached resolve(), so nothing is recorded"
		)
	)

	return violations


## Every gate refusal in this suite, each on a state whose digest is taken
## immediately before, each required to leave that digest byte-identical. The
## external proof that `resolve()` was never reached.
static func _test_every_refusal_leaves_the_state_identical() -> Array[String]:
	var violations: Array[String] = []

	var closed := _build_state()
	var closed_runner := ActionRunner.new(Authority.new(closed))
	var closed_digest := closed.digest()
	closed_runner.run(PowerStepPassAction.new("p2"), "p2")
	violations.append_array(
		_expect(
			closed.digest() == closed_digest,
			"a pass refused with the Power Step closed must leave the state digest identical"
		)
	)

	var open_state := _build_state()
	var open_runner := ActionRunner.new(Authority.new(open_state))
	open_runner.run(MoveAction.new("f1", Vector3i(1, -1, 0), _template()), "p1")
	var open_digest := open_state.digest()

	open_runner.run(MoveAction.new("f2", Vector3i(0, 1, -1), _template()), "p2")
	violations.append_array(
		_expect(
			open_state.digest() == open_digest,
			"a Move refused during an open Power Step must leave the state digest identical"
		)
	)

	open_runner.run(PowerStepPassAction.new("p3"), "p3")
	violations.append_array(
		_expect(
			open_state.digest() == open_digest,
			"a pass refused for a requester in no turn order must leave the state digest identical"
		)
	)

	return violations
