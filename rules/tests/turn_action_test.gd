## Tests TurnResult and TurnAction: the two constructors on TurnResult, the
## base TurnAction's actor_id() and its FAILURE_NOT_IMPLEMENTED resolve(), and
## that a subclass overriding resolve() returns its own result rather than the
## base's failure.
class_name TurnActionTest


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_ok_is_successful_with_empty_reason())
	violations.append_array(_test_failure_carries_its_reason())
	violations.append_array(_test_actor_id_returns_the_constructed_id())
	violations.append_array(_test_base_resolve_returns_not_implemented())
	violations.append_array(_test_subclass_resolve_overrides_the_base())

	if violations.is_empty():
		return true

	printerr("\n=== Turn Action Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


static func _build_state() -> GameState:
	return GameState.new(Board.new(), DeterministicRng.new(1))


static func _test_ok_is_successful_with_empty_reason() -> Array[String]:
	var violations: Array[String] = []
	var result := TurnResult.ok()

	violations.append_array(_expect(result.success, "TurnResult.ok() must have success == true"))
	violations.append_array(
		_expect(result.reason == &"", 'TurnResult.ok() must have reason == &""')
	)

	return violations


static func _test_failure_carries_its_reason() -> Array[String]:
	var violations: Array[String] = []
	var result := TurnResult.failure(&"some_reason")

	violations.append_array(
		_expect(not result.success, "TurnResult.failure() must have success == false")
	)
	violations.append_array(
		_expect(
			result.reason == &"some_reason",
			"TurnResult.failure() must carry the reason it was given"
		)
	)

	return violations


static func _test_actor_id_returns_the_constructed_id() -> Array[String]:
	var action := TurnAction.new("fighter_1")
	return _expect(
		action.actor_id() == "fighter_1",
		"actor_id() must return the id the action was constructed with"
	)


static func _test_base_resolve_returns_not_implemented() -> Array[String]:
	var violations: Array[String] = []
	var action := TurnAction.new("fighter_1")
	var result := action.resolve(_build_state())

	violations.append_array(
		_expect(not result.success, "the base TurnAction.resolve() must be unsuccessful")
	)
	violations.append_array(
		_expect(
			result.reason == TurnAction.FAILURE_NOT_IMPLEMENTED,
			"the base TurnAction.resolve() must fail with FAILURE_NOT_IMPLEMENTED"
		)
	)

	return violations


## A minimal subclass with its own FAILURE_* block, exercising the contract
## the class docstring states: one subclass per command, resolve() overridden,
## the base's FAILURE_NOT_IMPLEMENTED never reached.
class _AlwaysSucceedsAction:
	extends TurnAction
	const FAILURE_NEVER := &"turn_action_test_never"

	func resolve(_state: GameState) -> TurnResult:
		return TurnResult.ok()


static func _test_subclass_resolve_overrides_the_base() -> Array[String]:
	var violations: Array[String] = []
	var action := _AlwaysSucceedsAction.new("fighter_1")
	var result := action.resolve(_build_state())

	violations.append_array(
		_expect(result.success, "a subclass overriding resolve() must return its own TurnResult")
	)
	violations.append_array(
		_expect(
			result.reason != TurnAction.FAILURE_NOT_IMPLEMENTED,
			"a subclass overriding resolve() must not reach the base's FAILURE_NOT_IMPLEMENTED"
		)
	)

	return violations
