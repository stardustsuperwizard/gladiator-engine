## Which player takes the next Turn of the Combat Segment.
##
## **The active player is derived, not stored.** `GameState.turns_taken` is
## round-wide and already serialized (see its own docstring), and
## `state.turn_order()` is the canonical player list. Both together are enough
## to name whose Turn it is by a plain modulus, so there is no second field to
## keep in step with them: a stored active-player slot could disagree with
## `turns_taken` after a bug or a hand-edited save, a derived one cannot. It is
## also why a state restored by `GameState.from_dict()` resumes correctly with
## no extra work -- `turns_taken` came back with it, and this class recomputes
## the rest.
##
## `active_player()` returns `""` when there is no well-formed answer:
## `state.turn_order()` is empty, `state.turns_per_player` is zero or
## negative, or `state.combat_segment_complete()` is already true. That last
## case matters on its own -- at `turns_taken == turns_per_player *
## turn_order().size()` the modulus would otherwise wrap back to the front of
## the order and name a player for a Turn the Combat Segment does not have.
##
## **Pure.** `active_player()` mutates nothing, commits nothing, and draws
## nothing from `state.rng`.
##
## `RefCounted`, static methods only, never instantiated -- the same shape
## `PowerStep`, `EndSegment`, `StatusFlags` and `ChargeLockout` already use.
class_name TurnSequence
extends RefCounted


## The player whose Turn it is right now, or `""` when there is none: an empty
## `turn_order()`, an unconfigured `turns_per_player`, or a Combat Segment
## that has already run every Turn it has.
static func active_player(state: GameState) -> String:
	var order := state.turn_order()

	if order.is_empty():
		return ""
	if state.turns_per_player <= 0:
		return ""
	if state.combat_segment_complete():
		return ""

	return order[state.turns_taken % order.size()]
