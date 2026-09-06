## Spend a turn doing nothing. Spec §6's simplest core action.
##
## The trivial command that proves the pipeline resolves something real without
## waiting on Attack. It records that a turn was taken and nothing more: it
## must not touch `round_number`, must not rotate whose turn it is, and must
## not read or write any other field of the state. `turns_taken` is the
## observable proof that `resolve()` ran, which is what makes "a refused
## command never reaches `resolve()`" assertable at all.
##
## **It knows nothing about permission.** An action knows how to resolve itself
## against a `GameState`; who was allowed to submit it is the game side's
## question. Neither this class nor anything else in `rules/` may name the
## gate, by path or by global `class_name`.
##
## `FAILURE_NO_SUCH_FIGHTER` overlaps in meaning with the gate's own "no such
## fighter" refusal and is deliberately a different constant. The action's
## failures are the action's vocabulary; the gate's refusals are the gate's.
## Neither may be expressed in the other's terms. This one is reachable in
## practice by calling `resolve()` directly -- through the gate the actor has
## already been checked.
class_name PassAction
extends TurnAction

## The state holds no fighter with this action's `actor_id()`.
const FAILURE_NO_SUCH_FIGHTER := &"pass_no_such_fighter"


## Records one taken turn: increments `state.turns_taken` by exactly one and
## returns a successful result. Returns `FAILURE_NO_SUCH_FIGHTER`, changing
## nothing at all, when `actor_id()` names no fighter in `state`.
func resolve(state: GameState) -> TurnResult:
	if actor_id() not in state.fighter_ids():
		return TurnResult.failure(FAILURE_NO_SUCH_FIGHTER)

	state.turns_taken += 1
	return TurnResult.ok()
