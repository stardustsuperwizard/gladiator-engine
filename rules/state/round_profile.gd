## Authored tuning surface holding the round structure spec §5 reads.
##
## Data only -- no counting, no reading a state. Never mutated after
## authoring. `CombatProfile` is the pattern this follows.
class_name RoundProfile
extends Resource

## Opaque, author-assigned. Never a resource path.
@export var profile_id: String = ""

## Spec §5.2: Turns each player takes in a round's Combat Segment.
@export var turns_per_player: int = 0

## Spec §5.1: Rounds in a match.
@export var rounds_per_match: int = 0
