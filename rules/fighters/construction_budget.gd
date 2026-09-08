## Authored construction budget holding the 15-point rule for fighter authoring.
##
## Spec §3.2's construction budget becomes checkable: a `ConstructionBudget`
## Resource holding the rule's numbers, a predicate that answers whether a
## `FighterTemplate` satisfies it, and a test asserting every authored fighter
## does.
##
## Data only -- no validation at runtime, no gates, no refusals. This is an
## authoring rule, not a combat rule. Nothing in `AttackAction`, `DicePool` or
## any resolution path may call it, and it must never gate, refuse, or modify
## an action. Spec §3.2: "nothing in §7 reads the budget."
##
## Never mutated after authoring.
class_name ConstructionBudget
extends Resource

## Opaque, author-assigned. Never a resource path -- see
## `docs/hex-skirmish-game-spec.md` §3 for why nothing in `rules/` may embed a
## `res://resources/` path.
@export var budget_id: String = ""

## Exact sum of the six combat stats.
@export var total_points: int = 0

## Floor for each stat.
@export var min_per_stat: int = 0

## Ceiling for each stat.
@export var max_per_stat: int = 0


## True when every one of `template`'s six combat stats is within
## [min_per_stat, max_per_stat] and they sum to exactly total_points.
## False for a null template.
func is_satisfied_by(template: FighterTemplate) -> bool:
	if template == null:
		return false

	var stats := [
		template.move,
		template.save,
		template.health,
		template.range_hexes,
		template.attack,
		template.damage,
	]

	var sum := 0
	for stat in stats:
		if stat < min_per_stat or stat > max_per_stat:
			return false
		sum += stat

	return sum == total_points


## Each way `template` fails, as human-readable strings; empty when it passes.
## For a test failure message and an authoring tool, never for resolution.
func violations(template: FighterTemplate) -> PackedStringArray:
	var result: PackedStringArray = []

	if template == null:
		result.append("template is null")
		return result

	# Stats in order: move, save, health, range_hexes, attack, damage
	var stat_names := ["move", "save", "health", "range_hexes", "attack", "damage"]
	var stats := [
		template.move,
		template.save,
		template.health,
		template.range_hexes,
		template.attack,
		template.damage,
	]

	var sum := 0
	for i in range(stats.size()):
		var stat_value: int = stats[i]
		var stat_name: String = stat_names[i]
		if stat_value < min_per_stat:
			result.append("%s is %d, below minimum %d" % [stat_name, stat_value, min_per_stat])
		elif stat_value > max_per_stat:
			result.append("%s is %d, above maximum %d" % [stat_name, stat_value, max_per_stat])
		sum += stat_value

	if sum != total_points:
		result.append("total is %d, expected exactly %d" % [sum, total_points])

	return result
