## Cube hex-coordinate primitive.
##
## A hex coordinate is a bare `Vector3i` satisfying `x + y + z == 0` -- not a
## wrapper class. `Vector3i` already has value equality and hashes, so it
## works directly as a `Dictionary` key. This class is a static function
## library over `Vector3i` and is never instantiated.
##
## Direction vectors, the distance formula, and the `cube_lerp`/`cube_round`/
## line draw below are taken as-is from Red Blob Games' cube-coordinate
## reference (redblobgames.com/grids/hexagons), the canonical source for
## hex-grid math. They are not re-derived here.
class_name HexCoord
extends RefCounted

## The six cube direction vectors, in a fixed order:
## 0: east, 1: northeast, 2: northwest, 3: west, 4: southwest, 5: southeast.
## `neighbour()` and `neighbours()` both use this order.
const DIRECTIONS: Array[Vector3i] = [
	Vector3i(1, -1, 0),
	Vector3i(1, 0, -1),
	Vector3i(0, 1, -1),
	Vector3i(-1, 1, 0),
	Vector3i(-1, 0, 1),
	Vector3i(0, -1, 1),
]

## The line-draw tie-break, and the single reason `line()` is symmetric.
##
## A line between two hex centres can run exactly along the boundary between
## two hexes -- `line(Vector3i(0, 0, 0), Vector3i(1, -2, 1))` is the smallest
## case, whose midpoint `(0.5, -1, 0.5)` is equidistant from `(1, -1, 0)` and
## `(0, -1, 1)`. Something has to break that tie, and the convention here is:
## **offset both endpoints by this one fixed epsilon before interpolating**, so
## the sample lands just inside whichever hex the epsilon favours. The line
## resolves into exactly one of the two hexes, always the same one.
##
## *Both* endpoints, and the *same* epsilon on each. That is what makes
## `has_line_of_sight(A, B) == has_line_of_sight(B, A)` true by construction
## rather than by the tests happening to pass. With `a' = a + e` and
## `b' = b + e`:
##
##     lerp(a', b', t) == lerp(b', a', 1 - t)
##
## so the `A -> B` and `B -> A` sample points are the same points in reverse
## order and round to the same hexes. The two common alternatives -- nudge only
## the start, or pick the nudge from the direction of travel -- break that
## identity and produce "A can see B but B cannot see A", the bug
## `docs/godot-implementation-guide.md` §4 warns about.
##
## Applied in `line()` as `cube_lerp(a, b, t) + LINE_NUDGE`, which is the same
## thing: lerp is affine, so `lerp(a + e, b + e, t) == lerp(a, b, t) + e` for
## every `t`. Adding it once after interpolating keeps the offset identical at
## both ends, which is the property that matters.
##
## The three components are deliberately distinct and sum to zero. Summing to
## zero keeps the nudged point on the `x + y + z == 0` plane. Being distinct
## keeps `cube_round()`'s "which component moved furthest" comparison off exact
## ties, so that comparison also has a margin no floating-point noise can
## cross: every decision `cube_round()` makes about a sample of a cube line is
## either at least `1 / (2 * N)` away from flipping, or exactly on a boundary
## and moved ~1e-6 off it by this epsilon.
const LINE_NUDGE := Vector3(1e-6, 2e-6, -3e-6)


## True when `coord` is a valid cube coordinate: `x + y + z == 0`.
static func is_valid(coord: Vector3i) -> bool:
	return coord.x + coord.y + coord.z == 0


## The coordinate one step from `coord` in `DIRECTIONS[direction_index]`.
static func neighbour(coord: Vector3i, direction_index: int) -> Vector3i:
	return coord + DIRECTIONS[direction_index]


## The six coordinates adjacent to `coord`, in `DIRECTIONS` order.
static func neighbours(coord: Vector3i) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for direction in DIRECTIONS:
		result.append(coord + direction)
	return result


## Plain cube distance between two cube coordinates.
static func distance(a: Vector3i, b: Vector3i) -> int:
	var delta := a - b
	return (absi(delta.x) + absi(delta.y) + absi(delta.z)) / 2


## True when `a` and `b` are exactly one step apart.
static func are_adjacent(a: Vector3i, b: Vector3i) -> bool:
	return distance(a, b) == 1


## Linear interpolation between two cube coordinates, in continuous cube
## space. The result is a point, not a hex: pass it to `cube_round()` to get
## back a coordinate.
##
## Written as `a * (1 - t) + b * t` rather than `a + (b - a) * t` because
## floating-point addition is commutative, so the reversed call with the
## complementary weight produces the identical point.
static func cube_lerp(a: Vector3i, b: Vector3i, t: float) -> Vector3:
	return Vector3(a) * (1.0 - t) + Vector3(b) * t


## Rounds a continuous cube point to the nearest valid cube coordinate.
##
## Rounding all three components independently can break `x + y + z == 0`, so
## whichever component moved furthest is discarded and recomputed from the
## other two. Ties in "moved furthest" fall through this comparison chain in a
## fixed order -- x, then y, then z -- which is deterministic and therefore
## direction-independent. `LINE_NUDGE` keeps `line()`'s samples off those ties
## in the first place.
static func cube_round(coord: Vector3) -> Vector3i:
	var rx := roundi(coord.x)
	var ry := roundi(coord.y)
	var rz := roundi(coord.z)

	var dx := absf(rx - coord.x)
	var dy := absf(ry - coord.y)
	var dz := absf(rz - coord.z)

	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry

	return Vector3i(rx, ry, rz)


## The `distance(a, b) + 1` hexes a straight line from `a` to `b` passes
## through, inclusive of both endpoints, in order.
##
## Samples the segment at `t = i / N` for `N = distance(a, b)` and rounds each
## sample to a hex. See `LINE_NUDGE` for the tie-break that makes this
## symmetric: `line(a, b)` is `line(b, a)` reversed, always.
static func line(a: Vector3i, b: Vector3i) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var n := distance(a, b)

	if n == 0:
		result.append(a)
		return result

	for i in range(n + 1):
		var t := float(i) / float(n)
		result.append(cube_round(cube_lerp(a, b, t) + LINE_NUDGE))

	return result
