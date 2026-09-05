## Tests Board: hex types, terrain queries, and single-occupant placement.
##
## A contract test that cannot fail is worse than no contract test (see
## ContractScannerTest's docstring), so each of these was confirmed to fail
## once during development before the implementation made it pass.
class_name BoardTest


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_add_hex_rejects_invalid_coordinate())
	violations.append_array(_test_add_hex_rejects_duplicate_coordinate())
	violations.append_array(_test_all_hex_types_round_trip())
	violations.append_array(_test_is_blocked_true_for_blocked_and_off_board())
	violations.append_array(_test_place_occupant_into_empty_hex_succeeds())
	violations.append_array(_test_place_occupant_refused_when_already_occupied())
	violations.append_array(_test_place_occupant_refused_on_blocked_hex())
	violations.append_array(_test_place_occupant_refused_with_no_hex())
	violations.append_array(_test_place_occupant_refused_with_empty_id())
	violations.append_array(_test_place_occupant_succeeds_on_hazard_hex())
	violations.append_array(_test_remove_occupant_empties_then_allows_replace())
	violations.append_array(_test_distance_counts_blocked_hex_instead_of_routing_around())
	violations.append_array(_test_coords_returns_each_coordinate_once_in_stable_order())

	if violations.is_empty():
		return true

	printerr("\n=== Board Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


static func _test_add_hex_rejects_invalid_coordinate() -> Array[String]:
	var violations: Array[String] = []
	var board := Board.new()
	var invalid := Vector3i(1, 1, 1)

	violations.append_array(
		_expect(
			not board.add_hex(invalid, Board.HexType.NORMAL),
			"add_hex() must return false for a coordinate that fails HexCoord.is_valid()"
		)
	)
	violations.append_array(
		_expect(
			not board.has_hex(invalid), "add_hex() must not add a hex for an invalid coordinate"
		)
	)

	return violations


static func _test_add_hex_rejects_duplicate_coordinate() -> Array[String]:
	var violations: Array[String] = []
	var board := Board.new()
	var coord := Vector3i(0, 0, 0)

	violations.append_array(
		_expect(
			board.add_hex(coord, Board.HexType.NORMAL),
			"the first add_hex() at a coordinate must succeed"
		)
	)
	violations.append_array(
		_expect(
			not board.add_hex(coord, Board.HexType.BLOCKED),
			"add_hex() must return false for a coordinate that already carries a hex"
		)
	)
	violations.append_array(
		_expect(
			board.hex_type(coord) == Board.HexType.NORMAL,
			"a refused duplicate add_hex() must not overwrite the existing hex's type"
		)
	)

	return violations


static func _test_all_hex_types_round_trip() -> Array[String]:
	var violations: Array[String] = []
	var board := Board.new()
	var types := [
		Board.HexType.NORMAL,
		Board.HexType.STARTING,
		Board.HexType.EDGE,
		Board.HexType.BLOCKED,
		Board.HexType.HAZARD,
	]

	for i in range(types.size()):
		var coord := Vector3i(i, -i, 0)
		var type: Board.HexType = types[i]
		violations.append_array(
			_expect(board.add_hex(coord, type), "add_hex(%s, %s) must succeed" % [coord, type])
		)
		violations.append_array(
			_expect(
				board.hex_type(coord) == type,
				"hex_type(%s) must read back %s after add_hex()" % [coord, type]
			)
		)

	return violations


static func _test_is_blocked_true_for_blocked_and_off_board() -> Array[String]:
	var violations: Array[String] = []
	var board := Board.new()

	var blocked_coord := Vector3i(0, 0, 0)
	board.add_hex(blocked_coord, Board.HexType.BLOCKED)
	violations.append_array(
		_expect(board.is_blocked(blocked_coord), "a BLOCKED hex must report is_blocked() true")
	)

	var off_board := Vector3i(9, -9, 0)
	violations.append_array(
		_expect(
			not board.has_hex(off_board),
			"off_board coordinate must have no hex for this case to test anything"
		)
	)
	violations.append_array(
		_expect(
			board.is_blocked(off_board),
			"a coordinate with no hex on the board must report is_blocked() true"
		)
	)

	var non_blocking_types := [
		Board.HexType.NORMAL,
		Board.HexType.STARTING,
		Board.HexType.EDGE,
		Board.HexType.HAZARD,
	]
	for i in range(non_blocking_types.size()):
		var coord := Vector3i(i + 1, -(i + 1), 0)
		var type: Board.HexType = non_blocking_types[i]
		board.add_hex(coord, type)
		violations.append_array(
			_expect(not board.is_blocked(coord), "a %s hex must report is_blocked() false" % type)
		)

	return violations


static func _test_place_occupant_into_empty_hex_succeeds() -> Array[String]:
	var violations: Array[String] = []
	var board := Board.new()
	var coord := Vector3i(0, 0, 0)
	board.add_hex(coord, Board.HexType.NORMAL)

	violations.append_array(
		_expect(
			board.place_occupant(coord, &"fighter-1"),
			"place_occupant() into an empty, non-blocked hex must return true"
		)
	)
	violations.append_array(
		_expect(
			board.occupant_at(coord) == &"fighter-1",
			"occupant_at() must return the placed occupant id"
		)
	)
	violations.append_array(
		_expect(board.is_occupied(coord), "is_occupied() must be true after a successful placement")
	)

	return violations


static func _test_place_occupant_refused_when_already_occupied() -> Array[String]:
	var violations: Array[String] = []
	var board := Board.new()
	var coord := Vector3i(0, 0, 0)
	board.add_hex(coord, Board.HexType.NORMAL)
	board.place_occupant(coord, &"first")

	violations.append_array(
		_expect(
			not board.place_occupant(coord, &"second"),
			"place_occupant() into an already-occupied hex must return false"
		)
	)
	violations.append_array(
		_expect(
			board.occupant_at(coord) == &"first",
			"a refused placement must not overwrite the first occupant"
		)
	)

	return violations


static func _test_place_occupant_refused_on_blocked_hex() -> Array[String]:
	var violations: Array[String] = []
	var board := Board.new()
	var coord := Vector3i(0, 0, 0)
	board.add_hex(coord, Board.HexType.BLOCKED)

	violations.append_array(
		_expect(
			not board.place_occupant(coord, &"fighter-1"),
			"place_occupant() into a BLOCKED hex must return false"
		)
	)
	violations.append_array(
		_expect(
			not board.is_occupied(coord),
			"a refused placement into a BLOCKED hex must leave the hex unoccupied"
		)
	)

	return violations


static func _test_place_occupant_refused_with_no_hex() -> Array[String]:
	var violations: Array[String] = []
	var board := Board.new()
	var coord := Vector3i(0, 0, 0)

	violations.append_array(
		_expect(
			not board.place_occupant(coord, &"fighter-1"),
			"place_occupant() at a coordinate with no hex must return false"
		)
	)
	violations.append_array(
		_expect(
			not board.has_hex(coord),
			"a refused placement at a missing coordinate must not create a hex there"
		)
	)

	return violations


static func _test_place_occupant_refused_with_empty_id() -> Array[String]:
	var board := Board.new()
	var coord := Vector3i(0, 0, 0)
	board.add_hex(coord, Board.HexType.NORMAL)

	return _expect(
		not board.place_occupant(coord, &""),
		'place_occupant() with &"" as the id must return false'
	)


static func _test_place_occupant_succeeds_on_hazard_hex() -> Array[String]:
	var violations: Array[String] = []
	var board := Board.new()
	var coord := Vector3i(0, 0, 0)
	board.add_hex(coord, Board.HexType.HAZARD)

	violations.append_array(
		_expect(
			board.place_occupant(coord, &"fighter-1"),
			"place_occupant() into a HAZARD hex must succeed -- the type is recorded, not acted on"
		)
	)
	violations.append_array(
		_expect(
			board.hex_type(coord) == Board.HexType.HAZARD,
			"a successful placement must not change the hex's recorded type"
		)
	)

	return violations


static func _test_remove_occupant_empties_then_allows_replace() -> Array[String]:
	var violations: Array[String] = []
	var board := Board.new()
	var coord := Vector3i(0, 0, 0)
	board.add_hex(coord, Board.HexType.NORMAL)
	board.place_occupant(coord, &"fighter-1")

	violations.append_array(
		_expect(
			board.remove_occupant(coord), "remove_occupant() on an occupied hex must return true"
		)
	)
	violations.append_array(
		_expect(not board.is_occupied(coord), "remove_occupant() must leave the hex unoccupied")
	)
	violations.append_array(
		_expect(board.occupant_at(coord) == &"", 'occupant_at() must return &"" after removal')
	)
	violations.append_array(
		_expect(
			not board.remove_occupant(coord),
			"a second remove_occupant() on an already-empty hex must return false"
		)
	)
	violations.append_array(
		_expect(
			board.place_occupant(coord, &"fighter-2"), "placement into a vacated hex must succeed"
		)
	)
	violations.append_array(
		_expect(
			board.occupant_at(coord) == &"fighter-2",
			"occupant_at() must return the new occupant after replacement"
		)
	)

	return violations


## Distance is terrain-blind: a BLOCKED hex directly between two coordinates
## two steps apart must still count as 2, not be routed around. Board must
## not grow a distance() that consults terrain; HexCoord.distance() is the
## only distance function.
static func _test_distance_counts_blocked_hex_instead_of_routing_around() -> Array[String]:
	var board := Board.new()
	var a := Vector3i(0, 0, 0)
	var between := Vector3i(1, -1, 0)
	var b := Vector3i(2, -2, 0)

	board.add_hex(a, Board.HexType.NORMAL)
	board.add_hex(between, Board.HexType.BLOCKED)
	board.add_hex(b, Board.HexType.NORMAL)

	return _expect(
		HexCoord.distance(a, b) == 2,
		(
			"HexCoord.distance() must count a directly-between BLOCKED hex, not route "
			+ "around it -- distance(%s, %s) must be 2 even though %s is blocked" % [a, b, between]
		)
	)


static func _test_coords_returns_each_coordinate_once_in_stable_order() -> Array[String]:
	var violations: Array[String] = []
	var board := Board.new()
	var added := [Vector3i(0, 0, 0), Vector3i(1, -1, 0), Vector3i(-1, 1, 0)]

	for coord in added:
		board.add_hex(coord, Board.HexType.NORMAL)

	var first_call := board.coords()
	var second_call := board.coords()

	violations.append_array(
		_expect(
			first_call.size() == added.size(),
			"coords() must return exactly the added coordinates, no more and no fewer"
		)
	)
	for coord in added:
		violations.append_array(_expect(coord in first_call, "coords() must include %s" % coord))
	violations.append_array(
		_expect(
			first_call == second_call,
			"two coords() calls on an unchanged board must return the identical order"
		)
	)

	return violations
