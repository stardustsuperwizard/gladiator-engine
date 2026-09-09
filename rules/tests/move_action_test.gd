## Tests MoveAction.resolve() in isolation: called directly, with no gate
## involved and no game-side type named anywhere in this file.
##
## That omission is deliberate, matching pass_action_test.gd and
## attack_action_test.gd: this suite lives under `rules/`, which names no
## game-side class at all -- not by `res://` path and not by global
## `class_name`. The Authority gate case for a Move lives in
## `tests/action_runner_test.gd`.
##
## Every fixture `FighterTemplate` here is built in memory with only the `move`
## stat set to a number this suite chose -- `extraction_contract_test.gd`
## forbids naming a `res://resources/` path under `rules/`, and no other stat
## is read by `MoveAction`.
##
## **The search-versus-distance fixtures prove their own claims.** A hex whose
## straight-line `HexCoord.distance()` is within `move()` can still be absent
## from `Board.reachable_from()` when the direct route is blocked or occupied,
## or when the only route is a longer detour -- see `Board.reachable_from()`'s
## own docstring. The blocked, occupied and detour fixtures below reuse
## `rules/tests/reachability_test.gd`'s own geometry for those same claims and
## assert the property each depends on explicitly, so a fixture that
## accidentally tests an ordinary too-far refusal instead cannot pass silently.
class_name MoveActionTest


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_legal_move_updates_position_and_board_occupancy())
	violations.append_array(_test_moved_flag_and_position_persist_through_state_round_trip())
	violations.append_array(_test_destination_further_than_move_is_refused())
	violations.append_array(_test_blocked_path_within_move_is_refused())
	violations.append_array(_test_occupied_path_within_move_is_refused())
	violations.append_array(_test_detour_longer_than_move_is_refused())
	violations.append_array(_test_destination_is_origin_is_refused())
	violations.append_array(_test_no_such_fighter_is_refused())
	violations.append_array(_test_null_template_is_refused())
	violations.append_array(_test_rng_is_untouched_by_a_successful_move())
	violations.append_array(_test_rng_is_untouched_by_a_refused_move())
	violations.append_array(_test_turns_and_round_unchanged_after_a_successful_move())

	if violations.is_empty():
		return true

	printerr("\n=== Move Action Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


# --- Fixtures -----------------------------------------------------------


## A fighter template with only `move` set -- the one stat `MoveAction` reads.
static func _fighter_template(move: int) -> FighterTemplate:
	var template := FighterTemplate.new()
	template.template_id = "move-fixture-fighter"
	template.move = move
	return template


## A hexagonal board of `radius` rings around the origin, every hex NORMAL
## except the coordinates listed in `blocked`. Off-board is already blocked by
## `Board.is_blocked()`, so a narrow radius plus a short `blocked` list is
## enough to force a long detour.
static func _hex_board(radius: int, blocked: Array[Vector3i] = []) -> Board:
	var board := Board.new()

	for x in range(-radius, radius + 1):
		var low := maxi(-radius, -x - radius)
		var high := mini(radius, -x + radius)
		for y in range(low, high + 1):
			var coord := Vector3i(x, y, -x - y)
			board.add_hex(
				coord, Board.HexType.BLOCKED if coord in blocked else Board.HexType.NORMAL
			)

	return board


static func _build_state(radius: int, blocked: Array[Vector3i] = []) -> GameState:
	var state := GameState.new(_hex_board(radius, blocked), DeterministicRng.new(7))
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
	state.board.place_occupant(coord, StringName(fighter_id))


static func _stored_fighter(
	state: GameState, fighter_id: String, template: FighterTemplate
) -> Fighter:
	return Fighter.from_dict(state.fighter(fighter_id), template)


# --- Legal Move -----------------------------------------------------------


static func _test_legal_move_updates_position_and_board_occupancy() -> Array[String]:
	var violations: Array[String] = []
	var origin := Vector3i(0, 0, 0)
	var destination := Vector3i(1, -1, 0)
	var template := _fighter_template(1)
	var state := _build_state(3)
	_place(state, "a1", "p1", origin, template)

	var action := MoveAction.new("a1", destination, template)
	var result := action.resolve(state)

	violations.append_array(_expect(result.success, "a legal Move must return TurnResult.ok()"))
	violations.append_array(
		_expect(result.reason == &"", 'a successful Move result must have reason == &""')
	)
	violations.append_array(
		_expect(
			state.board.occupant_at(origin) == Board.EMPTY_OCCUPANT,
			"a legal Move must free the origin hex"
		)
	)
	violations.append_array(
		_expect(
			state.board.occupant_at(destination) == StringName("a1"),
			"a legal Move must record the actor as the occupant of the destination"
		)
	)

	var stored := _stored_fighter(state, "a1", template)
	violations.append_array(
		_expect(
			stored != null and stored.position() == destination,
			"the stored payload's position() must be the destination after a legal Move"
		)
	)

	return violations


## The moved position and the "moved" flag both survive a full GameState
## to_dict()/from_dict() round trip, not merely a read of the live state.
static func _test_moved_flag_and_position_persist_through_state_round_trip() -> Array[String]:
	var violations: Array[String] = []
	var origin := Vector3i(0, 0, 0)
	var destination := Vector3i(1, -1, 0)
	var template := _fighter_template(1)
	var state := _build_state(3)
	_place(state, "a1", "p1", origin, template)

	MoveAction.new("a1", destination, template).resolve(state)

	var restored := GameState.from_dict(state.to_dict())
	violations.append_array(
		_expect(restored != null, "the state after a legal Move must round-trip through GameState")
	)
	if restored == null:
		return violations

	var stored := _stored_fighter(restored, "a1", template)
	violations.append_array(
		_expect(stored != null, "the round-tripped fighter payload must still parse")
	)
	if stored == null:
		return violations

	violations.append_array(
		_expect(
			stored.position() == destination,
			"the round-tripped fighter must report the destination as its position()"
		)
	)
	violations.append_array(
		_expect(
			stored.has_status_flag(MoveAction.FLAG_MOVED),
			"the round-tripped fighter must have has_status_flag(MoveAction.FLAG_MOVED) == true"
		)
	)

	return violations


# --- Refusals: plainly too far ---------------------------------------------


static func _test_destination_further_than_move_is_refused() -> Array[String]:
	var violations: Array[String] = []
	var origin := Vector3i(0, 0, 0)
	var destination := Vector3i(2, -2, 0)
	var template := _fighter_template(1)
	var state := _build_state(3)
	_place(state, "a1", "p1", origin, template)
	var before := state.digest()

	violations.append_array(
		_expect(
			HexCoord.distance(origin, destination) > template.move,
			"this scenario must place the destination further than move() for it to test anything"
		)
	)

	var result := MoveAction.new("a1", destination, template).resolve(state)

	violations.append_array(
		_expect(
			result.reason == MoveAction.FAILURE_DESTINATION_UNREACHABLE,
			"a destination further than move() must be refused with FAILURE_DESTINATION_UNREACHABLE"
		)
	)
	violations.append_array(
		_expect(not result.success, "a refused Move must return success == false")
	)
	violations.append_array(
		_expect(state.digest() == before, "a refused Move must leave the state digest identical")
	)

	return violations


# --- Refusals: search versus distance --------------------------------------


## Straight-line distance 2, within move() == 2, but the single midpoint
## between origin and destination -- the only route between them -- is
## BLOCKED. Same geometry `reachability_test.gd` uses for the identical claim
## against `Board.reachable_from()` directly.
static func _test_blocked_path_within_move_is_refused() -> Array[String]:
	var violations: Array[String] = []
	var origin := Vector3i(0, 0, 0)
	var midpoint := Vector3i(1, -1, 0)
	var destination := Vector3i(2, -2, 0)
	var template := _fighter_template(2)
	var state := _build_state(3, [midpoint] as Array[Vector3i])
	_place(state, "a1", "p1", origin, template)
	var before := state.digest()

	violations.append_array(
		_expect(
			HexCoord.distance(origin, destination) <= template.move,
			(
				"this scenario must stand the destination within move() by straight-line distance "
				+ "for the refusal to be about the path, not about range"
			)
		)
	)

	var result := MoveAction.new("a1", destination, template).resolve(state)

	(
		violations
		. append_array(
			_expect(
				result.reason == MoveAction.FAILURE_DESTINATION_UNREACHABLE,
				"a destination behind a BLOCKED hex must be refused with FAILURE_DESTINATION_UNREACHABLE"
			)
		)
	)
	violations.append_array(
		_expect(state.digest() == before, "a refused Move must leave the state digest identical")
	)

	return violations


## Identical geometry to the BLOCKED case above, but the intervening hex is
## occupied by another fighter rather than BLOCKED terrain.
static func _test_occupied_path_within_move_is_refused() -> Array[String]:
	var violations: Array[String] = []
	var origin := Vector3i(0, 0, 0)
	var midpoint := Vector3i(1, -1, 0)
	var destination := Vector3i(2, -2, 0)
	var template := _fighter_template(2)
	var state := _build_state(3)
	_place(state, "a1", "p1", origin, template)
	_place(state, "blocker", "p2", midpoint, template)
	var before := state.digest()

	violations.append_array(
		_expect(
			HexCoord.distance(origin, destination) <= template.move,
			(
				"this scenario must stand the destination within move() by straight-line distance "
				+ "for the refusal to be about the path, not about range"
			)
		)
	)

	var result := MoveAction.new("a1", destination, template).resolve(state)

	(
		violations
		. append_array(
			_expect(
				result.reason == MoveAction.FAILURE_DESTINATION_UNREACHABLE,
				"a destination behind an occupied hex must be refused with FAILURE_DESTINATION_UNREACHABLE"
			)
		)
	)
	violations.append_array(
		_expect(state.digest() == before, "a refused Move must leave the state digest identical")
	)

	return violations


## Every neighbour of origin but one is BLOCKED, forcing a 3-step detour to a
## hex whose straight-line distance is only 2. Same geometry
## `reachability_test.gd` uses for the identical claim against
## `Board.reachable_from()` directly. `move()` is 2, so the direct route is
## refused, but the destination is present in `reachable_from(origin, 3)`: the
## route exists, it is just longer than `move()`.
static func _test_detour_longer_than_move_is_refused() -> Array[String]:
	var violations: Array[String] = []
	var origin := Vector3i(0, 0, 0)
	var blocked_neighbours := (
		[
			Vector3i(1, -1, 0),
			Vector3i(1, 0, -1),
			Vector3i(-1, 1, 0),
			Vector3i(-1, 0, 1),
			Vector3i(0, -1, 1),
		]
		as Array[Vector3i]
	)
	var destination := Vector3i(2, 0, -2)
	var template := _fighter_template(2)
	var state := _build_state(3, blocked_neighbours)
	_place(state, "a1", "p1", origin, template)
	var before := state.digest()

	(
		violations
		. append_array(
			_expect(
				HexCoord.distance(origin, destination) <= template.move,
				(
					"this scenario's destination must be within move() by straight-line distance for it "
					+ "to be a detour rather than an ordinary too-far case"
				)
			)
		)
	)
	(
		violations
		. append_array(
			_expect(
				destination not in state.board.reachable_from(origin, template.move),
				"the destination must be absent from reachable_from(origin, move()) for this to be a detour"
			)
		)
	)
	(
		violations
		. append_array(
			_expect(
				destination in state.board.reachable_from(origin, template.move + 1),
				(
					"the destination must be present in reachable_from() at a larger step count, proving "
					+ "the fixture is a detour rather than walled off entirely"
				)
			)
		)
	)

	var result := MoveAction.new("a1", destination, template).resolve(state)

	violations.append_array(
		_expect(
			result.reason == MoveAction.FAILURE_DESTINATION_UNREACHABLE,
			(
				"a destination reachable only by a longer detour must be refused with "
				+ "FAILURE_DESTINATION_UNREACHABLE"
			)
		)
	)
	violations.append_array(
		_expect(state.digest() == before, "a refused Move must leave the state digest identical")
	)

	return violations


# --- Refusals: identity ----------------------------------------------------


static func _test_destination_is_origin_is_refused() -> Array[String]:
	var violations: Array[String] = []
	var origin := Vector3i(0, 0, 0)
	var template := _fighter_template(1)
	var state := _build_state(3)
	_place(state, "a1", "p1", origin, template)
	var before := state.digest()

	var result := MoveAction.new("a1", origin, template).resolve(state)

	violations.append_array(
		_expect(
			result.reason == MoveAction.FAILURE_DESTINATION_IS_ORIGIN,
			"a Move to the fighter's own hex must be refused with FAILURE_DESTINATION_IS_ORIGIN"
		)
	)
	violations.append_array(
		_expect(state.digest() == before, "a refused Move must leave the state digest identical")
	)

	var stored := _stored_fighter(state, "a1", template)
	violations.append_array(
		_expect(
			stored != null and not stored.has_status_flag(MoveAction.FLAG_MOVED),
			'a Move refused as FAILURE_DESTINATION_IS_ORIGIN must not set the "moved" flag'
		)
	)

	return violations


static func _test_no_such_fighter_is_refused() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(1)
	var state := _build_state(3)
	var before := state.digest()

	var result := MoveAction.new("ghost", Vector3i(1, -1, 0), template).resolve(state)

	violations.append_array(
		_expect(
			result.reason == MoveAction.FAILURE_NO_SUCH_FIGHTER,
			"a Move naming no fighter in the state must be refused with FAILURE_NO_SUCH_FIGHTER"
		)
	)
	violations.append_array(_expect(not result.success, "the refusal must not crash resolve()"))
	violations.append_array(
		_expect(state.digest() == before, "a refused Move must leave the state digest identical")
	)

	return violations


static func _test_null_template_is_refused() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(1)
	var state := _build_state(3)
	_place(state, "a1", "p1", Vector3i(0, 0, 0), template)
	var before := state.digest()

	var result := MoveAction.new("a1", Vector3i(1, -1, 0), null).resolve(state)

	violations.append_array(
		_expect(
			result.reason == MoveAction.FAILURE_MISSING_DATA,
			"a Move constructed with a null template must be refused with FAILURE_MISSING_DATA"
		)
	)
	violations.append_array(_expect(not result.success, "the refusal must not crash resolve()"))
	violations.append_array(
		_expect(state.digest() == before, "a refused Move must leave the state digest identical")
	)

	return violations


# --- RNG and counters -------------------------------------------------------


static func _test_rng_is_untouched_by_a_successful_move() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(1)
	var state := _build_state(3)
	_place(state, "a1", "p1", Vector3i(0, 0, 0), template)
	var before_state := state.rng.get_state()
	var before_seed := state.rng.get_seed()

	var result := MoveAction.new("a1", Vector3i(1, -1, 0), template).resolve(state)

	violations.append_array(
		_expect(result.success, "this scenario must resolve for it to test anything")
	)
	violations.append_array(
		_expect(
			state.rng.get_state() == before_state,
			"a successful Move must not advance the generator's state"
		)
	)
	violations.append_array(
		_expect(
			state.rng.get_seed() == before_seed,
			"a successful Move must not change the generator's seed"
		)
	)

	return violations


static func _test_rng_is_untouched_by_a_refused_move() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(1)
	var state := _build_state(3)
	_place(state, "a1", "p1", Vector3i(0, 0, 0), template)
	var before_state := state.rng.get_state()
	var before_seed := state.rng.get_seed()

	var result := MoveAction.new("a1", Vector3i(2, -2, 0), template).resolve(state)

	violations.append_array(
		_expect(not result.success, "this scenario must be refused for it to test anything")
	)
	violations.append_array(
		_expect(
			state.rng.get_state() == before_state,
			"a refused Move must not advance the generator's state"
		)
	)
	violations.append_array(
		_expect(
			state.rng.get_seed() == before_seed,
			"a refused Move must not change the generator's seed"
		)
	)

	return violations


static func _test_turns_and_round_unchanged_after_a_successful_move() -> Array[String]:
	var violations: Array[String] = []
	var template := _fighter_template(1)
	var state := _build_state(3)
	_place(state, "a1", "p1", Vector3i(0, 0, 0), template)
	var before_turns := state.turns_taken
	var before_round := state.round_number

	var result := MoveAction.new("a1", Vector3i(1, -1, 0), template).resolve(state)

	violations.append_array(
		_expect(result.success, "this scenario must resolve for it to test anything")
	)
	violations.append_array(
		_expect(state.turns_taken == before_turns, "a successful Move must not touch turns_taken")
	)
	violations.append_array(
		_expect(state.round_number == before_round, "a successful Move must not touch round_number")
	)

	return violations
