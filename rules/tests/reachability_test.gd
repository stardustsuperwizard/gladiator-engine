## Tests Board.reachable_from(): breadth-first flood fill, not distance.
##
## The property under test throughout is routing, not range: a hex whose
## straight-line HexCoord.distance() is N or less can still be absent from
## reachable_from(origin, N) when every route to it is walled off by BLOCKED
## or occupied hexes, or when the only route is a detour longer than N steps.
## Conversely, an occupied origin must not empty its own result -- the mover
## standing there does not block itself.
##
## A contract test that cannot fail is worse than no contract test (see
## ContractScannerTest's docstring), so each of these was confirmed to fail
## once during development before the implementation made it pass.
class_name ReachabilityTest


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_one_step_returns_the_six_board_neighbours())
	violations.append_array(_test_two_steps_returns_all_eighteen_hexes_at_distance_one_or_two())
	violations.append_array(_test_zero_and_negative_steps_return_empty())
	violations.append_array(_test_origin_absent_and_no_duplicates())
	violations.append_array(_test_blocked_wall_prevents_reaching_a_distance_n_hex())
	violations.append_array(_test_occupied_wall_prevents_reaching_a_distance_n_hex())
	violations.append_array(_test_longer_detour_is_excluded_within_n_steps())
	violations.append_array(_test_occupied_adjacent_hex_excluded_unoccupied_included())
	violations.append_array(_test_occupied_origin_still_returns_neighbours())
	violations.append_array(_test_every_result_coordinate_has_a_hex())
	violations.append_array(_test_two_calls_are_identical())

	if violations.is_empty():
		return true

	printerr("\n=== Reachability Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


## A hexagonal board of `radius` rings around the origin, every hex NORMAL
## except the coordinates listed in `blocked`.
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


static func _test_one_step_returns_the_six_board_neighbours() -> Array[String]:
	var violations: Array[String] = []
	var origin := Vector3i(0, 0, 0)
	var board := _hex_board(3)

	var result := board.reachable_from(origin, 1)
	var expected := HexCoord.neighbours(origin)

	violations.append_array(
		_expect(
			result.size() == 6,
			(
				"reachable_from(origin, 1) on an obstacle-free board must return 6 hexes, got %d"
				% result.size()
			)
		)
	)
	for neighbour in expected:
		violations.append_array(
			_expect(
				neighbour in result,
				"reachable_from(origin, 1) must include the on-board neighbour %s" % neighbour
			)
		)
	(
		violations
		. append_array(
			_expect(
				result == expected,
				(
					(
						"reachable_from(origin, 1) must expand neighbours in HexCoord.DIRECTIONS order: "
						+ "expected %s, got %s"
					)
					% [expected, result]
				)
			)
		)
	)

	return violations


static func _test_two_steps_returns_all_eighteen_hexes_at_distance_one_or_two() -> Array[String]:
	var violations: Array[String] = []
	var origin := Vector3i(0, 0, 0)
	var board := _hex_board(3)

	var result := board.reachable_from(origin, 2)

	(
		violations
		. append_array(
			_expect(
				result.size() == 18,
				(
					"reachable_from(origin, 2) on a large obstacle-free board must return 18 hexes, got %d"
					% result.size()
				)
			)
		)
	)
	for coord in result:
		var distance := HexCoord.distance(origin, coord)
		violations.append_array(
			_expect(
				distance == 1 or distance == 2,
				(
					(
						"reachable_from(origin, 2) returned %s at distance %d: every hex must be "
						+ "at distance 1 or 2"
					)
					% [coord, distance]
				)
			)
		)

	return violations


static func _test_zero_and_negative_steps_return_empty() -> Array[String]:
	var violations: Array[String] = []
	var origin := Vector3i(0, 0, 0)
	var board := _hex_board(2)

	violations.append_array(
		_expect(
			board.reachable_from(origin, 0).is_empty(),
			"reachable_from(origin, 0) must return an empty array"
		)
	)
	violations.append_array(
		_expect(
			board.reachable_from(origin, -3).is_empty(),
			"reachable_from(origin, -3) must return an empty array"
		)
	)

	return violations


static func _test_origin_absent_and_no_duplicates() -> Array[String]:
	var violations: Array[String] = []
	var origin := Vector3i(0, 0, 0)
	var board := _hex_board(3)

	var result := board.reachable_from(origin, 2)
	var seen: Dictionary = {}
	var duplicate_count := 0

	violations.append_array(
		_expect(origin not in result, "reachable_from() must never include origin in the result")
	)
	for coord in result:
		if seen.has(coord):
			duplicate_count += 1
		seen[coord] = true
	violations.append_array(
		_expect(duplicate_count == 0, "reachable_from() must not return a coordinate twice")
	)

	return violations


## The only 2-step route from origin to a straight-line distance-2 hex passes
## through the single midpoint hex between them -- blocking that one hex
## removes every route, even though the target's straight-line distance is
## still 2.
static func _test_blocked_wall_prevents_reaching_a_distance_n_hex() -> Array[String]:
	var violations: Array[String] = []
	var origin := Vector3i(0, 0, 0)
	var midpoint := Vector3i(1, -1, 0)
	var target := Vector3i(2, -2, 0)
	var board := _hex_board(3, [midpoint] as Array[Vector3i])

	(
		violations
		. append_array(
			_expect(
				HexCoord.distance(origin, target) == 2,
				(
					"target %s must be straight-line distance 2 from origin for this case to test anything"
					% target
				)
			)
		)
	)
	violations.append_array(
		_expect(
			target not in board.reachable_from(origin, 2),
			(
				(
					"a BLOCKED midpoint at %s must remove every route to %s, which must be absent "
					+ "from reachable_from(origin, 2)"
				)
				% [midpoint, target]
			)
		)
	)

	return violations


## Same geometry as the BLOCKED case, but the wall is an occupant on an
## otherwise NORMAL hex -- occupancy blocks passage exactly like BLOCKED does.
static func _test_occupied_wall_prevents_reaching_a_distance_n_hex() -> Array[String]:
	var violations: Array[String] = []
	var origin := Vector3i(0, 0, 0)
	var midpoint := Vector3i(1, -1, 0)
	var target := Vector3i(2, -2, 0)
	var board := _hex_board(3)

	violations.append_array(
		_expect(
			board.place_occupant(midpoint, &"blocker"),
			"placing an occupant at %s must succeed for this case to test anything" % midpoint
		)
	)
	(
		violations
		. append_array(
			_expect(
				HexCoord.distance(origin, target) == 2,
				(
					"target %s must be straight-line distance 2 from origin for this case to test anything"
					% target
				)
			)
		)
	)
	(
		violations
		. append_array(
			_expect(
				target not in board.reachable_from(origin, 2),
				(
					(
						"an occupied midpoint at %s must remove every route to %s, which must be absent "
						+ "from reachable_from(origin, 2)"
					)
					% [midpoint, target]
				)
			)
		)
	)

	return violations


## Every neighbour of origin except one is BLOCKED, so the only way out is
## through the one open neighbour -- and the target, whose sole 2-step route
## runs through a BLOCKED neighbour, is reachable only by a 3-step detour
## around the wall.
static func _test_longer_detour_is_excluded_within_n_steps() -> Array[String]:
	var violations: Array[String] = []
	var origin := Vector3i(0, 0, 0)
	var open_exit := Vector3i(0, 1, -1)
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
	var detour_step := Vector3i(1, 1, -2)
	var target := Vector3i(2, 0, -2)
	var board := _hex_board(3, blocked_neighbours)

	(
		violations
		. append_array(
			_expect(
				HexCoord.distance(origin, target) == 2,
				(
					"target %s must be straight-line distance 2 from origin for this case to test anything"
					% target
				)
			)
		)
	)
	violations.append_array(
		_expect(
			not board.is_blocked(open_exit) and not board.is_blocked(detour_step),
			(
				"the detour route through %s and %s must stay open for this case to test anything"
				% [open_exit, detour_step]
			)
		)
	)
	(
		violations
		. append_array(
			_expect(
				(
					HexCoord.are_adjacent(origin, open_exit)
					and HexCoord.are_adjacent(open_exit, detour_step)
					and HexCoord.are_adjacent(detour_step, target)
				),
				(
					"origin -> %s -> %s -> %s must be a real 3-step route for this case to test anything"
					% [open_exit, detour_step, target]
				)
			)
		)
	)
	violations.append_array(
		_expect(
			target not in board.reachable_from(origin, 2),
			(
				(
					"%s is only reachable by a 3-step detour and must be absent from "
					+ "reachable_from(origin, 2)"
				)
				% target
			)
		)
	)
	(
		violations
		. append_array(
			_expect(
				target in board.reachable_from(origin, 3),
				(
					(
						"%s must be present in reachable_from(origin, 3): the detour exists, it is just "
						+ "longer than 2 steps"
					)
					% target
				)
			)
		)
	)

	return violations


static func _test_occupied_adjacent_hex_excluded_unoccupied_included() -> Array[String]:
	var violations: Array[String] = []
	var origin := Vector3i(0, 0, 0)
	var occupied_neighbour := Vector3i(1, -1, 0)
	var unoccupied_neighbour := Vector3i(0, 1, -1)
	var board := _hex_board(2)

	violations.append_array(
		_expect(
			board.place_occupant(occupied_neighbour, &"fighter-1"),
			(
				"placing an occupant at %s must succeed for this case to test anything"
				% occupied_neighbour
			)
		)
	)

	var result := board.reachable_from(origin, 1)

	violations.append_array(
		_expect(
			occupied_neighbour not in result,
			(
				"an occupied hex adjacent to origin at %s must be absent from the result"
				% occupied_neighbour
			)
		)
	)
	violations.append_array(
		_expect(
			unoccupied_neighbour in result,
			(
				"an unoccupied hex the same distance away at %s must be present in the result"
				% unoccupied_neighbour
			)
		)
	)

	return violations


static func _test_occupied_origin_still_returns_neighbours() -> Array[String]:
	var violations: Array[String] = []
	var origin := Vector3i(0, 0, 0)
	var board := _hex_board(2)

	violations.append_array(
		_expect(
			board.place_occupant(origin, &"fighter-1"),
			"placing an occupant at origin must succeed for this case to test anything"
		)
	)

	var result := board.reachable_from(origin, 1)

	violations.append_array(
		_expect(
			result.size() == 6,
			(
				(
					"an occupied origin must still return its 6 walkable neighbours, got %d: the "
					+ "occupant standing on origin must not block origin itself"
				)
				% result.size()
			)
		)
	)
	violations.append_array(
		_expect(origin not in result, "origin must still be absent from the result")
	)

	return violations


static func _test_every_result_coordinate_has_a_hex() -> Array[String]:
	var violations: Array[String] = []
	var origin := Vector3i(0, 0, 0)
	var board := _hex_board(1)

	var result := board.reachable_from(origin, 2)

	for coord in result:
		violations.append_array(
			_expect(
				board.has_hex(coord),
				"reachable_from() returned %s, which has no hex on the board" % coord
			)
		)

	return violations


static func _test_two_calls_are_identical() -> Array[String]:
	var origin := Vector3i(0, 0, 0)
	var board := _hex_board(3)

	var first_call := board.reachable_from(origin, 2)
	var second_call := board.reachable_from(origin, 2)

	return _expect(
		first_call == second_call,
		"two reachable_from() calls with the same arguments must return identical arrays"
	)
