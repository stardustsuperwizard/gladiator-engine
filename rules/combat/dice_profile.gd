## Authored die data: spec §7.2's die as `@export`ed `Resource` properties, so
## a die is authored entirely as a `.tres` file with no face value or symbol
## string written in GDScript.
##
## Data only -- no rolling, no matching, no counting. `DicePool` is the module
## that turns this data into results; this Resource is never mutated after
## authoring.
##
## `match_symbol` is the symbol this die's own roll counts by default, before
## any bonus. It exists because the two rolls learn their matching symbol from
## different places and one of them has nowhere else to keep it: an **attack**
## roll matches the weapon's `weapon_type`, which the caller passes in, but a
## **save** roll has no equivalent -- `FighterTemplate` carries `save` as a
## dice count only, with no save *type*. Authoring it here keeps that symbol
## out of GDScript, where a balance value may not live.
##
## `bonus_symbols` is **ordered**, and the order is the contract: flanking
## unlocks `bonus_symbols[0]`, surrounding unlocks `bonus_symbols[0]` and
## `bonus_symbols[1]`. See spec §8.
class_name DiceProfile
extends Resource

## Opaque, author-assigned. Never a resource path -- see `WeaponTemplate`.
@export var profile_id: String = ""

## One face per entry; the entry is the symbol that face shows.
@export var faces: PackedStringArray = PackedStringArray()

## The symbol this die's own roll counts by default. See the class docstring.
@export var match_symbol: String = ""

## Ordered: index 0 unlocks on flanking, index 0 and 1 unlock on surrounding.
@export var bonus_symbols: PackedStringArray = PackedStringArray()


## Number of faces this die has.
func face_count() -> int:
	return faces.size()


## The symbol at `index`, or `""` when `index` is out of range.
func symbol_at(index: int) -> String:
	if index < 0 or index >= faces.size():
		return ""
	return faces[index]
