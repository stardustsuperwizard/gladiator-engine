## Tests PassAction.resolve() in isolation: called directly, with no gate
## involved and no game-side type named anywhere in this file.
##
## That omission is deliberate rather than an oversight. This suite lives under
## `rules/`, and `rules/` uses no game-side class at all -- not by `res://`
## path and not by global `class_name` -- so the assertion that
## `PassAction.FAILURE_NO_SUCH_FIGHTER` differs from every `Authority.REFUSED_*`
## constant cannot live here. It lives in `tests/authority_test.gd`, which is
## game-side and may name both vocabularies.
class_name PassActionTest


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_resolve_increments_turns_taken())
	violations.append_array(_test_resolve_increments_once_per_call())
	violations.append_array(_test_resolve_leaves_the_rest_of_the_state_alone())
	violations.append_array(_test_missing_actor_fails_with_its_own_constant())
	violations.append_array(_test_missing_actor_changes_nothing())
	violations.append_array(_test_resolve_never_reaches_the_base_failure())
	violations.append_array(_test_is_a_turn_action_carrying_its_actor_id())

	if violations.is_empty():
		return true

	printerr("\n=== Pass Action Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


## A state holding one fighter, "f1". The payload carries an `"owner_id"`
## because that is the shape `Fighter.to_dict()` produces; nothing in
## `PassAction` reads it.
static func _build_state() -> GameState:
	var state := GameState.new(Board.new(), DeterministicRng.new(1))
	state.add_player("p1")
	state.add_fighter("f1", {"id": "f1", "owner_id": "p1"})
	return state


static func _test_resolve_increments_turns_taken() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	var before := state.turns_taken

	var result := PassAction.new("f1").resolve(state)

	violations.append_array(
		_expect(result.success, "resolve() with a known actor must return a successful TurnResult")
	)
	violations.append_array(
		_expect(result.reason == &"", 'a successful PassAction result must have reason == &""')
	)
	violations.append_array(
		_expect(
			state.turns_taken == before + 1,
			"resolve() with a known actor must increment turns_taken by exactly one"
		)
	)

	return violations


## Three resolutions, three increments -- the counter is incremented, not set.
static func _test_resolve_increments_once_per_call() -> Array[String]:
	var state := _build_state()
	var before := state.turns_taken

	for _i in range(3):
		PassAction.new("f1").resolve(state)

	return _expect(
		state.turns_taken == before + 3,
		"three successful resolve() calls must raise turns_taken by exactly three"
	)


## PassAction records a turn and nothing else. Asserted by digest: take the
## state's identity before the call, resolve, put `turns_taken` back by hand,
## and require the digest to match again. Anything else the action touched --
## `round_number`, the board, the generator position, a fighter payload, a
## score -- would show up as a differing digest.
static func _test_resolve_leaves_the_rest_of_the_state_alone() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	var before_round := state.round_number
	var before_turns := state.turns_taken
	var before_digest := state.digest()

	PassAction.new("f1").resolve(state)

	violations.append_array(
		_expect(state.round_number == before_round, "resolve() must not touch round_number")
	)

	state.turns_taken = before_turns
	violations.append_array(
		_expect(
			state.digest() == before_digest,
			(
				"with turns_taken restored the digest must match: resolve() must change nothing "
				+ "in the state but the turn counter"
			)
		)
	)

	return violations


static func _test_missing_actor_fails_with_its_own_constant() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()

	var result := PassAction.new("no_such_fighter").resolve(state)

	violations.append_array(
		_expect(not result.success, "resolve() with an unknown actor must be unsuccessful")
	)
	violations.append_array(
		_expect(
			result.reason == PassAction.FAILURE_NO_SUCH_FIGHTER,
			"resolve() with an unknown actor must fail with PassAction.FAILURE_NO_SUCH_FIGHTER"
		)
	)

	return violations


static func _test_missing_actor_changes_nothing() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	var before_turns := state.turns_taken
	var before_digest := state.digest()

	PassAction.new("no_such_fighter").resolve(state)

	violations.append_array(
		_expect(
			state.turns_taken == before_turns, "a failed resolve() must leave turns_taken unchanged"
		)
	)
	violations.append_array(
		_expect(
			state.digest() == before_digest,
			"a failed resolve() must leave the state digest identical"
		)
	)

	return violations


## Neither path may fall through to the base class's placeholder failure.
static func _test_resolve_never_reaches_the_base_failure() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()

	var permitted := PassAction.new("f1").resolve(state)
	violations.append_array(
		_expect(
			permitted.reason != TurnAction.FAILURE_NOT_IMPLEMENTED,
			"a successful PassAction must not return the base's FAILURE_NOT_IMPLEMENTED"
		)
	)

	var missing := PassAction.new("no_such_fighter").resolve(state)
	violations.append_array(
		_expect(
			missing.reason != TurnAction.FAILURE_NOT_IMPLEMENTED,
			"a failed PassAction must not return the base's FAILURE_NOT_IMPLEMENTED"
		)
	)

	return violations


static func _test_is_a_turn_action_carrying_its_actor_id() -> Array[String]:
	var violations: Array[String] = []
	var action := PassAction.new("f1")

	violations.append_array(_expect(action is TurnAction, "PassAction must be a TurnAction"))
	violations.append_array(
		_expect(
			action.actor_id() == "f1", "PassAction must report the actor id it was constructed with"
		)
	)

	return violations
