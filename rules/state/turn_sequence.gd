## The round's Turn structure: how many Turns a player still has, whether the
## Combat Segment is over, and which player takes the next Turn.
##
## **The allowance is derived, not stored.** Spec §5.2 (revised 2026-09-17): a
## player takes as many Turns in a round as they have champions on the board,
## and each champion may be acted with exactly once per round. So a player's
## remaining Turns are simply their champions that are still on the board and
## have not yet been activated -- read off the board and the payloads every
## time, never snapshotted. That is what makes a champion defeated before it
## acted take its Turn with it: it stops being an occupant, so it stops being
## counted, and its owner's remaining Turns drop by one without anything
## decrementing a counter. There is no per-player tally in `GameState` and no
## new key in `GameState.to_dict()`.
##
## **`GameState.turns_taken` is still the rotation's cursor.** It is round-wide
## and already serialized (see its own docstring), and `state.turn_order()` is
## the canonical player list. `active_player()` walks the order from
## `turns_taken` and returns the first player who still has a Turn, so §5.2's
## "a player with no unacted fighter left is skipped" falls out of the scan
## rather than being a second rule. It is also why a state restored by
## `GameState.from_dict()` resumes correctly with no extra work -- `turns_taken`
## came back with it, and this class recomputes the rest.
##
## `active_player()` returns `""` when there is no well-formed answer: an empty
## `state.turn_order()`, or a rotation in which no player has a Turn left. The
## second case is exactly `combat_segment_complete()`, and it is not asked as a
## separate guard -- the scan answers it on its own, and a modulus that wrapped
## back to the front of the order for a Turn the Segment does not have is what
## the scan's `""` prevents.
##
## **The predicate lives here rather than on `GameState`**, and the reason is
## the seam `GameState`'s own docstring keeps: counting a player's champions
## means reading a payload's `"owner_id"` and its status flags, and `GameState`
## reads no key of a fighter payload. `GameState.combat_segment_complete()` is
## gone; `EndSegment`, `StandardVictory` and `HotseatSession` ask this class.
##
## **A champion "on the board" is spec §9's defeat test**, as the tree already
## expresses it: the board's own occupant ids, the same walk
## `EndSegment._occupant_ids()` and `StandardVictory._survivors_by_side()` do.
## The owner comes off the payload's one `"owner_id"` key, exactly the way
## `StandardVictory._owner_id()` reads it -- no `FighterTemplate`, no
## `Fighter.from_dict()` -- and the activation flag is asked for through
## `Activation.has_activated()` rather than by reaching into `"status_flags"`.
##
## **Pure.** Nothing here mutates, commits, or draws from `state.rng`.
##
## `RefCounted`, static methods only, never instantiated -- the same shape
## `PowerStep`, `EndSegment`, `StatusFlags` and `ChargeLockout` already use.
class_name TurnSequence
extends RefCounted


## Spec §5.2's Turn allowance for `player_id`: how many of their champions are
## still on the board and have not been activated this round.
##
## `0` for a `player_id` in no `state.turn_order()`, and `0` once every
## champion they own has acted or been removed. Derived on every call; nothing
## is cached and nothing is written.
static func remaining_turns(state: GameState, player_id: String) -> int:
	if player_id not in state.turn_order():
		return 0

	var remaining := 0

	for coord in state.board.coords():
		var occupant := state.board.occupant_at(coord)
		if occupant == Board.EMPTY_OCCUPANT:
			continue

		var fighter_id := String(occupant)
		if _owner_id(state.fighter(fighter_id)) != player_id:
			continue

		if Activation.has_activated(state, fighter_id):
			continue

		remaining += 1

	return remaining


## True when no champion on the board has an unspent activation, so spec §5.2's
## Combat Segment is over and §10's End Segment may run.
##
## False for a state with an empty `turn_order()` -- a Segment with no players
## was never sized and has not been completed, the same direction
## `GameState.combat_segment_complete()` took for its own unconfigured state.
static func combat_segment_complete(state: GameState) -> bool:
	if state.turn_order().is_empty():
		return false

	for player_id in state.turn_order():
		if remaining_turns(state, player_id) > 0:
			return false

	return true


## The player whose Turn it is right now, or `""` when there is none: an empty
## `turn_order()`, or a Combat Segment that has already run every Turn it has.
##
## Walks the turn order from `state.turns_taken` and returns the first player
## with a Turn left, so spec §5.2's skip of a player whose roster is spent is
## the scan finding nobody at that offset and moving on. A full lap finding
## nobody is the complete Segment, and the answer is `""` rather than a
## wraparound.
static func active_player(state: GameState) -> String:
	var order := state.turn_order()

	if order.is_empty():
		return ""

	for offset in order.size():
		var player_id := order[(state.turns_taken + offset) % order.size()]
		if remaining_turns(state, player_id) > 0:
			return player_id

	return ""


## The payload's `"owner_id"`, or `""` when it is missing or not a `String`.
##
## One key read off an otherwise opaque payload, the way
## `StandardVictory._owner_id()` reads it -- and deliberately not through
## `Fighter.from_dict()`, which would demand a `FighterTemplate` this class has
## no business holding. A fourth copy of the read rather than a shared helper:
## unifying the existing readers is its own task, not this one's.
static func _owner_id(payload: Dictionary) -> String:
	var value: Variant = payload.get("owner_id")
	if typeof(value) != TYPE_STRING:
		return ""

	var owner_id: String = value
	return owner_id
