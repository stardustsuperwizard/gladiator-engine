## Tests the hex line draw and Board.has_line_of_sight().
##
## The interesting case is the last one. A line running exactly along the
## boundary between two hexes has to resolve into one of them, and the
## convention that decides which -- documented on HexCoord.LINE_NUDGE -- is
## also the only reason sight is symmetric. Both endpoints are offset by the
## same epsilon before interpolating, so `from -> to` and `to -> from` sample
## the same points and round to the same hexes. A per-direction nudge passes a
## small clear-board test and still ships "A can see B but B cannot see A".
##
## A contract test that cannot fail is worse than no contract test (see
## ContractScannerTest's docstring), so each of these was confirmed to fail
## once during development before the implementation made it pass.
class_name LineOfSightTest

## The smallest exact-boundary line: the midpoint of ORIGIN -> BOUNDARY_TARGET
## is (0.5, -1, 0.5), equidistant from BOUNDARY_LEFT and BOUNDARY_RIGHT.
const BOUNDARY_ORIGIN := Vector3i(0, 0, 0)
const BOUNDARY_TARGET := Vector3i(1, -2, 1)
const BOUNDARY_LEFT := Vector3i(1, -1, 0)
const BOUNDARY_RIGHT := Vector3i(0, -1, 1)

## Named once so a failing build reads as the convention, not as a magic value.
const TIE_BREAK := (
	"tie-break convention: both endpoints are offset by the same "
	+ "HexCoord.LINE_NUDGE epsilon before interpolating"
)


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_line_length_endpoints_validity_and_adjacency())
	violations.append_array(_test_clear_board_every_hex_sees_every_other())
	violations.append_array(_test_blocked_hex_on_the_line_blocks_sight())
	violations.append_array(_test_blocked_hex_beside_the_line_does_not_block_sight())
	violations.append_array(_test_endpoints_do_not_block_sight())
	violations.append_array(_test_occupied_hex_does_not_block_sight())
	violations.append_array(_test_off_board_coordinate_between_endpoints_blocks_sight())
	violations.append_array(_test_sight_is_symmetric_over_every_ordered_pair())
	violations.append_array(_test_boundary_line_resolves_by_the_shared_epsilon_nudge_tie_break())

	if violations.is_empty():
		return true

	printerr("\n=== Line Of Sight Test Violations ===")
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


static func _test_line_length_endpoints_validity_and_adjacency() -> Array[String]:
	var violations: Array[String] = []
	var pairs := [
		[Vector3i(0, 0, 0), Vector3i(0, 0, 0)],
		[Vector3i(0, 0, 0), Vector3i(1, -1, 0)],
		[Vector3i(0, 0, 0), Vector3i(3, -3, 0)],
		[Vector3i(-2, 3, -1), Vector3i(2, -1, -1)],
		[BOUNDARY_ORIGIN, BOUNDARY_TARGET],
	]

	for pair in pairs:
		var a: Vector3i = pair[0]
		var b: Vector3i = pair[1]
		var path := HexCoord.line(a, b)
		var expected := HexCoord.distance(a, b) + 1

		violations.append_array(
			_expect(
				path.size() == expected,
				(
					"line(%s, %s) must return distance + 1 = %d coordinates, got %d"
					% [a, b, expected, path.size()]
				)
			)
		)
		if path.size() != expected:
			continue

		violations.append_array(
			_expect(path[0] == a, "line(%s, %s) must begin at %s, began at %s" % [a, b, a, path[0]])
		)
		violations.append_array(
			_expect(
				path[path.size() - 1] == b,
				"line(%s, %s) must end at %s, ended at %s" % [a, b, b, path[path.size() - 1]]
			)
		)
		for coord in path:
			violations.append_array(
				_expect(
					HexCoord.is_valid(coord),
					"line(%s, %s) returned %s, which is not a valid cube coordinate" % [a, b, coord]
				)
			)
		for i in range(1, path.size()):
			violations.append_array(
				_expect(
					HexCoord.are_adjacent(path[i - 1], path[i]),
					(
						"line(%s, %s) must step one hex at a time, but %s and %s are %d apart"
						% [a, b, path[i - 1], path[i], HexCoord.distance(path[i - 1], path[i])]
					)
				)
			)

	return violations


static func _test_clear_board_every_hex_sees_every_other() -> Array[String]:
	var violations: Array[String] = []
	var board := _hex_board(2)
	var coords := board.coords()

	for a in coords:
		for b in coords:
			violations.append_array(
				_expect(
					board.has_line_of_sight(a, b),
					"on a board with no BLOCKED hex anywhere, %s must see %s" % [a, b]
				)
			)

	return violations


