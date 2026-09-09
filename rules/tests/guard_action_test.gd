## Tests GuardAction.resolve() in isolation: called directly, with no gate
## involved and no game-side type named anywhere in this file.
##
## That omission is deliberate, matching move_action_test.gd's own docstring:
## this suite lives under `rules/`, which names no game-side class at all --
## not by `res://` path and not by global `class_name`. The Authority gate
## case for a Guard lives in `tests/action_runner_test.gd`.
##
## Every fixture `FighterTemplate` here is built in memory --
## `extraction_contract_test.gd` forbids naming a `res://resources/` path
## under `rules/` -- though `GuardAction` reads no stat off it at all: the
## template exists only so `Fighter.from_dict()` has one to parse with.
class_name GuardActionTest


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_legal_guard_sets_the_flag_and_persists_through_state())
	violations.append_array(_test_legal_guard_changes_nothing_else())
	violations.append_array(_test_repeat_guard_is_idempotent())
	violations.append_array(_test_no_such_fighter_is_refused())
	violations.append_array(_test_null_template_is_refused())
	violations.append_array(_test_unparseable_payload_is_refused())
	violations.append_array(_test_rng_is_untouched_by_a_successful_guard())
	violations.append_array(_test_rng_is_untouched_by_a_refused_guard())

	if violations.is_empty():
		return true

	printerr("\n=== Guard Action Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


# --- Fixtures -----------------------------------------------------------


## A minimal fighter template -- GuardAction reads no stat off it.
static func _fighter_template() -> FighterTemplate:
	var template := FighterTemplate.new()
	template.template_id = "guard-fixture-fighter"
	return template


static func _build_state() -> GameState:
	var state := GameState.new(Board.new(), DeterministicRng.new(7))
	state.add_player("p1")
	state.add_player("p2")
	return state


## Records a fighter both ways the engine tracks one: an opaque payload in
## `GameState` and an occupant on the board.
static func _place(
	state: GameState,
	fighter_id: String,
	owner_id: String,
	coord: Vector3i,
	template: FighterTemplate
) -> void:
	var fighter := Fighter.new(fighter_id, template, owner_id, coord)
	state.add_fighter(fighter_id, fighter.to_dict())
	state.board.add_hex(coord, Board.HexType.NORMAL)
	state.board.place_occupant(coord, StringName(fighter_id))


static func _stored_fighter(
	state: GameState, fighter_id: String, template: FighterTemplate
) -> Fighter:
	return Fighter.from_dict(state.fighter(fighter_id), template)


# --- Legal Guard ------------------------------------------------------------


static func _test_legal_guard_sets_the_flag_and_persists_through_state() -> Array[String]:
	var violations: Array[String] = []
	var origin := Vector3i(0, 0, 0)
	var template := _fighter_template()
	var state := _build_state()
	_place(state, "a1", "p1", origin, template)

	var action := GuardAction.new("a1", template)
	var result := action.resolve(state)

	violations.append_array(_expect(result.success, "a legal Guard must return TurnResult.ok()"))
	violations.append_array(
		_expect(result.reason == &"", 'a successful Guard result must have reason == &""')
	)

	var stored := _stored_fighter(state, "a1", template)
	violations.append_array(
		_expect(
			stored != null and stored.has_status_flag(GuardAction.FLAG_GUARDED),
			(
				"Fighter.from_dict(state.fighter(id), template).has_status_flag"
				+ "(GuardAction.FLAG_GUARDED) must be true after a legal Guard"
			)
		)
	)

	var restored := GameState.from_dict(state.to_dict())
	violations.append_array(
		_expect(restored != null, "the state after a legal Guard must round-trip through GameState")
	)
	if restored == null:
		return violations

	var restored_fighter := _stored_fighter(restored, "a1", template)
	(
		violations
		. append_array(
			_expect(
				(
					restored_fighter != null
					and restored_fighter.has_status_flag(GuardAction.FLAG_GUARDED)
				),
				"the round-tripped fighter must still have has_status_flag(GuardAction.FLAG_GUARDED) == true"
			)
		)
	)

	return violations


## A successful Guard changes nothing beyond the flag: position, board
## occupancy, damage_counter, turns_taken and round_number are all unchanged,
## and it gains no "moved" flag.
static func _test_legal_guard_changes_nothing_else() -> Array[String]:
	var violations: Array[String] = []
	var origin := Vector3i(0, 0, 0)
	var template := _fighter_template()
	var state := _build_state()
	_place(state, "a1", "p1", origin, template)
	var before_turns := state.turns_taken
	var before_round := state.round_number

	GuardAction.new("a1", template).resolve(state)

	var stored := _stored_fighter(state, "a1", template)
	violations.append_array(
		_expect(stored != null, "the fighter must still parse after a legal Guard")
	)
	if stored == null:
		return violations

	violations.append_array(
		_expect(stored.position() == origin, "a legal Guard must not move the fighter")
	)
	violations.append_array(
		_expect(
			state.board.occupant_at(origin) == StringName("a1"),
			"a legal Guard must leave the fighter as the occupant of its own hex"
		)
	)
	violations.append_array(
		_expect(stored.damage_counter() == 0, "a legal Guard must not change the damage_counter")
	)
	violations.append_array(
		_expect(state.turns_taken == before_turns, "a legal Guard must not touch turns_taken")
	)
	violations.append_array(
		_expect(state.round_number == before_round, "a legal Guard must not touch round_number")
	)
	violations.append_array(
		_expect(
			not stored.has_status_flag(MoveAction.FLAG_MOVED),
			'a legal Guard must not set the "moved" flag'
		)
	)

	return violations


## A second Guard on an already-guarded fighter resolves and leaves the state
## digest byte-identical -- `Fighter.set_status_flag()` already returns
## `false` for a flag it holds, and the committed payload is identical.
static func _test_repeat_guard_is_idempotent() -> Array[String]:
	var violations: Array[String] = []
	var origin := Vector3i(0, 0, 0)
	var template := _fighter_template()
	var state := _build_state()
	_place(state, "a1", "p1", origin, template)

	GuardAction.new("a1", template).resolve(state)
	var before := state.digest()

	var result := GuardAction.new("a1", template).resolve(state)

	violations.append_array(
		_expect(
			result.success, "a repeat Guard on an already-guarded fighter must resolve, not refuse"
		)
	)
	violations.append_array(
		_expect(
			state.digest() == before,
			"a repeat Guard on an already-guarded fighter must leave the state digest identical"
		)
	)

	return violations


# --- Refusals ----------------------------------------------------------


static func _test_no_such_fighter_is_refused() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template()
	var state := _build_state()
	var before := state.digest()

	var result := GuardAction.new("ghost", template).resolve(state)

	violations.append_array(
		_expect(
			result.reason == GuardAction.FAILURE_NO_SUCH_FIGHTER,
			"a Guard naming no fighter in the state must be refused with FAILURE_NO_SUCH_FIGHTER"
		)
	)
	violations.append_array(_expect(not result.success, "the refusal must not crash resolve()"))
	violations.append_array(
		_expect(state.digest() == before, "a refused Guard must leave the state digest identical")
	)

	return violations


static func _test_null_template_is_refused() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template()
	var state := _build_state()
	_place(state, "a1", "p1", Vector3i(0, 0, 0), template)
	var before := state.digest()

	var result := GuardAction.new("a1", null).resolve(state)

	violations.append_array(
		_expect(
			result.reason == GuardAction.FAILURE_MISSING_DATA,
			"a Guard constructed with a null template must be refused with FAILURE_MISSING_DATA"
		)
	)
	violations.append_array(_expect(not result.success, "the refusal must not crash resolve()"))
	violations.append_array(
		_expect(state.digest() == before, "a refused Guard must leave the state digest identical")
	)

	return violations


## A fighter whose stored payload will not parse -- here, a "position" that is
## not a valid coordinate -- is FAILURE_MISSING_DATA, not a crash.
static func _test_unparseable_payload_is_refused() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template()
	var state := _build_state()
	state.add_fighter("a1", {"id": "a1", "owner_id": "p1", "position": "not-a-coordinate"})
	var before := state.digest()

	var result := GuardAction.new("a1", template).resolve(state)

	violations.append_array(
		_expect(
			result.reason == GuardAction.FAILURE_MISSING_DATA,
			(
				"a Guard naming a fighter whose payload will not parse "
				+ "must be refused with FAILURE_MISSING_DATA"
			)
		)
	)
	violations.append_array(_expect(not result.success, "the refusal must not crash resolve()"))
	violations.append_array(
		_expect(state.digest() == before, "a refused Guard must leave the state digest identical")
	)

	return violations


# --- RNG -----------------------------------------------------------------


static func _test_rng_is_untouched_by_a_successful_guard() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template()
	var state := _build_state()
	_place(state, "a1", "p1", Vector3i(0, 0, 0), template)
	var before_state := state.rng.get_state()
	var before_seed := state.rng.get_seed()

	var result := GuardAction.new("a1", template).resolve(state)

	violations.append_array(
		_expect(result.success, "this scenario must resolve for it to test anything")
	)
	violations.append_array(
		_expect(
			state.rng.get_state() == before_state,
			"a successful Guard must not advance the generator's state"
		)
	)
	violations.append_array(
		_expect(
			state.rng.get_seed() == before_seed,
			"a successful Guard must not change the generator's seed"
		)
	)

	return violations


static func _test_rng_is_untouched_by_a_refused_guard() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template()
	var state := _build_state()
	var before_state := state.rng.get_state()
	var before_seed := state.rng.get_seed()

	var result := GuardAction.new("ghost", template).resolve(state)

	violations.append_array(
		_expect(not result.success, "this scenario must be refused for it to test anything")
	)
	violations.append_array(
		_expect(
			state.rng.get_state() == before_state,
			"a refused Guard must not advance the generator's state"
		)
	)
	violations.append_array(
		_expect(
			state.rng.get_seed() == before_seed,
			"a refused Guard must not change the generator's seed"
		)
	)

	return violations
