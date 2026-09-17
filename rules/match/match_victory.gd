## The entry point for spec §11.3: has this match ended, by which ending, who
## won, and which rule decided it.
##
## Every caller asks this class, never a condition directly. It holds no §11.3
## rule of its own -- it reads `RoundProfile.victory_condition`, resolves it
## through an id -> implementation registry, and hands the state and the profile
## to whatever that names. Standard Victory's rules live in `StandardVictory`
## and nowhere else, and there is no `if condition == "standard"` here or in any
## resolver: a second condition is a new class plus one row in `_registry()`.
##
## **An unrecognised or empty condition never ends the match.** It resolves to
## no implementation, and the answer is an outcome with `over == false` and no
## winner. It deliberately does *not* fall back to Standard Victory: a match
## configured with a condition this build does not implement is misconfigured,
## and quietly ending it under a rule nobody asked for would be the worst
## available answer.
##
## **The check is derived, never stored.** §11.3 makes the end condition a check
## over the match state that the same state always answers the same way, so this
## is asked whenever the answer is wanted -- after a resolved action, at a
## Segment boundary -- rather than cached on `GameState`. Nothing here writes to
## the state and nothing draws from `state.rng`, on any path.
##
## `RefCounted`, static methods only, never instantiated -- the shape
## `EndSegment`, `ChargeLockout` and `DicePool` already use.
class_name MatchVictory
extends RefCounted


## §11.3 evaluated against `state` under `profile`'s configured condition.
##
## An outcome always comes back. A `null` argument, or a `victory_condition`
## naming no registered implementation, yields the unended outcome rather than a
## `null` the caller has to test for.
static func evaluate(state: GameState, profile: RoundProfile) -> MatchOutcome:
	if state == null or profile == null:
		return MatchOutcome.unended()

	var registered: Variant = _registry().get(profile.victory_condition)
	if registered == null:
		return MatchOutcome.unended()

	var condition: Callable = registered
	var outcome: MatchOutcome = condition.call(state, profile)
	return outcome


## Whether the match has ended, for a caller that wants only that much.
##
## Reads `evaluate().over` rather than answering separately, so the predicate
## and the outcome can never disagree -- the division `EndSegment.can_run()` and
## `EndSegment.run()` already keep.
static func has_ended(state: GameState, profile: RoundProfile) -> bool:
	return evaluate(state, profile).over


## `RoundProfile.victory_condition` -> the condition that implements it.
##
## Built per call rather than held as a `const`, because a `Callable` to a
## static method is not a constant expression. Adding §11.3's next condition is
## one row here and one new class; nothing else in this file changes.
static func _registry() -> Dictionary:
	return {StandardVictory.CONDITION_ID: StandardVictory.evaluate}
