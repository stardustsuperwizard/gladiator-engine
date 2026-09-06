## Tests Board.to_dict() / Board.from_dict(): the round trip, the JSON-safety
## of the wire shape, and every malformed-input refusal from_dict() documents.
##
## A contract test that cannot fail is worse than no contract test (see
## ContractScannerTest's docstring), so each of these was confirmed to fail
## once during development before the implementation made it pass.
class_name BoardSerializationTest


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_all_hex_types_round_trip())
	violations.append_array(_test_occupied_hexes_round_trip())
	violations.append_array(_test_coords_order_identical_after_round_trip())
	violations.append_array(_test_to_dict_equal_via_json_stringify_after_round_trip())
	violations.append_array(_test_to_dict_output_has_no_vector3i_or_stringname())
	violations.append_array(_test_empty_hex_serializes_with_empty_occupant())
	violations.append_array(_test_from_dict_null_for_missing_hexes_key())
	violations.append_array(_test_from_dict_null_for_hexes_not_array())
	violations.append_array(_test_from_dict_null_for_coord_with_two_elements())
	violations.append_array(_test_from_dict_null_for_invalid_cube_coord())
	violations.append_array(_test_from_dict_null_for_duplicate_coord())
	violations.append_array(_test_from_dict_null_for_occupant_on_blocked_hex())
	violations.append_array(_test_from_dict_empty_hexes_returns_empty_board())

	if violations.is_empty():
		return true

	printerr("\n=== Board Serialization Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


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
		board.add_hex(Vector3i(i, -i, 0), types[i])

	var restored := Board.from_dict(board.to_dict())

	violations.append_array(
		_expect(restored != null, "from_dict() must not refuse a well-formed board")
	)
	if restored == null:
		return violations

	for i in range(types.size()):
		var coord := Vector3i(i, -i, 0)
		violations.append_array(
			_expect(
				restored.hex_type(coord) == types[i],
				"hex_type(%s) must be %s after round-trip" % [coord, types[i]]
			)
		)

	return violations


static func _test_occupied_hexes_round_trip() -> Array[String]:
	var violations: Array[String] = []
	var board := Board.new()
	var occupied_a := Vector3i(0, 0, 0)
	var occupied_b := Vector3i(1, -1, 0)
	var empty_coord := Vector3i(-1, 1, 0)

	board.add_hex(occupied_a, Board.HexType.NORMAL)
	board.add_hex(occupied_b, Board.HexType.NORMAL)
	board.add_hex(empty_coord, Board.HexType.NORMAL)
	board.place_occupant(occupied_a, &"fighter-1")
	board.place_occupant(occupied_b, &"fighter-2")

	var restored := Board.from_dict(board.to_dict())

	violations.append_array(
		_expect(restored != null, "from_dict() must not refuse a well-formed board")
	)
	if restored == null:
		return violations

	violations.append_array(
		_expect(
			restored.occupant_at(occupied_a) == &"fighter-1",
			"occupant_at() must return the original occupant id after round-trip"
		)
	)
	violations.append_array(
		_expect(
			restored.occupant_at(occupied_b) == &"fighter-2",
			"occupant_at() must return the original occupant id after round-trip"
		)
	)
	violations.append_array(
		_expect(
			not restored.is_occupied(empty_coord),
			"a hex that was empty in the original must remain unoccupied after round-trip"
		)
	)

	return violations


static func _test_coords_order_identical_after_round_trip() -> Array[String]:
	var board := Board.new()
	var added := [Vector3i(2, -2, 0), Vector3i(0, 0, 0), Vector3i(-1, 1, 0), Vector3i(1, -1, 0)]
	for coord in added:
		board.add_hex(coord, Board.HexType.NORMAL)

	var restored := Board.from_dict(board.to_dict())
	if restored == null:
		return ["from_dict() must not refuse a well-formed board"]

	return _expect(
		restored.coords() == board.coords(),
		"coords() after round-trip must be identical -- same elements, same order -- to the original"
	)


static func _test_to_dict_equal_via_json_stringify_after_round_trip() -> Array[String]:
	var board := Board.new()
	board.add_hex(Vector3i(0, 0, 0), Board.HexType.STARTING)
	board.add_hex(Vector3i(1, -1, 0), Board.HexType.HAZARD)
	board.place_occupant(Vector3i(0, 0, 0), &"fighter-1")

	var restored := Board.from_dict(board.to_dict())
	if restored == null:
		return ["from_dict() must not refuse a well-formed board"]

	return _expect(
		JSON.stringify(restored.to_dict()) == JSON.stringify(board.to_dict()),
		"to_dict() of a round-tripped board must equal to_dict() of the original via JSON.stringify()"
	)


static func _test_to_dict_output_has_no_vector3i_or_stringname() -> Array[String]:
	var violations: Array[String] = []
	var board := Board.new()
	var coord := Vector3i(0, 0, 0)
	board.add_hex(coord, Board.HexType.NORMAL)
	board.place_occupant(coord, &"fighter-1")

	var data := board.to_dict()
	var entry: Dictionary = data["hexes"][0]

	violations.append_array(
		_expect(
			typeof(entry["coord"]) == TYPE_ARRAY,
			'to_dict()\'s "coord" entry must be a plain Array, not a Vector3i'
		)
	)
	violations.append_array(
		_expect(
			typeof(entry["occupant"]) == TYPE_STRING,
			'to_dict()\'s "occupant" entry must be a plain String, not a StringName'
		)
	)

	return violations


static func _test_empty_hex_serializes_with_empty_occupant() -> Array[String]:
	var violations: Array[String] = []
	var board := Board.new()
	var coord := Vector3i(0, 0, 0)
	board.add_hex(coord, Board.HexType.NORMAL)

	var data := board.to_dict()
	var entry: Dictionary = data["hexes"][0]

	violations.append_array(
		_expect(entry["occupant"] == "", 'an empty hex must serialize with "occupant" as ""')
	)

	var restored := Board.from_dict(data)
	violations.append_array(
		_expect(restored != null, "from_dict() must not refuse a well-formed board")
	)
	if restored != null:
		violations.append_array(
			_expect(
				not restored.is_occupied(coord),
				'a hex serialized with "" occupant must round-trip as unoccupied'
			)
		)

	return violations


static func _test_from_dict_null_for_missing_hexes_key() -> Array[String]:
	return _expect(
		Board.from_dict({}) == null, 'from_dict() must return null when "hexes" is missing'
	)


static func _test_from_dict_null_for_hexes_not_array() -> Array[String]:
	return _expect(
		Board.from_dict({"hexes": "not an array"}) == null,
		'from_dict() must return null when "hexes" is not an Array'
	)


static func _test_from_dict_null_for_coord_with_two_elements() -> Array[String]:
	var data := {"hexes": [{"coord": [0, 0], "type": Board.HexType.NORMAL, "occupant": ""}]}
	return _expect(
		Board.from_dict(data) == null,
		'from_dict() must return null when an entry\'s "coord" has two elements'
	)


static func _test_from_dict_null_for_invalid_cube_coord() -> Array[String]:
	var data := {"hexes": [{"coord": [1, 1, 1], "type": Board.HexType.NORMAL, "occupant": ""}]}
	return _expect(
		Board.from_dict(data) == null,
		'from_dict() must return null when "coord" fails HexCoord.is_valid()'
	)


static func _test_from_dict_null_for_duplicate_coord() -> Array[String]:
	var entry := {"coord": [0, 0, 0], "type": Board.HexType.NORMAL, "occupant": ""}
	var data := {"hexes": [entry.duplicate(), entry.duplicate()]}
	return _expect(
		Board.from_dict(data) == null,
		"from_dict() must return null when two entries share one coordinate"
	)


static func _test_from_dict_null_for_occupant_on_blocked_hex() -> Array[String]:
	var data := {
		"hexes":
		[
			{"coord": [0, 0, 0], "type": Board.HexType.BLOCKED, "occupant": "fighter-1"},
		]
	}
	return _expect(
		Board.from_dict(data) == null,
		(
			"from_dict() must return null when an entry places an occupant on a BLOCKED hex "
			+ "-- place_occupant()'s existing refusal is what rejects it"
		)
	)


static func _test_from_dict_empty_hexes_returns_empty_board() -> Array[String]:
	var restored := Board.from_dict({"hexes": []})
	var violations: Array[String] = []

	violations.append_array(
		_expect(restored != null, 'from_dict({"hexes": []}) must be valid, not malformed')
	)
	if restored != null:
		violations.append_array(
			_expect(
				restored.coords().is_empty(),
				"an empty hexes array must produce a board with no coords"
			)
		)

	return violations
