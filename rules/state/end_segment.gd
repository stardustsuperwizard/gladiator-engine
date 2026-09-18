## Spec §10's End Segment: the round ends, its flags clear, the next one
## begins.
##
## Runs once §5.2's Combat Segment is over -- no champion on the board has an
## unspent activation, which `TurnSequence.combat_segment_complete()` is the
## one implementation of -- and refuses otherwise. It walks §10's six-step
## sequence,
## clears every flag in `StatusFlags.round_level()` from every fighter still on
## the board, resets the Turn counter and advances `round_number`.
##
## **Spec §10 step 6's final-round branch.** When `MatchVictory.has_ended()`
## reports the match is over, the Segment runs only steps 1-2 (both card-blocked
## comments, no-ops today) and returns success without clearing flags, resetting
## `turns_taken`, or advancing `round_number`. Nothing is written to `state` and
## nothing is read from `state.rng` on that path. The match-end question is asked
## first, at the top of the sequence, before the incomplete-Segment check -- so an
## elimination ends the match even mid-round, and a final-round Segment succeeds
## whether the elimination has already happened or is discovered by `MatchVictory`.
## A match that has ended is therefore *runnable*, not refusable, and `can_run()`
## says so: the form below succeeds, so the predicate reports success too.
##
## **It is not a `TurnAction`, and it does not route through the gate.** This
## is the first state-mutating thing in the project that is not a player
## command, so the reasoning is written out here rather than left to be
## rediscovered:
##
## - No player submits it. It names no actor and has no requester, and the
##   gate's every predicate is written against "may *this requester* submit
##   *this command*" -- a Segment transition supplies neither half. There is no
##   entitlement question for `Authority` to answer, and inventing a requester
##   id so that one could be asked would be inventing the answer too.
## - `AGENTS.md`'s second architectural commitment is that every *action* goes
##   through one authority object. A Segment boundary is not an action. What
##   that commitment exists to prevent is a **view** mutating state behind the
##   gate's back, and this is not that: `run()` is a pure function of the
##   `GameState` handed to it, lives in `rules/` alongside every other rule,
##   takes no ambient input and draws nothing from `state.rng`.
## - **The precedent this sets for §4's Setup**, stated plainly: a state
##   transition no player submits is a rules-side function the game side calls
##   once. It is not a `TurnAction`, it does not get a requester id invented
##   for it, and it does not route through the gate.
##
## **Contrast it with the Power Step pass.** `PowerStepPassAction` is a state
## transition of the same round structure, and it *is* a `TurnAction` and *does*
## go through `Authority` -- because a player submits it. Spec §5.3 is explicit
## that passing is a move, not an absence: somebody chooses to make it, and who
## may make it is exactly the question the gate exists to answer. The two are
## different questions with different answers, and neither is a loophole for the
## other. If a future Segment step turns out to be something a player *submits*
## -- §10 step 1's Score, once scoring cards exist and a player chooses which to
## reveal -- that step is a command, and a command goes through the gate.
##
## **The entry point is `run()`, deliberately not `resolve()`.** `resolve()` is
## what a `TurnAction` does, and `tests/gate_bypass_contract_test.gd` flags any
## receiver-qualified `.resolve(` under `scripts/` and `scenes/` so that a view
## cannot quietly resolve a command around the gate. A Segment named `resolve()`
## would either trip that scanner or earn an exemption from it, and an exemption
## is exactly what that guard must never grow. A different verb costs nothing
## and keeps the scanner firing for the one case it was written for.
##
## **Steps 1-4 are present as comments and nothing else.** Score, Equip,
## Discard and Refill all read or move cards, and `rules/cards/` does not
## exist. Their *positions* in the sequence are the deliverable, so the card
## work slots into an existing order rather than restructuring one. There is no
## stub function, no empty method and no placeholder card for any of them.
##
## **What it does not touch.** `power_step_open` and the consecutive-pass
## record are left alone rather than defensively reset: the Combat Segment is
## complete only because every Turn's Power Step ended, and
## `PowerStep.end_on_second_pass()` closes the Step and clears the record on the
## pass that ends it. Both are already at rest, and a second class writing them
## would be a second owner of that rule. The board is read-only here -- nothing
## is placed, removed or moved -- and no player's score, hand or piles are read.
##
## **Nothing draws from `state.rng`**, on any path, refusal or success.
##
## `RefCounted`, static methods only, never instantiated -- the same shape
## `Flanking`, `DicePool`, `PowerStep` and `ChargeLockout` already use.
class_name EndSegment
extends RefCounted

