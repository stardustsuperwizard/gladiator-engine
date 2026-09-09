## Spec §5.3's Power Step pass: a player declines to act in the open Power Step.
##
## **Passing is a move, not an absence.** §5.3 is explicit that a player passes
## by saying so, and that the Step ends only on two passes in a row. That is
## why this is a real command submitted through the gate like any other, rather
## than a flag the engine sets for a player who did nothing: even with no cards
## in the game the two passes happen, and the Step is empty, not skipped.
##
## **Two passes at two layers, and the class names say which layer.**
## `PassAction` means "spend my Action Step doing nothing." This means "I
## decline to act in the Power Step." Neither class references the other, and
## neither one's `FAILURE_*` block is expressible in the other's terms.
##
## **It names no actor.** A Power Step pass is a player's declaration, not a
## fighter's action, so `actor_id()` is `""` and the passing player is held
## separately as `player_id()`. The gate reads that empty actor and skips its
## ownership checks: a command that names no fighter names nothing to own.
##
## **It does not decide when the Step ends.** `PowerStep.end_on_second_pass()`
## owns that rule and owns the `turns_taken` increment that goes with it; this
## class owns only the three reasons a pass cannot be made at all.
##
## **It knows nothing about permission.** Whether this player was entitled to
## submit a pass at this moment is the game side's question, answered before
## `resolve()` is reached; `FAILURE_NO_SUCH_PLAYER` below is the action's own
## vocabulary and deliberately not any gate refusal, exactly as
## `PassAction.FAILURE_NO_SUCH_FIGHTER` is.
##
## **Draws nothing from `state.rng`.** Neither the pass nor the Step ending it
## may cause touches the generator.
class_name PowerStepPassAction
extends TurnAction

## `player_id()` names no player in `state.turn_order()`.
const FAILURE_NO_SUCH_PLAYER := &"power_step_pass_no_such_player"

## There is no open Power Step to pass. `state.power_step_open` is false --
## the Turn's Action Step has not resolved a command yet, or the Step has
## already ended.
const FAILURE_STEP_NOT_OPEN := &"power_step_pass_step_not_open"

## This player is already the most recent entry in the consecutive-pass record.
##
## This is what makes "two passes in a row" mean two *different* players: §5.1
## has the Power Step alternating between them, so a player cannot pass twice
## without the opponent acting in between. With this refusal in place the
## record never holds two entries from the same player, and `PASSES_TO_END`
## entries is exactly "both players passed in a row."
const FAILURE_ALREADY_PASSED := &"power_step_pass_already_passed"

## The player declining to act. Set once, at construction; this command has no
## actor, so the id cannot be carried as one.
var _player_id: String


## Takes the passing player rather than a fighter, and calls `super("")`: see
## the class docstring on why this command names no actor.
func _init(player_id: String) -> void:
	super("")
	_player_id = player_id


## The player declining to act.
func player_id() -> String:
	return _player_id


## Resolves this pass against `state`, per spec §5.3.
##
## Refuses first, changing nothing at all -- `_refusal()` fixes the order the
## reasons are tried in, so a request failing more than one condition always
## reports the same one. Then hands the pass to
## `PowerStep.end_on_second_pass()`, which is what decides whether this pass
## ended the Step and completed the Turn, and returns a successful result
## either way: a pass that does not end the Step is still a pass that was made.
func resolve(state: GameState) -> TurnResult:
	var reason := _refusal(state)
	if not reason.is_empty():
		return TurnResult.failure(reason)

	PowerStep.end_on_second_pass(state, _player_id)
	return TurnResult.ok()


## Why this pass cannot resolve, or `&""` when it can.
##
## The single implementation of the predicate, in a fixed order: the player's
## identity first, then whether there is an open Step to pass at all, then
## whether this player has already passed.
func _refusal(state: GameState) -> StringName:
	if _player_id not in state.turn_order():
		return FAILURE_NO_SUCH_PLAYER

	if not state.power_step_open:
		return FAILURE_STEP_NOT_OPEN

	var passes := state.power_step_passes()
	if not passes.is_empty() and passes[-1] == _player_id:
		return FAILURE_ALREADY_PASSED

	return &""