static func _test_blocked_hex_on_the_line_blocks_sight() -> Array[String]:
	var violations: Array[String] = []
	var a := Vector3i(0, 0, 0)
	var between := Vector3i(1, -1, 0)
	var b := Vector3i(3, -3, 0)
	var board := _hex_board(3, [between] as Array[Vector3i])

	violations.append_array(
		_expect(
			between in HexCoord.line(a, b),
			"%s must lie on line(%s, %s) for this case to test anything" % [between, a, b]
		)
	)
	violations.append_array(
		_expect(
			not board.has_line_of_sight(a, b),
			"a BLOCKED hex at %s on the line from %s to %s must break sight" % [between, a, b]
		)
	)

	return violations


static func _test_blocked_hex_beside_the_line_does_not_block_sight() -> Array[String]:
	var violations: Array[String] = []
	var a := Vector3i(0, 0, 0)
	var beside := Vector3i(1, 0, -1)
	var b := Vector3i(3, -3, 0)
	var board := _hex_board(3, [beside] as Array[Vector3i])

	violations.append_array(
		_expect(
			beside not in HexCoord.line(a, b),
			"%s must lie off line(%s, %s) for this case to test anything" % [beside, a, b]
		)
	)
	violations.append_array(
		_expect(
			board.has_line_of_sight(a, b),
			(
				"a BLOCKED hex at %s to one side of the line from %s to %s must not break sight"
				% [beside, a, b]
			)
		)
	)

	return violations


static func _test_endpoints_do_not_block_sight() -> Array[String]:
	var violations: Array[String] = []
	var blocked := Vector3i(1, -1, 0)
	var origin := Vector3i(0, 0, 0)
	var board := _hex_board(2, [blocked] as Array[Vector3i])

	violations.append_array(
		_expect(board.has_line_of_sight(origin, origin), "a hex must see itself")
	)
	violations.append_array(
		_expect(
			board.has_line_of_sight(blocked, blocked),
			"a BLOCKED hex must still see itself -- endpoints are excluded from the check"
		)
	)
	violations.append_array(
		_expect(
			board.has_line_of_sight(origin, blocked),
			(
				"%s must see the adjacent BLOCKED hex %s -- an endpoint never blocks"
				% [origin, blocked]
			)
		)
	)
	violations.append_array(
		_expect(
			board.has_line_of_sight(blocked, origin),
			(
				"the BLOCKED hex %s must see the adjacent hex %s -- an endpoint never blocks"
				% [blocked, origin]
			)
		)
	)

	return violations


static func _test_occupied_hex_does_not_block_sight() -> Array[String]:
	var violations: Array[String] = []
	var a := Vector3i(0, 0, 0)
	var between := Vector3i(1, -1, 0)
	var b := Vector3i(2, -2, 0)
	var board := _hex_board(2)

	violations.append_array(
		_expect(
			board.place_occupant(between, &"fighter-1"),
			"placing an occupant at %s must succeed for this case to test anything" % between
		)
	)
	violations.append_array(
		_expect(
			between in HexCoord.line(a, b),
			"%s must lie on line(%s, %s) for this case to test anything" % [between, a, b]
		)
	)
	violations.append_array(
		_expect(
			board.has_line_of_sight(a, b),
			(
				"an occupied hex at %s must not break sight from %s to %s -- only BLOCKED blocks"
				% [between, a, b]
			)
		)
	)

	return violations


static func _test_off_board_coordinate_between_endpoints_blocks_sight() -> Array[String]:
	var violations: Array[String] = []
	var a := Vector3i(0, 0, 0)
	var between := Vector3i(1, -1, 0)
	var b := Vector3i(2, -2, 0)
	var board := Board.new()

	board.add_hex(a, Board.HexType.NORMAL)
	board.add_hex(b, Board.HexType.NORMAL)

	violations.append_array(
		_expect(
			not board.has_hex(between),
			"%s must have no hex for this case to test anything" % between
		)
	)
	violations.append_array(
		_expect(
			between in HexCoord.line(a, b),
			"%s must lie on line(%s, %s) for this case to test anything" % [between, a, b]
		)
	)
	violations.append_array(
		_expect(
			not board.has_line_of_sight(a, b),
			(
				"a coordinate with no hex at %s, lying between %s and %s, must break sight"
				% [between, a, b]
			)
		)
	)

	return violations


