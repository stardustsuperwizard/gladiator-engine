## The one chokepoint every player command passes through.
##
## `run()` asks `Authority` first and resolves second. That order is the whole
## class: a refused request returns a `TurnResult` built from the refusal and
## `action.resolve()` is never reached -- not called and discarded, not called
## behind a flag, not called at all. The state a refused command would have
## touched is therefore byte-identical afterwards, which
## `tests/action_runner_test.gd` pins with `GameState.digest()`.
##
## **Nothing may call `rules/` around this.** Local hotseat included, where the
## gate looks like pure ceremony: if hotseat resolves directly, the calling
## convention has to be rebuilt for AI, undo, replays and networking alike.
## The UI gathers intent and renders what comes back; it never mutates state.
##
## **It names no concrete command.** `run()` is written entirely against the
## `TurnAction` base and knows nothing about what any subclass does. There is
## no command-kind enum, registry, factory or dispatch table here, and there
## must never be one -- adding a command is one new `TurnAction` subclass and
## no edit to this file. `tests/command_taxonomy_contract_test.gd` enforces
## that by running a subclass declared inside the test itself.
##
## **It holds no `GameState` of its own.** The state comes back off
## `Authority.state()` at the moment it is needed, so there is no second
## reference here to drift out of step with the one the gate validated against.
class_name ActionRunner
extends RefCounted

## The gate this runner asks. The only collaborator; also the route to the
## state, which is deliberately not cached here.
var _authority: Authority


func _init(authority: Authority) -> void:
	_authority = authority


## Submits `action` on behalf of `requester_id`.
##
## Returns the refusal as an unsuccessful `TurnResult` when the `Authority`
## refuses -- carrying that `Authority.REFUSED_*` constant verbatim, so the
## caller can tell a refusal from an action's own `FAILURE_*` -- and otherwise
## returns whatever `action.resolve()` returns, unwrapped and unmodified,
## success or failure alike.
func run(action: TurnAction, requester_id: String) -> TurnResult:
	var reason := _authority.refusal(action, requester_id)
	if not reason.is_empty():
		return TurnResult.failure(reason)

	return action.resolve(_authority.state())
