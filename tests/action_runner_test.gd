## Tests the gate: a refused request never reaches `resolve()`, and a permitted
## one does.
##
## "Never reaches `resolve()`" is asserted two independent ways, because it is
## the single property the whole command pipeline rests on. Externally, by
## `GameState.digest()` -- a refused `PassAction` leaves the state
## byte-identical. Internally, by a spy `TurnAction` declared in this file that
## counts its own `resolve()` calls, which catches a resolve that ran and
## happened to change nothing.
##
## Lives under `tests/` rather than `rules/tests/`: `ActionRunner` and
## `Authority` are `res://scripts/` code, which
## `rules/tests/extraction_contract_test.gd` fails the build over.
class_name ActionRunnerTest


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_permitted_pass_resolves())
	violations.append_array(_test_refused_request_returns_the_refusal())
	violations.append_array(_test_every_refusal_leaves_the_state_identical())
	violations.append_array(_test_refused_request_never_calls_resolve())
	violations.append_array(_test_permitted_request_calls_resolve_exactly_once())
	violations.append_array(_test_resolve_receives_the_authoritys_state())
	violations.append_array(_test_action_failure_is_passed_through_unmodified())
	violations.append_array(_test_run_reason_matches_refusal())

	if violations.is_empty():
		return true

	printerr("\n=== Action Runner Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


static func _build_state() -> GameState:
	var state := GameState.new(Board.new(), DeterministicRng.new(1))
	state.add_player("p1")
	state.add_player("p2")
	state.add_fighter("f1", {"id": "f1", "owner_id": "p1"})
	state.add_fighter("f2", {"id": "f2", "owner_id": "p2"})
	return state


## Records whether and how often `resolve()` ran, and what state it was handed.
## The direct evidence for the property the digest can only infer.
class _SpyAction:
	extends TurnAction
	const FAILURE_SPY := &"action_runner_test_spy_failure"

	var resolve_calls: int = 0
	var seen_state: GameState = null
	var succeed: bool = true

	func resolve(state: GameState) -> TurnResult:
		resolve_calls += 1
		seen_state = state
		return TurnResult.ok() if succeed else TurnResult.failure(FAILURE_SPY)


static func _test_permitted_pass_resolves() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	var runner := ActionRunner.new(Authority.new(state))
	var before := state.turns_taken

	var result := runner.run(PassAction.new("f1"), "p1")

	violations.append_array(
		_expect(
			result.success, "run() on a permitted PassAction must return a successful TurnResult"
		)
	)
	violations.append_array(
		_expect(result.reason == &"", 'a successful run() result must have reason == &""')
	)
	violations.append_array(
		_expect(
			state.turns_taken == before + 1,
			"run() on a permitted PassAction must raise turns_taken by exactly one"
		)
	)

	return violations


static func _test_refused_request_returns_the_refusal() -> Array[String]:
	var violations: Array[String] = []
	var runner := ActionRunner.new(Authority.new(_build_state()))

	var result := runner.run(PassAction.new("f2"), "p2")

	violations.append_array(
		_expect(not result.success, "run() on a refused request must return success == false")
	)
	violations.append_array(
		_expect(
			result.reason == Authority.REFUSED_NOT_YOUR_TURN,
			"run() must carry the exact Authority refusal constant as the result's reason"
		)
	)

	return violations


## All four refusals, each on a fresh state, each required to leave
## `turns_taken` and the digest exactly as they were. The digest is the
## external proof that `resolve()` never ran.
static func _test_every_refusal_leaves_the_state_identical() -> Array[String]:
	var violations: Array[String] = []

	var cases := [
		["f2", "p2", Authority.REFUSED_NOT_YOUR_TURN],
		["f2", "p1", Authority.REFUSED_NOT_YOUR_FIGHTER],
		["no_such_fighter", "p1", Authority.REFUSED_NO_SUCH_FIGHTER],
	]

	for entry in cases:
		var actor: String = entry[0]
		var requester: String = entry[1]
		var expected: StringName = entry[2]

		var state := _build_state()
		var runner := ActionRunner.new(Authority.new(state))
		var before_turns := state.turns_taken
		var before_digest := state.digest()

		var result := runner.run(PassAction.new(actor), requester)

		violations.append_array(
			_expect(
				result.reason == expected,
				"run(%s, %s) must be refused with %s" % [actor, requester, expected]
			)
		)
		violations.append_array(
			_expect(
				state.turns_taken == before_turns,
				"a refused run(%s, %s) must leave turns_taken unchanged" % [actor, requester]
			)
		)
		violations.append_array(
			_expect(
				state.digest() == before_digest,
				"a refused run(%s, %s) must leave the state digest identical" % [actor, requester]
			)
		)

	# The no-active-player branch needs a state with no turn order at all.
	var empty := GameState.new(Board.new(), DeterministicRng.new(1))
	empty.add_fighter("f1", {"id": "f1", "owner_id": "p1"})
	var empty_runner := ActionRunner.new(Authority.new(empty))
	var empty_digest := empty.digest()

	var empty_result := empty_runner.run(PassAction.new("f1"), "p1")
	violations.append_array(
		_expect(
			empty_result.reason == Authority.REFUSED_NO_ACTIVE_PLAYER,
			"run() against a state with no players must be refused with REFUSED_NO_ACTIVE_PLAYER"
		)
	)
	violations.append_array(
		_expect(
			empty.digest() == empty_digest,
			"a run() refused for no active player must leave the state digest identical"
		)
	)

	return violations


## The direct assertion. A refused request must not call `resolve()` at all --
## not called and discarded, not called behind a flag, not called.
static func _test_refused_request_never_calls_resolve() -> Array[String]:
	var violations: Array[String] = []
	var runner := ActionRunner.new(Authority.new(_build_state()))

	var wrong_turn := _SpyAction.new("f2")
	runner.run(wrong_turn, "p2")
	violations.append_array(
		_expect(wrong_turn.resolve_calls == 0, "a wrong-turn refusal must not call resolve()")
	)

	var wrong_owner := _SpyAction.new("f2")
	runner.run(wrong_owner, "p1")
	violations.append_array(
		_expect(wrong_owner.resolve_calls == 0, "a wrong-owner refusal must not call resolve()")
	)

	var unknown_actor := _SpyAction.new("no_such_fighter")
	runner.run(unknown_actor, "p1")
	violations.append_array(
		_expect(
			unknown_actor.resolve_calls == 0, "an unknown-actor refusal must not call resolve()"
		)
	)

	var empty := GameState.new(Board.new(), DeterministicRng.new(1))
	empty.add_fighter("f1", {"id": "f1", "owner_id": "p1"})
	var no_active := _SpyAction.new("f1")
	ActionRunner.new(Authority.new(empty)).run(no_active, "p1")
	violations.append_array(
		_expect(no_active.resolve_calls == 0, "a no-active-player refusal must not call resolve()")
	)

	return violations


static func _test_permitted_request_calls_resolve_exactly_once() -> Array[String]:
	var violations: Array[String] = []
	var runner := ActionRunner.new(Authority.new(_build_state()))
	var spy := _SpyAction.new("f1")

	var result := runner.run(spy, "p1")

	violations.append_array(
		_expect(spy.resolve_calls == 1, "a permitted request must call resolve() exactly once")
	)
	violations.append_array(
		_expect(result.success, "run() must return the spy's successful TurnResult")
	)

	return violations


## The runner keeps no `GameState` of its own; it reads the one the gate
## validated against back off `Authority.state()`.
static func _test_resolve_receives_the_authoritys_state() -> Array[String]:
	var state := _build_state()
	var authority := Authority.new(state)
	var spy := _SpyAction.new("f1")

	ActionRunner.new(authority).run(spy, "p1")

	return _expect(
		is_same(spy.seen_state, state) and is_same(spy.seen_state, authority.state()),
		"resolve() must be handed the very state the Authority holds, not a copy or a second reference"
	)


## A permitted action that fails on its own terms reaches the caller carrying
## its own `FAILURE_*` constant. The runner unwraps nothing and substitutes
## nothing, so a caller can always tell a refusal from a failed resolution.
static func _test_action_failure_is_passed_through_unmodified() -> Array[String]:
	var violations: Array[String] = []
	var runner := ActionRunner.new(Authority.new(_build_state()))
	var spy := _SpyAction.new("f1")
	spy.succeed = false

	var result := runner.run(spy, "p1")

	violations.append_array(
		_expect(spy.resolve_calls == 1, "the permitted failing action must still have resolved")
	)
	violations.append_array(
		_expect(not result.success, "a failed resolution must reach the caller as success == false")
	)
	violations.append_array(
		_expect(
			result.reason == _SpyAction.FAILURE_SPY,
			"run() must return the action's own failure reason, unmodified"
		)
	)

	return violations


## The reason `run()` reports is the reason `refusal()` produced for the same
## request -- not a reason of the runner's own invention.
static func _test_run_reason_matches_refusal() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	state.add_fighter("ownerless", {"id": "ownerless"})
	var authority := Authority.new(state)
	var runner := ActionRunner.new(authority)

	var requests := [
		["f2", "p2"],
		["f2", "p1"],
		["ownerless", "p1"],
		["no_such_fighter", "p1"],
	]

	for request in requests:
		var actor: String = request[0]
		var requester: String = request[1]
		var expected := authority.refusal(PassAction.new(actor), requester)
		var result := runner.run(PassAction.new(actor), requester)

		violations.append_array(
			_expect(
				result.reason == expected,
				"run(%s, %s) must report exactly the reason refusal() gives" % [actor, requester]
			)
		)

	return violations
