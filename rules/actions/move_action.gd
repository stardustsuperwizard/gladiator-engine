## Spec §6's Move: a fighter steps to a reachable destination.
##
## `resolve()` refuses first, changing nothing, then commits the board and the
## payload together: `Board.place_occupant()` at the destination, then
## `Board.remove_occupant()` at the origin, then the fighter's own position and
## its new `"moved"` flag, then the payload back into `GameState`. That order --
## secure the destination before freeing the origin -- is `AttackAction`'s own
## `_apply_push()` documented as an architecture constraint, and it applies here
## for the identical reason: a refused relocation must never leave a fighter
## standing on no hex at all.
##
## **Reachability is `Board.reachable_from()`, and only that.** It is a
## breadth-first search that routes *around* `BLOCKED` and occupied hexes,
## unlike `HexCoord.distance()`, which counts straight through them. A
## destination behind a wall, behind another fighter, or reachable only by a
## detour longer than `move()` steps is refused exactly the same way a
## destination that is simply too far is -- `FAILURE_DESTINATION_UNREACHABLE`
## deliberately does not distinguish why the search said no.
##
## **The `"moved"` flag is this class's own vocabulary.** `Fighter` carries the
## flag mechanism -- `set_status_flag()`, `has_status_flag()`,
## `clear_status_flag()` -- and names no flag itself; `FLAG_MOVED` lives here,
## the same way `AttackAction` owns `FAILURE_TARGET_IS_SELF` and `PassAction`
## owns `FAILURE_NO_SUCH_FIGHTER`. It is a plain `String`, not a `StringName`:
## `Fighter.set_status_flag()` takes a `String`, `Fighter.to_dict()` serializes
## flags as plain strings, and `Fighter.from_dict()` rejects a non-`String`
## entry. The `FAILURE_*` constants below stay `StringName` because
## `TurnResult.failure()` takes one; the two differ on purpose.
##
## **The flag must be set before the payload is committed.** `set_status_flag()`
## runs on the in-memory `Fighter` before `to_dict()` is read out of it and
## handed to `state.update_fighter()` -- `update_fighter()` replaces the stored
## payload wholesale, so setting the flag after that call would write it to a
## throwaway object the state never sees again.
##
## **The template is injected, never resolved.** It arrives through `_init()`,
## exactly as `AttackAction`'s templates do: nothing here calls `load()` or
## `preload()`, consults a registry, or asks `GameState` for one.
##
## **Neither `turns_taken` nor `round_number` is touched.** Move has three
## observable effects of its own -- position, occupancy, the flag -- so it
## follows `AttackAction`'s precedent rather than `PassAction`'s, which
## increments `turns_taken` only because that increment is its sole observable
## effect.
##
## **Draws nothing from `state.rng`.** Move is fully determined by the board
## and the `move()` stat; `rules/tests/ambient_rng_contract_test.gd` and
## `rules/tests/ambient_rng_scanner_test.gd` enforce that no generator call
## appears here.
class_name MoveAction
extends TurnAction

## Spec §6's `"moved"` flag, set on the acting fighter by a successful Move.
const FLAG_MOVED := "moved"

## `actor_template` is `null`, or the state holds a payload for `actor_id()`
## that will not parse.
const FAILURE_MISSING_DATA := &"move_missing_data"

## The state holds no fighter with this action's `actor_id()`.
const FAILURE_NO_SUCH_FIGHTER := &"move_no_such_fighter"

## The destination is the hex the fighter already stands on.
const FAILURE_DESTINATION_IS_ORIGIN := &"move_destination_is_origin"

## The destination is absent from `Board.reachable_from(origin, fighter.move())`
## -- too far, blocked, occupied, off the board, or only reachable by a detour
## longer than `move()`. Every one of those reports this single constant; see
## the class docstring.
const FAILURE_DESTINATION_UNREACHABLE := &"move_destination_unreachable"

## Where this action moves the actor. Set once, at construction.
var _destination: Vector3i

## The authored data this resolver needs to read the actor's `move()`
## allowance, injected rather than resolved.
var _template: FighterTemplate


## Both arguments beyond `actor_id` are required and stored exactly as given;
## nothing is validated here. A `null` template is refused by `resolve()` with
## `FAILURE_MISSING_DATA`, which is where it can actually be answered.
func _init(actor_id: String, destination: Vector3i, actor_template: FighterTemplate) -> void:
	super(actor_id)
	_destination = destination
	_template = actor_template


## Resolves this Move against `state`, per spec §6.
##
## Refuses first, changing nothing at all -- `_refusal()` fixes the order the
## reasons are tried in, so a request failing more than one condition always
## reports the same one. Then, in exactly the order the class docstring gives:
## secures the destination on the board, frees the origin, moves the fighter,
## sets `FLAG_MOVED`, and commits the payload.
func resolve(state: GameState) -> TurnResult:
	var fighter := _read_fighter(state)

	var reason := _refusal(state, fighter)
	if not reason.is_empty():
		return TurnResult.failure(reason)

	var origin := fighter.position()
	if not state.board.place_occupant(_destination, StringName(actor_id())):
		return TurnResult.failure(FAILURE_DESTINATION_UNREACHABLE)

	state.board.remove_occupant(origin)
	fighter.move_to(_destination)
	fighter.set_status_flag(FLAG_MOVED)
	state.update_fighter(actor_id(), fighter.to_dict())
	return TurnResult.ok()


## Why this Move cannot resolve, or `&""` when it can.
##
## The single implementation of the predicate, in a fixed order: the injected
## data and the fighter's identity first, then whether there is anywhere to go
## at all, then whether the search can actually get there.
func _refusal(state: GameState, fighter: Fighter) -> StringName:
	if _template == null:
		return FAILURE_MISSING_DATA

	if fighter == null:
		var ids := state.fighter_ids()
		return FAILURE_NO_SUCH_FIGHTER if actor_id() not in ids else FAILURE_MISSING_DATA

	if _destination == fighter.position():
		return FAILURE_DESTINATION_IS_ORIGIN

	if _destination not in state.board.reachable_from(fighter.position(), fighter.move()):
		return FAILURE_DESTINATION_UNREACHABLE

	return &""


## `actor_id()`'s payload as a `Fighter` over `_template`, or `null` when the
## template is `null` or the payload will not parse. `_refusal()` is what turns
## either case into the right `FAILURE_*` constant.
func _read_fighter(state: GameState) -> Fighter:
	if _template == null:
		return null
	return Fighter.from_dict(state.fighter(actor_id()), _template)
