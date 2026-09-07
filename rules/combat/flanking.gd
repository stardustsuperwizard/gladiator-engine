## Spec §8: flanking and surrounding, expressed as one pure adjacency count.
##
## `bonus_count()` answers how many extra success-symbol types a roll
## unlocks -- `NONE`, `FLANKED` or `SURROUNDED` -- from where a fighter
## stands and which other fighters stand around it. Spec §8 applies the same
## check symmetrically: once to the target (bonus on the attack roll) and
## once to the attacker (bonus on the defence roll), which is why this is
## one function used twice rather than two.
##
## Never instantiated -- every member is `static`. Reads no `GameState` and no
## `Board`; adjacency only, via `HexCoord.are_adjacent()` -- line of sight
## plays no part in spec §8's definition of flanking.
##
## `candidates` is a normalised view, not a `GameState` fighter payload:
## `{"id": String, "owner_id": String, "position": Vector3i}` per entry.
## `GameState` stores fighters as opaque dictionaries whose `"position"` is a
## JSON `[x, y, z]` array, not a `Vector3i` (`Fighter.to_dict()`/
## `Fighter._coord_from()`). Building the normalised list -- deserializing
## positions, deciding whether a defeated fighter still counts -- is the
## caller's job, not this file's.
class_name Flanking
extends RefCounted

## No adjacent enemy other than the excluded fighter.
const NONE := 0

## Exactly one adjacent enemy other than the excluded fighter.
const FLANKED := 1

## Two or more adjacent enemies other than the excluded fighter. The result
## is capped here: three or more still returns this value.
const SURROUNDED := 2

## Candidate-entry keys. Named as constants so the one place this file reaches
## into a candidate dictionary is obvious -- the same precedent `Authority`
## follows with its own `OWNER_ID_KEY`.
const ID_KEY := "id"
const OWNER_ID_KEY := "owner_id"
const POSITION_KEY := "position"


## Counts the entries of `candidates` that are adjacent to `subject_position`,
## owned by a player other than `subject_owner_id`, and not the fighter named
## by `excluded_fighter_id` -- the other active participant in the attack:
## the attacker when measuring the target, the target when measuring the
## attacker.
##
## Returns `NONE` for a count of 0, `FLANKED` for exactly 1, and `SURROUNDED`
## for 2 or more.
##
## A candidate entry missing `ID_KEY`, `OWNER_ID_KEY` or `POSITION_KEY`, or
## holding a `POSITION_KEY` value that is not a `Vector3i`, is skipped rather
## than counted or erroring -- an unreadable candidate is not an enemy, and
## skipping is the safe direction. Defeated fighters are not filtered here:
## whether one still flanks is entirely a function of whether the caller put
## it in `candidates`.
static func bonus_count(
	subject_position: Vector3i,
	subject_owner_id: String,
	excluded_fighter_id: String,
	candidates: Array[Dictionary]
) -> int:
	var count := 0

	for candidate in candidates:
		if (
			not candidate.has(ID_KEY)
			or not candidate.has(OWNER_ID_KEY)
			or not candidate.has(POSITION_KEY)
		):
			continue

		var id_field: Variant = candidate[ID_KEY]
		if typeof(id_field) != TYPE_STRING:
			continue

		var owner_field: Variant = candidate[OWNER_ID_KEY]
		if typeof(owner_field) != TYPE_STRING:
			continue

		var position_field: Variant = candidate[POSITION_KEY]
		if typeof(position_field) != TYPE_VECTOR3I:
			continue

		if id_field == excluded_fighter_id:
			continue

		if owner_field == subject_owner_id:
			continue

		var position: Vector3i = position_field
		if not HexCoord.are_adjacent(subject_position, position):
			continue

		count += 1
		if count >= SURROUNDED:
			return SURROUNDED

	return count
