## Authored tuning surface holding the round structure spec §5 reads, and
## every §11 match-configuration dial alongside it.
##
## This is spec §3.1's `MatchProfile`, under its existing name. `MatchProfile`
## as a separate class was considered and rejected: it would duplicate this
## class's `Resource`-only, data-only shape for no reason but the name, and
## every one of §11's dials governs the same match this class already
## describes. `RoundProfile` keeps its name and grows to cover §11 instead.
##
## Data only -- no counting, no reading a state, no method that interprets a
## dial. Never mutated after authoring. `CombatProfile` is the pattern this
## follows.
class_name RoundProfile
extends Resource

## Opaque, author-assigned. Never a resource path.
@export var profile_id: String = ""

## Spec §5.2: Turns each player takes in a round's Combat Segment.
@export var turns_per_player: int = 0

## Spec §5.1: Rounds in a match.
@export var rounds_per_match: int = 0

## Spec §11.2: what awards VP. MVP value is "deathmatch".
@export var game_mode: String = ""

## Spec §11.3: when the match ends, and who won. MVP value is "standard".
@export var victory_condition: String = ""

## Spec §11.4: opt-in rules not present in every match. Empty in the MVP.
@export var optional_modules: Array[String] = []
