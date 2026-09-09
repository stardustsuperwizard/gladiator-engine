## The engine's do-nothing Action Step command. Not one of spec §6's core
## actions -- §6 has never listed Pass; its core actions are Move, Attack,
## Charge, Guard and Focus/Mulligan. §5.3's default Action Step, taken by a
## player who does not choose, is Guard, not this. `PassAction` came in as
## Slice 0 scaffolding to prove the pipeline resolved something real without
## waiting on Attack, and that label was never accurate.
##
## It resolves successfully against a known actor and its only effect on the
## state is the one every command has: `PowerStep.note_action()` on the success
## path, opening the Turn's Power Step and clearing any consecutive-pass
## record. It still touches neither `turns_taken` nor `round_number`. Spec
## §5.3's Turn-completion rule settles that a Turn is not over until its Power
## Step has ended, and anything counting Turns counts *completed* Turns, not
## resolved actions; no action increments that counter, this one included.
##
## **Why it is kept rather than retired.** Three reasons: `ChargeLockout`
## documents Pass as "the action a locked-out fighter still has," and §6's
## lockout is in force. `tests/action_runner_test.gd`, `tests/authority_test.gd`
## and `tests/command_taxonomy_contract_test.gd` all exercise the gate with it
## -- it is the module's minimal concrete `TurnAction`, and that is a real job.
## And retiring it would ripple through those suites for no rule that needs it
## gone.
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


## Returns a successful result, having changed nothing in `state` beyond
## `PowerStep.note_action()`. Returns `FAILURE_NO_SUCH_FIGHTER`, changing
## nothing at all, when `actor_id()` names no fighter in `state`.
func resolve(state: GameState) -> TurnResult:
	if actor_id() not in state.fighter_ids():
		return TurnResult.failure(FAILURE_NO_SUCH_FIGHTER)

	PowerStep.note_action(state)
	return TurnResult.ok()