## Symmetry is the property the whole tie-break exists to guarantee, so it is
## asserted over every ordered pair of a board that actually has obstacles
## rather than on a hand-picked line or two.
static func _test_sight_is_symmetric_over_every_ordered_pair() -> Array[String]:
	var violations: Array[String] = []
	var blocked := (
		[
			Vector3i(1, -1, 0),
			Vector3i(0, -1, 1),
			Vector3i(-1, 2, -1),
			Vector3i(2, 0, -2),
			Vector3i(-2, 0, 2),
		]
		as Array[Vector3i]
	)
	var board := _hex_board(3, blocked)
	var coords := board.coords()
	var asymmetric := 0

	for a in coords:
		for b in coords:
			if board.has_line_of_sight(a, b) != board.has_line_of_sight(b, a):
				asymmetric += 1
				(
					violations
					. append_array(
						_expect(
							false,
							(
								"has_line_of_sight(%s, %s) = %s but has_line_of_sight(%s, %s) = %s -- %s"
								% [
									a,
									b,
									board.has_line_of_sight(a, b),
									b,
									a,
									board.has_line_of_sight(b, a),
									TIE_BREAK
								]
							)
						)
					)
				)

	violations.append_array(
		_expect(
			asymmetric == 0,
			(
				"%d of %d ordered pairs disagreed about sight -- %s"
				% [asymmetric, coords.size() * coords.size(), TIE_BREAK]
			)
		)
	)

	return violations


## The boundary case: the centre-to-centre line runs exactly along the edge
## between BOUNDARY_LEFT and BOUNDARY_RIGHT. It must resolve into exactly one
## of them -- the same one from either end -- and blocking the other must not
## break the line.
static func _test_boundary_line_resolves_by_the_shared_epsilon_nudge_tie_break() -> Array[String]:
	var violations: Array[String] = []
	var a := BOUNDARY_ORIGIN
	var b := BOUNDARY_TARGET

	# Both candidates sit one step from each endpoint: the tie is real.
	for candidate in [BOUNDARY_LEFT, BOUNDARY_RIGHT]:
		violations.append_array(
			_expect(
				HexCoord.distance(a, candidate) == 1 and HexCoord.distance(candidate, b) == 1,
				(
					"%s must be one step from both %s and %s for this to be a boundary case"
					% [candidate, a, b]
				)
			)
		)

	var forward := HexCoord.line(a, b)
	var backward := HexCoord.line(b, a)
	backward.reverse()

	violations.append_array(
		_expect(
			forward == backward,
			(
				"line(%s, %s) = %s must be line(%s, %s) reversed = %s -- %s"
				% [a, b, forward, b, a, backward, TIE_BREAK]
			)
		)
	)

	var chosen := forward[1] if forward.size() == 3 else Vector3i.ZERO
	var rejected := BOUNDARY_RIGHT if chosen == BOUNDARY_LEFT else BOUNDARY_LEFT

	violations.append_array(
		_expect(
			chosen == BOUNDARY_LEFT or chosen == BOUNDARY_RIGHT,
			(
				"line(%s, %s) must resolve the boundary into exactly one of %s or %s, got %s -- %s"
				% [a, b, BOUNDARY_LEFT, BOUNDARY_RIGHT, forward, TIE_BREAK]
			)
		)
	)
	violations.append_array(
		_expect(
			rejected not in forward,
			(
				"line(%s, %s) must pass through one side of the boundary, not both -- got %s -- %s"
				% [a, b, forward, TIE_BREAK]
			)
		)
	)

	var chosen_blocked := _hex_board(2, [chosen] as Array[Vector3i])
	violations.append_array(
		_expect(
			not chosen_blocked.has_line_of_sight(a, b),
			(
				"BLOCKING the chosen boundary hex %s must break sight from %s to %s -- %s"
				% [chosen, a, b, TIE_BREAK]
			)
		)
	)
	violations.append_array(
		_expect(
			chosen_blocked.has_line_of_sight(a, b) == chosen_blocked.has_line_of_sight(b, a),
			(
				"both directions must agree with the chosen boundary hex %s BLOCKED -- %s"
				% [chosen, TIE_BREAK]
			)
		)
	)

	var rejected_blocked := _hex_board(2, [rejected] as Array[Vector3i])
	violations.append_array(
		_expect(
			rejected_blocked.has_line_of_sight(a, b),
			(
				"BLOCKING the other boundary hex %s must not break sight from %s to %s -- %s"
				% [rejected, a, b, TIE_BREAK]
			)
		)
	)
	violations.append_array(
		_expect(
			rejected_blocked.has_line_of_sight(a, b) == rejected_blocked.has_line_of_sight(b, a),
			(
				"both directions must agree with the other boundary hex %s BLOCKED -- %s"
				% [rejected, TIE_BREAK]
			)
		)
	)

	return violations
