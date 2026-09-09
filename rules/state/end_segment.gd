## Spec §10's End Segment: the round's own sequence, run once the Combat
## Segment (§5.2) is over.
##
## It clears every round-level status flag from every fighter **on the board**,
## resets the Turn counter, and advances `round_number`. That is what makes
## spec §6's round-scoped rules round-scoped: a fighter that Moved in round 1
## may Move in round 2, one that Guarded saves at its unmodified target again,
## one that Charged may Charge again, and §6's lockout releases.
##
## **This does not route through the command gate, and the entry point is
## `run()` rather than `resolve()`.** It is the first state-mutating thing in
## the project that is not a player command, so the reasoning is written down
## here rather than left to be re-derived:
##
## - **It is not a `TurnAction`.** No player submits it, it names no actor, and
##   there is no requester whose entitlement `Authority` could answer. Every
##   predicate on that gate is written against "may *this requester* submit
##   *this command*"; a Segment transition supplies neither half of the
##   question, so there is nothing for the gate to decide.
## - **`AGENTS.md`'s second architectural commitment is about actions.** Every
##   *action* goes through one authority object; a Segment boundary is not an
##   action. What that commitment exists to prevent is a **view** mutating
##   state behind the gate's back, and this is not that: `run()` is a pure
##   function of the `GameState` handed to it, lives in `rules/` alongside
##   every other rule, takes no ambient input, and draws nothing from
##   `state.rng` on any path.
## - **Contrast it with the Power Step pass in the same epic.**
##   `PowerStepPassAction` *is* a player command -- a player submits it, the
##   gate asks whether that player is entitled to submit it right now, and it
##   is refused when they are not. The two are different questions, and this
##   class is not a loophole in the answer to the first one.
## - **The precedent it sets for spec §4's Setup**, stated plainly: a state
##   transition no player submits is a rules-side function the game side calls
##   once. It is not a `TurnAction`, it does not get a requester id invented
##   for it, and it does not route through the gate.
##
## **`can_run()` is the predicate and `run()` reports the reason**, both
## answered by one private helper so the two can never disagree about what is
## runnable.
##
## **Only spec §10 step 5's enumerated set is cleared**, via
## `StatusFlags.round_level()`. Spec §9 hedges -- "*most* per-round status
## flags ... clear at end of round" -- and `enhanced` is the shape of the
## exception, so clearing every flag a fighter holds would be the wrong reading.
## See `StatusFlags`'s own docstring.
##
## **"On the board" is read off the board.** A fighter whose payload sits in
## the state but whom `Board.occupant_at()` reports nowhere -- spec §9's defeat,
## as `AttackAction` leaves it -- is skipped entirely: its payload is not read,
## not rewritten and not committed. The walk is over `state.fighter_ids()` with
## board membership as the test, rather than over the board's own ids, so the
## state's canonical fighter order stays the order of the work and `digest()`
## stays stable.
##
## **Nothing here touches `power_step_open` or the consecutive-pass record, and
## that is not an oversight.** The Combat Segment is complete only because every
## Turn's Power Step ended, and ending a Step closes it and clears the record --
## so both are already at rest by the time this runs. Defensively resetting them
## would be this class asserting a rule `PowerStep` already owns.
##
## **It does not write to `Board` at all.** No fighter is placed, re-placed or
## removed; the board is read-only here.
##
## **In code it names `GameState`, `Board`, `Fighter`, `StatusFlags` and
## `TurnResult`, and nothing under `rules/actions/`.** Several action classes are
## named in the prose above, to say what this class is *not* and what it leaves
## alone; none of them is called, read or depended on below. `StatusFlags` exists
## so that the clearing step does not have to reach for one.
##
## `RefCounted`, static methods only, never instantiated -- the same shape
## `Flanking`, `DicePool` and `ChargeLockout` already use in this tree.
class_name EndSegment
extends RefCounted

