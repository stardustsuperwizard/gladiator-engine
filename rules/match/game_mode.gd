## The entry point for spec §11.2: what awards VP, decided by the active game
## mode.
##
## Every caller asks this class, never a mode directly. It holds no award rule
## of its own -- it resolves `RoundProfile.game_mode` through an id ->
## implementation registry and hands the `CombatProfile` to whatever that
## names. Deathmatch's one rule lives in `Deathmatch` and nowhere else, and
## there is no `if mode_id == "deathmatch"` here or in any resolver: a second
## mode is a new class plus one row in `_registry()`.
##
## **An unregistered mode id awards 0.** §11.2 says nothing outside the active
## mode awards VP, so a mode id this build does not implement is treated the
## same as one that awards nothing -- not a fallback to Deathmatch, which
## would award VP under a mode nobody configured.
##
## **Pure.** Nothing here writes to a state and nothing draws from
## `state.rng` -- neither method below is even handed a `GameState`.
##
## `RefCounted`, static methods only, never instantiated -- the shape
## `MatchVictory`, `StandardVictory`, `EndSegment` and `ChargeLockout` already
## use.
class_name GameMode
extends RefCounted


## The VP a defeat resolved under `mode_id` awards, given `combat_profile`: the
## registered mode's own answer, or `0` when `mode_id` names no registered
## mode.
static func defeat_award(mode_id: String, combat_profile: CombatProfile) -> int:
	var registered: Variant = _registry().get(mode_id)
	if registered == null:
		return 0

	var award: Callable = registered
	return award.call(combat_profile)


## Whether `mode_id` names a mode this registry implements.
static func is_known(mode_id: String) -> bool:
	return _registry().has(mode_id)


## `RoundProfile.game_mode` -> the mode that implements it.
##
## Built per call rather than held as a `const`, because a `Callable` to a
## static method is not a constant expression. Adding §11.2's next mode is one
## row here and one new class; nothing else in this file changes.
static func _registry() -> Dictionary:
	return {Deathmatch.MODE_ID: Deathmatch.defeat_award}
