## Tests HexCoord: validity, neighbours, adjacency and distance.
##
## A contract test that cannot fail is worse than no contract test (see
## ContractScannerTest's docstring), so each of these was confirmed to fail
## once during development before the implementation made it pass.
class_name HexCoordTest


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_is_valid())
	violations.append_array(_test_neighbours_are_six_distinct_valid_adjacent())
	violations.append_array(_test_neighbours_are_in_directions_order())
	violations.append_array(_test_distance_self_and_neighbours())
	violations.append_array(_test_distance_three_steps_away())
	violations.append_array(_test_distance_is_symmetric())
	violations.append_array(_test_are_adjacent())

	if violations.is_empty():
		return true

	printerr("\n=== HexCoord Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


static func _test_is_valid() -> Array[String]:
	var violations: Array[String] = []

	violations.append_array(
		_expect(HexCoord.is_valid(Vector3i(0, 0, 0)), "(0, 0, 0) must be a valid cube coordinate")
	)
	violations.append_array(
		_expect(HexCoord.is_valid(Vector3i(1, -1, 0)), "(1, -1, 0) must be a valid cube coordinate")
	)
	violations.append_array(
		_expect(
			not HexCoord.is_valid(Vector3i(1, 1, 1)),
			"(1, 1, 1) must not be a valid cube coordinate"
		)
	)

	return violations


static func _test_neighbours_are_six_distinct_valid_adjacent() -> Array[String]:
	var violations: Array[String] = []
	var origin := Vector3i(0, 0, 0)
	var result := HexCoord.neighbours(origin)

	violations.append_array(
		_expect(result.size() == 6, "neighbours() must return exactly six coordinates")
	)

	var seen: Dictionary = {}
	for coord in result:
		violations.append_array(
			_expect(
				HexCoord.is_valid(coord), "neighbour %s must be a valid cube coordinate" % coord
			)
		)
		violations.append_array(
			_expect(
				HexCoord.distance(origin, coord) == 1,
				"neighbour %s must be at distance 1 from the origin" % coord
			)
		)
		violations.append_array(
			_expect(not seen.has(coord), "neighbour %s must not repeat" % coord)
		)
		seen[coord] = true

	return violations


static func _test_neighbours_are_in_directions_order() -> Array[String]:
	var violations: Array[String] = []
	var origin := Vector3i(2, -1, -1)
	var result := HexCoord.neighbours(origin)

	for i in range(HexCoord.DIRECTIONS.size()):
		var expected := origin + HexCoord.DIRECTIONS[i]
		violations.append_array(
			_expect(
				result[i] == expected,
				"neighbours()[%d] must be %s (DIRECTIONS order), got %s" % [i, expected, result[i]]
			)
		)

	return violations


static func _test_distance_self_and_neighbours() -> Array[String]:
	var violations: Array[String] = []
	var origin := Vector3i(0, 0, 0)

	violations.append_array(
		_expect(
			HexCoord.distance(origin, origin) == 0, "distance from a coordinate to itself must be 0"
		)
	)

	for coord in HexCoord.neighbours(origin):
		violations.append_array(
			_expect(
				HexCoord.distance(origin, coord) == 1, "distance to neighbour %s must be 1" % coord
			)
		)

	return violations


static func _test_distance_three_steps_away() -> Array[String]:
	var origin := Vector3i(0, 0, 0)
	var three_away := Vector3i(3, -3, 0)
	return _expect(
		HexCoord.distance(origin, three_away) == 3,
		"distance to a coordinate three straight steps away must be 3"
	)


static func _test_distance_is_symmetric() -> Array[String]:
	var violations: Array[String] = []
	var pairs := [
		[Vector3i(0, 0, 0), Vector3i(3, -3, 0)],  # straight-line pair
		[Vector3i(0, 0, 0), Vector3i(2, -1, -1)],  # off the straight axes
		[Vector3i(1, -2, 1), Vector3i(-2, 1, 1)],
	]

	for pair in pairs:
		var a: Vector3i = pair[0]
		var b: Vector3i = pair[1]
		violations.append_array(
			_expect(
				HexCoord.distance(a, b) == HexCoord.distance(b, a),
				"distance(%s, %s) must equal distance(%s, %s)" % [a, b, b, a]
			)
		)

	return violations


static func _test_are_adjacent() -> Array[String]:
	var violations: Array[String] = []
	var origin := Vector3i(0, 0, 0)

	for coord in HexCoord.neighbours(origin):
		violations.append_array(
			_expect(
				HexCoord.are_adjacent(origin, coord), "%s must be adjacent to the origin" % coord
			)
		)

	violations.append_array(
		_expect(
			not HexCoord.are_adjacent(origin, origin), "a coordinate must not be adjacent to itself"
		)
	)

	var two_away := Vector3i(2, -1, -1)
	violations.append_array(
		_expect(
			not HexCoord.are_adjacent(origin, two_away),
			"a coordinate two steps away must not be adjacent"
		)
	)

	return violations
