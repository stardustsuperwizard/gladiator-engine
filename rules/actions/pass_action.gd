## The engine's do-nothing Action Step command. Not one of spec §6's core
## actions -- §6 has never listed Pass; its core actions are Move, Attack,
## Charge, Guard and Focus/Mulligan. §5.3's default Action Step, taken by a
## player who does not choose, is Guard, not this. `PassAction` came in as
## Slice 0 scaffolding to prove the pipeline resolved something real without
## waiting on Attack, and that label was never accurate.
##
## It resolves successfully against a known actor and its effect on the state
## is the two every command has: `Activation.record(state, actor_id())` and
## `PowerStep.note_action()`, both on the success path -- the first recording
## spec §5.2's once-per-round activation, the second opening the Turn's Power
## Step and clearing any consecutive-pass record. It still touches neither
## `turns_taken` nor `round_number`. Spec §5.3's Turn-completion rule settles
## that a Turn is not over until its Power Step has ended, and anything
## counting Turns counts *completed* Turns, not resolved actions; no action
## increments that counter, this one included.
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

## Spec §5.2's once-per-round activation: the actor has already been acted with
## this round. See `Activation`.
##
## Pass is not exempt. `ChargeLockout` calls it "the action a locked-out
## fighter still has", and that stays true -- nothing here consults the Charge
## lockout -- but §5.2's allowance is a different rule: a champion gets one
## Action Step per round whatever it spends it on, and spending it here spends
## it. An exemption would hand a player an extra Turn for free.
const FAILURE_ALREADY_ACTIVATED := &"pass_already_activated"


## Returns a successful result, having changed nothing in `state` beyond
## `Activation.record()` and `PowerStep.note_action()`. Refuses, changing
## nothing at all: `FAILURE_NO_SUCH_FIGHTER` when `actor_id()` names no fighter
## in `state`, and `FAILURE_ALREADY_ACTIVATED` when that fighter has already
## been acted with this round.
##
## There is no `_refusal()` here, unlike the four actions that have one: this
## action has no injected data, no geometry and no target, so its two reasons
## are the whole of its resolution and a separate predicate would be a function
## wrapping two lines.
func resolve(state: GameState) -> TurnResult:
	if actor_id() not in state.fighter_ids():
		return TurnResult.failure(FAILURE_NO_SUCH_FIGHTER)

	if Activation.has_activated(state, actor_id()):
		return TurnResult.failure(FAILURE_ALREADY_ACTIVATED)

	Activation.record(state, actor_id())
	PowerStep.note_action(state)
	return TurnResult.ok()
