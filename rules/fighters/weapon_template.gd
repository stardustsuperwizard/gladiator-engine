## Authored weapon data: spec §3's `Weapon` template fields as `@export`ed
## `Resource` properties, so a weapon is authored entirely as a `.tres` file
## with no number written in GDScript.
##
## Data only -- no damage logic, no validation, no derived stats. The runtime
## fighter that carries a mutable copy of this data is a separate type
## (sibling task #31); this Resource is never mutated after authoring.
##
## `range_hexes`, not `range`: `range()` is a GDScript global, and a member
## shadowing it is at best a warning -- the same trap `GameState.round_number`
## and `DeterministicRng.get_seed()` were named around.
##
## `weapon_type`, not `type`: `weapon.type` reads ambiguously against
## `Resource`'s own vocabulary and against `typeof()`. It is an `@export_enum`
## `String`, not an `int` enum, so the authored value renders as the word
## `"melee"` or `"ranged"` in a `.tres` diff rather than as a bare `0` or `1` --
## the inspector is meant to be a legible balance-editing surface. `MELEE` and
## `RANGED` exist so call sites compare against a constant rather than a bare
## string literal.
class_name WeaponTemplate
extends Resource

const MELEE := "melee"
const RANGED := "ranged"

## Opaque, author-assigned. Never a resource path -- see
## `docs/hex-skirmish-game-spec.md` §3 and the parent Feature's data-model
## notes for why nothing in `rules/` may embed a `res://resources/` path.
@export var template_id: String = ""
@export var display_name: String = ""
@export var range_hexes: int = 0
@export var dice_count: int = 0
@export var damage_value: int = 0
@export_enum("melee", "ranged") var weapon_type: String = MELEE
@export var ability_tags: PackedStringArray = PackedStringArray()


## True when `tag` is present in `ability_tags`, by exact string match -- no
## normalisation, no case folding. A data-set membership query only; nothing
## here dispatches on the tag's meaning.
func has_ability_tag(tag: String) -> bool:
	return tag in ability_tags