## The Combat Segment is not over: at least one Turn of this round remains.
const FAILURE_COMBAT_SEGMENT_INCOMPLETE := &"end_segment_combat_incomplete"


## True when `run()` would do its work -- §10's sequence, or §11.3's match-end
## form -- rather than refuse.
##
## The predicate and the reason are one implementation -- `_refusal()` -- so the
## two can never disagree about what is runnable. A match that has ended is
## runnable: `run()` answers it with the match-end form, which succeeds, and a
## predicate that called that state unrunnable would be the disagreement this
## division exists to rule out.
static func can_run(state: GameState, profile: RoundProfile) -> bool:
	return _refusal(state, MatchVictory.has_ended(state, profile)).is_empty()


## Spec §10's End Segment.
##
## Asks §11.3's match-end question first, and once. When the match has ended,
## runs only steps 1-2 (both comments, no-ops today) and returns success without
## a single mutation. When it has not, refuses an incomplete Combat Segment
## changing nothing at all -- no flag cleared, no counter moved, no board write,
## no `state.rng` draw -- and otherwise walks §10's sequence in order.
static func run(state: GameState, profile: RoundProfile) -> TurnResult:
	# §11.3: the match-end question, asked first and asked once, through
	# `MatchVictory` -- the answer is then handed to `_refusal()` rather than
	# asked for a second time.
	var match_ended := MatchVictory.has_ended(state, profile)

	var reason := _refusal(state, match_ended)
	if not reason.is_empty():
		return TurnResult.failure(reason)

	if match_ended:
		# 1. Score   -- unimplemented: reads scoring cards. `rules/cards/` does not
		#               exist.
		# 2. Equip   -- unimplemented: plays attachment cards.

		# Match has ended. No further steps. No mutations.
		return TurnResult.ok()

	# 3. Discard -- unimplemented: discards from hand.
	# 4. Refill  -- unimplemented: draws back to hand-size caps.

	# 5. Clear round-level status flags on the board.
	_clear_round_level_flags(state)

	# 6. Next round begins.
	state.turns_taken = 0
	state.round_number += 1
	return TurnResult.ok()


## Why the Segment cannot run, or `&""` when it can.
##
## The single implementation of the predicate, in a fixed order: §11.3's ending
## first -- a match that has ended refuses nothing, because `run()` answers it
## with the match-end form -- and then whether the round's Turns are all taken.
##
## Takes `match_ended` as an answer rather than the `RoundProfile` it is derived
## from, so that `MatchVictory` is asked exactly once per entry point while
## `can_run()` and `run()` still share one implementation of the refusal.
static func _refusal(state: GameState, match_ended: bool) -> StringName:
	if match_ended:
		return &""

	if not TurnSequence.combat_segment_complete(state):
		return FAILURE_COMBAT_SEGMENT_INCOMPLETE

	return &""


## §10 step 5: removes every flag in `StatusFlags.round_level()` from every
## fighter **on the board**.
##
## The set of fighters on the board comes from the board itself -- the occupant
## ids it reports across `coords()` -- which is the same test spec §9's defeat
## already gets expressed by: a defeated fighter is one `Board.remove_occupant()`
## has taken off. Its stored payload is therefore left exactly as it is: not
## read, not rewritten, not committed.
##
## The *order of the work* is `state.fighter_ids()` rather than the board walk,
## with board membership as a filter. The state's canonical fighter order is
## what `to_dict()` writes and `digest()` hashes, so doing the work in that
## order keeps the identity of the result independent of how the board happens
## to enumerate its hexes.
static func _clear_round_level_flags(state: GameState) -> void:
	var on_board := _occupant_ids(state)
	var flags := StatusFlags.round_level()

	for fighter_id in state.fighter_ids():
		if StringName(fighter_id) not in on_board:
			continue

		state.update_fighter(fighter_id, Fighter.without_flags(state.fighter(fighter_id), flags))


## Every occupant id the board reports, `Board.EMPTY_OCCUPANT` excluded.
##
## `StringName`, because that is what `Board` records occupants as; the caller
## converts its `String` fighter ids at the comparison rather than converting a
## whole board's worth of ids here.
static func _occupant_ids(state: GameState) -> Array[StringName]:
	var ids: Array[StringName] = []

	for coord in state.board.coords():
		var occupant := state.board.occupant_at(coord)
		if occupant == Board.EMPTY_OCCUPANT:
			continue
		ids.append(occupant)

	return ids
