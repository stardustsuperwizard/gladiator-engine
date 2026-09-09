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

	violations.append_array(_test_resolve_leaves_turns_taken_unchanged())
	violations.append_array(_test_resolve_leaves_turns_taken_unchanged_across_repeats())
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


static func _test_resolve_leaves_turns_taken_unchanged() -> Array[String]:
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
			state.turns_taken == before,
			"resolve() with a known actor must leave turns_taken exactly as it was"
		)
	)

	return violations


## Three resolutions, no change -- the counter is not this action's to write.
static func _test_resolve_leaves_turns_taken_unchanged_across_repeats() -> Array[String]:
	var state := _build_state()
	var before := state.turns_taken

	for _i in range(3):
		PassAction.new("f1").resolve(state)

	return _expect(
		state.turns_taken == before,
		"three successful resolve() calls must leave turns_taken exactly as it was"
	)


## PassAction's only observable effect is the one every command has:
## `PowerStep.note_action()` on the success path, which opens the Turn's Power
## Step and clears the consecutive-pass record. Nothing else moves.
##
## Asserted by digest, in the shape this case has always used and with one
## addition: take the state's identity before the call, resolve, put back *only*
## the Power Step this action is allowed to have opened, and require the digest
## to match again. Anything else the action touched -- `turns_taken`,
## `round_number`, the board, the generator position, a fighter payload, a
## score -- would still show up as a differing digest.
static func _test_resolve_leaves_the_rest_of_the_state_alone() -> Array[String]:
	var violations: Array[String] = []
	var state := _build_state()
	var before_round := state.round_number
	var before_digest := state.digest()

	PassAction.new("f1").resolve(state)

	violations.append_array(
		_expect(state.round_number == before_round, "resolve() must not touch round_number")
	)
	violations.append_array(
		_expect(state.power_step_open, "a successful resolve() must open the Turn's Power Step")
	)

	state.power_step_open = false

	violations.append_array(
		_expect(
			state.digest() == before_digest,
			(
				"with the Power Step put back, a successful resolve() must leave the state digest "
				+ "byte-identical -- nothing else restored"
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
