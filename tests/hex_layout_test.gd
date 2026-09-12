## Tests `HexLayout`: the `to_pixel()`/`from_pixel()` round trip over a full
## board, the origin and adjacency spacing `to_pixel()` must hold, that a
## sampled point anywhere inside a hex's own outline rounds back to it, and
## `corners()`'s own distance-from-origin contract.
##
## A contract test that cannot fail is worse than no contract test (see
## `ContractScannerTest`'s docstring); each assertion here was confirmed to
## fail against a broken implementation before being trusted.
class_name HexLayoutTest

## More than one size, per the Issue's acceptance criteria -- a bug scaled by
## `size` would otherwise hide behind a single sample.
const SIZES := [16.0, 40.0]

## Small enough that `abs(a - b) < EPSILON` is a real equality check on
## `float` results, generous enough to absorb ordinary floating-point noise.
const EPSILON := 0.001


static func run() -> bool:
	var violations: Array[String] = []

	violations.append_array(_test_round_trip_over_radius_four_board())
	violations.append_array(_test_origin_and_adjacency_spacing())
	violations.append_array(_test_sample_inside_outline_rounds_back())
	violations.append_array(_test_corners_distance_from_origin())

	if violations.is_empty():
		return true

	printerr("\n=== Hex Layout Test Violations ===")
	for violation in violations:
		printerr("FAIL " + violation)

	return false


static func _expect(condition: bool, message: String) -> Array[String]:
	return [] if condition else [message] as Array[String]


## Every valid cube coordinate within `radius` rings of the origin -- the same
## generation shape `rules/tests/line_of_sight_test.gd` and its siblings use
## for a hexagonal board.
static func _radius_coords(radius: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for x in range(-radius, radius + 1):
		var low := maxi(-radius, -x - radius)
		var high := mini(radius, -x + radius)
		for y in range(low, high + 1):
			result.append(Vector3i(x, y, -x - y))
	return result


static func _test_round_trip_over_radius_four_board() -> Array[String]:
	var violations: Array[String] = []

	for size in SIZES:
		for coord in _radius_coords(4):
			var pixel := HexLayout.to_pixel(coord, size)
			var round_tripped := HexLayout.from_pixel(pixel, size)
			violations.append_array(
				_expect(
					round_tripped == coord,
					(
						"from_pixel(to_pixel(%s, %s), %s) must be %s, got %s"
						% [coord, size, size, coord, round_tripped]
					)
				)
			)

	return violations


static func _test_origin_and_adjacency_spacing() -> Array[String]:
	var violations: Array[String] = []
	var origin := Vector3i(0, 0, 0)

	for size in SIZES:
		violations.append_array(
			_expect(
				HexLayout.to_pixel(origin, size) == Vector2.ZERO,
				"to_pixel(Vector3i(0, 0, 0), %s) must be Vector2.ZERO" % size
			)
		)

		var expected_spacing: float = sqrt(3.0) * size
		for neighbour in HexCoord.neighbours(origin):
			var distance: float = HexLayout.to_pixel(origin, size).distance_to(
				HexLayout.to_pixel(neighbour, size)
			)
			violations.append_array(
				_expect(
					absf(distance - expected_spacing) < EPSILON,
					(
						"adjacent hexes %s and %s at size %s must be %s pixels apart, got %s"
						% [origin, neighbour, size, expected_spacing, distance]
					)
				)
			)

	return violations


## A point sampled anywhere inside a hex's own drawn outline -- its centre,
## points just inside each corner, and points just inside each edge's
## midpoint -- must round back to that hex. Run against a coordinate off the
## origin so a translation bug cannot hide behind `Vector2.ZERO`.
static func _test_sample_inside_outline_rounds_back() -> Array[String]:
	var violations: Array[String] = []
	var coord := Vector3i(2, -1, -1)

	for size in SIZES:
		var center := HexLayout.to_pixel(coord, size)
		var offsets := HexLayout.corners(size)

		violations.append_array(
			_expect(
				HexLayout.from_pixel(center, size) == coord,
				"the centre of %s at size %s must round back to %s" % [coord, size, coord]
			)
		)

		for i in range(offsets.size()):
			# Just inside each corner -- pulled 1% toward the centre so the
			# sample lands strictly inside the outline rather than on its
			# boundary, where a neighbouring hex could legitimately claim it.
			var near_corner := center + offsets[i] * 0.99
			(
				violations
				. append_array(
					_expect(
						HexLayout.from_pixel(near_corner, size) == coord,
						(
							"a point just inside %s's corner %d at size %s must round back to %s, got %s"
							% [coord, i, size, coord, HexLayout.from_pixel(near_corner, size)]
						)
					)
				)
			)

			# Just inside each edge's midpoint, by the same 1% pull toward the
			# centre.
			var next_offset := offsets[(i + 1) % offsets.size()]
			var edge_midpoint := center + (offsets[i] + next_offset) * 0.5 * 0.99
			(
				violations
				. append_array(
					_expect(
						HexLayout.from_pixel(edge_midpoint, size) == coord,
						(
							"a point just inside %s's edge %d midpoint at size %s must round back to %s, got %s"
							% [coord, i, size, coord, HexLayout.from_pixel(edge_midpoint, size)]
						)
					)
				)
			)

	return violations


static func _test_corners_distance_from_origin() -> Array[String]:
	var violations: Array[String] = []

	for size in SIZES:
		var offsets := HexLayout.corners(size)

		violations.append_array(
			_expect(offsets.size() == 6, "corners(%s) must return exactly six offsets" % size)
		)

		for i in range(offsets.size()):
			var distance: float = offsets[i].length()
			violations.append_array(
				_expect(
					absf(distance - size) < EPSILON,
					"corners(%s)[%d] must be %s from the origin, got %s" % [size, i, size, distance]
				)
			)

	return violations
