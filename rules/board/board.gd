## Hex board container: typed hexes and single-occupant placement.
##
## Terrain and occupancy are two `Dictionary`s keyed by `Vector3i`, not a
## `Hex` cell object -- spec §3's `Hex { coord, type, occupantId,
## featureToken }` describes the shape of the data, not a required class.
## Feature tokens are out of scope for this Feature, so a cell object would
## carry two fields and have one caller.
##
## The occupant id is opaque: `Board` stores a `StringName` and never
## interprets, parses, or validates it beyond the `&""` empty check. Fighters
## do not exist yet, and `Board` must acquire no knowledge of them.
class_name Board
extends RefCounted

## The five hex types from docs/hex-skirmish-game-spec.md §2.
enum HexType { NORMAL, STARTING, EDGE, BLOCKED, HAZARD }

const EMPTY_OCCUPANT: StringName = &""

## coord -> HexType, one entry per hex added to the board.
var _terrain: Dictionary = {}

## coord -> StringName, only for hexes currently occupied. A hex with no
## entry here is empty.
var _occupants: Dictionary = {}

## Every coordinate added, in insertion order -- kept alongside `_terrain` so
## `coords()` has a deterministic order without depending on Dictionary key
## iteration order.
var _coord_order: Array[Vector3i] = []


## Adds a hex of `type` at `coord`. Returns `false` and changes nothing when
## `coord` fails `HexCoord.is_valid()`, or when a hex already exists there.
func add_hex(coord: Vector3i, type: HexType) -> bool:
	if not HexCoord.is_valid(coord):
		return false
	if _terrain.has(coord):
		return false

	_terrain[coord] = type
	_coord_order.append(coord)
	return true


## True when a hex has been added at `coord`.
func has_hex(coord: Vector3i) -> bool:
	return _terrain.has(coord)


## The type of the hex at `coord`, or `HexType.NORMAL` when there is no hex
## there. `has_hex()` is the way to distinguish "no hex" from an actual
## NORMAL hex.
func hex_type(coord: Vector3i) -> HexType:
	return _terrain.get(coord, HexType.NORMAL)


## Every coordinate on the board, in the order they were added. Two calls on
## an unchanged board return the identical order.
func coords() -> Array[Vector3i]:
	return _coord_order.duplicate()


## True for a `BLOCKED` hex, and true for a coordinate with no hex on the
## board -- an off-board coordinate can neither be seen through nor walked
## through, same as a BLOCKED one, and giving both cases one answer is what
## stops callers (line of sight, reachability) from separately forgetting the
## membership test. `has_hex()` remains the way to ask about membership.
func is_blocked(coord: Vector3i) -> bool:
	if not _terrain.has(coord):
		return true
	return _terrain[coord] == HexType.BLOCKED


## Places `occupant_id` at `coord`. Returns `true` and records the occupant
## on success. Returns `false` and changes nothing when: there is no hex at
## `coord`; the hex `is_blocked()`; the hex is already occupied; or
## `occupant_id` is `&""`.
func place_occupant(coord: Vector3i, occupant_id: StringName) -> bool:
	if occupant_id == EMPTY_OCCUPANT:
		return false
	if not has_hex(coord):
		return false
	if is_blocked(coord):
		return false
	if is_occupied(coord):
		return false

	_occupants[coord] = occupant_id
	return true


## The occupant at `coord`, or `&""` when the hex is empty or absent.
func occupant_at(coord: Vector3i) -> StringName:
	return _occupants.get(coord, EMPTY_OCCUPANT)


## True when `coord` currently has an occupant.
func is_occupied(coord: Vector3i) -> bool:
	return _occupants.has(coord)


## Empties the hex at `coord`. Returns `true` when there was an occupant to
## remove, `false` when the hex was already empty or absent.
func remove_occupant(coord: Vector3i) -> bool:
	if not _occupants.has(coord):
		return false

	_occupants.erase(coord)
	return true
