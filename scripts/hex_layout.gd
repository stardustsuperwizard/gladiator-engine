## The one place a pixel coordinate meets a cube coordinate.
##
## `docs/godot-implementation-guide.md` §4 requires the conversion between
## cube coordinates and pixels to live in exactly one file, so mixing the two
## never happens by accident anywhere else. `BoardView` calls through here for
## both directions and never derives a pixel or hex position itself.
##
## Pointy-top orientation, the standard Red Blob Games layout
## (redblobgames.com/grids/hexagons) over the cube coordinates
## `rules/board/hex_coord.gd` already uses. The algorithms are taken as-is, not
## re-derived, and the cube-coordinate choice is settled -- see the guide and
## `HexCoord`'s own docstring. `size` is the hex's circumradius, the distance
## from its centre to a corner, matching `corners()`'s own contract.
##
## Static methods only, over `Vector3i`/`Vector2` values, exactly as
## `HexCoord` is a function library over `Vector3i` rather than a wrapper
## object. This class is never instantiated.
class_name HexLayout
extends RefCounted

## sqrt(3), used throughout the pointy-top pixel conversion below.
const SQRT_3 := 1.7320508075688772


## The pixel centre of `coord`'s hex, relative to the board's own local
## origin -- `to_pixel(Vector3i.ZERO, size)` is always `Vector2.ZERO`. Where
## that origin sits on screen is the caller's transform, not this method's
## concern: `BoardView`'s own centring offset lives on its `Node2D` transform,
## never folded in here.
##
## Converts the cube coordinate to axial (`q = coord.x`, `r = coord.z`, the
## standard cube-to-axial reduction since `coord.y == -coord.x - coord.z`)
## and applies Red Blob Games' pointy-top axial-to-pixel matrix.
static func to_pixel(coord: Vector3i, size: float) -> Vector2:
	var q := float(coord.x)
	var r := float(coord.z)
	var x := size * (SQRT_3 * q + SQRT_3 / 2.0 * r)
	var y := size * (1.5 * r)
	return Vector2(x, y)


## The cube coordinate whose hex contains `point`, `point` being in the same
## local space `to_pixel()` produces.
##
## Applies Red Blob Games' pointy-top pixel-to-axial matrix -- the inverse of
## `to_pixel()`'s -- to get a fractional axial point, converts that to a
## fractional cube point, and rounds through `HexCoord.cube_round()`: a raw
## pixel-to-axial conversion lands on a continuous point, not a hex, exactly as
## `HexCoord.cube_lerp()`'s own docstring makes explicit for the line-drawing
## case.
static func from_pixel(point: Vector2, size: float) -> Vector3i:
	var q := (SQRT_3 / 3.0 * point.x - 1.0 / 3.0 * point.y) / size
	var r := (2.0 / 3.0 * point.y) / size
	var x := q
	var z := r
	var y := -x - z
	return HexCoord.cube_round(Vector3(x, y, z))


## The six corner offsets of one hex, relative to its own centre, for drawing
## a filled polygon or an outline. Pointy-top corners sit at 60-degree
## intervals starting 30 degrees off the x-axis, so the flat edges land on top
## and bottom rather than a corner. Each offset is `size` away from the
## origin -- `size` is the hex's circumradius, not its edge length.
static func corners(size: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in range(6):
		var angle_deg := 60.0 * i - 30.0
		var angle_rad := deg_to_rad(angle_deg)
		result.append(Vector2(size * cos(angle_rad), size * sin(angle_rad)))
	return result
