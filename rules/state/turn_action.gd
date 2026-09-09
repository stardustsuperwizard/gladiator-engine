## Base class for every player command in `rules/`.
##
## **Subclass contract:** one new `TurnAction` subclass per command, each
## declaring its own `FAILURE_*` constant block -- `FAILURE_NOT_IMPLEMENTED`
## below is the worked example. There is no registry, command-kind enum, or
## dispatch table anywhere, and there must never be one: generality comes from
## subclassing `resolve()`, not from a lookup keyed on a command kind.
##
## **A concrete command calls `PowerStep.note_action(state)` on its success
## path**, immediately before it returns its successful `TurnResult`, and never
## on a failure path -- a refused command must still change nothing. The one
## exception is the Power Step pass itself, which is the command whose
## consecutive record `note_action()` clears. That one
## call does both jobs spec §5.3 needs: it opens the Turn's Power Step once the
## Action Step's action has resolved, and it resets the consecutive-pass record
## when a command lands between two passes, so pass, action, pass leaves the
## Step open. `note_action()` is idempotent, so a command composing another
## command may reach it twice harmlessly. A command does *not* touch
## `turns_taken` or `round_number`: a Turn is not over until its Power Step has
## ended, and `PowerStep.end_on_second_pass()` is the one place that says so.
##
## A refusal by `Authority` is `Authority`'s answer, never one of these
## constants. The two vocabularies stay separate: `TurnAction.FAILURE_*`
## explains why a command that reached `resolve()` could not resolve;
## `Authority` explains why a command never reached `resolve()` at all.
## Neither this class nor any subclass may reference `Authority` or
## `ActionRunner`.
class_name TurnAction
extends RefCounted

## The base's own failure reason, and the pattern every subclass's own
## `FAILURE_*` block follows: returned when a subclass has not overridden
## `resolve()`.
const FAILURE_NOT_IMPLEMENTED := &"turn_action_not_implemented"

## The id of the fighter this command acts with. Set once, at construction.
var _actor_id: String


func _init(actor_id: String) -> void:
	_actor_id = actor_id


## The id of the fighter this command acts with.
func actor_id() -> String:
	return _actor_id


## Resolves this command against `state`. The base implementation is not
## meaningful on its own -- it exists so `TurnAction` stays instantiable and
## directly testable -- and returns an unsuccessful `TurnResult` whose reason
## is `FAILURE_NOT_IMPLEMENTED`. Every concrete command overrides this.
func resolve(_state: GameState) -> TurnResult:
	return TurnResult.failure(FAILURE_NOT_IMPLEMENTED)