## The Combat Segment is not over: at least one Turn of this round remains.
## Also the answer for a state that was never sized -- `turns_per_player` at or
## below zero, or no players -- because a Segment that was never sized has not
## been completed. See `GameState.combat_segment_complete()`.
const FAILURE_COMBAT_SEGMENT_INCOMPLETE := &"end_segment_combat_incomplete"

## The match is already on its final round; there is no next round to begin.
##
## Spec §10 step 6's final-round branch -- run only steps 1-2, then go to
## victory determination -- is not implemented here. Refusing is what this class
## does instead, and what a match does when it ends belongs to §11.
const FAILURE_FINAL_ROUND := &"end_segment_final_round"


## True when `run()` would do its work rather than refuse.
##
## One line, delegating to the same helper `run()` refuses from; never a second
## copy of the predicate.
static func can_run(state: GameState) -> bool:
	return _refusal(state).is_empty()


## Spec §10's End Segment, run against `state`.
##
## Refuses first, having changed nothing at all -- no flag cleared, no counter
## moved, no board write, no `state.rng` draw. `_refusal()` fixes the order the
## reasons are tried in.
##
## The six steps below are spec §10's own sequence, in its order. Steps 1 to 4
## are documented no-ops: all four read or move cards, and there is no card
## system in this tree -- `rules/cards/` does not exist. Their positions are
## kept so the card work slots into an existing sequence rather than
## restructuring one.
static func run(state: GameState) -> TurnResult:
	var reason := _refusal(state)
	if not reason.is_empty():
		return TurnResult.failure(reason)

	# 1. Score -- unimplemented: reveals and scores each scoring card in hand
	#    whose condition is met. Waits on the card system.
	# 2. Equip -- unimplemented: plays attachment cards, capped against current
	#    points. Waits on the card system.
	# 3. Discard -- unimplemented: optionally discards hand cards. Waits on the
	#    card system.
	# 4. Refill -- unimplemented: draws scoring and ability cards back up to
	#    the hand-size caps. Waits on the card system.

	# 5. Clear round-level status flags on the board.
	_clear_round_level_flags(state)

	# 6. Next round begins. The final-round branch is FAILURE_FINAL_ROUND
	#    above, not a case here.
	state.turns_taken = 0
	state.round_number += 1
	return TurnResult.ok()


## Why the Segment refuses to run against `state`, or `&""` when it may.
##
## Checked in this order, so a state failing both always reports the same
## reason:
##
## 1. the Combat Segment is not complete;
## 2. the match is already on its final round.
static func _refusal(state: GameState) -> StringName:
	if not state.combat_segment_complete():
		return FAILURE_COMBAT_SEGMENT_INCOMPLETE

	if state.is_final_round():
		return FAILURE_FINAL_ROUND

	return &""


## Spec §10 step 5. Walks `state.fighter_ids()` -- the canonical order -- and
## rewrites the payload of each fighter the board reports as an occupant,
## minus every flag in `StatusFlags.round_level()`.
##
## A fighter not on the board is skipped before its payload is even read.
static func _clear_round_level_flags(state: GameState) -> void:
	var on_board := _occupant_ids(state)
	var flags := StatusFlags.round_level()

	for fighter_id in state.fighter_ids():
		if StringName(fighter_id) not in on_board:
			continue

		state.update_fighter(fighter_id, Fighter.without_flags(state.fighter(fighter_id), flags))


## Every occupant id the board currently reports, read off the board itself
## rather than off any fighter's recorded position. Duplicates are impossible --
## a hex holds at most one occupant -- so this is a set in all but name.
static func _occupant_ids(state: GameState) -> Array[StringName]:
	var ids: Array[StringName] = []

	for coord in state.board.coords():
		var occupant := state.board.occupant_at(coord)
		if occupant == Board.EMPTY_OCCUPANT:
			continue

		ids.append(occupant)

	return ids
