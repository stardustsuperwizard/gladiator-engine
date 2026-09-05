## Cube hex-coordinate primitive.
##
## A hex coordinate is a bare `Vector3i` satisfying `x + y + z == 0` -- not a
## wrapper class. `Vector3i` already has value equality and hashes, so it
## works directly as a `Dictionary` key. This class is a static function
## library over `Vector3i` and is never instantiated.
##
## Direction vectors and the distance formula are taken as-is from Red Blob
## Games' cube-coordinate reference (redblobgames.com/grids/hexagons), the
## canonical source for hex-grid math. They are not re-derived here.
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
