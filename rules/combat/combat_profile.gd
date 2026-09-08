## Authored tuning surface holding every combat dial spec §7 reads.
##
## Data only -- no rolling, no counting, no reading a board or a fighter.
## Never mutated after authoring. Modifiers are stored positive; the caller
## decides the sign.
class_name CombatProfile
extends Resource

## Opaque, author-assigned. Never a resource path.
@export var profile_id: String = ""

## Faces per die in combat resolution.
@export var die_sides: int = 0

## Baseline attack target number.
@export var attack_target: int = 0

## Baseline save target number.
@export var save_target: int = 0

## Distance at or within which an attacker is engaged.
@export var engagement_range: int = 0

## Subtracted from the attack target when the attacker is engaged.
@export var engagement_modifier: int = 0

## Subtracted from the attack target when the target is flanked.
@export var attack_flank_modifier: int = 0

## Subtracted from the attack target when the target is surrounded.
@export var attack_surround_modifier: int = 0

## Subtracted from the save target when the attacker is flanked.
@export var save_flank_modifier: int = 0

## Subtracted from the save target when the attacker is surrounded.
@export var save_surround_modifier: int = 0

## Subtracted from the save target when the defender is guarded.
@export var guard_modifier: int = 0

## Clamp floor -- a natural 1 always fails.
@export var min_target: int = 0

## Clamp ceiling -- a natural 6 always succeeds.
@export var max_target: int = 0


## The target number after `modifier`, clamped to [min_target, max_target].
## `modifier` is signed and, as every §7.3 row is a bonus, ordinarily negative.
func clamped_target(base_target: int, modifier: int) -> int:
	var result := base_target + modifier
	return clampi(result, min_target, max_target)
