## Authored fighter data: spec §3's `Fighter` template fields as `@export`ed
## `Resource` properties, so a fighter is authored entirely as a `.tres` file
## with no number written in GDScript.
##
## This is the "what it is" half of the parent Feature's split -- the "what
## has happened to it" half (damage counters, status flags, position) is the
## runtime `Fighter` type in sibling task #31 and does not live here. Data
## only, no behaviour, and never mutated after authoring; a runtime fighter
## copies out of this rather than writing back onto it, since Godot caches and
## shares `Resource` instances across every fighter built from the same
## template.
class_name FighterTemplate
extends Resource

## Opaque, author-assigned. Never a resource path -- see `WeaponTemplate`.
@export var template_id: String = ""
@export var display_name: String = ""
@export var move: int = 0
@export var save: int = 0
@export var health: int = 0
@export var point_value: int = 0
@export var weapons: Array[WeaponTemplate] = []
@export var tags: PackedStringArray = PackedStringArray()


## True when `tag` is present in `tags`, by exact string match -- same rule as
## `WeaponTemplate.has_ability_tag()`.
func has_tag(tag: String) -> bool:
	return tag in tags
