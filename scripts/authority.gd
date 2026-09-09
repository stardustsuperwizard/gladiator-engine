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
## **An entitlement rule is a gate change; adding a command still is not.**
## Spec §5.1 gives the Action Step to the active player alone and the Power
## Step to both players, alternating, and a gate that cannot express that
## cannot gate the Power Step at all. So `refusal()` below reads
## `state().power_step_open`. That is not the exception it looks like: the
## edit names no concrete `TurnAction` subclass, adds no enum, registry or
## dispatch table, and is written entirely against the base -- `actor_id()`
## remains the only thing asked of an action. The same edit serves the first
## instant-speed card, the first standing ability and the first clock-driven
## timeout, because it answers *entitlement*, which is the one question this
## class exists to answer. A command that merely wants to resolve still costs
## nothing here.
##
## **Refusal order, which a request failing more than one condition is
## reported by:**
##
## 1. no active player -> `REFUSED_NO_ACTIVE_PLAYER`
## 2. an actorless command -- `actor_id()` is empty -- is permitted when the
##    requester is the active player, or when the Power Step is open and the
##    requester is in `turn_order()`; otherwise `REFUSED_NOT_YOUR_TURN`
## 3. otherwise, not the active player -> `REFUSED_NOT_YOUR_TURN`
## 4. unknown actor -> `REFUSED_NO_SUCH_FIGHTER`
## 5. wrong owner -> `REFUSED_NOT_YOUR_FIGHTER`
##
## Step 2 skips the two ownership checks rather than softening them: a command
## that names no fighter names nothing to own, and running the checks anyway
## would refuse every such command `REFUSED_NO_SUCH_FIGHTER` before it could
## ever reach `resolve()`. A command that *does* name an actor stays gated to
## the active player exactly as before, so an open Power Step does not let the
## non-active player Move, Attack, Guard or Charge.
##
## **Reading `"owner_id"` out of a fighter payload is the intended seam.**
## `GameState` stores fighters as opaque dictionaries and documents that *it*
## never reads a key of one; `Fighter.to_dict()` writes `"owner_id"` for a
## game-side reader, and this is that reader. It is not a boundary violation
## and it is not a reason to give `GameState` an ownership accessor.
##
## **`active_player_id()` is set, not derived.** It is deliberately not
## computed from `turns_taken` and `turn_order()`. Deriving it would bake a
## turn-advance rule into the gate, and turn structure is a rule: spec §5.3
## defines Turn completion, and that rule landed in `rules/` -- a Turn ends
## when its Power Step ends, and the counter is incremented there. Nothing in
## this class advances a turn or rotates the active player; the game sets it
## through `set_active_player()`.
class_name Authority
extends RefCounted

## No player is active, so nobody may act. Distinct from "not your turn": the
## state has no turn to be yours.
const REFUSED_NO_ACTIVE_PLAYER := &"authority_no_active_player"

## The requester is not entitled to act right now: not the active player, or
## -- for an actorless command -- not the active player and not a participant
## in an open Power Step. One constant covers both, deliberately. "You are not
## entitled to act right now" is exactly what a non-participant submitting a
## Power Step pass is being told, and a second constant would split one answer
## into two the caller would have to learn to treat alike.
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
## rather than repeating it. Checks run in the fixed order the class docstring
## sets out -- no active player, then the actorless case, then wrong turn, then
## unknown actor, then wrong owner -- so a request failing more than one
## condition always reports the same reason.
func refusal(action: TurnAction, requester_id: String) -> StringName:
	if _active_player_id.is_empty():
		return REFUSED_NO_ACTIVE_PLAYER

	if action.actor_id().is_empty():
		return _actorless_refusal(requester_id)

	if requester_id != _active_player_id:
		return REFUSED_NOT_YOUR_TURN

	return _ownership_refusal(action.actor_id(), requester_id)


## Whether `requester_id` may submit an actorless command right now, as the
## class docstring's step 2: the active player always may, and any other player
## in the turn order may while the Power Step is open. Split out of `refusal()`
## rather than inlined so that predicate stays one screen and one idea.
func _actorless_refusal(requester_id: String) -> StringName:
	if requester_id == _active_player_id:
		return &""

	if _state.power_step_open and requester_id in _state.turn_order():
		return &""

	return REFUSED_NOT_YOUR_TURN


## Whether `requester_id` owns `fighter_id`, as the class docstring's steps 4
## and 5. Reached only for a command that names an actor; an actorless one has
## nothing to own and never gets here.
func _ownership_refusal(fighter_id: String, requester_id: String) -> StringName:
	# A deep copy, per GameState.fighter(); nothing below writes to it, and an
	# absent fighter reads back as an empty Dictionary.
	var payload := _state.fighter(fighter_id)
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
