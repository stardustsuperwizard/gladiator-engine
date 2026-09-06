## Who may act right now.
##
## The game-side half of the command gate. `Authority` answers one question --
## is *this* requester allowed to submit *this* command at this moment -- and
## nothing else. Turn order, ownership and session are game-side concerns the
## rules module has no opinion about, which is why this class lives in
## `scripts/` and not in `rules/`. `ActionRunner` is the only intended caller.
##
## **It never answers whether the move is legal.** Range, line of sight,
## movement allowance and action economy belong to a `TurnAction`'s own
## `resolve()`. A refusal here means the command never reached `resolve()` at
## all; a `TurnAction.FAILURE_*` means it reached `resolve()` and could not
## resolve. The two vocabularies stay separate, which is why the constants
## below are prefixed `authority_` and no action may reuse one.
##
## **It names no concrete command.** Every predicate below is written against
## the `TurnAction` base -- `actor_id()` is the only thing it asks an action
## for. There is no command-kind enum, registry, factory or dispatch table
## here, and there must never be one: adding a command is one new `TurnAction`
## subclass and no edit to this file.
##
## **Reading `"owner_id"` out of a fighter payload is the intended seam.**
## `GameState` stores fighters as opaque dictionaries and documents that *it*
## never reads a key of one; `Fighter.to_dict()` writes `"owner_id"` for a
## game-side reader, and this is that reader. It is not a boundary violation
## and it is not a reason to give `GameState` an ownership accessor.
##
## **`active_player_id()` is set, not derived.** It is deliberately not
## computed from `turns_taken` and `turn_order()`. Deriving it would bake a
## turn-advance rule into the gate that no Feature has yet defined, and would
## force an edit here once turn sequencing actually is specified. Nothing in
## this class advances a turn.
class_name Authority
extends RefCounted

## No player is active, so nobody may act. Distinct from "not your turn": the
## state has no turn to be yours.
const REFUSED_NO_ACTIVE_PLAYER := &"authority_no_active_player"

## The requester is not the active player.
const REFUSED_NOT_YOUR_TURN := &"authority_not_your_turn"

## The action names an actor the state does not hold. Deliberately a different
## constant from any action's own "no such fighter" failure -- see the class
## docstring on separate vocabularies.
const REFUSED_NO_SUCH_FIGHTER := &"authority_no_such_fighter"

## The actor exists but the requester does not own it, including the malformed
## cases: no `"owner_id"` in the payload, or one that is not a `String`. An
## unreadable owner is not an owner, and refusing is the safe direction.
const REFUSED_NOT_YOUR_FIGHTER := &"authority_not_your_fighter"

## The fighter-payload key naming the owning player. Named here rather than
## inlined so the one place this class reaches into an opaque payload is
## obvious; `Fighter.to_dict()` is what writes it.
const OWNER_ID_KEY := "owner_id"

## The live state, held by reference. `Authority` is the single holder of it on
## the game side -- `ActionRunner` reads it back through `state()` rather than
## keeping a second reference that could drift.
var _state: GameState

## Whose turn it is. A field the game sets; see the class docstring.
var _active_player_id: String = ""


## Stores `state` and seeds the active player from the front of its turn order,
## leaving it empty when there is no turn order to seed from.
func _init(state: GameState) -> void:
	_state = state

	var order := state.turn_order()
	if not order.is_empty():
		_active_player_id = order[0]


## The state this `Authority` gates, by reference rather than a copy: resolving
## an action has to mutate the same state everyone else is reading.
func state() -> GameState:
	return _state


## The player currently allowed to act, or `""` when there is none.
func active_player_id() -> String:
	return _active_player_id


## Makes `player_id` the active player. Returns `false` and changes nothing
## when `player_id` is not in `state().turn_order()` -- which also covers `""`,
## since an empty id cannot be added to a turn order.
func set_active_player(player_id: String) -> bool:
	if player_id not in _state.turn_order():
		return false

	_active_player_id = player_id
	return true


## Why this request is refused, or `&""` when it is permitted.
##
## The single implementation of the predicate; `can_perform()` delegates here
## rather than repeating it. Checks run in a fixed order -- no active player,
## then wrong turn, then unknown actor, then wrong owner -- so a request
## failing more than one condition always reports the same reason.
func refusal(action: TurnAction, requester_id: String) -> StringName:
	if _active_player_id.is_empty():
		return REFUSED_NO_ACTIVE_PLAYER

	if requester_id != _active_player_id:
		return REFUSED_NOT_YOUR_TURN

	# A deep copy, per GameState.fighter(); nothing below writes to it, and an
	# absent fighter reads back as an empty Dictionary.
	var payload := _state.fighter(action.actor_id())
	if payload.is_empty():
		return REFUSED_NO_SUCH_FIGHTER

	var owner_field: Variant = payload.get(OWNER_ID_KEY)
	if typeof(owner_field) != TYPE_STRING:
		return REFUSED_NOT_YOUR_FIGHTER
	if owner_field != requester_id:
		return REFUSED_NOT_YOUR_FIGHTER

	return &""


## Whether `requester_id` may submit `action` right now. One line, delegating
## to `refusal()`; never a second copy of the predicate.
func can_perform(action: TurnAction, requester_id: String) -> bool:
	return refusal(action, requester_id).is_empty()
